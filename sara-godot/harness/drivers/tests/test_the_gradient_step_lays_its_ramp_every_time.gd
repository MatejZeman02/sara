## The gradient step lays its ramp every time.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The step lost gradients three ways. A sky came out one flat colour and a layer
## black but for a stripe, the boot's first brush picked under the drag, and a
## docker over the press took one. Each run printed the step's quiet line. A held
## ramp lost a fourth way: a second drag over the same points took the first ramp's near
## end and laid it onto the far one. These run the steps through a real step
## table by hand on the main canvas, with the Tool Options docker open clear of
## the drag so the `ramp` step finds its editor, and read the layer back through
## the `read_pixels` step's own read. The running app's half is
## `scenarios/the-gradient-step-lays-its-ramp-every-time.json`.
extends "res://tests/test_framework.gd"

## The ramp is laid by a kernel, and the window needs a display.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")

## The view: half size, so the whole document stands in the window's top left.
const ZOOM := 0.5
const PAN := Vector2(40.0, 40.0)

## The drag, in document pixels, and the row the layer is read along.
const ROW := 500
const FROM := Vector2(400.0, ROW)
const TO := Vector2(1500.0, ROW)

## Columns before the press and past the release, where the ramp is its near
## colour and its far colour whole, and one between them.
const NEAR_X := 200
const FAR_X := 1700
const MIDDLE_X := 950

## The near stops the `ramp` step sets in turn, and the far stop it sets once.
const NEARS := ["#ff0000", "#00ff00", "#ffff00"]
const FAR := "#0000ff"

## How many times the two steps run.
const TIMES := 30

## Where the Tool Options docker stands, in root units, clear of the drag.
const OPTIONS_AT := Vector2i(1100, 60)
const OPTIONS_SIZE := Vector2i(420, 560)

## The docker the refusals stand over the canvas, and its title.
const DOCKER_SIZE := Vector2i(200, 160)
const DOCKER := "Gradient Docker"

## A colour read is the asked one within this, in each channel.
const CLOSE := 0.02

var _host: Node = null
var _canvas: Node = null
var _run: CaptureRun = null
var _table: StepTable = null
var _options: ToolOptionsDocker = null
var _docker: Window = null
## Every event the docker's own control was handed.
var _caught: Array = []
var _folder: String = ""
var _lines: SaErrorCatcher = null

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "GradientTestHost"
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    _canvas.bind_tools(Fixtures.make_tool_registry())
    _canvas.notification(Container.NOTIFICATION_SORT_CHILDREN)
    var canvas: SaCanvas = _canvas.canvas
    canvas.scale = Vector2(ZOOM, ZOOM)
    canvas.position = PAN
    var machine := canvas.tool_machine()
    machine.set_active_tool(&"gradient")
    _front = Fixtures.FrontDocuments.over(_canvas.canvas as SaCanvas)
    _options = ToolOptionsDocker.new()
    _options.position = OPTIONS_AT
    _options.size = OPTIONS_SIZE
    _host.add_child(_options)
    _options.target_tool_machine = machine
    # A docker is built hidden, and the `ramp` step edits the editor on screen.
    _options.show()
    _caught = []
    _run = CaptureRun.new()
    _table = StepTable.new(_run)
    _folder = OS.get_temp_dir().path_join("sara-d28-gradient-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
    _lines = SaErrorCatcher.new()
    OS.add_logger(_lines)


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    OS.remove_logger(_lines)
    _lines = null
    _table = null
    _run = null
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _canvas = null
    _options = null
    _docker = null
    _caught = []
    SaCursorPolicy.forget_pointer_device()
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)


## Thirty times a `ramp` step and then the same gradient: every one lays its
## ramp, the near colour the ramp step set before the press and the far one
## past the release, with a blend of the two between. Before the fix the second
## drag pressed on the first ramp's held near end and laid it onto the far
## one, a ramp of no length, and every gradient after it was one flat colour.
##
## Read against the run before rather than against the stops' sRGB numbers,
## because the document keeps its texels in its own working space: each near
## stop lays the texel it laid the first time, the far stop the same one every
## run, and the three near stops three different texels.
func test_a_ramp_step_then_a_gradient_thirty_times_lays_the_ramp_every_time() -> void:
    var doc: SaDocument = (_canvas.canvas as SaCanvas).document
    assert_true(_view_holds(FROM) and _view_holds(TO), "The drag is on the canvas's view")
    var options := Rect2(_options.position, _options.size)
    assert_false(options.has_point(_root(FROM)) or options.has_point(_root(TO)), "and clear of the Tool Options docker")
    _drive({"ramp": {"select": 1, "color": FAR}})

    var missed: Array = []
    var nears: Dictionary = {}
    var far := Color(0, 0, 0, 0)
    for i in TIMES:
        var stop: String = NEARS[i % NEARS.size()]
        _drive({"ramp": {"select": 0, "color": stop}})
        _drive(_gradient({}))
        var near := _colour(doc, NEAR_X)
        var middle := _colour(doc, MIDDLE_X)
        if i == 0:
            far = _colour(doc, FAR_X)
        var laid := near.a > 0.99 and not _close(near, far) and not _close(middle, near) and not _close(middle, far)
        if not laid or not _close(near, nears.get(stop, near)) or not _close(_colour(doc, FAR_X), far):
            missed.append("run %d: near %s, middle %s, far %s" % [i + 1, near, middle, _colour(doc, FAR_X)])
        nears[stop] = nears.get(stop, near)
    assert_eq(missed, [], "Every run laid its ramp, %d of %d missed" % [missed.size(), TIMES])
    var firsts: Array = nears.values()
    assert_eq(firsts.size(), NEARS.size(), "Every near stop was laid")
    if firsts.size() == NEARS.size():
        var apart := not _close(firsts[0], firsts[1]) and not _close(firsts[1], firsts[2]) and not _close(firsts[0], firsts[2])
        assert_true(apart, "as a texel of its own, so each ramp step reached the ramp: %s" % [firsts])
    assert_eq(_holding(_lines.texts([SaErrorCatcher.ERROR]), "gradient failed"), [], "No run failed")
    assert_eq(_held(), false, "The last ramp's ends were let go")
    assert_eq(_holding(_lines.printed(), "SaCapture: ramp {").size(), TIMES + 1, "Every ramp step found its editor")


