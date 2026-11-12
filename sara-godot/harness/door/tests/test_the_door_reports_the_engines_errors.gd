## The door reports the engine's errors from a logger inside Sara.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The errors and warnings of an answer were read out of the run log, which the
## engine buffers. These open the door in this process over TCP, as
## `test_the_door_answers_in_verdict_lines.gd` does, run real steps through a
## real step table, and read the errors off the answer with the run log moved
## aside, so nothing in the answer could have come from it.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const DoorLog := preload("res://harness/door/sa_door_log.gd")
const DoorErrors := preload("res://harness/report/sa_door_errors.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("q6-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("q6-door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("q6-door-run")

## A file that opens as a PNG and holds no picture, which the engine's own PNG
## loader reports as an error when the `import` step asks for it. A file whose
## first bytes match no format is refused by Sara before any loader, and so is
## a file that is not there. A refusal is a
## warning, so neither stands for an error of the engine's.
static var no_picture: String = SaDataRoot.path("q6-door/no-picture.png")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 600

## Frames an answer is held back while `_runner.frame` raises the same error in each.
const NAG_FRAMES: int = 30

var _host: Node = null
var _canvas: SaCanvas = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
## Whether `_runner.frame` raises the repeated error, for the case that counts it.
var _nagging: bool = false

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "Q6DoorTestHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(640, 480)
    _host.add_child(_canvas)
    _canvas.size = Vector2(640, 480)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known, _nag_when_asked)
    _front = Fixtures.FrontDocuments.over(_canvas)
    _nagging = false
    _write_no_picture()


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null
    if _host != null:
        _host.free()
        _host = null
        _canvas = null


## Writes [member no_picture], the PNG signature and a sentence where the
## header should be.
static func _write_no_picture() -> void:
    DirAccess.make_dir_recursive_absolute(no_picture.get_base_dir())
    var file := FileAccess.open(no_picture, FileAccess.WRITE)
    file.store_buffer(PackedByteArray(SaImageImport.PNG_SIGNATURE))
    file.store_string("This is no picture.")
    file.close()


## The same warning from the same line, which is what an engine message
## repeated every frame looks like to a logger.
func _nag() -> void:
    push_warning("q6: the same warning every frame")


## The suite's part of each frame, a nag while a test asks for one.
func _nag_when_asked() -> void:
    if _nagging:
        _nag()


func _ask(client: StreamPeerTCP, request: Dictionary) -> Dictionary:
    return _runner.ask(client, request)


## The first line of *lines* that holds *text*, or "".
static func _holding(lines: Variant, text: String) -> String:
    for line: Variant in lines if lines is Array else []:
        if String(line).contains(text):
            return String(line)
    return ""


## The case that matters: a step makes the engine report an error, and
## the answer to that step holds it with its function, file and line, while
## the run log is somewhere the door has never been told of.
##
## Windows will not rename a file another handle holds open, and the engine
## holds its log open for the whole run, so there the error is asked for with
## the log in place and the suite's line says so.
func test_an_error_arrives_in_the_answer_with_its_origin_and_no_log() -> void:
    var log_path := SaTrail.log_path()
    var away := log_path + ".q6-away"
    var can_move := OS.get_name() != "Windows"
    var moved := can_move and FileAccess.file_exists(log_path) and DirAccess.rename_absolute(log_path, away) == OK
    if can_move:
        assert_true(moved or not FileAccess.file_exists(log_path), "The run log is moved aside: %s" % log_path)
    else:
        skip("Windows will not rename the run log the engine holds open, so the error was asked for with the log in place")
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var started := Time.get_ticks_usec()
    var answer := _ask(client, {"id": 1, "import": no_picture})
    var took := Time.get_ticks_usec() - started
    if moved:
        DirAccess.rename_absolute(away, log_path)
    var error := _holding(answer.get("errors"), no_picture.get_file())
    assert_false(error.is_empty(), "The import's error is in its answer: %s" % answer)
    assert_true(error.contains(" at: ") and (error.contains(".cpp:") or error.contains(".gd:")), "with its origin: %s" % error)
    assert_false(FileAccess.file_exists(away), "and the log is back where it was")
    var figure := "Figure: an error reached its answer %.1f ms after the step was asked for, the log moved aside %s"
    print(figure % [took / 1000.0, moved])
    client.disconnect_from_host()


## A report repeated over many frames is one entry with its count, in the
## answer and in the session's entries alike.
func test_an_error_repeated_every_frame_is_one_entry_with_its_count() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    _nagging = true
    var answer := _ask(client, {"id": 1, "settle": NAG_FRAMES, "comment": "nagged"})
    _nagging = false
    var warnings: Array = answer.get("warnings", [])
    var nagged := warnings.filter(func(line: Variant) -> bool: return String(line).contains("the same warning"))
    assert_eq(nagged.size(), 1, "The repeats are one line: %s" % str(warnings))
    var count := int(String(nagged[0]).get_slice(" x", 1)) if nagged.size() == 1 else 0
    assert_true(count >= NAG_FRAMES, "counted %d times over %d frames: %s" % [count, NAG_FRAMES, str(nagged)])
    var own_path: String = (get_script() as Script).resource_path
    assert_true(String(nagged[0]).contains("_nag (%s" % own_path), "from the line that raised it: %s" % str(nagged))
    var again := _ask(client, {"id": 2, "comment": "quiet"})
    assert_eq(_holding(again.get("warnings"), "the same warning"), "", "and the next answer has none of it")
    client.disconnect_from_host()


## The `errors` step answers the whole session's entries, filtered by level,
## in verdict lines and as entries a client can read without parsing them.
func test_the_errors_step_answers_the_sessions_entries() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    _ask(client, {"id": 1, "import": no_picture})
    _nagging = true
    _ask(client, {"id": 2, "settle": 5, "comment": "nagged"})
    _nagging = false
    var answer := _ask(client, {"id": 3, "errors": {"level": "all"}})
    var entries: Array = answer.get("entries", [])
    var levels: Array = entries.map(func(entry: Variant) -> String: return String((entry as Dictionary).get("level")))
    assert_true(levels.has("ERROR") and levels.has("WARNING"), "Both steps' reports are there: %s" % str(entries))
    for entry: Variant in entries:
        for key: String in ["level", "message", "function", "file", "line", "count"]:
            assert_true((entry as Dictionary).has(key), "each entry carries its %s: %s" % [key, entry])
    assert_false(_holding(answer.get("verdicts"), "SaCapture: errors at level all").is_empty(), "and says so in a verdict")
    var errors_only := _ask(client, {"id": 4, "errors": {"level": "error"}})
    var kept: Array = errors_only.get("entries", [])
    assert_true(
        kept.all(func(entry: Variant) -> bool: return (entry as Dictionary).get("level") != "WARNING"),
        "the error level leaves the warnings out: %s" % str(kept)
    )
    assert_true(kept.size() >= 1, "and keeps the errors")
    client.disconnect_from_host()


func test_the_logger_goes_with_the_door() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    assert_true(_door._errors != null, "Listening installs the errors logger")
    assert_eq(DoorErrors.session_entries("all"), [], "which starts empty")
    _door.close()
    assert_true(_door._errors == null, "closing takes it out")
    assert_eq(DoorErrors.capture({}), "SaCapture: errors, no door listens, so nothing keeps them", "and the step says so")


## The cap holds a flood to a bounded list, and the `errors` step says how
## much it left out. The answer of the step that raised the flood names every
## report of it, the ones the list had no room for as well, and no line in it
## stands for a report without naming one.
func test_the_entries_stop_at_the_cap() -> void:
    var logger: DoorErrors = DoorErrors.new()
    for i in DoorErrors.CAP + 7:
        logger._keep("ERROR", {"function": "f", "file": "x.gd", "line": i}, "number %d" % i)
    var taken := logger.take()
    assert_eq((taken["errors"] as Array).size(), DoorErrors.CAP + 7, "The step's answer names every report it raised")
    assert_eq(
        (taken["errors"] as Array).back(),
        "ERROR: number %d at: f (x.gd:%d)" % [DoorErrors.CAP + 6, DoorErrors.CAP + 6],
        "the last with its origin"
    )
    assert_eq((logger.entries("all") as Array).size(), DoorErrors.CAP + 1, "The session keeps the cap's worth")
    assert_eq((logger.entries("all") as Array).back().get("count"), 7, "and counts the rest")
    assert_eq(logger.take()["errors"], [], "A second take has nothing new")


## What the log route delivered, measured for the record: the time before a
## warning raised now is in the run log.
func test_the_log_route_for_the_record() -> void:
    var log_path := SaTrail.log_path()
    if not FileAccess.file_exists(log_path):
        print("Figure: no run log at %s to measure" % log_path)
        return
    var offset := FileAccess.open(log_path, FileAccess.READ).get_length()
    var marker := "q6 marker %d" % Time.get_ticks_usec()
    var started := Time.get_ticks_usec()
    push_warning(marker)
    var seen := -1.0
    while Time.get_ticks_usec() - started < 3_000_000:
        var lines: Array = DoorLog.read_since(offset)["lines"]
        if not _holding(lines, marker).is_empty():
            seen = (Time.get_ticks_usec() - started) / 1000.0
            break
        OS.delay_msec(5)
    if seen < 0.0:
        print("Figure: a warning was not in the run log 3000 ms after it was raised")
    else:
        print("Figure: a warning reached the run log %.1f ms after it was raised" % seen)
    assert_true(true, "measured")
