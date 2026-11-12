## A live capture session on a local socket.
##
## Sara started with `--agent-socket=<path>` listens on a Unix socket there,
## accepts one client, and answers each HTTP request posting a step: a request
## is a scenario step, an answer is what the step left behind. A scenario file
## and a conversation are then the same thing read from two places. Nothing here
## dispatches a step: every request goes through `SaCapture._run_step` and no
## other path exists, so a step kind an agent gains is a step kind a scenario
## gains and neither can drift.
##
## Two ways to fail a listen fail quietly but for the return value, so both are
## checked here: a path over `sun_path`'s 108 bytes, which a scratch folder under
## a long temp path is already past, and a leftover socket file, so a stale one
## is unlinked first and the live one on the way out.
##
## Windows has no Unix socket Godot can listen on, so `--agent-port-file=<path>`
## listens on TCP instead, bound to 127.0.0.1 on a port the system picks. It
## writes the port and a token of 32 random bytes to that file, and every request
## must carry the token or it is refused and its connection closed. The loopback
## binding keeps the network out and the token keeps out other programs on the
## machine, as a Unix socket's folder permissions do. The TCP way works on Linux
## and macOS too, which is how the suite proves it.
##
## Whenever the door listens it says where in `door.json` in the data root. A
## client that sends `{"attach": true}` first makes the door drop it on a hang-up
## or the idle timeout and go on listening, and `--agent-door` is an attach door
## from the start, so a client that went away never closes a painter's Sara.
##
## The answer is the step's verdict, not the state dump, which runs to hundreds of
## thousands of characters and is past a small model's context before its first
## stroke: the id, `ok`, the verdict lines the step printed, where the document
## sits in the window, the shot's path, the errors and warnings the step raised
## (`report/sa_door_errors.gd`), and whether the painter changed the document
## since the last step (`sa_door_glance.gd`). A request that sets `dump` gets the
## dump as well. The verdict lines are kept by a logger the door installs while it
## listens, because the run log is buffered and a client with no pipe to the
## process never saw a step's own `print` in it.
##
## `{"steps": true}` answers every step kind with its first sentence and
## `{"steps": "zoom"}` one kind's whole doc, read by `sa_door_catalogue.gd`. A
## request it cannot run answers its error with `help` naming that request, and
## `sa_door_wire.gd` reads the HTTP/1.1 on either way in (`POST /step` with a step
## or an array of them, the token as `Authorization: Bearer`).
class_name SaAgentDoor
extends RefCounted

## The executor a request goes through and the run it reports on, by path the
## way the runner reaches them, so the door types what it holds rather than
## taking the runner as a `Node` and reaching its members by name in a string.
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const DoorErrors := preload("res://harness/report/sa_door_errors.gd")
const DoorWire := preload("res://harness/door/sa_door_wire.gd")
const DoorCatalogue := preload("res://harness/door/sa_door_catalogue.gd")
const AgentInvite := preload("res://ui/boot/sa_agent_invite.gd")
const KnownFile := preload("res://harness/door/sa_known_file.gd")
const DoorRefusals := preload("res://harness/door/sa_door_refusals.gd")
const DoorLog := preload("res://harness/door/sa_door_log.gd")
const ScenarioDocument := preload("res://harness/scenario/sa_scenario_document.gd")

## Seconds without a request before the session gives itself up, so an
## abandoned door does not hold a GPU. Counted from the last request rather
## than from the start.
const DEFAULT_IDLE_TIMEOUT: float = 600.0

## What `sun_path` holds, minus the terminator. The check is here because the
## engine's own message names a file and a number and not the rule.
const MAX_PATH_BYTES: int = 107

## Frames to let the app settle after a step before the dump is taken, unless
## the request names its own. Two, because one is not enough for a container to
## sort its children and a scenario's own steps wait far longer than that. A
## request that names 0 is answered in the frame its step ran.
const DEFAULT_SETTLE_FRAMES: int = 2

## The address the TCP way in binds, and the only one. Written once so that no
## edit can widen it by passing a second value somewhere.
const LOOPBACK := "127.0.0.1"

## The known file's name in the data root, `user://door.json` for a painter's
## Sara and `<settings-dir>/data/door.json` for a scratch run, so a session the
## harness launched never takes the file from the Sara on the painter's screen.
## The paragraph an agent is handed names the same file, so the name is its.
const KNOWN_FILE := AgentInvite.KNOWN_FILE

## Seconds before an idle close at which the door warns, so a client that is
## thinking sees it coming in the next thing it reads and can send a `ping`.
const WARN_BEFORE: float = 60.0