## A gradient whose press would land on a docker is refused: nothing is sent,
## the layer is as it was, and the line names the docker and the way round.
func test_a_gradient_dragged_onto_a_docker_is_refused() -> void:
    var doc: SaDocument = (_canvas.canvas as SaCanvas).document
    var steps: int = doc.undo_redo.get_history_count()
    _stand_docker_over(FROM)
    _drive(_gradient({}))
    var refused := _holding(_lines.texts([SaErrorCatcher.ERROR]), "gradient failed")
    assert_eq(refused.size(), 1, "The step fails loudly: %s" % [_lines.texts([SaErrorCatcher.ERROR])])
    if refused.size() == 1:
        assert_true(refused[0].contains("no ramp was laid, '%s' covers the press" % DOCKER), "naming the docker: %s" % refused[0])
        assert_true(refused[0].contains('"route": "tool"'), "and the way round")
    for x: int in [NEAR_X, MIDDLE_X, FAR_X]:
        assert_eq(_colour(doc, x).a, 0.0, "Nothing was laid at document x %d" % x)
    assert_eq(doc.undo_redo.get_history_count(), steps, "and no step was written")
    assert_eq(_caught, [], "The docker was handed nothing")


## A release onto a docker is refused as well, since the docker would take the
## release and leave the drag open.
func test_a_gradient_released_onto_a_docker_is_refused() -> void:
    var doc: SaDocument = (_canvas.canvas as SaCanvas).document
    _stand_docker_over(TO)
    _drive(_gradient({}))
    var refused := _holding(_lines.texts([SaErrorCatcher.ERROR]), "gradient failed")
    assert_eq(refused.size(), 1, "The step fails loudly: %s" % [_lines.texts([SaErrorCatcher.ERROR])])
    if refused.size() == 1:
        assert_true(refused[0].contains("'%s' covers the release" % DOCKER), "naming the release: %s" % refused[0])
    assert_eq(_colour(doc, MIDDLE_X).a, 0.0, "and nothing was laid")


## A press off the canvas's view is refused with the view it missed.
func test_a_gradient_pressed_off_the_view_is_refused() -> void:
    var off := Vector2(-200.0, ROW)
    assert_false(_view_holds(off), "The press is off the view")
    _drive(_gradient({"from": [off.x, off.y]}))
    var refused := _holding(_lines.texts([SaErrorCatcher.ERROR]), "gradient failed")
    assert_eq(refused.size(), 1, "The step fails loudly: %s" % [_lines.texts([SaErrorCatcher.ERROR])])
    if refused.size() == 1:
        assert_true(refused[0].contains("is outside the canvas's view"), "saying where: %s" % refused[0])


## The way round: `"route": "tool"` lays the ramp under the docker through the
## tool's own `draw_between`, and the docker hears nothing.
func test_the_tool_route_lays_the_ramp_under_a_docker() -> void:
    var doc: SaDocument = (_canvas.canvas as SaCanvas).document
    _stand_docker_over(FROM)
    _drive(_gradient({"route": "tool"}))
    var near := _colour(doc, NEAR_X)
    var far := _colour(doc, FAR_X)
    assert_true(near.a > 0.99 and far.a > 0.99, "The ramp is laid from end to end: %s, %s" % [near, far])
    assert_false(_close(near, far), "and is a ramp, not a flat colour")
    assert_eq(_holding(_lines.texts([SaErrorCatcher.ERROR]), "gradient failed"), [], "with no failed line")
    var said := _holding(_lines.printed(), "by the tool's own door")
    assert_eq(said.size(), 1, "The line names the route: %s" % [_lines.printed()])
    assert_eq(_caught, [], "The docker was handed nothing")


