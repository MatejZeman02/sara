## The door speaks HTTP/1.1 on both of its ways in.
##
## Each case opens the door in this process, once on a Unix socket and once on
## TCP at 127.0.0.1, connects to it with a stream peer of the same kind and
## drives both ends by hand until an answer or a close arrives. The token goes
## in `Authorization: Bearer` on both, read from the file the door wrote. A
## client of the retired line protocol is refused on both.
##
## The steps go through a table that records them rather than running them,
## because what is under test is the wire, as in `test_w1_door_on_tcp.gd`.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")

## Rounds of polling both ends before a case gives up, a few milliseconds each.
const ROUNDS: int = 400

## The two ways in, each case run on both.
const WAYS: Array[String] = ["socket", "tcp"]


## The executor's place, with every step kept rather than run.
class RecordingTable:
    extends StepTable

    var ran: Array = []

    func _init() -> void:
        super(CaptureRun.new(SaDataRoot.path("http-door-run")))

    func run(step: Dictionary) -> void:
        ran.append(step)

    func state() -> Dictionary:
        return {"steps_run": ran.size()}


var _door: AgentDoor = null
var _table: RecordingTable = null
var _run: CaptureRun = null
var _token: String = ""


func before_each() -> void:
    _door = AgentDoor.new(SaDataRoot.path("http-door/door.json"))
    _table = RecordingTable.new()
    _run = CaptureRun.new(SaDataRoot.path("http-door-run"))
    _token = ""


## Called by a case between its two ways in as well, so it may find no door.
func after_each() -> void:
    if _door == null:
        return
    _door.close()
    _door = null
    _table = null
    _run = null


## The ways in this machine has. Windows has no Unix socket, and the door says
## so rather than opening one (`SaAgentDoor.open`), so there each case runs on
## TCP alone and the suite's line says the socket's half was left out.
func _ways() -> Array[String]:
    if OS.get_name() != "Windows":
        return WAYS
    skip("Windows has no Unix socket, so every case ran on TCP alone and the socket token file was not read")
    return ["tcp"] as Array[String]


## The socket's path, short enough for `sun_path` wherever the data root is.
static func _socket_path() -> String:
    var runtime := OS.get_environment("XDG_RUNTIME_DIR")
    var folder := runtime if not runtime.is_empty() else "/tmp"
    return folder.path_join("sara-http-%d.sock" % OS.get_process_id())


## Opens the door on *way* and keeps the token it wrote.
func _open(way: String) -> bool:
    var opened := false
    var file := ""
    if way == "socket":
        opened = _door.open(_socket_path())
        file = _door.token_file
    else:
        file = SaDataRoot.path("http-door.port")
        opened = _door.open_port(file)
    if opened:
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
        _token = String((parsed as Dictionary).get("token", "")) if parsed is Dictionary else ""
    return opened


## A client connected to the door on *way*, once the door has taken it.
func _connect(way: String) -> StreamPeerSocket:
    var client: StreamPeerSocket = null
    if way == "socket":
        var uds := StreamPeerUDS.new()
        uds.connect_to_host(_door.socket_path)
        client = uds
    else:
        var tcp := StreamPeerTCP.new()
        tcp.connect_to_host(AgentDoor.LOOPBACK, _door.port)
        client = tcp
    for _i in ROUNDS:
        client.poll()
        _door.poll(_table, _run)
        if client.get_status() == StreamPeerSocket.STATUS_CONNECTED:
            break
        OS.delay_msec(2)
    return client


## An HTTP request posting *body* to *target*, with the token unless *token*
## is given, "" meaning none.
func _request(body: String, target: String = "/step", token: Variant = null) -> String:
    var bearer := _token if token == null else String(token)
    var head := "POST %s HTTP/1.1\r\nHost: sara\r\nContent-Type: application/json\r\n" % target
    if not bearer.is_empty():
        head += "Authorization: Bearer %s\r\n" % bearer
    return head + "Content-Length: %d\r\n\r\n%s" % [body.to_utf8_buffer().size(), body]


