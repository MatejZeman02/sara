## A stroke carries its own colour, so a stroke in a new colour is one step
## and an array of them paints faster.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The `colour` step was a request of its own with its own settle, so a stroke
## in a new colour cost two steps. The stroke's `colour` key sets the brush in
## the frame the stroke's step runs. These send one request, an array of three
## strokes each naming another colour, through a real door over TCP, read the
## colour standing at each stroke's middle, and count the frames the array took
## against the same three strokes with a `colour` step before each.
extends "res://tests/test_framework.gd"

## The brush needs a RenderingDevice, and the window a display.
const REQUIRES_GPU := true

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const MainCanvasScript := preload("res://render/main_canvas.gd")
const PixelDriver := preload("res://harness/scenario/sa_scenario_pixels.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("c5-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("c5-door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("c5-door-run")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 900

## How far a channel read at a stroke's middle may lie from the colour named,
## the half-float the layer holds it in being the whole of the difference.
const TOLERANCE: float = 0.01

## The colours, in the order the strokes are sent, each a channel that says
## which stroke it is.
const COLOURS: Array[String] = ["#ff0000", "#00ff00", "#0000ff"]

## Where the first stroke starts from the canvas's corner in root units, how far
## each stroke runs, and how far apart the three lie.
const FROM_CORNER := Vector2(60, 60)
const RUN := Vector2(300, 0)
const GAP := Vector2(0, 140)

var _host: Node = null
var _main: Node = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _folder: String = ""
## Frames the suite's own loop has run, the count of how long a request took.
var _frames: int = 0
## What tells the brush of a pick, for after_each to let go of.
var _follow: Callable = Callable()


func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "C5DoorTestHost"
    EventBus.add_child(_host)
    _main = MainCanvasScript.new()
    _host.add_child(_main)
    _main.bind_tools(Fixtures.make_tool_registry())
    _main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    # The fixture's registry lets go of the base module's own listener so the
    # module does not outlive the suite, so the brush is told the pick here, the
    # way the module's listener tells it in the running app.
    _follow = func(picked: Color) -> void: _main.tool_machine.get_tool(&"brush").settings.color = picked
    EventBus.color_picked.connect(_follow)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known, _count_frame)
    _folder = OS.get_temp_dir().path_join("sara-c5-door-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
    _frames = 0


func after_each() -> void:
    EventBus.color_picked.disconnect(_follow)
    # A lambda held by the object it closes over is a cycle nothing frees.
    _follow = Callable()
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null
    if _host != null:
        _host.free()
        _host = null
    _main = null
    SaCursorPolicy.forget_pointer_device()
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)


## The suite's part of each frame, counted.
func _count_frame() -> void:
    _frames += 1


func _ask(client: StreamPeerTCP, request: Variant) -> Variant:
    var answer := _runner.ask(client, request)
    return answer.get("body", answer)


## Where the first stroke starts, in root units.
func _origin() -> Vector2:
    return (_main.canvas as SaCanvas).get_global_rect().position + FROM_CORNER


## Stroke *i*, naming its colour when *named*.
func _stroke(i: int, named: bool) -> Dictionary:
    var from := _origin() + GAP * i
    var to := from + RUN
    var spec := {"from": [from.x, from.y], "to": [to.x, to.y], "steps": 12, "pressure": 1.0}
    if named:
        spec["colour"] = COLOURS[i]
    return {"stroke": spec}


## The array of three strokes, each naming its colour, or each after a `colour`
## step of its own.
func _array(named: bool) -> Array:
    var steps: Array = []
    for i in COLOURS.size():
        if not named:
            steps.append({"colour": COLOURS[i]})
        steps.append(_stroke(i, named))
    return steps


## The red, green and blue of the active layer at stroke *i*'s middle, through
## the `read_pixels` step's own read.
func _rgb_at_middle(i: int) -> Color:
    var canvas: SaCanvas = _main.canvas
    var doc: SaDocument = canvas.document
    var at := _origin() + GAP * i + RUN / 2.0
    var texel := canvas.get_global_transform_with_canvas().affine_inverse() * at
    var index := SaLayerOps.new(doc).layers().find(doc.active_layer)
    var rect := [int(texel.x), int(texel.y), 1, 1]
    var answer := PixelDriver.read_into(doc, {"layer": index, "rect": rect, "file": "texel.npy"}, _folder)
    var body := FileAccess.get_file_as_bytes(String(answer["path"]))
    var end := body.size()
    return Color(body.decode_float(end - 16), body.decode_float(end - 12), body.decode_float(end - 8), body.decode_float(end - 4))


## The frames one request took to be answered, through a fresh client.
func _frames_of(request: Array) -> int:
    var client := _runner.connect_client()
    var before := _frames
    var answer: Variant = _ask(client, request)
    var took := _frames - before
    var answered := answer is Array and (answer as Array).size() == request.size()
    assert_true(answered, "The array is answered by an array: %s" % str(answer))
    client.disconnect_from_host()
    return took


func test_an_array_of_three_strokes_each_in_its_own_colour_paints_each_in_it() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var answer: Variant = _ask(client, _array(true))
    assert_true(answer is Array and (answer as Array).size() == 3, "One request is answered three times: %s" % str(answer))
    for entry: Variant in answer as Array:
        assert_eq((entry as Dictionary).get("errors"), [], "Each answer raises nothing: %s" % str(entry))
    var named := 0
    for i in COLOURS.size():
        var painted := _rgb_at_middle(i)
        # In the document's own encoding, Oklab by default, so the colour a
        # swatch shows is read back as the space holds it.
        var wanted := (_main.canvas as SaCanvas).document.color_space.from_display(Color.html(COLOURS[i]))
        for channel in 3:
            var said := "Stroke %d's channel %d is the colour it named at its middle: %s, wanted %s"
            assert_almost_eq(painted[channel], wanted[channel], TOLERANCE, said % [i, channel, str(painted), str(wanted)])
        # A wash stroke reaches the tip's coverage at that texel and stops
        # there, so the middle of the soft default tip reads a little under
        # one, where build-up's overlapping dabs climbed to it. Well clear of
        # the ground's nought is all "it is paint there" asks.
        assert_true(painted.a > 0.9, "and it is paint there: %s" % str(painted))
        var verdicts := str((answer as Array)[i].get("verdicts"))
        if verdicts.contains("colour %s" % COLOURS[i]):
            named += 1
    assert_eq(named, 3, "and each verdict names the colour it went in: %s" % str(answer))
    client.disconnect_from_host()


func test_the_brush_keeps_the_colour_the_last_stroke_named() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var seen: Array[Color] = []
    var listener := func(picked: Color) -> void: seen.append(picked)
    EventBus.color_picked.connect(listener)
    _ask(client, _array(true))
    EventBus.color_picked.disconnect(listener)
    assert_eq(seen.size(), 3, "Each stroke picked its colour once, in the frame of its own step")
    if seen.size() == 3:
        assert_eq(seen[2].to_html(false), "0000ff", "and the last stays the brush's colour afterwards")
    client.disconnect_from_host()


func test_strokes_that_name_a_colour_take_fewer_frames_than_a_colour_step_before_each() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var with_key := _frames_of(_array(true))
    var with_step := _frames_of(_array(false))
    print("frames: array of coloured strokes %d, colour step before each %d" % [with_key, with_step])
    var said := "The array of coloured strokes took %d frames, a colour step before each took %d"
    assert_true(with_key < with_step, said % [with_key, with_step])
