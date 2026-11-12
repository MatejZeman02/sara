## A door `select` whose mask cannot be read puts its reason
## in the answer's errors.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A `select` whose relative
## mask was not in the run's folder answered `"errors": []` 37 times, and the
## strokes after it painted with no selection. These open the door in this
## process over TCP, as the door's other suites do, on a real main canvas with
## a rectangle already selected, and send a `select` naming a mask that is not
## there and one naming a mask that is. The first answers one error naming the
## path and leaves the rectangle as it was, the second answers `errors` empty
## and selects the mask.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const MainCanvasScript := preload("res://render/main_canvas.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("door/door.json")
static var scratch_port_file: String = SaDataRoot.path("door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("door-run")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 600

## The selection each case starts from, which a failed `select` must leave.
const BEFORE := Rect2i(40, 40, 120, 80)

## The rectangle the readable mask covers, apart from `BEFORE`.
const MASKED := Rect2i(300, 200, 64, 48)

## The fault's own name, relative and pointing out of the run's folder.
const MISSING := "../scratch-set/steps/h3-summer.veil-sel.npy"

var _host: Node = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _front: Fixtures.FrontDocuments = null
var _document: SaDocument = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "U641DoorHost"
    EventBus.add_child(_host)
    var main: Node = MainCanvasScript.new()
    _host.add_child(main)
    main.bind_tools(Fixtures.make_tool_registry())
    main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _front = Fixtures.FrontDocuments.over(main.canvas as SaCanvas)
    _document = (main.canvas as SaCanvas).document
    _document.selection.select_rect(BEFORE)
    DirAccess.make_dir_recursive_absolute(scratch_run_folder)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known, Callable(), Input.flush_buffered_events)


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null
    _document = null
    if _host != null:
        _host.free()
        _host = null


## The answer to one door `select` naming *mask*.
func _select(mask: String) -> Dictionary:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    return _runner.ask(client, {"id": 1, "select": {"mask": mask}})


## The lines of *lines* that hold *text*.
static func _holding(lines: Variant, text: String) -> Array:
    var out: Array = []
    for line: Variant in lines if lines is Array else []:
        if String(line).contains(text):
            out.append(String(line))
    return out


func test_a_select_whose_mask_is_not_there_answers_one_error_naming_it() -> void:
    var answer := _select(MISSING)
    var errors: Variant = answer.get("errors")
    assert_eq((errors as Array).size() if errors is Array else -1, 1, "One error: %s" % str(answer))
    var named := _holding(errors, "h3-summer.veil-sel.npy")
    assert_eq(named.size(), 1, "and it names the path tried: %s" % str(errors))
    if named.size() == 1:
        assert_true(String(named[0]).contains("select failed"), "and says the select failed: %s" % named[0])
    assert_eq(_document.selection.bounds, BEFORE, "The selection is the rectangle it was")


func test_a_select_whose_mask_is_there_answers_no_error_and_selects_it() -> void:
    var size := _document.canvas_size
    var image := Image.create(size.x, size.y, false, Image.FORMAT_L8)
    image.fill_rect(MASKED, Color.WHITE)
    var path := scratch_run_folder.path_join("mask.png")
    assert_eq(image.save_png(path), OK, "The mask is written")
    var answer := _select("mask.png")
    assert_eq(answer.get("errors"), [], "The select raises nothing: %s" % str(answer))
    var bounds := _document.selection.bounds
    assert_true(bounds.encloses(MASKED), "and the selection holds the mask's rectangle: %s" % bounds)
    assert_false(bounds.intersects(BEFORE), "and no longer the rectangle before it: %s" % bounds)
