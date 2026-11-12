## A stroke step says whether it wants the hand's smoothing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Paint ships with the stabiliser on at 0.5, and it acts on a stroke the door
## sends point by point as it does on a hand, so an arc of radius 200 traced at
## 10 px landed 7 px inside the points given.
## These load the shipped Paint onto the brush, trace that arc through a real
## step table by the tool route, once with `"smoothing": false` and once
## without, and find where each landed along every waypoint's own radius, read
## back through the `read_pixels` step's own read. The running app's half is
## `scenarios/a-stroke-step-says-whether-it-wants-the-hand-s-smoothing.json`.
extends "res://tests/test_framework.gd"

## The brush needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const Npy = preload("res://harness/sa_npy.gd")
const ScenarioStroke = preload("res://harness/scenario/sa_scenario_stroke.gd")
const Smoothing = preload("res://harness/scenario/smoothing/sa_stroke_smoothing.gd")

## The reported arc: radius 200, its waypoints 10 px apart along it, the top
## half of a circle so the stabiliser has a long bend to cut.
const RADIUS := 200.0
const SPACING := 10.0
## How far either side of the radius a landing is looked for, past the reach
## of Paint's 25 px radius on a 1080 px side and of any lag the Average leaves.
const REACH := 40
## The waypoints at either end left out of a landing, where the brush's end
## caps meet the radius slantwise.
const ENDS := 3
## How far inside the points the smoothed arc's middle lands at the least,
## where it measured 2.7 px on 2026-10-07. Twice the unsmoothed promise, so the
## two strokes cannot both pass by measuring nothing.
const INSIDE := 2.0
## The title the stroke's lines open with, which the logger below keeps.
const VERDICT := "SaCapture: stroke"

var _host: Node = null
var _canvas: Node = null
var _run: CaptureRun = null
var _table: StepTable = null
var _folder: String = ""

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "R5SmoothingTestHost"
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    _canvas.bind_tools(Fixtures.make_tool_registry())
    _canvas.notification(Container.NOTIFICATION_SORT_CHILDREN)
    var machine := (_canvas.canvas as SaCanvas).tool_machine()
    machine.set_active_tool(&"brush")
    var settings: Resource = machine.get_tool(&"brush").settings
    for field: String in _paint()["settings"]:
        settings.set_indexed(field, _paint()["settings"][field])
    _run = CaptureRun.new()
    _table = StepTable.new(_run)
    _folder = OS.get_temp_dir().path_join("sara-r5-smoothing-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
    _front = Fixtures.FrontDocuments.over(_canvas.canvas as SaCanvas)


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
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)


## The row's promise. Unsmoothed, the arc lands within 1 px of every waypoint
## along its radius. Smoothed, as every stroke was before the key, it lands
## inside them. Paint's stabiliser is what the preset ships after both.
func test_the_arc_lands_on_its_points_unsmoothed_and_inside_them_smoothed() -> void:
    var settings := _brush_settings()
    assert_eq(int(settings.stabilizer_mode), 1, "Paint as it shipped carries the Average")
    assert_eq(float(settings.stabilizer_amount), 0.5, "at 0.5")

    var lines := SaErrorCatcher.new()
    OS.add_logger(lines)
    _drive(_arc({"smoothing": false}))
    OS.remove_logger(lines)
    var unsmoothed := _landings()
    assert_eq(int(settings.stabilizer_mode), 1, "Paint has its Average back after the unsmoothed stroke")
    assert_eq(float(settings.stabilizer_amount), 0.5, "at 0.5")
    var worst := 0.0
    for landing: float in unsmoothed:
        worst = maxf(worst, absf(landing - RADIUS))
    assert_true(worst <= 1.0, "Unsmoothed, every waypoint's radius holds the paint within 1 px: %s" % [unsmoothed])
    var said := _holding(lines.printed(), VERDICT)
    assert_eq(said.size(), 1, "The stroke prints one line: %s" % [said])
    if said.size() == 1:
        var clause := ", unsmoothed, the brush tool's stabiliser 1 off for it and put back"
        assert_true(said[0].contains(clause), "saying so: %s" % said[0])

    assert_true(_document().undo_redo.undo(), "undone before the smoothed stroke")
    lines = SaErrorCatcher.new()
    OS.add_logger(lines)
    _drive(_arc({}))
    OS.remove_logger(lines)
    var smoothed := _landings()
    assert_eq(int(settings.stabilizer_mode), 1, "Paint keeps its Average through the smoothed stroke")
    assert_eq(float(settings.stabilizer_amount), 0.5, "at 0.5")
    assert_eq(smoothed.size(), unsmoothed.size(), "Both strokes are read at the same waypoints")
    for i in mini(smoothed.size(), unsmoothed.size()):
        var said_inside := "Smoothed, the paint lands inside the unsmoothed at every waypoint: %s" % [smoothed]
        assert_true(smoothed[i] < unsmoothed[i], said_inside)
    # The middle third, where the Average's window is full and the release
    # has not begun to ease it onto the pen.
    var third: int = floori(smoothed.size() / 3.0)
    var middle := smoothed.slice(third, 2 * third)
    for landing: float in middle:
        assert_true(landing < RADIUS - INSIDE, "and in the middle third more than %s px inside the points: %s" % [INSIDE, middle])
    var measured := [worst, RADIUS - middle.max(), RADIUS - middle.min()]
    print("R5: unsmoothed at most %.2f px off the points, smoothed %.2f to %.2f px inside them in the middle third" % measured)
    said = _holding(lines.printed(), VERDICT)
    assert_eq(said.size(), 1, "The smoothed stroke prints one line too")
    if said.size() == 1:
        assert_false(said[0].contains("unsmoothed"), "and it is the line it always was: %s" % said[0])


