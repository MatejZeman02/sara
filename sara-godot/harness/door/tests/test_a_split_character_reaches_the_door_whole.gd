## A character cut between two reads reaches the door whole.
##
## A door that decodes each read on its own would break a request naming a layer
## "Vrstva č. 2" whose "č" the kernel split across two reads came out with two
## replacement characters in its place. These cases open the TCP way in, send
## an HTTP request in two writes cut inside that character or its token, poll the door between
## them so it reads the first half alone, and look at the step the table got.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_port_file: String = SaDataRoot.path("d13-door.port")
## A layer's name, sent as a `comment` step, a kind the table knows and takes
## a string, since the door refuses a step it has no kind for before the table.
const NAME := "Vrstva č. 2"

## Rounds of polling both ends before a case gives up, a few milliseconds each.
const ROUNDS: int = 400


## The executor's place, keeping every step rather than running it.
class RecordingTable:
    extends StepTable

    var ran: Array = []

    func _init() -> void:
        super(CaptureRun.new(SaDataRoot.path("d13-door-run")))

    func run(step: Dictionary) -> void:
        ran.append(step)


var _door: AgentDoor = null
var _table: RecordingTable = null
var _run: CaptureRun = null
var _runner: DoorRunner = null


func before_each() -> void:
    _door = AgentDoor.new()
    _table = RecordingTable.new()
    _run = CaptureRun.new(SaDataRoot.path("d13-door-run"))
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_port_file)


func after_each() -> void:
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null


## Sends *bytes* and polls the door until it has read them, so the next write
## arrives in a read of its own.
func _write_and_let_read(client: StreamPeerTCP, bytes: PackedByteArray) -> void:
    client.put_data(bytes)
    for _i in 20:
        client.poll()
        _runner.frame()
        OS.delay_msec(2)


## Polls both ends until the door answers, and returns the answer's JSON.
func _wait_for_answer(client: StreamPeerTCP) -> Dictionary:
    var answer := Fixtures.DoorHttp.wait(client, _runner.frame)
    var body: Variant = answer.get("body")
    return body as Dictionary if body is Dictionary else answer


## Where in *bytes* the first character of more than one byte begins.
func _first_wide_character(bytes: PackedByteArray) -> int:
    for i in bytes.size():
        if bytes[i] >= 0x80:
            return i
    return -1


func test_a_name_cut_inside_a_character_reaches_the_step_whole() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var request := Fixtures.DoorHttp.request(JSON.stringify({"id": 4, "comment": NAME}), _runner.token())
    var cut := _first_wide_character(request) + 1
    assert_true(cut > 0, "The request holds a character of two bytes")
    _write_and_let_read(client, request.slice(0, cut))
    assert_true(_table.ran.is_empty(), "Half a request runs nothing")
    client.put_data(request.slice(cut))
    var answer := _wait_for_answer(client)
    assert_eq(answer.get("id"), 4.0, "The request cut inside a character is answered")
    assert_true(bool(answer.get("ok", false)), "as JSON, not refused")
    assert_eq(_table.ran, [{"comment": NAME}], "and the step carries the name whole")
    client.disconnect_from_host()


func test_a_token_cut_in_two_writes_is_still_the_token() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var request := Fixtures.DoorHttp.request(JSON.stringify({"id": 5, "comment": NAME}), _runner.token())
    var in_token := request.get_string_from_utf8().find("Bearer ") + 7 + 10
    _write_and_let_read(client, request.slice(0, in_token))
    assert_true(_door.is_open(), "Half a token keeps the connection waiting")
    assert_true(_table.ran.is_empty(), "and runs nothing")
    client.put_data(request.slice(in_token))
    var answer := _wait_for_answer(client)
    assert_eq(answer.get("id"), 5.0, "The token read in two pieces lets the client in")
    assert_eq(_table.ran, [{"comment": NAME}], "and its step carries the name whole")
    client.disconnect_from_host()
