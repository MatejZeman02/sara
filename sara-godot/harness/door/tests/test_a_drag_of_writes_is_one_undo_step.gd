## The writes of a NumPy slider's drag send `"history":
## false`, record no step, and the write sent when the slider is let go records
## every one of them as the one step, which one undo takes back to the picture
## before the drag. The array lands by kernel now, at the chunk's own depth, so
## the values it holds are graded here too.
##
## Built like the pixels suite beside the driver: the driver with no run,
## handed the document and a [Held] of the suite's own, and every texel read
## back through the `texel` step's own reader.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const Landing = preload("res://harness/door/sa_pixel_landing.gd")
const TexelProbe = preload("res://harness/report/sa_texel_probe.gd")

## Needs a RenderingDevice, because every case reads chunks back.
const REQUIRES_GPU := true

## Two chunks across, so a drag can reach a chunk the layer did not have.
const SIZE := Vector2i(512, 256)

## What the layer holds before the drag, in chunk (0, 0) only. Every colour
## here is a sum of halves a half float holds exactly, so a texel compares equal.
const PAINT := Color(0.75, 0.375, 0.125, 1.0)

## The thirty writes of a drag, as a slider at thirty frames a second sends
## in one second.
const DRAG := 30

var _doc: SaDocument = null
var _folder := ""


func before_each() -> void:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = SaDocument.new()
    # Half floats, the depth of the document Sara opens with, so the kernel
    # writes a depth other than the array's.
    _doc.setup_default_document(SIZE, compositor, SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16))
    _doc.active_layer.get_or_create_chunk(Vector2i(0, 0)).albedo().clear(PAINT)
    _folder = OS.get_temp_dir().path_join("sara-drag-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)


func after_each() -> void:
    _doc.free()
    _doc = null
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)