## One cause: another tool put in hand between the press and the release,
## which the boot's first brush was. The step reads the tool at the release
## and says the drag laid no ramp, where it printed only a quiet line before.
func test_a_drag_another_tool_took_is_a_failed_line() -> void:
    _drive(_gradient({}), {"tool": "brush"})
    var failed := _holding(_lines.texts([SaErrorCatcher.ERROR]), "gradient failed")
    assert_eq(failed.size(), 1, "The step fails loudly: %s" % [_lines.texts([SaErrorCatcher.ERROR])])
    if failed.size() == 1:
        assert_true(failed[0].contains("the brush tool was in hand at the release"), "naming the tool: %s" % failed[0])


## The fourth way, kept on purpose: with `"hold": true` the ends stay, and the
## same drag again takes the near end onto the far one. The step says the ramp
## has no length rather than printing its quiet line over one flat colour.
func test_a_held_end_dragged_onto_the_other_is_a_failed_line() -> void:
    var doc: SaDocument = (_canvas.canvas as SaCanvas).document
    _drive(_gradient({"hold": true}))
    assert_eq(_held(), true, "The first ramp's ends are held")
    _drive(_gradient({"hold": true}))
    var failed := _holding(_lines.texts([SaErrorCatcher.ERROR]), "gradient failed")
    assert_eq(failed.size(), 1, "The step fails loudly: %s" % [_lines.texts([SaErrorCatcher.ERROR])])
    if failed.size() == 1:
        assert_true(failed[0].contains("a ramp of no length"), "saying so: %s" % failed[0])
    assert_true(_close(_colour(doc, NEAR_X), _colour(doc, FAR_X)), "and the layer is the one flat colour it says")


# --- Helpers --------------------------------------------------------------------


## The drag from [constant FROM] to [constant TO], with *extra* written over it.
func _gradient(extra: Dictionary) -> Dictionary:
    var spec := {"from": [FROM.x, FROM.y], "to": [TO.x, TO.y], "steps": 6}
    spec.merge(extra, true)
    return {"gradient": spec}


## Runs *step* and every step it splices, one after the other as the runner
## would, with *after_press* run straight after the gesture's press when given.
func _drive(step: Dictionary, after_press: Dictionary = {}) -> void:
    _run.steps = [step]
    _run.step_index = 0
    while _run.step_index < _run.steps.size():
        var next: Dictionary = _run.steps[_run.step_index]
        _run.step_index += 1
        _table.run(next)
        Input.flush_buffered_events()
        if next.has("press") and not after_press.is_empty():
            _table.run(after_press)
            Input.flush_buffered_events()


## A docker over document point *at*, catching whatever it is handed.
func _stand_docker_over(at: Vector2) -> void:
    _docker = Window.new()
    _docker.title = DOCKER
    _docker.size = DOCKER_SIZE
    _docker.position = Vector2i(_root(at) - Vector2(DOCKER_SIZE) * 0.5)
    var catcher := Control.new()
    catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
    catcher.gui_input.connect(_caught.append)
    _docker.add_child(catcher)
    _docker.window_input.connect(_caught.append)
    _host.add_child(_docker)


## Document point *at* in root units.
func _root(at: Vector2) -> Vector2:
    return (_canvas.canvas as SaCanvas).get_global_transform_with_canvas() * at


## Whether the canvas's view holds document point *at*.
func _view_holds(at: Vector2) -> bool:
    return SaCanvasView.for_canvas(_canvas.canvas).get_visible_rect().has_point(_root(at))


## Whether the gradient holds a ramp's ends, as its own report says.
func _held() -> bool:
    var gradient: ToolState = (_canvas.canvas as SaCanvas).tool_machine().registered_tools[&"gradient"]
    var report: Dictionary = gradient.capture_report(&"gradient", true)
    return bool((report["gradient"] as Dictionary)["held"])


## The active layer's colour at document column *x* of the drag's row, read
## through the `read_pixels` step's own read.
func _colour(doc: SaDocument, x: int) -> Color:
    var index := SaLayerOps.new(doc).layers().find(doc.active_layer)
    var answer := PixelDriver.read_into(doc, {"layer": index, "rect": [x, ROW, 1, 1], "file": "texel.npy"}, _folder)
    var body := FileAccess.get_file_as_bytes(String(answer["path"]))
    var at := body.size() - 16
    return Color(body.decode_float(at), body.decode_float(at + 4), body.decode_float(at + 8), body.decode_float(at + 12))


## Whether *read* is *asked*, within [constant CLOSE] in every channel.
static func _close(read: Color, asked: Color) -> bool:
    return (
        absf(read.r - asked.r) < CLOSE
        and absf(read.g - asked.g) < CLOSE
        and absf(read.b - asked.b) < CLOSE
        and absf(read.a - asked.a) < CLOSE
    )


## The lines of *lines* that hold *text*.
static func _holding(lines: PackedStringArray, text: String) -> Array:
    var out: Array = []
    for line in lines:
        if line.contains(text):
            out.append(line)
    return out
