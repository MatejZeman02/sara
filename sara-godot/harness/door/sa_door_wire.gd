## The door's connection, read and written as HTTP/1.1.
##
## `SaAgentDoor` holds one client at a time, and this is that client's socket:
## the bytes it sent and not yet taken, and the one way an answer goes back to
## it. A request is a request line, headers and a body of `Content-Length`
## bytes, answered with a status line, headers and a JSON body, and the
## connection stays open for the next request.
##
## The line protocol, one JSON object per line each way, has retired. Every
## HTTP request opens with its method in capitals, and a line
## client opened with the brace of a JSON object or with its token, which is
## lower case hex, so the first byte tells an old client from a request and
## such a connection is refused at once rather than left to wait for headers
## that never come.
##
## Godot has `HTTPClient` and no server, so the request is parsed here, by
## `Request.parse`, which reads only what the door asks of HTTP: no chunked
## body, no pipelining beyond reading the requests in order, and an
## `Expect: 100-continue` answered so a client that asks for it does not wait.
extends RefCounted


## One HTTP request as it arrived, or the refusal of one that could not be
## read. A refusal has a `status` other than zero and the `reason` said in its
## answer, and closes the connection, because after a request whose length is
## unknown nothing on the wire can be trusted to start the next one.
class Request:
    extends RefCounted

    ## Bytes of a request line and its headers at most, so a client that never
    ## ends its headers cannot grow the buffer without bound.
    const HEAD_LIMIT: int = 16384
    ## Bytes of a body at most. A batch of a few hundred steps is far under it.
    const BODY_LIMIT: int = 8 * 1024 * 1024

    var method: String = ""
    var target: String = ""
    ## Header names in lower case, as HTTP says they compare.
    var headers: Dictionary = {}
    var body: PackedByteArray = PackedByteArray()
    ## Zero for a request read whole, else the status of its refusal.
    var status: int = 0
    var reason: String = ""

    func _init(
        request_method: String = "",
        request_target: String = "",
        request_headers: Dictionary = {},
        request_body: PackedByteArray = PackedByteArray(),
        refusal: int = 0,
        refusal_reason: String = ""
    ) -> void:
        method = request_method
        target = request_target
        headers = request_headers
        body = request_body
        status = refusal
        reason = refusal_reason

    ## Whether the client asked for the connection to close after the answer.
    func closes() -> bool:
        return String(headers.get("connection", "")).to_lower().contains("close")

    ## The value of the header *name*, given in lower case, or "".
    func header(name: String) -> String:
        return String(headers.get(name, ""))

    ## Whether `Authorization` is `Bearer` and *token*. Every byte is compared
    ## whatever the first difference, so how long a refusal takes says nothing
    ## about how much of a guess was right.
    func carries(token: String) -> bool:
        var a := header("authorization").to_utf8_buffer()
        var b := ("Bearer " + token).to_utf8_buffer()
        var differ := a.size() ^ b.size()
        for i in b.size():
            differ |= (a[i] if i < a.size() else 0) ^ b[i]
        return differ == 0

    ## Reads the first request in *buffer*: `{"request": Request, "used": n}`
    ## with the bytes it took, `{"head": Request}` when the headers are whole
    ## and the body is still arriving, with `"continue": true` beside it when
    ## they ask for a `100 Continue` first, or `{}` while the head is.
    static func parse(buffer: PackedByteArray) -> Dictionary:
        var head_end := _head_end(buffer)
        if head_end < 0:
            if buffer.size() > HEAD_LIMIT:
                return _refused(buffer.size(), 431, "the request line and headers are over %d bytes" % HEAD_LIMIT)
            return {}
        var lines := buffer.slice(0, head_end).get_string_from_utf8().split("\n")
        var first := lines[0].strip_edges().split(" ")
        if first.size() != 3 or not first[2].begins_with("HTTP/1.") or first[0].is_empty():
            return _refused(head_end, 400, "the request line is not METHOD TARGET HTTP/1.1")
        var fields := {}
        for i in range(1, lines.size()):
            var line := lines[i].strip_edges()
            if line.is_empty():
                continue
            var colon := line.find(":")
            if colon <= 0:
                return _refused(head_end, 400, "a header line has no name and colon: %s" % line.left(80))
            fields[line.left(colon).strip_edges().to_lower()] = line.substr(colon + 1).strip_edges()
        if fields.has("transfer-encoding"):
            return _refused(head_end, 400, "a chunked body is not read here, send Content-Length")
        var length_text := String(fields.get("content-length", "0"))
        if not length_text.is_valid_int() or int(length_text) < 0:
            return _refused(head_end, 400, "Content-Length is not a whole number of bytes")
        var length := int(length_text)
        if length > BODY_LIMIT:
            return _refused(head_end, 413, "the body is over %d bytes" % BODY_LIMIT)
        if buffer.size() < head_end + length:
            var head := {"head": Request.new(first[0], first[1], fields)}
            if String(fields.get("expect", "")).to_lower() == "100-continue":
                head["continue"] = true
            return head
        var request := Request.new(first[0], first[1], fields, buffer.slice(head_end, head_end + length))
        return {"request": request, "used": head_end + length}

    static func _refused(used: int, refusal: int, why: String) -> Dictionary:
        return {"request": Request.new("", "", {}, PackedByteArray(), refusal, why), "used": used}

    ## Where the blank line after the headers ends, or -1 before it arrives.
    ## A bare newline is taken for a carriage return and newline, as HTTP asks
    ## a server to be lenient in.
    static func _head_end(buffer: PackedByteArray) -> int:
        var from := 0
        while true:
            var newline := buffer.find(0x0A, from)
            if newline < 0:
                return -1
            var next := newline + 1
            if next < buffer.size() and buffer[next] == 0x0D:
                next += 1
            if next < buffer.size() and buffer[next] == 0x0A:
                return next + 1
            from = newline + 1
        return -1