## The request keys that are the door's and never the step's.
const REQUEST_KEYS: Array[String] = ["id", "settle", "dump"]

## Bytes of randomness in the token, which goes on the wire as their hex.
const TOKEN_BYTES: int = 32

## How long a connection has to send a request carrying its token before it is
## closed, so a program that connects and says nothing cannot hold the one
## client slot against the client the known file was written for.
const TOKEN_SECONDS: float = 5.0

var socket_path: String = ""
var idle_timeout: float = DEFAULT_IDLE_TIMEOUT

## The file the TCP way in wrote its port and token to, removed on the way out.
## Empty on a Unix socket.
var port_file: String = ""

## The port the TCP way in listens on, zero on a Unix socket. The system picks
## it, so this is read back from the server rather than chosen.
var port: int = 0

## Where the known file was written, or "" when this door wrote none, which is
## when another live Sara holds it.
var known_file: String = ""

## The file beside the Unix socket that holds its token for HTTP, removed on
## the way out. Empty on TCP, whose port file holds it.
var token_file: String = ""

## How many connections the door has taken, which a ping answers with, so a
## client can show that its session held one.
var connections: int = 0

## A `UDSServer` or a `TCPServer`, and the connection one of them handed over.
## Everything after the accept is the same for both.
var _server: SocketServer = null
var _wire: DoorWire = null
## The connections turned away while one is held, answered and then closed.
var _refusals: DoorRefusals = DoorRefusals.new(TOKEN_SECONDS, DEFAULT_IDLE_TIMEOUT)
## The token every request carries, on either way in.
var _token: String = ""
## Whether the connection held has sent a request with the token.
var _trusted: bool = false
var _connected_usec: int = 0
## The steps of the HTTP request being served that have not run yet, and the
## answers of those that have, sent together once the last is answered.
var _batch: Array = []
var _batch_answers: Array = []
## Whether the request being served sent an array, answered by an array.
var _batch_is_array: bool = false
## Whether the connection closes once the request being served is answered.
var _batch_closes: bool = false
var _last_request_usec: int = 0
## When a trusted client last sent a request, which an attached door's idle
## clock does not keep once the client hung up, for [method _lets_the_lock_go].
var _heard_usec: int = 0
## The run log as this session reads it, and what a step raised, which is what
## a dump's `printed` and every answer's `errors` come from.
var _log := DoorLog.new()

## The step being answered, and the frames left before the answer goes out. A
## step is run in one frame and answered in a later one, because half of what a
## capture does only reaches the screen on the next draw.
var _pending: Dictionary = {}
## The trail place the request being served entered, `SaTrail.NOTED` while no
## request is in hand. A request of thirty eyes holds frames for seconds, and
## with no place of its own those stalls read as whatever stood last, the load
## of minutes before.
var _request_ticket: int = SaTrail.NOTED
var _pending_frames: int = 0
## Holds an answer back until the frame that shows its step is drawn.
var drawn_wait := SaDoorDrawnWait.new()
## The painter's changes between steps, which every answer reports.
var changes := SaDoorGlance.Changes.new()
## Answers a run of shows and hides in one frame, pays for its picture, and
## names the dialogs standing in each of its answers from one walk of the tree.
var _eyes := SaDoorEyeRun.new()

## Where the known file goes. The data root's unless the constructor names
## another place, which is how a suite keeps its doors out of the real one.
var _known_path: String = ""
## Whether a client leaving, or going idle, drops that client rather than
## ending the session. Set by an attach request or by `--agent-door`.
var _keeps_listening: bool = false
## Whether this idle spell has had its warning.
var _warned: bool = false
## The verdict lines printed since the last answer, installed with the engine
## while the door listens and taken out when it closes.
var _verdicts: SaDoorVerdicts = null
## The engine's errors and warnings while the door listens, installed and
## taken out with the verdict lines.
var _errors: DoorErrors = null
## The step kinds `{"steps": true}` answers with, read at the first ask.
var _catalogue := DoorCatalogue.new()


## *known_path* is where the known file goes, the data root's when empty.
## *keeps_listening* makes a door that outlives its clients from the start,
## which `--agent-door` asks for.
func _init(known_path: String = "", keeps_listening: bool = false) -> void:
    _known_path = KnownFile.path(known_path)
    _keeps_listening = keeps_listening


## The value of `--<name>=` on *args*, or "" when it is absent or empty.
static func _argument(args: PackedStringArray, name: String) -> String:
    var prefix := "--%s=" % name
    for arg in args:
        if arg.begins_with(prefix):
            return arg.substr(prefix.length())
    return ""


