## A stroke step's frames follow the stroke's length.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A stroke step taking sixteen frames whatever its length would lay 2592
## short dashes at about two a second. A straight stroke with no `steps`
## now takes a frame for every `SAMPLE_SPACING` of its length in root units,
## at least one and at most sixteen. These play a 4 px dash and a 400 px
## stroke by the tool route through a real step table, read the frames each
## line says it took, and read the layer back through the `read_pixels` step's
## own read against the same stroke at `"steps": 16`.
extends "res://tests/test_framework.gd"

## The brush needs a RenderingDevice, and the window a display.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const ScenarioStroke = preload("res://harness/scenario/sa_scenario_stroke.gd")

## The row every stroke here runs along, and where they start, in document
## pixels.
const ROW := 300.0
const FROM_X := 200.0
## The margin round a stroke the read takes in, wider than the brush's radius.
const MARGIN := 80
## The title every stroke's line opens with, which the logger below keeps.
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
    _host.name = "W2StrokeLengthTestHost"
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    _canvas.bind_tools(Fixtures.make_tool_registry())
    _canvas.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _view(1.0)
    _run = CaptureRun.new()
    _table = StepTable.new(_run)
    _folder = OS.get_temp_dir().path_join("sara-w2-stroke-length-%d" % OS.get_process_id())
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
    if _folder.is_empty():
        return
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)


## The note's own measure: a 4 px dash takes two frames or fewer and a 400 px
## stroke sixteen, and each lays the texels the same stroke at sixteen lays.
func test_a_dash_takes_a_frame_and_a_long_stroke_sixteen_and_both_lay_what_sixteen_lay() -> void:
    for length: float in [4.0, 400.0]:
        var said := _play(length, -1)
        var frames := _frames_of(said)
        if length < 10.0:
            var dash := "A %s px dash takes two frames or fewer, took %d: %s" % [length, frames, said]
            assert_true(frames >= 1 and frames <= 2, dash)
        else:
            assert_eq(frames, 16, "A %s px stroke takes the sixteen it took: %s" % [length, said])
        var laid := _read(length)
        assert_true(_undo(), "undone before the same stroke at sixteen")
        assert_eq(_frames_of(_play(length, 16)), 16, 'and at `"steps": 16` it takes sixteen')
        var at_sixteen := _read(length)
        assert_true(_undo(), "undone before the next")
        assert_true(_covered(laid) > 0, "The %s px stroke laid paint" % length)
        assert_eq(_worst(laid, at_sixteen), 0.0, "and the very texels the stroke at sixteen lays, %s px" % length)


## The same holds with the hand's smoothing on, Paint's Average at 0.5, since
## the stabiliser walks what it owes at the release to the stroke's end.
func test_with_the_average_at_half_the_texels_match_as_well() -> void:
    var settings: Variant = (_canvas.canvas as SaCanvas).tool_machine().active_tool.get("settings")
    assert_true(settings != null, "The brush in hand has settings")
    settings.set("stabilizer_mode", 1)
    settings.set("stabilizer_amount", 0.5)
    assert_eq(int(settings.get("stabilizer_mode")), 1, "The Average stands on the brush the strokes press with")
    for length: float in [4.0, 400.0]:
        _play(length, -1)
        var laid := _read(length)
        assert_true(_undo(), "undone before the same stroke at sixteen")
        _play(length, 16)
        var at_sixteen := _read(length)
        assert_true(_undo(), "undone before the next")
        assert_true(_covered(laid) > 0, "The %s px stroke laid paint" % length)
        # Not exactly nought: the default spacing is 0.05, so a stroke has more
        # dabs and the float sums of the two splits round apart by about 1e-4.
        assert_true(
            _worst(laid, at_sixteen) <= 1e-3,
            "and with the Average on, what the stroke at sixteen lays, %s px, to a thousandth" % length
        )
    settings.set("stabilizer_mode", 0)


## The length is read in root units, where a pen's samples land: zoomed out to
## a half, 400 document pixels are 200 units and take eight frames, and zoomed
## in to two, 100 are as many units as 200 and take eight as well.
func test_the_length_is_read_in_root_units() -> void:
    _view(0.5)
    assert_eq(_frames_of(_play(400.0, -1)), 8, "400 document pixels at a half are 200 units, eight frames")
    assert_true(_undo(), "undone")
    _view(2.0)
    assert_eq(_frames_of(_play(100.0, -1)), 8, "100 document pixels at two are 200 units, eight frames")
    assert_true(_undo(), "undone")