## Whether *step* is a ping and nothing the door runs before one, a `quit` or
## an `attach`, so a batch can answer a run of them in one frame.
static func is_ping(step: Dictionary) -> bool:
    return step.has("ping") and not step.has("quit") and not step.has("attach")


## The words of the statuses the door answers with.
const REASONS := {
    200: "OK",
    400: "Bad Request",
    401: "Unauthorized",
    404: "Not Found",
    405: "Method Not Allowed",
    409: "Conflict",
    413: "Content Too Large",
    431: "Request Header Fields Too Large",
}

var _peer: StreamPeerSocket = null
## The bytes read and not yet taken. Bytes rather than text, because a read can
## end inside a character of two or more bytes, and a half decoded on its own
## comes out as a replacement character.
var _buffer: PackedByteArray = PackedByteArray()
## Whether this request's `100 Continue` has gone out.
var _continued: bool = false
## The request whose head is whole and whose body is still arriving, with no
## body, or null. The door reads its token here, so a client whose first
## request is large is known by its head rather than dropped while the body
## comes, and a stranger is refused before the body is read.
var waiting_head: Request = null


func _init(peer: StreamPeerSocket) -> void:
    _peer = peer


## Whether the client is still there, after asking the socket.
func connected() -> bool:
    _peer.poll()
    return _peer.get_status() == StreamPeerSocket.STATUS_CONNECTED


## Bytes arrived and not yet taken.
func buffered() -> int:
    return _buffer.size()


## Keeps what has arrived as bytes, decoding nothing yet.
func read_available() -> void:
    var available := _peer.get_available_bytes()
    if available > 0:
        var got: Array = _peer.get_data(available)
        _buffer.append_array(got[1])


## Whether the bytes waiting open with something other than a method in
## capitals, which is a client of the retired line protocol or no HTTP client
## at all. The first byte is read and never decoded, so it answers as soon as
## one byte has come.
func opens_wrong() -> bool:
    return not _buffer.is_empty() and (_buffer[0] < 0x41 or _buffer[0] > 0x5A)


## The first whole HTTP request in the buffer, taken off it, or null while it
## has not all arrived. A refused one comes back as a `Request` with a status.
func take_request() -> Request:
    var parsed := Request.parse(_buffer)
    waiting_head = parsed.get("head") as Request
    if parsed.has("continue") and not _continued:
        _continued = true
        _peer.put_data("HTTP/1.1 100 Continue\r\n\r\n".to_utf8_buffer())
    if not parsed.has("request"):
        return null
    _continued = false
    _buffer = _buffer.slice(int(parsed["used"]))
    return parsed["request"] as Request


## Sends *body* as the JSON of an HTTP answer of *status*. *closing* says the
## connection ends after it, and *extra* holds any header of its own.
func send_http(status: int, body: Variant, closing: bool = false, extra: Dictionary = {}) -> void:
    var payload := (JSON.stringify(body) + "\n").to_utf8_buffer()
    var head := "HTTP/1.1 %d %s\r\n" % [status, REASONS.get(status, "Error")]
    head += "Content-Type: application/json\r\nContent-Length: %d\r\n" % payload.size()
    head += "Connection: %s\r\n" % ("close" if closing else "keep-alive")
    for name: String in extra:
        head += "%s: %s\r\n" % [name, extra[name]]
    var bytes := (head + "\r\n").to_utf8_buffer()
    bytes.append_array(payload)
    _peer.put_data(bytes)


func close() -> void:
    _peer.disconnect_from_host()