## Whether *args* ask for a door by either way in. `SaBoot.capture_requested`
## asks the same of the same two arguments without loading this file.
static func asked_for(args: PackedStringArray) -> bool:
    return (
        args.has("--agent-door")
        or not _argument(args, "agent-socket").is_empty()
        or not _argument(args, "agent-port-file").is_empty()
    )


## A door opened the way *args* ask, or null when they ask for none or it
## would not open. `--agent-port-file` wins over `--agent-socket` when both are
## given, because it is the one that works on every platform. `--agent-door`
## alone is [method open_known].
static func from_command_line(args: PackedStringArray) -> SaAgentDoor:
    if not asked_for(args):
        return null
    var idle := _argument(args, "agent-idle")
    var idle_seconds := float(idle) if not idle.is_empty() else DEFAULT_IDLE_TIMEOUT
    var file := _argument(args, "agent-port-file")
    if file.is_empty() and _argument(args, "agent-socket").is_empty():
        return open_known("", idle_seconds)
    var door := SaAgentDoor.new()
    door.idle_timeout = idle_seconds
    var opened := door.open_port(file) if not file.is_empty() else door.open(_argument(args, "agent-socket"))
    return door if opened else null


## The door `--agent-door` opens at boot and Modules › Local Server opens in
## a running Sara: the TCP way in with the known file as its port file, a door
## that outlives its clients. *known_path* is the data root's known file when
## empty. Null when it would not open, or when a live Sara other than this one
## already holds the known file, since opening removes what is there first and
## that Sara would lose its file.
static func open_known(known_path: String = "", idle_seconds: float = DEFAULT_IDLE_TIMEOUT) -> SaAgentDoor:
    var file := KnownFile.path(known_path)
    var holder := KnownFile.live_holder(file)
    if holder > 0:
        push_error(
            (
                "SaAgentDoor: Sara %d already listens and %s says where, so this one opens no door"
                % [holder, ProjectSettings.globalize_path(file)]
            )
        )
        return null
    var door := SaAgentDoor.new(file, true)
    door.idle_timeout = idle_seconds
    return door if door.open_port(file) else null


## The live Sara other than this one that holds the known file at
## *known_path*, the data root's when empty, or 0 when none does.
static func known_holder(known_path: String = "") -> int:
    return KnownFile.live_holder(KnownFile.path(known_path))


## The file that says where this door listens, the path an agent is handed:
## the known file when this door wrote it, else its own port or token file.
func where_file() -> String:
    for file: String in [known_file, port_file, token_file]:
        if not file.is_empty():
            return file
    return ""


## Starts listening on a Unix socket at *path*, or says why it could not in a
## line naming the cause.
##
## The two named causes are answered before the engine is asked, because the
## engine's own failure is one condition line and a return of 22.
func open(path: String) -> bool:
    if path.is_empty():
        return false
    if OS.get_name() == "Windows":
        push_error("SaAgentDoor: Windows has no Unix socket to listen on. Start Sara with --agent-port-file=<path>")
        return false
    if path.to_utf8_buffer().size() > MAX_PATH_BYTES:
        push_error(
            (
                "SaAgentDoor: the socket path is %d bytes and a Unix socket holds %d. Put it under XDG_RUNTIME_DIR: %s"
                % [path.to_utf8_buffer().size(), MAX_PATH_BYTES, path]
            )
        )
        return false
    if FileAccess.file_exists(path):
        # A stale file from a session that did not get to unlink its own, which
        # fails the listen exactly the way a too-long path does.
        DirAccess.remove_absolute(path)
    var server := UDSServer.new()
    var err := server.listen(path)
    if err != OK or not server.is_listening():
        push_error("SaAgentDoor: could not listen on %s (error %d)" % [path, err])
        return false
    var token := Crypto.new().generate_random_bytes(TOKEN_BYTES).hex_encode()
    var beside := path + ".json"
    if not _write_owner_only(beside, {"socket": path, "token": token}, "token file"):
        server.stop()
        DirAccess.remove_absolute(path)
        return false
    _server = server
    _token = token
    socket_path = path
    token_file = beside
    _listening("listening on %s, its token in %s" % [path, beside])
    _write_known({"socket": path, "token": token})
    return true


