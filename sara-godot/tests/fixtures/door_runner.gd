## The door's runner in a suite: one frame of the app as the door sees it,
## the client that connects over TCP, and the request that waits for its
## answer, for every suite that opens the door in its own process.
##
## Twenty-two suites each wrote `_read`, `_frame` and `_connect` by hand, and
## the copies had drifted apart in their ports, rounds and extras. A suite
## builds one of these in `before_each` from the door, the table and the run
## it made, and `rg DoorRunner` lists them.
extends RefCounted

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")

## Rounds of polling before a wait gives up, a few milliseconds each.
const ROUNDS: int = 400

## The door the suite opened.
var door: AgentDoor
## The executor a request runs through.
var table: StepTable
## The run whose steps a frame plays and whose folder a shot is looked for in.
var run: CaptureRun
## The rounds a connection and an answer are waited for.
var rounds: int
## The known file the door writes its port and token to, or empty when the
## door was opened without one and its port is read off the door.
var known: String

## What the suite does in every frame before the runner's part, or nothing.
var _before: Callable
## What the suite does in every frame after the runner's part, or nothing.
var _after: Callable


func _init(
    the_door: AgentDoor,
    the_table: StepTable,
    the_run: CaptureRun,
    the_rounds: int = ROUNDS,
    the_known: String = "",
    before: Callable = Callable(),
    after: Callable = Callable(),
) -> void:
    door = the_door
    table = the_table
    run = the_run
    rounds = the_rounds
    known = the_known
    _before = before
    _after = after


## The JSON object in *file*, or {} when it is missing or not an object.
static func read(file: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
    return parsed as Dictionary if parsed is Dictionary else {}


## One frame of the runner: a wait counted down, the run's next step played,
## or the door polled, with the suite's own parts around it.
func frame() -> void:
    if _before.is_valid():
        _before.call()
    if run.wait_frames > 0:
        run.wait_frames -= 1
    elif run.step_index < run.steps.size():
        var step: Dictionary = run.steps[run.step_index] as Dictionary
        run.step_index += 1
        table.run(step)
    else:
        door.poll(table, run)
    # The tree turns a background save and an export over frames each frame in
    # the app, and no frame is drawn in a suite.
    SaSadSave.turn()
    SaExportInTurns.turn()
    if _after.is_valid():
        _after.call()


## The port the door listens on, from the known file when there is one.
func port() -> int:
    return door.port if known.is_empty() else int(read(known).get("port", 0))


## The token the known file holds, or empty when there is no known file.
func token() -> String:
    return "" if known.is_empty() else String(read(known).get("token", ""))


## A client connected to the door's port, frames run while it connects.
func connect_client() -> StreamPeerTCP:
    var client := StreamPeerTCP.new()
    client.connect_to_host(AgentDoor.LOOPBACK, port())
    for _i in rounds:
        client.poll()
        frame()
        if client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
            break
        OS.delay_msec(2)
    return client


## Sends *request* on *client* with the known file's token and waits for the
## answer, as `Fixtures.DoorHttp.ask` reads it.
func ask(client: StreamPeerSocket, request: Variant) -> Dictionary:
    return Fixtures.DoorHttp.ask(client, request, token(), frame, rounds)