## Thirty writes without history leave the history as it was, the one with it
## after them is one step, and one undo gives back the picture before the
## first, the chunk the drag made taken away and the region a later write grew
## to put back too.
func test_thirty_writes_without_history_and_the_let_go_are_one_step() -> void:
    var held := Landing.Held.new()
    var before := _doc.undo_redo.get_history_count()
    for i in DRAG:
        # The drag's rectangle grows halfway, so what undo keeps grows with it.
        var rect: Rect2i = Rect2i(200, 10, 100, 20) if i * 2 < DRAG else Rect2i(150, 5, 150, 30)
        var answer := _write(rect, _step(i), held, false)
        assert_false(answer.has("error"), "write %d answers without a refusal: %s" % [i, answer])
    assert_eq(_doc.undo_redo.get_history_count(), before, "thirty writes without history record no step")
    assert_eq(held.layers_held(), 1, "and the layer holds what they overwrote")
    assert_eq(_doc.active_layer.chunks.size(), 2, "the drag made the chunk it reached")
    assert_eq(_at(Vector2i(160, 6)), _step(DRAG - 1), "the last write's picture is the one shown")

    var last := _write(Rect2i(150, 5, 150, 30), _step(DRAG - 1), held, true, "live Goal")
    assert_false(last.has("error"), "the let go answers without a refusal: %s" % last)
    assert_eq(_doc.undo_redo.get_history_count(), before + 1, "the let go records the one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "live Goal", "named as the write named it")
    assert_eq(held.layers_held(), 0, "and the layer holds nothing more")

    assert_true(_doc.undo_redo.undo(), "one undo")
    assert_eq(_at(Vector2i(160, 6)), PAINT, "puts back where the grown rectangle reached")
    assert_eq(_at(Vector2i(210, 20)), PAINT, "and where the first write reached")
    assert_eq(_doc.active_layer.chunks.keys(), [Vector2i(0, 0)], "and takes away the chunk the drag made")
    assert_true(_doc.undo_redo.redo(), "one redo")
    assert_eq(_at(Vector2i(280, 20)), _step(DRAG - 1), "brings the let go's picture back")


## A step recorded between two writes of a drag lets the held writes go, and
## so does an undo and a new step that bring `get_version()` back to the number
## it had. The let go then records only what came after, and never puts back a
## picture an undo has since taken away.
func test_a_step_in_the_middle_of_a_drag_lets_the_held_writes_go() -> void:
    var held := Landing.Held.new()
    _write(Rect2i(10, 10, 20, 20), Color(0.5, 0.5, 0.5, 1.0), held, true, "first")
    var version := _doc.undo_redo.get_version()
    _write(Rect2i(10, 10, 20, 20), Color(0.125, 0.125, 0.125, 1.0), held, false)
    assert_eq(held.layers_held(), 1, "a write without history holds the layer")

    assert_true(_doc.undo_redo.undo(), "an undo in the middle of the drag")
    _doc.undo_redo.create_action("elsewhere")
    _doc.undo_redo.commit_action()
    assert_eq(_doc.undo_redo.get_version(), version, "an undo and a new step bring the version back where it was")
    assert_eq(held.layers_held(), 0, "and still let the held writes go")

    _write(Rect2i(10, 10, 20, 20), Color(0.25, 0.25, 0.25, 1.0), held, false)
    _write(Rect2i(10, 10, 20, 20), Color(0.375, 0.375, 0.375, 1.0), held, true, "let go")
    assert_true(_doc.undo_redo.undo(), "the let go's undo")
    assert_eq(_at(Vector2i(15, 15)), PAINT, "goes back to the picture the undo left, not to the one it took away")


## A write with history and no [Held] records itself, as every write before
## the drag's own writes do, and a write without history and no [Held] records nothing.
func test_a_write_with_no_held_records_itself_or_nothing() -> void:
    var before := _doc.undo_redo.get_history_count()
    _write(Rect2i(10, 10, 20, 20), Color(0.5, 0.5, 0.5, 1.0), null, false)
    assert_eq(_doc.undo_redo.get_history_count(), before, "without history nothing is recorded")
    _write(Rect2i(10, 10, 20, 20), Color(0.625, 0.625, 0.625, 1.0), null, true, "alone")
    assert_true(_doc.undo_redo.undo(), "with it one step")
    assert_eq(_at(Vector2i(15, 15)), Color(0.5, 0.5, 0.5, 1.0), "which takes back only itself")


## The array goes up in `float32` and a kernel writes it at the chunk's own
## depth, half floats in Sara's own new document: values past one and below zero
## land as they are, and a chunk the write makes holds zeros where the array
## does not reach.
func test_the_kernel_lands_the_arrays_values_at_the_chunks_depth() -> void:
    var field := _doc.active_layer.get_field(Vector2i(0, 0))
    assert_eq(field.format, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, "the layer is half floats")
    var bright := Color(3.0, -0.5, 0.25, 1.0)
    var answer := _write(Rect2i(250, 100, 40, 30), bright, null, true, "bright")
    assert_eq(answer["chunks"], [[0, 0], [1, 0]], "the write reaches both chunks")
    assert_true(float(answer["ms"]) > 0.0, "and says what it took: %s" % answer)
    assert_eq(_at(Vector2i(252, 101)), bright, "the old chunk holds the array's values")
    assert_eq(_at(Vector2i(289, 129)), bright, "and so does the new one, past one and below zero")
    assert_eq(_at(Vector2i(300, 100)), Color(0, 0, 0, 0), "which is blank where the array does not reach")
    assert_eq(_at(Vector2i(249, 100)), PAINT, "and the old chunk keeps its paint beside the rectangle")


## The colour the *i*th write of the drag lands, a step of a thirty-second.
func _step(i: int) -> Color:
    return Color(i / 32.0, 0.5, 0.25, 1.0)


func _write(rect: Rect2i, color: Color, held: Landing.Held, history: bool, step_name := "") -> Dictionary:
    var file := "drag.npy"
    var out := FileAccess.open(_folder.path_join(file), FileAccess.WRITE)
    out.store_buffer(PixelDriver.Npy.header(rect.size))
    var texel := PackedFloat32Array([color.r, color.g, color.b, color.a]).to_byte_array()
    var body := PackedByteArray()
    for _i in rect.size.x * rect.size.y:
        body.append_array(texel)
    out.store_buffer(body)
    out.close()
    var spec := {"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "file": file, "history": history}
    if not step_name.is_empty():
        spec["name"] = step_name
    return PixelDriver.write_from(_doc, spec, _folder, held)


func _at(at: Vector2i) -> Color:
    var texel: Variant = TexelProbe._read_point(_doc, null, at)["layer"]
    if texel == null:
        return Color(0, 0, 0, 0)
    return Color(texel["r"], texel["g"], texel["b"], texel["a"])