func _send(client: StreamPeerSocket, text: String) -> void:
    client.put_data(text.to_utf8_buffer())


## Polls both ends until *client* has a whole HTTP answer, and returns
## `{"status": n, "headers": {...}, "body": parsed}`, or `{"closed": true}`
## when the door closed the connection first. *received* keeps what came.
func _wait_for_answer(client: StreamPeerSocket, received: PackedByteArray = PackedByteArray()) -> Dictionary:
    for _i in ROUNDS:
        _door.poll(_table, _run)
        client.poll()
        if client.get_status() == StreamPeerSocket.STATUS_CONNECTED:
            var available := client.get_available_bytes()
            if available > 0:
                var got: Array = client.get_data(available)
                received.append_array(got[1])
        var answer := _parse_answer(received)
        if not answer.is_empty():
            received.clear()
            return answer
        if client.get_status() != StreamPeerSocket.STATUS_CONNECTED:
            return {"closed": true}
        OS.delay_msec(2)
    return {"timed_out": true}


## The whole answer at the front of *bytes*, or {} while it is not whole.
static func _parse_answer(bytes: PackedByteArray) -> Dictionary:
    var text := bytes.get_string_from_utf8()
    var head_end := text.find("\r\n\r\n")
    if head_end < 0:
        return {}
    var lines := text.substr(0, head_end).split("\r\n")
    var headers := {}
    for i in range(1, lines.size()):
        var colon := lines[i].find(":")
        headers[lines[i].left(colon).to_lower()] = lines[i].substr(colon + 1).strip_edges()
    var length := int(headers.get("content-length", "0"))
    var body_bytes := text.substr(head_end + 4).to_utf8_buffer()
    if body_bytes.size() < length:
        return {}
    return {
        "status": int(lines[0].split(" ")[1]),
        "headers": headers,
        "body": JSON.parse_string(body_bytes.slice(0, length).get_string_from_utf8()),
    }


func test_one_step_is_answered_with_its_json() -> void:
    for way in _ways():
        before_each()
        assert_true(_open(way), "The door opens on the %s" % way)
        var client := _connect(way)
        _send(client, _request(JSON.stringify({"id": 7, "zoom": 2.0})))
        var answer := _wait_for_answer(client)
        assert_eq(answer.get("status"), 200, "One step is answered 200 on the %s" % way)
        var headers: Dictionary = answer.get("headers", {})
        assert_eq(headers.get("content-type"), "application/json", "as JSON")
        assert_true(headers.has("content-length"), "with its length")
        assert_eq(headers.get("connection"), "keep-alive", "and the connection stays open")
        var body: Dictionary = answer.get("body", {})
        assert_eq(body.get("id"), 7.0, "The answer is the step's")
        assert_true(bool(body.get("ok", false)), "and it worked")
        assert_eq(_table.ran, [{"zoom": 2.0}], "The step reached the executor without the door's keys")
        client.disconnect_from_host()
        after_each()


func test_a_batch_of_three_is_answered_in_order() -> void:
    for way in _ways():
        before_each()
        assert_true(_open(way), "The door opens on the %s" % way)
        var client := _connect(way)
        var steps := [{"id": 1, "zoom": 2.0}, {"id": 2, "ping": "x"}, {"id": 3, "zoom": 3.0}]
        _send(client, _request(JSON.stringify(steps)))
        var answer := _wait_for_answer(client)
        assert_eq(answer.get("status"), 200, "A batch is answered 200 on the %s" % way)
        var body: Variant = answer.get("body")
        assert_true(body is Array, "with an array")
        if body is Array:
            assert_eq((body as Array).map(func(one: Dictionary) -> Variant: return one.get("id")), [1.0, 2.0, 3.0], "in order")
        assert_eq(_table.ran, [{"zoom": 2.0}, {"ping": "x"}, {"zoom": 3.0}], "Each step ran, in order")
        client.disconnect_from_host()
        after_each()