## Starts listening on TCP at 127.0.0.1, on a port the system picks, and writes
## the port and a fresh token to *file*. False, with a line naming the cause,
## when either half fails, and then nothing is left listening.
##
## A file already at *file* is removed before the listen, so a client waiting
## for the file to appear never reads a port from a session that has gone.
func open_port(file: String) -> bool:
    if file.is_empty():
        return false
    if FileAccess.file_exists(file):
        DirAccess.remove_absolute(file)
    var server := TCPServer.new()
    var err := server.listen(0, LOOPBACK)
    if err != OK or not server.is_listening():
        push_error("SaAgentDoor: could not listen on %s (error %d)" % [LOOPBACK, err])
        return false
    var token := Crypto.new().generate_random_bytes(TOKEN_BYTES).hex_encode()
    if not _write_port_file(file, server.get_local_port(), token):
        server.stop()
        return false
    _server = server
    _token = token
    port = server.get_local_port()
    port_file = file
    _listening("listening on %s:%d, port and token in %s" % [LOOPBACK, port, file])
    _write_known({"port": port, "token": token})
    return true


## What both ways in do once they listen.
func _listening(line: String) -> void:
    _last_request_usec = Time.get_ticks_usec()
    if _verdicts == null:
        _verdicts = SaDoorVerdicts.install()
    if _errors == null:
        _errors = DoorErrors.new()
        DoorErrors.install(_errors)
    SaBootMarks.mark(&"door_listening")
    print("SaAgentDoor: %s" % line)


## Writes `{"port": ..., "token": ...}` to *file*, whole or not at all.
##
## Written beside the file and renamed into place, so a client polling for it
## reads either nothing or all of it. The permissions go to the owner's alone
## before the token is written, where the platform has them. On Windows the
## file inherits its folder's, which is why the door guide
## puts the file in the user's own temporary folder, and the call is not made
## there at all.
static func _write_port_file(file: String, listening_port: int, token: String) -> bool:
    return _write_owner_only(file, {"port": listening_port, "token": token}, "port file")


## Writes *fields* to *file* as one JSON line, whole or not at all, readable by
## the owner alone where the platform has permissions. *what* names the file in
## a failure's line.
static func _write_owner_only(file: String, fields: Dictionary, what: String) -> bool:
    DirAccess.make_dir_recursive_absolute(file.get_base_dir())
    var partial := file + ".partial"
    var handle := FileAccess.open(partial, FileAccess.WRITE)
    if handle == null:
        push_error("SaAgentDoor: could not write the %s %s (%s)" % [what, file, error_string(FileAccess.get_open_error())])
        return false
    if OS.get_name() != "Windows":
        FileAccess.set_unix_permissions(partial, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)
    handle.store_string(JSON.stringify(fields) + "\n")
    handle.close()
    var err := DirAccess.rename_absolute(partial, file)
    if err != OK:
        DirAccess.remove_absolute(partial)
        push_error("SaAgentDoor: could not put the %s in place at %s (error %d)" % [what, file, err])
        return false
    return true


## Writes where this door listens to the known file, with this process's id,
## unless a live Sara other than this one already holds it. The file a client
## attaches through is then always the Sara that opened first, and a second
## Sara says so rather than taking the file from under the first.
func _write_known(where: Dictionary) -> void:
    var holder := KnownFile.live_holder(_known_path)
    if holder > 0:
        print("SaAgentDoor: the known file %s names Sara %d, which runs, so it is left as it is" % [_known_path, holder])
        return
    var fields := where.duplicate()
    fields["pid"] = OS.get_process_id()
    if _write_owner_only(_known_path, fields, "known file"):
        known_file = _known_path
        print("SaAgentDoor: where the door listens is in %s" % ProjectSettings.globalize_path(_known_path))


## Whether the known file still names this door, rather than one opened since.
func _names_this_door() -> bool:
    var held := KnownFile.read(known_file)
    if int(held.get("pid", 0)) != OS.get_process_id():
        return false
    if not socket_path.is_empty():
        return String(held.get("socket", "")) == socket_path
    return int(held.get("port", 0)) == port


## True while the door is up, which is what stops `_finish` quitting the app.
func is_open() -> bool:
    return _server != null


