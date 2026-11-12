## The door's TCP way in, forced on Linux.
##
## Windows has no Unix socket for Godot to listen on, so a door started with
## `--agent-port-file` listens on 127.0.0.1 with a token instead, which every
## HTTP request carries. A client of the retired line protocol, which opened
## with the token as a line of its own, is refused. Nothing here
## needs Windows: the TCP way in is the same code on every platform, and these
## cases open it in this process, connect to it with a `StreamPeerTCP` and
## drive both ends by hand until an answer or a close arrives.
##
## The step goes through a table that records it rather than running it,
## because what is under test is the wire and the token, and the table behind
## it is the one every scenario already runs. `scripts/test_door.py` has the
## same cases end to end, against a real Sara whose steps do run.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_port_file: String = SaDataRoot.path("w1-door.port")

## Rounds of polling both ends before a case gives up on what it waits for,
## a few milliseconds each.
const ROUNDS: int = 400


## The executor's place, with every step kept rather than run and a dump that
## says how many there were.
class RecordingTable:
    extends StepTable

    var ran: Array = []

    func _init() -> void:
        super(CaptureRun.new(SaDataRoot.path("w1-door-run")))

    func run(step: Dictionary) -> void:
        ran.append(step)

    func state() -> Dictionary:
        return {"steps_run": ran.size()}


var _door: AgentDoor = null
var _table: RecordingTable = null
var _run: CaptureRun = null
var _runner: DoorRunner = null


func before_each() -> void:
    _door = AgentDoor.new()
    _table = RecordingTable.new()
    _run = CaptureRun.new(SaDataRoot.path("w1-door-run"))
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS)


func after_each() -> void:
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null


## The port file as the door wrote it.
func _port_file() -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(scratch_port_file))
    return parsed as Dictionary if parsed is Dictionary else {}


## The token the door wrote.
func _token() -> String:
    return String(_port_file().get("token", ""))


## The answer to *step* sent with *token*, the door's own when null.
func _ask(client: StreamPeerTCP, step: Variant, token: Variant = null) -> Dictionary:
    var bearer := _token() if token == null else String(token)
    return Fixtures.DoorHttp.ask(client, step, bearer, _runner.frame)


## Polls both ends until *client* is closed, and says whether it was, every
## byte that came gathered in *received*.
func _wait_for_close(client: StreamPeerTCP, received: PackedByteArray) -> bool:
    for _i in ROUNDS:
        _runner.frame()
        client.poll()
        # A closed peer has no bytes to ask about, and asking is an engine error.
        if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
            return true
        var available := client.get_available_bytes()
        if available > 0:
            var got: Array = client.get_data(available)
            received.append_array(got[1])
            client.poll()
            if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
                return true
        OS.delay_msec(2)
    return false


func test_the_port_file_names_a_loopback_port_and_a_token() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var written := _port_file()
    assert_eq(int(written.get("port", 0)), _door.port, "The file names the port the door listens on")
    assert_true(_door.port > 0, "which the system picked")
    var token := String(written.get("token", ""))
    assert_eq(token.length(), AgentDoor.TOKEN_BYTES * 2, "The token is the hex of its random bytes")
    var again := AgentDoor.new()
    assert_true(again.open_port(SaDataRoot.path("w1-door-again.port")), "A second door opens beside the first")
    var second_token := String(
        (JSON.parse_string(FileAccess.get_file_as_string(SaDataRoot.path("w1-door-again.port"))) as Dictionary).get("token", "")
    )
    assert_true(second_token != token, "and writes a token of its own")
    again.close()


func test_a_step_with_the_token_is_answered() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var answer := _ask(client, {"id": 7, "zoom": 2.0, "dump": true})
    assert_eq(answer.get("status"), 200, "The request is answered")
    assert_eq(answer.get("id"), 7.0, "The answer is to the request that was sent")
    assert_true(bool(answer.get("ok", false)), "and it worked")
    assert_eq(_table.ran, [{"zoom": 2.0}], "The step reached the executor, without the door's own keys")
    assert_eq((answer.get("state", {}) as Dictionary).get("steps_run"), 1.0, "The dump, asked for, is the table's")
    client.disconnect_from_host()