## The paced form takes the key as well, and its report puts the Average back.
func test_a_stroke_at_a_pens_rate_lays_its_points_unsmoothed() -> void:
    var spec := _arc({"smoothing": false})
    spec["stroke"]["rate"] = 4000.0
    _drive(spec)
    var worst := 0.0
    for landing: float in _landings():
        worst = maxf(worst, absf(landing - RADIUS))
    assert_true(worst <= 1.0, "Paced and unsmoothed, the arc lands within 1 px, at most %.2f off" % worst)
    assert_eq(int(_brush_settings().stabilizer_mode), 1, "and Paint has its Average back")


## A brush with its stabiliser off already has nothing held and nothing put
## back, and its line still says the stroke was unsmoothed.
func test_a_brush_without_a_stabiliser_is_left_as_it_is() -> void:
    _brush_settings().stabilizer_mode = 0
    var lines := SaErrorCatcher.new()
    OS.add_logger(lines)
    _drive(_arc({"smoothing": false}))
    OS.remove_logger(lines)
    assert_eq(int(_brush_settings().stabilizer_mode), 0, "The brush's stabiliser is still off")
    var said := _holding(lines.printed(), VERDICT)
    assert_eq(said.size(), 1, "The stroke prints one line")
    if said.size() == 1:
        var bare: bool = said[0].ends_with("frames, unsmoothed") or said[0].contains("frames, unsmoothed  ")
        assert_true(bare, "unsmoothed and nothing put back: %s" % said[0])
        assert_false(said[0].contains("put back"), "with nothing to put back")


## A key that is neither true nor false splices nothing and leaves the
## stabiliser alone, rather than guessing which was meant.
func test_a_smoothing_that_is_not_a_boolean_paints_nothing() -> void:
    _run.steps = []
    _run.step_index = 0
    ScenarioStroke.new(_run).stroke({"from": [100, 200], "to": [500, 200], "smoothing": "off"})
    assert_eq(_run.steps.size(), 0, "no step was spliced")
    assert_eq(int(_brush_settings().stabilizer_mode), 1, "and Paint keeps its Average")


## The clause the line ends on: nothing without the key, so every line written
## before it reads as it did.
func test_the_smoothing_clause() -> void:
    assert_eq(Smoothing.clause({}), "", "No key, no clause")
    assert_eq(Smoothing.clause({"smoothing": {}}), ", unsmoothed", "Nothing held, nothing put back")
    assert_eq(
        Smoothing.clause({"smoothing": {"tool": "brush", "stabilizer_mode": 2}}),
        ", unsmoothed, the brush tool's stabiliser 2 off for it and put back",
        "and a held one names the mode put back"
    )


# --- Helpers --------------------------------------------------------------------


## The shipped Paint, as its recipe, with the Average at 0.5 it shipped with,
## which is the stabiliser met.
static func _paint() -> Dictionary:
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == "Paint":
            var recipe: Dictionary = entry.duplicate(true)
            recipe["settings"]["stabilizer_mode"] = 1
            recipe["settings"]["stabilizer_amount"] = 0.5
            return recipe
    return {}