## One frame of the door: take a connection, read what arrived, answer what is
## due. Returns false when the session is over and the app should quit. A request
## runs through *table*, the same executor a scenario file goes through, and a
## shot is looked for in *run*'s folder.
func poll(table: StepTable, run: CaptureRun) -> bool:
    if _server == null:
        return false
    # A hang-up is looked for before a new connection is taken, since `curl`
    # starts its next call within the frame its last one ended in, and that
    # call was refused as a second client while the first still seemed held.
    if _wire != null and not _wire.connected():
        _hung_up()
    _accept()
    _refusals.idle_seconds = idle_timeout
    _refusals.poll()
    if _wire == null:
        return _goes_on_idle()

    if not _pending.is_empty():
        _pending_frames -= 1
        var held := _step_of(_pending)
        var working := (
            ScenarioDocument.still_loading(held) or ScenarioDocument.still_saving(held) or _shot_owed(held, run) or _eyes.owes()
        )
        if _pending_frames <= 0 and not working and drawn_wait.arrived():
            # Named in the frame trace, for the answer to a load that waited
            # reads the stack of the document the load put in.
            var traced := SaFrameTrace.now()
            _answer(table, run)
            SaFrameTrace.spent("door answer", traced)
        return true
    if not _batch.is_empty():
        return _run_batch(table, run)

    _wire.read_available()
    if _wire.opens_wrong():
        var why := "the door speaks HTTP/1.1, POST /step, and the line protocol has retired"
        _wire.send_http(400, {"ok": false, "error": why}, true)
        _drop("a connection that did not open with an HTTP request")
        return true
    return _poll_http(table, run)


## Lets go of a client that has gone and waits for the next, since a client
## closes when it is done, `curl` after every call. A session ends at `quit` or
## at the idle timeout, never at a hang-up.
func _hung_up() -> void:
    if not _trusted:
        _drop("a connection left before its token")
        return
    _drop("the %s client hung up" % ("attached" if _keeps_listening else "HTTP"))


## One frame of the held connection: the next whole request, if one
## has arrived, checked for its token and its route and started.
func _poll_http(table: StepTable, run: CaptureRun) -> bool:
    var request := _wire.take_request()
    if request == null:
        _unheard_too_long()
        return _goes_on_idle()
    if request.status != 0:
        _wire.send_http(request.status, {"ok": false, "error": request.reason, "help": DoorCatalogue.HELP}, true)
        _drop("a request that could not be read, %s" % request.reason)
        return true
    if not _carries_the_token(request):
        return true
    if not _trusted:
        _trust()
    _restart_idle_clock()
    _heard_usec = _last_request_usec
    if request.target == "/" and request.method == "GET":
        # The first thing a client that does not know the door tries.
        _wire.send_http(200, {"ok": true, "help": DoorCatalogue.HELP}, request.closes())
        return true
    if request.target != "/step":
        var elsewhere := {"ok": false, "error": "the door answers POST /step and nothing else", "help": DoorCatalogue.HELP}
        _wire.send_http(404, elsewhere, request.closes())
        return true
    if request.method != "POST":
        var unposted := {"ok": false, "error": "/step takes POST", "help": DoorCatalogue.HELP}
        _wire.send_http(405, unposted, request.closes(), {"Allow": "POST"})
        return true
    # A JSON of its own rather than `parse_string`, which says a bad body as an
    # engine error, and that would turn up in the next answer's errors.
    var json := JSON.new()
    var parsed: Variant = json.data if json.parse(request.body.get_string_from_utf8()) == OK else null
    if not (parsed is Dictionary or parsed is Array):
        var why := "the body is one JSON object, a step, or an array of them"
        var unread := {"ok": false, "error": why, "json": json.get_error_message(), "help": DoorCatalogue.HELP}
        _wire.send_http(400, unread, request.closes())
        return true
    _batch = parsed as Array if parsed is Array else [parsed]
    _batch_answers = []
    _batch_is_array = parsed is Array
    _batch_closes = request.closes()
    if _batch.is_empty():
        _send_batch()
        return true
    return _run_batch(table, run)


## Runs the batch's next step after every ping before it, as one slice since
## a ping wants no frame and a pop each is quadratic. The last stays, so no
## answer goes out early.
func _run_batch(table: StepTable, run: CaptureRun) -> bool:
    var pings := 0
    while pings < _batch.size() and _batch[pings] is Dictionary and DoorWire.is_ping(_batch[pings]):
        pings += 1
    if pings > 1:
        var leading := _batch.slice(0, pings - 1)
        _batch = _batch.slice(pings - 1)
        for ping: Variant in leading:
            _run_request(table, run, ping)
    return _run_request(table, run, _batch.pop_front())


## Whether *request*, whole or only its head, carries the token. One that does
## not is answered 401 and dropped. The answer says where the token is and
## nothing about the steps, and the file is the owner's alone, so naming it
## lets in only whoever could already read it.
func _carries_the_token(request: DoorWire.Request) -> bool:
    if request.carries(_token):
        return true
    var refused := {"ok": false, "error": "the token goes in Authorization: Bearer", "token_file": _token_home()}
    _wire.send_http(401, refused, true, {"WWW-Authenticate": "Bearer"})
    _drop("a request without the token")
    return false