func test_a_wrong_token_is_refused_and_closed_and_the_door_listens_on() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var stranger := _runner.connect_client()
    var refused := _ask(stranger, {"id": 1, "zoom": 3.0}, "0".repeat(AgentDoor.TOKEN_BYTES * 2))
    assert_eq(refused.get("status"), 401, "A request with a wrong token is refused")
    assert_true(_wait_for_close(stranger, PackedByteArray()), "and its connection closed")
    assert_true(_table.ran.is_empty(), "and its step never ran")
    assert_true(_door.is_open(), "The door is still up")

    var client := _runner.connect_client()
    assert_eq(_ask(client, {"id": 2}).get("id"), 2.0, "and answers the client with the token")
    client.disconnect_from_host()


func test_the_old_token_line_is_refused_and_closed() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var old := _runner.connect_client()
    old.put_data(("%s\n%s\n" % [_token(), JSON.stringify({"id": 1, "zoom": 3.0})]).to_utf8_buffer())
    var heard := PackedByteArray()
    assert_true(_wait_for_close(old, heard), "A connection that opens with the old token line is closed")
    var answer := Fixtures.DoorHttp.parse(heard)
    assert_eq(answer.get("status"), 400, "with a 400 that says why: %s" % heard.get_string_from_utf8())
    assert_true(String((answer.get("body", {}) as Dictionary).get("error", "")).contains("HTTP"), "naming HTTP")
    assert_true(_table.ran.is_empty(), "Its step never ran")
    assert_true(_door.is_open(), "and the door is still up")

    var client := _runner.connect_client()
    assert_eq(_ask(client, {"id": 2}).get("id"), 2.0, "The next client is answered")
    client.disconnect_from_host()


func test_a_second_connection_is_answered_and_closed_while_the_client_stays() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    assert_eq(_ask(client, {"id": 1, "zoom": 2.0}).get("id"), 1.0, "The client with the token is answered")

    var stranger := _runner.connect_client()
    stranger.put_data(Fixtures.DoorHttp.request(JSON.stringify({"id": 9, "zoom": 5.0}), "not the token"))
    var heard := PackedByteArray()
    assert_true(_wait_for_close(stranger, heard), "A second connection is closed")
    var answer := Fixtures.DoorHttp.parse(heard)
    assert_eq(answer.get("status"), 409, "after an answer of 409: %s" % heard.get_string_from_utf8())
    var why := String((answer.get("body", {}) as Dictionary).get("error", ""))
    assert_true(why.contains("another notebook or script is connected"), "that names the other client: %s" % why)
    assert_true(why.contains("frees the door"), "and how to free the door")

    assert_eq(_ask(client, {"id": 3}).get("id"), 3.0, "and the first is still answered")
    assert_eq(_table.ran, [{"zoom": 2.0}], "Only the client's step ran")
    client.disconnect_from_host()


func test_a_connection_that_leaves_before_its_token_ends_nothing() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var stranger := _runner.connect_client()
    stranger.disconnect_from_host()
    for _i in 20:
        assert_true(_door.poll(_table, _run), "The session goes on")
        OS.delay_msec(2)
    var client := _runner.connect_client()
    assert_eq(_ask(client, {"id": 4}).get("id"), 4.0, "and answers the next connection with the token")
    client.disconnect_from_host()


func test_closing_removes_the_port_file() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    assert_true(FileAccess.file_exists(scratch_port_file), "and wrote its file")
    _door.close()
    assert_false(FileAccess.file_exists(scratch_port_file), "which closing removes")
    assert_false(_door.is_open(), "and the door is shut")


func test_the_command_line_opens_the_tcp_way_in() -> void:
    var args := PackedStringArray(["--agent-port-file=%s" % ProjectSettings.globalize_path(scratch_port_file)])
    assert_true(AgentDoor.asked_for(args), "The port file asks for a door")
    assert_true(SaBoot.capture_requested(args), "and so the boot builds the capture node for it")
    assert_false(SaBoot.capture_requested(PackedStringArray(["--agent-port-file="])), "but not with no file named")
    var door := AgentDoor.from_command_line(args)
    assert_not_null(door, "The door opens from the command line")
    assert_true(door.port > 0, "on TCP")
    assert_true(door.socket_path.is_empty(), "and not on a Unix socket")
    door.close()
    assert_null(AgentDoor.from_command_line(PackedStringArray(["--capture"])), "No door without either argument")
