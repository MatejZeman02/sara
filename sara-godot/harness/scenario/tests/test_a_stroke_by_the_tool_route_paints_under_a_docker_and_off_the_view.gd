## A stroke by the tool route paints under a docker and off the view.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A client wants to paint under a docker and get the result without panning
## or zooming. A stroke on real input
## is hit-tested by the window, so a docker over the press takes it, and a
## point off the view has no window point to press at. `"route": "tool"`
## hands each frame's event to the main canvas's tool machine instead. These
## stand a docker over the canvas's middle and zoom so the document's right
## quarter is off the window, run the step's frames through a real step table
## by hand, and read the layer back through the `read_pixels` step's own read.
## The running app's half is
## `scenarios/a-stroke-can-go-straight-to-the-brush-under-a-docker-or-off-the-view.json`.
extends "res://tests/test_framework.gd"

## The brush needs a RenderingDevice, and the window a display.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const ScenarioStroke = preload("res://harness/scenario/sa_scenario_stroke.gd")

## The view: the document's x 1440, three quarters across, lands on the
## window's right edge, so its right quarter is off the window.
const ZOOM := 1.2
const PAN := Vector2(192.0, 0.0)

## The docker over the window's middle, in root units, and its title.
const DOCKER_AT := Vector2i(760, 380)
const DOCKER_SIZE := Vector2i(400, 320)
const DOCKER := "Tool Route Docker"

## The stroke, in document pixels: from the left of the docker, under it,
## and on into the quarter off the window.
const ROW := 450
const FROM := Vector2(300.0, ROW)
const TO := Vector2(1800.0, ROW)
const STEPS := 30

## Document columns of the row: under the docker, and off the window.
const UNDER := [600, 700, 800]
const OFF_VIEW := [1500, 1600, 1700]

## The title the stroke's lines open with, which the logger below keeps.
const VERDICT := "SaCapture: stroke"

var _host: Node = null
var _canvas: Node = null
var _run: CaptureRun = null
var _table: StepTable = null
var _docker: Window = null
## Every event the docker's own control was handed.
var _caught: Array = []
var _folder: String = ""

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "ToolRouteTestHost"
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    _canvas.bind_tools(Fixtures.make_tool_registry())
    _canvas.notification(Container.NOTIFICATION_SORT_CHILDREN)
    var canvas: SaCanvas = _canvas.canvas
    canvas.scale = Vector2(ZOOM, ZOOM)
    canvas.position = PAN
    _front = Fixtures.FrontDocuments.over(_canvas.canvas as SaCanvas)
    _docker = Window.new()
    _docker.title = DOCKER
    _docker.position = DOCKER_AT
    _docker.size = DOCKER_SIZE
    var catcher := Control.new()
    catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
    catcher.gui_input.connect(_caught.append)
    _docker.add_child(catcher)
    _docker.window_input.connect(_caught.append)
    _host.add_child(_docker)
    _caught = []
    _run = CaptureRun.new()
    _table = StepTable.new(_run)
    _folder = OS.get_temp_dir().path_join("sara-d28-route-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)


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
    _docker = null
    _caught = []
    SaCursorPolicy.forget_pointer_device()
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)