## Closes a connection with no request head in `TOKEN_SECONDS`, so a program
## that says nothing cannot hold the one client slot. A head that is in is
## judged by its token at once, and its body may then take what it needs.
func _unheard_too_long() -> void:
    if _trusted or _wire == null:
        return
    if _wire.waiting_head != null:
        _carries_the_token(_wire.waiting_head)
        return
    var waited := float(Time.get_ticks_usec() - _connected_usec) / 1_000_000.0
    if waited > TOKEN_SECONDS:
        _drop("a connection that sent no token")


## Takes what is waiting to connect. The first becomes the client, trusted once
## a request carries its token, on either way in. Any other while one is held
## is answered with a refusal and closed, because the door serves one client.
func _accept() -> void:
    while _server.is_connection_available():
        var incoming := _server.take_socket_connection()
        if _wire != null:
            _refusals.hold(incoming)
            print("SaAgentDoor: a second connection, held for its answer, the door serves one client")
            continue
        _wire = DoorWire.new(incoming)
        connections += 1
        _connected_usec = Time.get_ticks_usec()
        _trusted = false


## The held connection is the client from here on.
func _trust() -> void:
    _trusted = true
    # A client that attaches after another went idle gets the whole timeout.
    _restart_idle_clock()
    # From the log's end rather than from the first answer, so a session does
    # not open with the whole of startup in its first `printed`.
    _log.start_at_the_end()
    # And the errors of startup are not the first answer's either.
    if _errors != null:
        _errors.take()
    print("SaAgentDoor: client connected")


## Closes the held connection without a word to it and goes back to listening.
func _drop(why: String) -> void:
    _wire.close()
    _wire = null
    _trusted = false
    # A step the client left behind still ran, and its answer has nobody to
    # go to, so it is not sent to the next client in its place. Nor are the
    # steps of its batch that had not run yet.
    _pending = {}
    _batch = []
    _batch_answers = []
    _leave_request()
    print("SaAgentDoor: %s, closed" % why)


## Runs one request, one step of an HTTP body. False ends the
## session. Anything but a JSON object is refused, which ends a batch.
func _run_request(table: StepTable, run: CaptureRun, given: Variant) -> bool:
    if not (given is Dictionary):
        _reply({"ok": false, "error": "a step is one JSON object", "step": given, "help": DoorCatalogue.HELP})
        return true
    var request := given as Dictionary
    if bool(request.get("quit", false)):
        _reply({"id": request.get("id", null), "ok": true, "quit": true})
        return false
    if bool(request.get("attach", false)):
        # Said by the first request of a client that found a Sara already
        # open. From here on a hang-up or the idle timeout drops the client
        # and the door waits for the next, whoever started this Sara.
        _keeps_listening = true
        _reply({"id": request.get("id", null), "ok": true, "attached": true})
        return true
    if request.has("ping"):
        # The clock was reset when the request was read, so a ping answers at once.
        table.run({"ping": request["ping"]})
        _reply({"id": request.get("id", null), "ok": true, "ping": true, "connections": connections})
        return true

    if request.has("steps"):
        # The step kinds, from the build's packed catalogue or the checkout's
        # source, answered at once and without a dump, since nothing ran. The
        # table has no `steps` kind, so the key cannot shadow one.
        var listed := _catalogue.answer(request["steps"])
        listed["id"] = request.get("id", null)
        _reply(listed)
        return true

    # A step with no kind the table knows, or its argument the wrong shape, is
    # refused with help before it runs, where the table would only warn.
    var refused := _catalogue.refusal(_step_of(request))
    if not refused.is_empty():
        refused["id"] = request.get("id", null)
        _reply(refused)
        return true

    if _eyes.begins(request, _batch):
        return bool(_eyes.as_one(_run_request.bind(table, run, request)))
    _pending = request
    _pending_frames = _eyes.settle(request, _batch, DEFAULT_SETTLE_FRAMES)
    drawn_wait.begin(run.tree().root if run.tree() != null else null)
    changes.step_begins()
    run.painter_changes = changes.count
    # What was printed between two requests is nobody's verdict, a painter's
    # own work in an attached Sara above all.
    _take_verdicts()

    var step := _step_of(request)
    if not step.is_empty():
        _request_ticket = SaTrail.enter("the door request %s" % String(step.keys()[0]))
    # A request of `{"id": 1}` alone runs nothing and answers where the view
    # stands, and with `"dump": true` it is the dump and nothing else, which
    # needs no step kind of its own.
    if not step.is_empty():
        # Named in the frame trace, which otherwise counts a slow step among
        # the frame's unnamed rest, as the nights file's opacity step was.
        var traced := SaFrameTrace.now()
        table.run(ScenarioDocument.as_the_door_runs(step))
        SaFrameTrace.spent("door step %s" % String(step.keys()[0]), traced)
    _eyes.after(request, _batch)
    var working := (
        ScenarioDocument.still_loading(step) or ScenarioDocument.still_saving(step) or _shot_owed(step, run) or _eyes.owes()
    )
    if _pending_frames == 0 and not working:
        # `"settle": 0` is answered in the frame the step ran, for a step whose
        # verdict is printed before it returns. A pixel write is one, and the
        # default's two frames would slow every write of a NumPy slider's drag.
        # A shot `SaShotSettle` held back is not, and waits for its picture.
        _answer(table, run)
        if SaDoorEyeRun.runs_on(request, _batch):
            return _run_request(table, run, _batch.pop_front())
    return true