func _document() -> SaDocument:
    return (_canvas.canvas as SaCanvas).document


func _brush_settings() -> Resource:
    return (_canvas.canvas as SaCanvas).tool_machine().get_tool(&"brush").settings


## Where the arc's circle stands in the document: its middle, low enough that
## the top half fits.
func _centre() -> Vector2:
    var size := Vector2(_document().canvas_size)
    return Vector2(size.x / 2.0, size.y / 2.0 + RADIUS / 2.0)


## The arc's waypoints in document pixels, SPACING apart along the top half of
## the circle, left to right.
func _waypoints() -> Array[Vector2]:
    var count := int(roundf(PI * RADIUS / SPACING))
    var out: Array[Vector2] = []
    for i in count + 1:
        var angle := PI + PI * float(i) / float(count)
        out.append(_centre() + Vector2(cos(angle), sin(angle)) * RADIUS)
    return out


## The arc as a `stroke` step by the tool route, with *extra* keys beside it.
func _arc(extra: Dictionary) -> Dictionary:
    var points: Array = []
    for at in _waypoints():
        points.append({"at": [at.x, at.y], "pressure": 0.8})
    var spec := {"route": "tool", "space": "document", "points": points}
    spec.merge(extra)
    return {"stroke": spec}


## Runs *step* and every step it splices, one a frame as the runner would.
func _drive(step: Dictionary) -> void:
    _run.steps = [step]
    _run.step_index = 0
    while _run.step_index < _run.steps.size():
        var next: Dictionary = _run.steps[_run.step_index]
        _run.step_index += 1
        _table.run(next)
        Input.flush_buffered_events()


## Where the paint lands along each waypoint's radius, ENDS left out at either
## end: the alpha-weighted mean distance from the centre over REACH either side
## of RADIUS. A soft round's profile across a straight stroke is even about its
## middle, so the mean is the middle wherever the stroke went. Along an arc the
## inside of the bend gathers a little more of each dab than the outside, and
## the mean of dabs laid exactly on the circle reads about 0.25 px inside it,
## which the 1 px of the promise holds.
func _landings() -> Array[float]:
    var centre := _centre()
    var corner := Vector2i(centre - Vector2(RADIUS + REACH, RADIUS + REACH))
    var size := Vector2i(2 * (int(RADIUS) + REACH), int(RADIUS) + 2 * REACH)
    var doc := _document()
    var index := SaLayerOps.new(doc).layers().find(doc.active_layer)
    var spec := {"layer": index, "rect": [corner.x, corner.y, size.x, size.y], "file": "arc.npy"}
    var answer := PixelDriver.read_into(doc, spec, _folder)
    var image: Variant = Npy.read(String(answer.get("path", "")))
    assert_true(image is Image, "The arc's pixels read back: %s" % [answer])
    var out: Array[float] = []
    if not image is Image:
        return out
    var waypoints := _waypoints()
    for i in range(ENDS, waypoints.size() - ENDS):
        var along := (waypoints[i] - centre).normalized()
        var weight := 0.0
        var total := 0.0
        for step in range(-4 * REACH, 4 * REACH + 1):
            var distance := RADIUS + float(step) / 4.0
            var alpha := _alpha_at(image as Image, centre + along * distance - Vector2(corner))
            weight += alpha
            total += alpha * distance
        out.append(snappedf(total / weight, 0.01) if weight > 0.0 else 0.0)
    return out


## The alpha of *image* at *at*, between its four nearest texels. A texel's
## centre is at its own index, as the stamp brush's kernel states it
## (`sa_dab_texel`), so a dab sent to (x, y) is centred on texel (x, y). Read
## with the centre half a texel on, the arc leant half a pixel right and down.
static func _alpha_at(image: Image, at: Vector2) -> float:
    var x := int(floorf(at.x))
    var y := int(floorf(at.y))
    var fx := at.x - float(x)
    var fy := at.y - float(y)
    var top := lerpf(_texel(image, x, y), _texel(image, x + 1, y), fx)
    var bottom := lerpf(_texel(image, x, y + 1), _texel(image, x + 1, y + 1), fx)
    return lerpf(top, bottom, fy)


static func _texel(image: Image, x: int, y: int) -> float:
    if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
        return 0.0
    return image.get_pixel(x, y).a


## The lines of *lines* that hold *text*.
static func _holding(lines: PackedStringArray, text: String) -> Array:
    var out: Array = []
    for line in lines:
        if line.contains(text):
            out.append(line)
    return out
