## The known file, and a client that attaches to a Sara already
## open rather than launching one.
##
## The door is opened in this process with a known file of the suite's own, so
## no case touches the real one, and both ends are driven by hand the way
## `test_door_on_tcp.gd` drives them. What is under test is what a hang-up
## and the idle timeout do to a session, so the table records steps rather than
## running them. `scripts/test_door_attach.py` has the same story against a
## real Sara whose steps do run.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("p1-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("p1-door/door.port")

## Rounds of polling both ends before a case gives up on what it waits for,
## a few milliseconds each.
const ROUNDS: int = 400

## An idle timeout short enough to wait out in a suite.
const SHORT_IDLE: float = 0.3


## The executor's place, with every step kept rather than run.
class RecordingTable:
    extends StepTable

    var ran: Array = []

    func _init() -> void:
        super(CaptureRun.new(SaDataRoot.path("p1-door-run")))

    func run(step: Dictionary) -> void:
        ran.append(step)

    func state() -> Dictionary:
        return {"steps_run": ran.size()}


var _door: AgentDoor = null
var _table: RecordingTable = null
var _run: CaptureRun = null
var _runner: DoorRunner = null


func before_each() -> void:
    _door = AgentDoor.new(scratch_known)
    _table = RecordingTable.new()
    _run = CaptureRun.new(SaDataRoot.path("p1-door-run"))
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known)


func after_each() -> void:
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null


## A client connected and attached, having read the door's answer to it.
func _attach(id: int) -> StreamPeerTCP:
    var client := _runner.connect_client()
    var answer := _ask(client, {"id": id, "attach": true})
    assert_true(bool(answer.get("attached", false)), "The door answers an attach as one: %s" % answer)
    return client


## The answer to *request*, parsed, or `{"closed": true}` for a close.
func _ask(client: StreamPeerTCP, request: Dictionary) -> Dictionary:
    return _runner.ask(client, request)


## Polls the door for *seconds*, and answers false as soon as a poll ends the
## session.
func _poll_for(seconds: float) -> bool:
    var until := Time.get_ticks_msec() + int(seconds * 1000.0)
    while Time.get_ticks_msec() < until:
        if not _door.poll(_table, _run):
            return false
        OS.delay_msec(5)
    return true


func test_the_known_file_says_where_the_door_listens_and_goes_on_close() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var known := DoorRunner.read(scratch_known)
    assert_eq(int(known.get("port", 0)), _door.port, "The known file names the port")
    assert_eq(String(known.get("token", "")), String(DoorRunner.read(scratch_port_file).get("token", "")), "and the token")
    assert_eq(int(known.get("pid", 0)), OS.get_process_id(), "and the Sara that listens")
    assert_eq(_door.known_file, scratch_known, "The door says where it wrote it")
    _door.close()
    assert_false(FileAccess.file_exists(scratch_known), "Closing removes the known file")


func test_a_unix_socket_is_named_in_the_known_file() -> void:
    if OS.get_name() == "Windows":
        return
    var runtime := OS.get_environment("XDG_RUNTIME_DIR")
    var path := (runtime if not runtime.is_empty() else "/tmp").path_join("sara-p1-%d.sock" % OS.get_process_id())
    assert_true(_door.open(path), "The Unix way in opens")
    assert_eq(String(DoorRunner.read(scratch_known).get("socket", "")), path, "and the known file names its path")
    _door.close()
    assert_false(FileAccess.file_exists(scratch_known), "which closing removes")


func test_a_hang_up_after_an_attach_leaves_the_door_open_for_the_next() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var first := _attach(1)
    assert_eq(_ask(first, {"id": 2, "zoom": 2.0}).get("id"), 2.0, "The attached client is answered")
    first.disconnect_from_host()
    assert_true(_poll_for(0.1), "Its hang-up does not end the session")
    assert_true(_door.is_open(), "and the door is still up")
    assert_true(FileAccess.file_exists(scratch_known), "with its known file")

    var second := _attach(3)
    var answer := _ask(second, {"id": 4, "dump": true})
    assert_eq(answer.get("id"), 4.0, "A second client attaches and is answered")
    assert_eq((answer.get("state", {}) as Dictionary).get("steps_run"), 1.0, "by the same session")
    second.disconnect_from_host()
    _door.close()
    assert_false(FileAccess.file_exists(scratch_known), "The known file goes with the door")


func test_an_idle_attached_client_is_dropped_and_the_door_listens_on() -> void:
    _door.idle_timeout = SHORT_IDLE
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _attach(1)
    assert_true(_poll_for(SHORT_IDLE * 2.0), "The idle timeout does not end an attach session")
    client.poll()
    assert_true(client.get_status() != StreamPeerTCP.STATUS_CONNECTED, "but the idle client is dropped")
    assert_true(_door.is_open(), "The door still listens")
    var next := _attach(2)
    assert_eq(_ask(next, {"id": 3}).get("id"), 3.0, "and answers the next client")
    next.disconnect_from_host()


func test_a_launched_session_still_ends_at_the_idle_timeout() -> void:
    _door.idle_timeout = SHORT_IDLE
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    assert_eq(_ask(client, {"id": 1}).get("id"), 1.0, "A client that did not attach is answered")
    assert_false(_poll_for(SHORT_IDLE * 3.0), "and the idle timeout ends its session")
    client.disconnect_from_host()


func test_a_launched_session_outlives_its_client_and_ends_at_quit() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    assert_eq(_ask(client, {"id": 1}).get("id"), 1.0, "A client that did not attach is answered")
    client.disconnect_from_host()
    assert_true(_poll_for(0.2), "and its leaving does not end the session, as `curl` leaves after every call")
    var next := _runner.connect_client()
    var token := String(DoorRunner.read(scratch_known).get("token", ""))
    next.put_data(Fixtures.DoorHttp.request(JSON.stringify({"id": 2, "quit": true}), token))
    assert_false(_poll_for(0.5), "A quit from the next client ends it")
    var answer := Fixtures.DoorHttp.wait(next, func() -> void: pass)
    assert_true(bool((answer.get("body", {}) as Dictionary).get("quit", false)), "and is answered first: %s" % answer)


func test_a_ping_answers_at_once_and_holds_the_idle_close_off() -> void:
    _door.idle_timeout = SHORT_IDLE * 2.0
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    for i in 4:
        assert_true(_poll_for(SHORT_IDLE), "The session is alive after %d pings" % i)
        var answer := _ask(client, {"id": i, "ping": true})
        assert_true(bool(answer.get("ping", false)), "A ping is answered as one")
        assert_false(answer.has("state"), "and with no dump")
    assert_eq(_table.ran, [{"ping": true}, {"ping": true}, {"ping": true}, {"ping": true}], "Each went through the table")
    client.disconnect_from_host()


func test_a_file_left_by_a_sara_that_is_gone_is_written_over() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_known.get_base_dir())
    var stale := FileAccess.open(scratch_known, FileAccess.WRITE)
    # A process id no system hands out, which is what a crashed Sara's is by
    # the time anyone reads its file.
    stale.store_string(JSON.stringify({"port": 1, "token": "gone", "pid": 2147483000}))
    stale.close()
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    assert_eq(int(DoorRunner.read(scratch_known).get("port", 0)), _door.port, "and takes the known file from a Sara that is gone")


func test_the_command_line_asks_for_an_attach_door() -> void:
    var args := PackedStringArray(["--agent-door"])
    assert_true(AgentDoor.asked_for(args), "--agent-door asks for a door")
    assert_true(SaBoot.capture_requested(args), "and so the boot builds the capture node for it")