## The file the token is in, beside the socket or the port file.
func _token_home() -> String:
    return token_file if not token_file.is_empty() else port_file


## Whether *step* is a shot the run still owes, held back by `SaShotSettle`
## for a later frame. Its answer waits for the picture however few frames the
## request asked to settle, or a client reads the canvas before the change, or
## the picture an earlier shot of the same name left.
static func _shot_owed(step: Dictionary, run: CaptureRun) -> bool:
    return step.has("shot") and run.last_shot.has("owed")


## *request* without the door's own keys, which is the step the table runs.
static func _step_of(request: Dictionary) -> Dictionary:
    var step := request.duplicate()
    for key in REQUEST_KEYS:
        step.erase(key)
    return step


## The verdict lines printed since the last take, or none when the door is not
## listening.
func _take_verdicts() -> Array:
    return Array(_verdicts.take()) if _verdicts != null else []


## Sends the answer for the step that has finished settling: the compact one,
## with the dump of old beside it when the request set `dump`.
func _answer(table: StepTable, run: CaptureRun) -> void:
    var request := _pending
    _pending = {}
    var step := _step_of(request)
    # Assigned rather than written as a ternary in the literal: a String and a
    # null are not mutually compatible and the language server says so.
    var shot: Variant = null
    if step.has("shot") and String(run.last_shot.get("path", "")) == run.shot_file(String(step["shot"])):
        # The file this shot wrote, never one of the same name an earlier shot
        # left. The machine's own path, for a client that opens the file
        # itself: with no `--capture-out` the folder is `user://captures` and
        # only Godot reads that.
        shot = ProjectSettings.globalize_path(String(run.last_shot["path"]))
    var verdicts := _take_verdicts()
    var raised := DoorLog.raised_in(_errors.take() if _errors != null else {})
    var answer := {
        "id": request.get("id", null),
        "ok": true,
        "verdicts": verdicts,
        "view": SaDoorGlance.view_line(),
        "shot": shot,
        "errors": raised["errors"],
        "warnings": raised["warnings"],
    }
    drawn_wait.stamp(answer, step)
    changes.stamp(answer)
    if step.has("errors"):
        # The step's verdict lines say it in text, and this is the same whole,
        # for a client that reads the entries as JSON.
        answer["entries"] = DoorErrors.session_entries(DoorErrors.level_of(step["errors"]))
    if step.has("save"):
        answer["save"] = run.last_save
    if step.has("load"):
        answer["load"] = run.last_load
        answer["verdicts"] = _load_lines_first(verdicts, run.last_load.get("lines", []) as Array)
        if run.last_load.has("error"):
            answer["ok"] = false
            answer["error"] = run.last_load["error"]
    if step.has("export"):
        answer["export"] = run.last_export
        # A step that wrote no file is no success, whatever else it did.
        if run.last_export.has("error"):
            answer["ok"] = false
            answer["error"] = run.last_export["error"]
    if step.has("shot") and run.last_shot.has("error"):
        # A shot that wrote no file is no success, as an export that wrote none.
        answer["ok"] = false
        answer["error"] = run.last_shot["error"]
    if step.has("usage") and SaUsageTally.current != null:
        answer["usage"] = SaUsageTally.current.report()
    if bool(request.get("dump", false)):
        answer["step"] = step
        answer["printed"] = _log.printed_since()
        answer["state"] = table.state()
        answer["frames"] = int(request.get("settle", DEFAULT_SETTLE_FRAMES))
    _reply(answer)
    _leave_request()
    SaCanvas.after_door_step(run.tree().root if run.tree() != null else null)


## *verdicts* opened with *lines*, the lines a `load` printed, each once and
## the loaded line first, so the answer holds them however the log handed
## them over. The painter's door once answered the recovery copy's line alone.
static func _load_lines_first(verdicts: Array, lines: Array) -> Array:
    var out := lines.duplicate()
    for line: Variant in verdicts:
        if not out.has(line):
            out.append(line)
    return out