## A `steps` given still wins, both ways.
func test_a_steps_given_still_wins() -> void:
    assert_eq(_frames_of(_play(4.0, 16)), 16, "A dash asked for sixteen takes sixteen")
    assert_true(_undo(), "undone")
    assert_eq(_frames_of(_play(400.0, 3)), 3, "and a long stroke asked for three takes three")
    assert_true(_undo(), "undone")


## The rule itself: one frame a spacing, rounded up, at least one and at most
## sixteen.
func test_the_rule_is_one_frame_a_spacing() -> void:
    var spacing: float = ScenarioStroke.SAMPLE_SPACING
    assert_eq(ScenarioStroke.steps_for(0.0), 1, "A stroke of no length is still one frame")
    assert_eq(ScenarioStroke.steps_for(4.0), 1, "A dash of a few pixels is one")
    assert_eq(ScenarioStroke.steps_for(spacing), 1, "and so is one spacing")
    assert_eq(ScenarioStroke.steps_for(spacing + 0.5), 2, "and a little more is two")
    assert_eq(ScenarioStroke.steps_for(400.0), 16, "400 units are the sixteen every stroke took")
    assert_eq(ScenarioStroke.steps_for(4000.0), 16, "and a longer one no more")


# --- Helpers --------------------------------------------------------------------


## Puts the document's origin at (40, 40) of the window at *zoom*.
func _view(zoom: float) -> void:
    var canvas: SaCanvas = _canvas.canvas
    canvas.scale = Vector2(zoom, zoom)
    canvas.position = Vector2(40.0, 40.0)


## Plays a straight stroke *length* document pixels along the row by the tool
## route, with *steps* when it is not negative, and answers its lines.
func _play(length: float, steps: int) -> Array:
    var spec := {
        "route": "tool",
        "space": "document",
        "from": [FROM_X, ROW],
        "to": [FROM_X + length, ROW],
        "pressure": 0.8,
    }
    if steps >= 0:
        spec["steps"] = steps
    var lines := SaErrorCatcher.new()
    OS.add_logger(lines)
    _run.steps = [{"brush": {"seed": 241}}, {"stroke": spec}]
    _run.step_index = 0
    while _run.step_index < _run.steps.size():
        var next: Dictionary = _run.steps[_run.step_index]
        _run.step_index += 1
        _table.run(next)
        Input.flush_buffered_events()
    OS.remove_logger(lines)
    var said: Array = []
    for line in lines.printed():
        if line.contains(VERDICT):
            said.append(line)
    return said


## The frames the one line in *said* says its stroke took, or -1.
static func _frames_of(said: Array) -> int:
    if said.size() != 1:
        return -1
    var found := RegEx.create_from_string("  (\\d+) frames").search(String(said[0]))
    return int(found.get_string(1)) if found != null else -1


## The active layer round a stroke *length* pixels long, as floats, read
## through the `read_pixels` step's own read.
func _read(length: float) -> PackedFloat32Array:
    var doc: SaDocument = (_canvas.canvas as SaCanvas).document
    var index := SaLayerOps.new(doc).layers().find(doc.active_layer)
    var rect := [int(FROM_X) - MARGIN, int(ROW) - MARGIN, int(length) + 2 * MARGIN, 2 * MARGIN]
    var answer := PixelDriver.read_into(doc, {"layer": index, "rect": rect, "file": "read.npy"}, _folder)
    var body := FileAccess.get_file_as_bytes(String(answer["path"]))
    # A version 1 array's header is ten bytes and the length its ninth names.
    return body.slice(10 + body.decode_u16(8)).to_float32_array()


## The undo of the stroke just played.
func _undo() -> bool:
    return (_canvas.canvas as SaCanvas).document.undo_redo.undo()


## The texels of *read* with any alpha.
static func _covered(read: PackedFloat32Array) -> int:
    var count := 0
    for i in range(3, read.size(), 4):
        if read[i] > 0.0:
            count += 1
    return count


## The widest gap between two reads of one rectangle, and 1 when their sizes
## differ.
static func _worst(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
    if a.size() != b.size():
        return 1.0
    var worst := 0.0
    for i in a.size():
        worst = maxf(worst, absf(a[i] - b[i]))
    return worst