func test_a_refused_step_ends_a_batch_with_its_answer_last() -> void:
    for way in _ways():
        before_each()
        assert_true(_open(way), "The door opens on the %s" % way)
        var client := _connect(way)
        _send(client, _request(JSON.stringify([{"id": 1, "zoom": 2.0}, "not a step", {"id": 3, "zoom": 3.0}])))
        var answer := _wait_for_answer(client)
        var body: Array = answer.get("body", []) if answer.get("body") is Array else []
        assert_eq(body.size(), 2, "The batch stops at the refused step on the %s" % way)
        if body.size() == 2:
            assert_true(bool(body[0].get("ok", false)), "The step before it worked")
            assert_false(bool(body[1].get("ok", true)), "and the refused step's answer is last")
        assert_eq(_table.ran, [{"zoom": 2.0}], "and the step after it never ran")
        client.disconnect_from_host()
        after_each()


func test_a_request_without_the_token_is_refused_and_closed() -> void:
    for way in _ways():
        before_each()
        assert_true(_open(way), "The door opens on the %s" % way)
        var client := _connect(way)
        _send(client, _request(JSON.stringify({"id": 1, "zoom": 2.0}), "/step", ""))
        var answer := _wait_for_answer(client)
        assert_eq(answer.get("status"), 401, "No token is answered 401 on the %s" % way)
        assert_eq((answer.get("headers", {}) as Dictionary).get("connection"), "close", "and says it closes")
        assert_eq(_wait_for_answer(client), {"closed": true}, "and it does")
        var wrong := _connect(way)
        _send(wrong, _request(JSON.stringify({"id": 2, "zoom": 2.0}), "/step", "0".repeat(64)))
        assert_eq(_wait_for_answer(wrong).get("status"), 401, "A wrong token is refused the same")
        assert_eq(_table.ran, [], "Neither step ran")
        var client_after := _connect(way)
        _send(client_after, _request(JSON.stringify({"id": 3, "zoom": 2.0})))
        assert_eq(_wait_for_answer(client_after).get("status"), 200, "and the door still answers the token")
        client_after.disconnect_from_host()
        after_each()


func test_a_malformed_request_is_answered_400_and_the_door_stays_open() -> void:
    for way in _ways():
        before_each()
        assert_true(_open(way), "The door opens on the %s" % way)
        var client := _connect(way)
        _send(client, _request("{not json"))
        var answer := _wait_for_answer(client)
        assert_eq(answer.get("status"), 400, "A body that is not JSON is answered 400 on the %s" % way)
        _send(client, _request(JSON.stringify({"id": 2, "zoom": 2.0})))
        assert_eq(_wait_for_answer(client).get("status"), 200, "and the same connection goes on")
        _send(client, "POST\r\n\r\n")
        assert_eq(_wait_for_answer(client).get("status"), 400, "A request line that cannot be read is answered 400")
        assert_eq(_wait_for_answer(client), {"closed": true}, "and that connection closed")
        assert_true(_door.is_open(), "The door is still open")
        var again := _connect(way)
        _send(again, _request(JSON.stringify({"id": 3, "zoom": 3.0})))
        assert_eq(_wait_for_answer(again).get("status"), 200, "and answers the next connection")
        assert_eq(_table.ran, [{"zoom": 2.0}, {"zoom": 3.0}], "Only the good requests ran")
        again.disconnect_from_host()
        after_each()


func test_two_requests_share_one_connection() -> void:
    for way in _ways():
        before_each()
        assert_true(_open(way), "The door opens on the %s" % way)
        var client := _connect(way)
        _send(client, _request(JSON.stringify({"id": 1, "zoom": 2.0})))
        var first := _wait_for_answer(client)
        _send(client, _request(JSON.stringify({"id": 2, "zoom": 3.0})))
        var second := _wait_for_answer(client)
        assert_eq((first.get("body", {}) as Dictionary).get("id"), 1.0, "The first request is answered on the %s" % way)
        assert_eq((second.get("body", {}) as Dictionary).get("id"), 2.0, "and the second on the same connection")
        assert_eq(client.get_status(), StreamPeerSocket.STATUS_CONNECTED, "which is still open")
        _send(client, _request(JSON.stringify({"id": 3, "ping": true})))
        var pinged := _wait_for_answer(client).get("body", {}) as Dictionary
        assert_eq(pinged.get("connections"), 1.0, "and a ping says the door took one connection")
        client.disconnect_from_host()
        after_each()