## Gives back the place the request being served entered, which is where a
## stall while it runs or settles is. A request that entered none, a ping or a
## dump, gives back nothing.
func _leave_request() -> void:
    SaTrail.give_back(_request_ticket)
    _request_ticket = SaTrail.NOTED


## Answers the request just finished with its place in the batch's answer,
## which goes out when the batch is over. A refused step, or a `quit`, is the
## batch's last. Every answer names the dialogs standing over the canvas here,
## the catalogue's and a ping's as well as a step's.
func _reply(answer: Dictionary) -> void:
    if _wire == null:
        return
    _eyes.name_dialogs(answer, (Engine.get_main_loop() as SceneTree).root)
    _batch_answers.append(answer)
    if not bool(answer.get("ok", false)) or bool(answer.get("quit", false)):
        _batch = []
    if _batch.is_empty():
        _send_batch()


## Sends the answer of the HTTP request being served, an array for an array,
## and closes the connection after it when the request asked.
func _send_batch() -> void:
    var body: Variant = _batch_answers if _batch_is_array else _batch_answers[0]
    _batch_answers = []
    _wire.send_http(200, body, _batch_closes)
    if _batch_closes:
        _drop("an HTTP client that asked for the connection to close")


func _restart_idle_clock() -> void:
    _last_request_usec = Time.get_ticks_usec()
    _warned = false


## Whether the session goes on after this frame's idle check. A launched
## session ends at the timeout. An attach door drops the client it holds and
## goes on, and with no client it has nothing to time out.
##
## A warning comes first, a minute before the timeout or half of it when the
## timeout is shorter, which a launched client reads off the pipe in its next
## answer and an attached one in the door's log.
func _goes_on_idle() -> bool:
    if idle_timeout <= 0.0:
        return true
    _lets_the_lock_go()
    if _keeps_listening and _wire == null:
        _restart_idle_clock()
        return true
    var idle := float(Time.get_ticks_usec() - _last_request_usec) / 1_000_000.0
    var warn_at := idle_timeout - minf(WARN_BEFORE, idle_timeout / 2.0)
    var what := "dropping the client" if _keeps_listening else "closing"
    if idle >= warn_at and not _warned:
        _warned = true
        push_warning("SaAgentDoor: no request for %.1f seconds, %s in %.1f unless one comes" % [idle, what, idle_timeout - idle])
    if idle < idle_timeout:
        return true
    if _keeps_listening:
        _drop("no request for %.1f seconds from the attached client" % idle)
        _restart_idle_clock()
        return true
    push_warning("SaAgentDoor: no request for %.1f seconds, closing" % idle)
    return false


## Lets the lock on the system's pointer go once no request has come for the
## idle timeout. A notebook hangs up two seconds after each call and attaches
## again at the next, so a hang-up is not the notebook going away, and an
## attached door restarts its own idle clock while nobody is connected. A
## client that took the lock and was never heard again leaves the painter's
## mouse dead for the timeout and no longer.
func _lets_the_lock_go() -> void:
    if not SaCursorPolicy.system_pointer_locked or _heard_usec == 0:
        return
    var idle := float(Time.get_ticks_usec() - _heard_usec) / 1_000_000.0
    if idle < idle_timeout:
        return
    var dropped := SaCursorPolicy.unlock_system_pointer()
    print("SaAgentDoor: no request for %.1f seconds, the cursor lock let go after dropping %d events" % [idle, dropped])


## Unlinks the socket, or removes the port file. A socket file left at the path
## fails the next listen, and a port file left behind names a port nothing
## answers on.
func close() -> void:
    # A closed door has no hand left to drive, so the painter's comes back.
    SaCursorPolicy.unlock_system_pointer()
    _refusals.close()
    if _wire != null:
        _wire.close()
        _wire = null
    if _server != null:
        _server.stop()
        _server = null
    if _verdicts != null:
        SaDoorVerdicts.uninstall(_verdicts)
        _verdicts = null
    if _errors != null:
        DoorErrors.uninstall(_errors)
        _errors = null
    # The known file only while it still names this door, since a Sara opened
    # after this one may hold it by now. Before the port file, which can be the
    # same file and would then take the proof with it.
    if not known_file.is_empty() and _names_this_door():
        DirAccess.remove_absolute(known_file)
    known_file = ""
    for path: String in [socket_path, port_file, token_file]:
        if not path.is_empty() and FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)
    socket_path = ""
    port_file = ""
    token_file = ""
    port = 0
    _token = ""
