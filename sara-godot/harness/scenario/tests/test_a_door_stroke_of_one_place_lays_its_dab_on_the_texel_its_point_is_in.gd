## A door stroke of one place lays its dab on the texel its point is in, and
## says which texel it laid.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## With Inked Pen at radius 1, a 2 px dab in
## pixel mode, 9 of 59 door strokes given as two equal points left the target
## texel as it was, and the door answered OK. A dab under 3 px snaps its centre
## with `floor`, and the tool route carried a document point to the window
## and the brush carried it back, so a point that came back a hair under its
## integer was floored a texel left or up. These stroke 200 integer points as
## two equal points by the tool route, at zoom 1 and at 0.61, and read the
## centre of the dab each stroke laid out of the brush, and the stroke's line
## for the texel it names. The running app's half is
## `scenarios/a-door-stroke-of-one-place-lays-its-dab-on-the-texel-its-point-is-in.json`.
extends "res://tests/test_framework.gd"

## The brush needs a RenderingDevice, and the window a display.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const ScenarioStroke = preload("res://harness/scenario/sa_scenario_stroke.gd")

## How many points each zoom strokes.
const POINTS := 200
## The view's origin in the window, off the whole pixel as a fit leaves it.
const PAN := Vector2(441.0, 235.2)
## The radius of Inked Pen in the stroke, in document pixels.
const RADIUS_PX := 1.0
## The title the stroke's lines open with.
const VERDICT := "SaCapture: stroke"

var _host: Node = null
var _canvas: Node = null
var _run: CaptureRun = null
var _table: StepTable = null
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "U557OnePlaceTestHost"
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    _canvas.bind_tools(Fixtures.make_tool_registry())
    _canvas.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _front = Fixtures.FrontDocuments.over(_canvas.canvas as SaCanvas)
    _run = CaptureRun.new()
    _table = StepTable.new(_run)
    var canvas: SaCanvas = _canvas.canvas
    var brush: Object = canvas.tool_machine().active_tool
    brush.get("settings").radius = RADIUS_PX / canvas.document.brush_side


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    _table = null
    _run = null
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _canvas = null
    SaCursorPolicy.forget_pointer_device()


## At zoom 0.61 every one of the 200 dabs has its centre in the texel its
## point names, so the floor of pixel mode lays it there.
func test_at_zoom_0_61_every_dab_of_one_place_lands_in_its_own_texel() -> void:
    var missed := _missed_at(0.61)
    assert_eq(missed, [], "Every dab in its own texel at zoom 0.61, %d missed: %s" % [missed.size(), missed])


## And at zoom 1, the view a painter works at most.
func test_at_zoom_1_every_dab_of_one_place_lands_in_its_own_texel() -> void:
    var missed := _missed_at(1.0)
    assert_eq(missed, [], "Every dab in its own texel at zoom 1, %d missed: %s" % [missed.size(), missed])


## The stroke's line names the texel its one dab was laid on, the target.
func test_the_line_names_the_texel_the_dab_was_laid_on() -> void:
    _view(0.61)
    var lines := SaErrorCatcher.new()
    OS.add_logger(lines)
    _drive(_one_place(Vector2i(612, 407)))
    OS.remove_logger(lines)
    var said := _holding(lines.printed(), VERDICT)
    assert_eq(said.size(), 1, "One line: %s" % [said])
    if said.size() == 1:
        assert_true(said[0].contains("1 dab laid, on texel (612, 407)"), "naming the texel: %s" % said[0])


## The texel clause in its three shapes: none, a few each named, and many by
## their two ends.
func test_the_dabs_clause_names_each_texel_or_says_none_was_laid() -> void:
    var dabs := ScenarioStroke.DabsLaid
    assert_eq(dabs.clause(0, []), ", no dab laid", "None is said, never left out")
    assert_eq(
        dabs.clause(2, [Vector2i(3, 4), Vector2i(5, 4)]), ", 2 dabs laid, on texels (3, 4) and (5, 4)", "A few are each named"
    )
    assert_eq(
        dabs.clause(40, [Vector2i(3, 4), Vector2i(9, 4), Vector2i(90, 4)]),
        ", 40 dabs laid, the first on texel (3, 4) and the last on (90, 4)",
        "and many by their two ends"
    )


# --- Helpers --------------------------------------------------------------------


## The points of *zoom*'s run whose dab's centre left its texel, each as the
## point, the centre and the dab count, after stroking [constant POINTS] of
## them as two equal points.
func _missed_at(zoom: float) -> Array:
    _view(zoom)
    var canvas: SaCanvas = _canvas.canvas
    var brush: Object = canvas.tool_machine().active_tool
    var missed: Array = []
    for i in POINTS:
        var at := Vector2i(100 + (i * 37) % 1500, 100 + (i * 53) % 800)
        _drive(_one_place(at))
        var dab: SaDabParams = brush.get("last_dab")
        var count: int = brush.get("stroke_info").dab_index
        var centre := dab.position + dab.scatter if dab != null else Vector2(-1, -1)
        if count != 1 or Vector2i(centre.floor()) != at:
            missed.append([at, centre, count])
    return missed


## The canvas at *zoom*, its origin at [constant PAN].
func _view(zoom: float) -> void:
    var canvas: SaCanvas = _canvas.canvas
    canvas.scale = Vector2(zoom, zoom)
    canvas.position = PAN


## A stroke of one place at *at*, by the tool route in document pixels.
func _one_place(at: Vector2i) -> Dictionary:
    var point := [float(at.x), float(at.y)]
    return {
        "stroke":
        {
            "route": "tool",
            "space": "document",
            "points": [{"at": point, "pressure": 0.8}, {"at": point, "pressure": 0.8}],
            "smoothing": false,
        }
    }


## Runs *step* and every step it splices, one a frame as the runner would.
func _drive(step: Dictionary) -> void:
    _run.steps = [step]
    _run.step_index = 0
    while _run.step_index < _run.steps.size():
        var next: Dictionary = _run.steps[_run.step_index]
        _run.step_index += 1
        _table.run(next)
        Input.flush_buffered_events()


## The lines of *lines* that hold *text*.
static func _holding(lines: PackedStringArray, text: String) -> Array:
    var out: Array = []
    for line in lines:
        if line.contains(text):
            out.append(line)
    return out