func test_a_hung_up_http_client_leaves_the_door_listening() -> void:
    for way in _ways():
        before_each()
        assert_true(_open(way), "The door opens on the %s" % way)
        var client := _connect(way)
        _send(client, _request(JSON.stringify({"id": 1, "zoom": 2.0})))
        _wait_for_answer(client)
        client.disconnect_from_host()
        var going := true
        for _i in 20:
            going = going and _door.poll(_table, _run)
            OS.delay_msec(2)
        assert_true(going, "A launched door whose HTTP client hung up goes on, as `curl` hangs up after every call")
        var next := _connect(way)
        _send(next, _request(JSON.stringify({"id": 2, "quit": true})))
        var ended := false
        for _i in ROUNDS:
            if not _door.poll(_table, _run):
                ended = true
                break
            OS.delay_msec(2)
        assert_true(ended, "A quit from the next client ends the session on the %s" % way)
        next.poll()
        var got := PackedByteArray()
        if next.get_available_bytes() > 0:
            got = next.get_data(next.get_available_bytes())[1]
        var answer := _parse_answer(got)
        assert_true(bool((answer.get("body", {}) as Dictionary).get("quit", false)), "and is answered first")
        after_each()


func test_a_call_that_connects_as_the_last_hangs_up_is_served() -> void:
    for way in _ways():
        before_each()
        assert_true(_open(way), "The door opens on the %s" % way)
        var first := _connect(way)
        _send(first, _request(JSON.stringify({"id": 1, "zoom": 2.0})))
        _wait_for_answer(first)
        # No poll of the door between the hang-up and the next connect, which
        # is how `curl` in a shell loop meets it.
        first.disconnect_from_host()
        var second := _connect(way)
        _send(second, _request(JSON.stringify({"id": 2, "zoom": 3.0})))
        var answer := _wait_for_answer(second)
        assert_eq(answer.get("status"), 200, "The next call is served on the %s, not refused as a second client" % way)
        second.disconnect_from_host()
        after_each()


func test_a_line_of_the_retired_protocol_is_refused_on_both_ways_in() -> void:
    for way in _ways():
        before_each()
        assert_true(_open(way), "The door opens on the %s" % way)
        var client := _connect(way)
        _send(client, JSON.stringify({"id": 5, "zoom": 2.0}) + "\n")
        var answer := _wait_for_answer(client)
        assert_eq(answer.get("status"), 400, "A JSON line on the %s is answered 400: %s" % [way, answer])
        var error := String((answer.get("body", {}) as Dictionary).get("error", ""))
        assert_true(error.contains("line protocol"), "saying the line protocol has retired")
        assert_eq(answer.get("headers", {}).get("connection"), "close", "and the connection closes")
        assert_true(_table.ran.is_empty(), "Its step never ran on the %s" % way)
        client.disconnect_from_host()
        after_each()


func test_the_socket_token_file_is_the_owners_and_goes_on_close() -> void:
    if not _ways().has("socket"):
        return
    assert_true(_open("socket"), "The door opens")
    var file := _door.token_file
    assert_eq(file, _socket_path() + ".json", "The token is written beside the socket")
    assert_eq(_token.length(), AgentDoor.TOKEN_BYTES * 2, "as the hex of its random bytes")
    # The group's and the others' bits, 0o077, which GDScript writes in hex.
    assert_eq(FileAccess.get_unix_permissions(file) & 0x3F, 0, "readable by the owner alone")
    _door.close()
    assert_false(FileAccess.file_exists(file), "Closing removes it")