## Both stretches hold paint, the view is where it was, the docker heard
## nothing, the stroke is one undo step, and its line says what it went under.
func test_the_tool_route_paints_under_the_docker_and_off_the_view() -> void:
    var canvas: SaCanvas = _canvas.canvas
    var doc: SaDocument = canvas.document
    var view := canvas.get_global_transform_with_canvas()
    var window := Rect2(Vector2.ZERO, _host.get_window().get_visible_rect().size)
    assert_true(Rect2(DOCKER_AT, DOCKER_SIZE).has_point(view * Vector2(UNDER[1], ROW)), "The docker stands over the stroke")
    assert_false(window.has_point(view * Vector2(OFF_VIEW[0], ROW)), "and the document's right quarter is off the window")
    var steps: int = doc.undo_redo.get_history_count()

    var lines := SaErrorCatcher.new()
    OS.add_logger(lines)
    _drive(_stroke("tool", 0.8))
    OS.remove_logger(lines)

    for x: int in UNDER:
        assert_true(_alpha(doc, x) > 0.5, "Paint under the docker at document x %d, alpha %s" % [x, _alpha(doc, x)])
    for x: int in OFF_VIEW:
        assert_true(_alpha(doc, x) > 0.5, "and off the window at document x %d, alpha %s" % [x, _alpha(doc, x)])
    assert_true(
        absf(_alpha(doc, OFF_VIEW[1]) - _alpha(doc, UNDER[1])) < 0.01,
        "The brush does not clip to the view: off it the paint is as dark as under the docker"
    )
    assert_eq(canvas.get_global_transform_with_canvas(), view, "The view was not moved")
    assert_eq(_caught, [], "The docker was handed nothing")
    assert_eq(doc.undo_redo.get_history_count(), steps + 1, "The stroke is one undo step")
    assert_true(doc.undo_redo.undo(), "and one undo")
    assert_eq(_alpha(doc, UNDER[1]), 0.0, "takes the paint away")

    var said := _holding(lines.printed(), VERDICT)
    assert_eq(said.size(), 1, "The stroke prints one line: %s" % [said])
    if said.size() == 1:
        assert_true(said[0].contains("stroke by the tool route, document (300, 450)"), "naming its route: %s" % said[0])
        assert_true(said[0].contains("GPU dispatches"), "the dabs it laid")
        assert_true(said[0].contains("under '%s' at 7 of its 31 points" % DOCKER), "the docker it went under")
        # Counted from the window, since 8 of the 31 are off a 1920 wide one
        # and 18 off a 1280 wide one under Windows.
        var off := 0
        for step: int in STEPS + 1:
            if not window.has_point(view * FROM.lerp(TO, float(step) / STEPS)):
                off += 1
        var off_said := "off the view at %d of its %d points" % [off, STEPS + 1]
        assert_true(said[0].contains(off_said), "and the points off the view: %s" % off_said)
    var caught := lines.texts([SaErrorCatcher.ERROR])
    assert_eq(_holding(caught, VERDICT), [], "A docker over the route's points is a fact, never an error")


## The press end of a stroke at one pressure is no lighter than its release
## end, so the stroke does not fade in, and its alpha follows the pressure.
func test_the_first_dab_follows_the_presss_pressure() -> void:
    var doc: SaDocument = (_canvas.canvas as SaCanvas).document
    var ends: Dictionary = {}
    for pressure: float in [0.3, 0.9]:
        _drive(_stroke("tool", pressure))
        ends[pressure] = [_alpha(doc, int(FROM.x)), _alpha(doc, int(TO.x))]
        assert_true(doc.undo_redo.undo(), "undone before the next pressure")
    for pressure: float in ends:
        var press: float = ends[pressure][0]
        var release: float = ends[pressure][1]
        assert_true(press > 0.2, "At %s the press point holds paint, alpha %s" % [pressure, press])
        assert_true(press >= release, "and no less than the release end, %s against %s" % [press, release])
    assert_true(ends[0.3][0] < ends[0.9][0] - 0.2, "The press point follows the pressure: %s" % [ends])


## A stroke at exactly 1.0 with the pen upright paints where it was asked. The
## cursor package takes such a motion for a mouse's made-up pressure and would
## hand the brush the display server's pointer, so the route keeps the place.
func test_a_stroke_at_full_pressure_with_no_tilt_paints_where_it_was_asked() -> void:
    var doc: SaDocument = (_canvas.canvas as SaCanvas).document
    _drive(_stroke("tool", 1.0))
    for x: int in UNDER + OFF_VIEW:
        assert_true(_alpha(doc, x) > 0.5, "Paint at document x %d, alpha %s" % [x, _alpha(doc, x)])


## The paced form goes by the route as well, and reaches the far end.
func test_a_stroke_at_a_pens_rate_goes_by_the_route() -> void:
    var doc: SaDocument = (_canvas.canvas as SaCanvas).document
    var spec: Dictionary = _stroke("tool", 0.8)
    spec["stroke"]["rate"] = 4000.0
    _drive(spec)
    for x: int in UNDER + OFF_VIEW:
        assert_true(_alpha(doc, x) > 0.5, "Paint at document x %d, alpha %s" % [x, _alpha(doc, x)])
    assert_eq(_caught, [], "and the docker was handed nothing")


## The same stroke on the default route is real input, the docker takes its
## press, and the step still says so loudly.
func test_the_default_route_still_says_the_docker_took_the_press() -> void:
    var spec: Dictionary = _stroke("input", 0.8)
    var under := Vector2(UNDER[0], ROW)
    spec["stroke"]["from"] = [under.x, under.y]
    var lines := SaErrorCatcher.new()
    OS.add_logger(lines)
    _drive(spec)
    OS.remove_logger(lines)
    var failed := _holding(lines.texts([SaErrorCatcher.ERROR]), "failed: no dab reached the GPU")
    assert_eq(failed.size(), 1, "The default route's stroke fails loudly: %s" % [lines.texts([SaErrorCatcher.ERROR])])
    if failed.size() == 1:
        assert_true(failed[0].contains("'%s' covers" % DOCKER), "naming the docker: %s" % failed[0])
        assert_false(failed[0].contains("tool route"), "and no route, the line it always printed")


## A route the step does not know splices nothing rather than guessing.
func test_an_unknown_route_paints_nothing() -> void:
    _run.steps = []
    _run.step_index = 0
    ScenarioStroke.new(_run).stroke({"route": "gui", "from": [100, 200], "to": [500, 200]})
    assert_eq(_run.steps.size(), 0, "no step was spliced")


## The tool route's frames: the priming hover and the press at the first
## waypoint, a motion per waypoint after it and the release, each carrying the
## point as written so it maps through the view of its own frame.
func test_the_route_runs_one_event_a_frame() -> void:
    var path := [{"at": [10, 20], "pressure": 0.4}, {"at": [30, 20], "pressure": 0.6}, {"at": [50, 20], "pressure": 0.7}]
    var frames: Array = ScenarioStroke.ToolRoute.frames(path, "document", "left", 0.0)
    var kinds: Array = []
    for frame: Dictionary in frames:
        kinds.append(frame["stroke"]["tool_event"]["event"])
    assert_eq(kinds, ["hover", "press", "motion", "motion", "release"], "One event a frame")
    var hover: Dictionary = frames[0]["stroke"]["tool_event"]
    assert_eq(hover["pressure"], 0.4, "The hover carries the press's pressure, so the brush is primed with it")
    assert_eq(hover["at"], [10, 20], "at the point as written")
    assert_eq(hover["space"], "document", "in the space it was written in")
    var paced: Array = ScenarioStroke.ToolRoute.frames(path, "window", "left", 240.0)
    assert_eq(paced.size(), 2, "A paced stroke leaves the motions to its step")


## The two clauses the route's line ends on, and none for a stroke with
## nothing over it and nothing off the view.
func test_the_route_clause_says_what_it_went_under() -> void:
    var covers := [{"title": "Layers", "first": 3, "at": [700, 400], "points": 5, "was": [600, 300]}]
    assert_eq(
        ScenarioStroke.tool_route_clause(covers, 16, 4),
        (
            ", the tool route went under 'Layers' at 5 of its 17 points, from frame 3 at (700, 400),"
            + " and off the view at 4 of its 17 points, painted where the document has them"
        ),
        "Both facts, in the order the reader meets them"
    )
    assert_eq(ScenarioStroke.tool_route_clause([], 16, 0), "", "and nothing for a stroke in the open")
    assert_eq(ScenarioStroke.route_clause({"route": "tool"}), "by the tool route, ", "The route opens the line")
    assert_eq(ScenarioStroke.route_clause({}), "", "and the default route's line is the one it always was")
    var points := PackedVector2Array([Vector2(10, 10), Vector2(1919, 10), Vector2(1920, 10), Vector2(10, -1)])
    assert_eq(ScenarioStroke.off_view_count(points, [0.0, 0.0, 1920.0, 1080.0]), 2, "The far edge and above are off")


# --- Helpers --------------------------------------------------------------------


## The stroke across the docker and off the window, on *route* at *pressure*.
func _stroke(route: String, pressure: float) -> Dictionary:
    return {
        "stroke":
        {
            "route": route,
            "space": "document",
            "from": [FROM.x, FROM.y],
            "to": [TO.x, TO.y],
            "pressure": pressure,
            "steps": STEPS,
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


## The active layer's alpha at document column *x* of the stroke's row, read
## through the `read_pixels` step's own read.
func _alpha(doc: SaDocument, x: int) -> float:
    var index := SaLayerOps.new(doc).layers().find(doc.active_layer)
    var answer := PixelDriver.read_into(doc, {"layer": index, "rect": [x, ROW, 1, 1], "file": "texel.npy"}, _folder)
    var body := FileAccess.get_file_as_bytes(String(answer["path"]))
    return snappedf(body.decode_float(body.size() - 4), 0.001)


## The lines of *lines* that hold *text*.
static func _holding(lines: PackedStringArray, text: String) -> Array:
    var out: Array = []
    for line in lines:
        if line.contains(text):
            out.append(line)
    return out
