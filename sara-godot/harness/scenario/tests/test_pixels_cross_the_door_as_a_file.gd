## The `read_pixels` and `write_pixels` steps' arithmetic, a
## layer's texels as a `.npy` file of `float32` and back as one undo step.
##
## The file is parsed here by hand, header and body, rather than through the
## driver's own reader, so a header NumPy would refuse fails here even when the
## driver agrees with itself. The texels are graded against the `texel` step's
## own answer at the same points, the readback every scenario already trusts.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const TexelProbe = preload("res://harness/report/sa_texel_probe.gd")

## Needs a RenderingDevice, because every case reads chunks back.
const REQUIRES_GPU := true

## Two chunks across, so a rectangle can straddle the seam between them.
const SIZE := Vector2i(512, 256)

## A colour no clamp would leave alone.
const BRIGHT := Color(2.0, 0.5, 0.25, 1.0)


## A stroke read back through the step answers what `texel` reads at the same
## points, the value above one among them, and a point past the paint zero.
func test_a_stroke_reads_back_as_the_texel_step_reads_it() -> void:
    var doc := _document()
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    doc.stroke_layer.get_or_create_chunk(Vector2i(0, 0)).albedo().clear(BRIGHT)
    doc.commit_stroke()
    var folder := _folder()

    # By index from the bottom, where the default document's ground sits under
    # the layer a stroke lands on.
    var index := SaLayerOps.new(doc).layers().find(doc.active_layer)
    assert_true(index > 0, "the painted layer is above the ground")
    var answer := PixelDriver.read_into(doc, {"layer": index, "rect": [250, 10, 12, 4], "file": "stroke.npy"}, folder)
    assert_false(answer.has("error"), "the read answers without a refusal: %s" % answer)
    assert_eq(answer["shape"], [4, 12, 4], "the shape is (h, w, 4)")
    assert_eq(answer["rect"], [250, 10, 12, 4], "and the rectangle is the one asked for")
    var parsed := _parse(String(answer["path"]))
    assert_eq(parsed["shape"], [4, 12, 4], "the file's own header says the same shape")

    for at: Vector2i in [Vector2i(250, 10), Vector2i(255, 13), Vector2i(256, 11), Vector2i(261, 13)]:
        var texel: Dictionary = TexelProbe._read_point(doc, null, at)
        var read := _texel_of(parsed, at - Vector2i(250, 10))
        var layer: Variant = texel["layer"]
        var want := Color(0, 0, 0, 0) if layer == null else Color(layer["r"], layer["g"], layer["b"], layer["a"])
        assert_eq(read, want, "the file at %s is the texel step's own answer" % at)
    assert_eq(_texel_of(parsed, Vector2i(0, 0)).r, 2.0, "and a value above one comes back above one")
    assert_eq(_texel_of(parsed, Vector2i(6, 0)), Color(0, 0, 0, 0), "past the painted chunk the file holds zeros")

    doc.free()
    _clear(folder)


## With no rectangle the layer's allocated bounds are read, one chunk here.
func test_no_rectangle_reads_the_allocated_bounds() -> void:
    var doc := _document()
    doc.active_layer.get_or_create_chunk(Vector2i(1, 0)).albedo().clear(BRIGHT)
    var folder := _folder()

    var answer := PixelDriver.read_into(doc, {"layer": String(doc.active_layer.name)}, folder)
    assert_eq(answer["rect"], [256, 0, 256, 256], "the one chunk the layer holds, found by name")
    assert_eq(_parse(String(answer["path"]))["shape"], [256, 256, 4], "and the file is its size")

    doc.free()
    _clear(folder)


## `"canvas"` for the rectangle reads the whole canvas, the
## layer's paint in its corner and zeros everywhere else, where no rectangle
## reads only the chunk the layer holds. A write is not given the word.
func test_the_canvas_for_a_rectangle_reads_all_of_it_whatever_the_layer_holds() -> void:
    var doc := _document()
    doc.active_layer.get_or_create_chunk(Vector2i(1, 0)).albedo().clear(BRIGHT)
    var folder := _folder()

    var answer := PixelDriver.read_into(doc, {"rect": "canvas"}, folder)
    assert_false(answer.has("error"), "the read answers without a refusal: %s" % answer)
    assert_eq(answer["rect"], [0, 0, SIZE.x, SIZE.y], "the rectangle is the canvas's")
    assert_eq(answer["shape"], [SIZE.y, SIZE.x, 4], "and the shape is its size")
    var parsed := _parse(String(answer["path"]))
    assert_eq(parsed["shape"], [SIZE.y, SIZE.x, 4], "the file's own header says the same")
    assert_eq(_texel_of(parsed, Vector2i(300, 10)).r, 2.0, "the painted chunk is where it was")
    assert_eq(_texel_of(parsed, Vector2i(10, 10)), Color(0, 0, 0, 0), "and the rest of the canvas is zeros")
    assert_eq(doc.active_layer.chunks.keys(), [Vector2i(1, 0)], "and the read allocated nothing")

    var refused := PixelDriver.write_from(doc, {"rect": "canvas", "file": "none.npy"}, folder)
    assert_true(String(refused.get("error", "")).contains("[x, y, w, h]"), "a write is given four numbers: %s" % refused)

    doc.free()
    _clear(folder)


## A read where nothing is painted answers zeros and allocates nothing.
func test_a_read_over_no_paint_answers_zeros_and_allocates_nothing() -> void:
    var doc := _document()
    var folder := _folder()

    var answer := PixelDriver.read_into(doc, {"rect": [100, 100, 300, 20]}, folder)
    var parsed := _parse(String(answer["path"]))
    var body: PackedByteArray = parsed["body"]
    var zeros := PackedByteArray()
    zeros.resize(300 * 20 * 16)
    assert_eq(body, zeros, "every byte of the body is zero")
    assert_true(doc.active_layer.chunks.is_empty(), "and the layer still holds no chunk")

    var empty := PixelDriver.read_into(doc, {"file": "empty.npy"}, folder)
    assert_eq(empty["shape"], [0, 0, 4], "an empty layer with no rectangle answers an empty array")

    doc.free()
    _clear(folder)


## A file of known values into an empty layer allocates only the chunk its
## paint reaches, reads back as written, and one undo takes it away.
func test_a_write_allocates_only_where_it_paints_and_undoes_in_one_step() -> void:
    var doc := _document()
    var folder := _folder()
    # Twenty across from 246, so the rectangle reaches both chunks. Only the
    # right half, x from 256, carries paint, and chunk (0, 0) must stay empty.
    var floats := PackedFloat32Array()
    for y in 20:
        for x in 20:
            var paint := 246 + x >= 256
            floats.append_array([3.0 if paint else 0.0, 0.25 if paint else 0.0, 0.0, 1.0 if paint else 0.0])
    var path := folder.path_join("known.npy")
    _save(path, Vector2i(20, 20), floats)

    var answer := PixelDriver.write_from(doc, {"rect": [246, 5, 20, 20], "file": "known.npy", "name": "Known"}, folder)
    assert_false(answer.has("error"), "the write answers without a refusal: %s" % answer)
    assert_eq(answer["chunks"], [[1, 0]], "it names the one chunk it wrote")
    assert_eq(doc.active_layer.chunks.keys(), [Vector2i(1, 0)], "and only that chunk is allocated")
    var texel: Dictionary = TexelProbe._read_point(doc, null, Vector2i(260, 10))["layer"]
    assert_eq(Color(texel["r"], texel["g"], texel["b"], texel["a"]), Color(3.0, 0.25, 0.0, 1.0), "the texel is the array's")
    assert_eq(doc.undo_redo.get_current_action_name(), "Known", "the step carries the name the request gave")

    assert_true(doc.undo_redo.undo(), "one undo")
    assert_true(doc.active_layer.chunks.is_empty(), "takes the chunk away again")
    assert_false(doc.undo_redo.has_undo(), "and it was the only step")

    doc.free()
    _clear(folder)


## A missing layer, a shape that does not match the rectangle and a file that
## is not there are each a verdict saying which, with the layer untouched.
func test_a_bad_request_says_which_and_leaves_the_layer_alone() -> void:
    var doc := _document()
    var folder := _folder()
    _save(folder.path_join("small.npy"), Vector2i(2, 2), _filled(4, BRIGHT))

    var missing := PixelDriver.write_from(doc, {"layer": "Nope", "rect": [0, 0, 2, 2], "file": "small.npy"}, folder)
    assert_true(String(missing.get("error", "")).contains("Nope"), "a missing layer is named: %s" % missing)
    var index := PixelDriver.read_into(doc, {"layer": 7}, folder)
    assert_true(String(index.get("error", "")).contains("7"), "and so is an index past the stack: %s" % index)
    var shape := PixelDriver.write_from(doc, {"rect": [0, 0, 3, 2], "file": "small.npy"}, folder)
    assert_true(String(shape.get("error", "")).contains("(2, 2, 4)"), "a shape that does not fit says both: %s" % shape)
    var gone := PixelDriver.write_from(doc, {"rect": [0, 0, 2, 2], "file": "gone.npy"}, folder)
    assert_true(String(gone.get("error", "")).contains("not there"), "a file that is not there says so: %s" % gone)
    var text := folder.path_join("text.npy")
    var file := FileAccess.open(text, FileAccess.WRITE)
    file.store_string("not an array")
    file.close()
    var bad := PixelDriver.write_from(doc, {"rect": [0, 0, 2, 2], "file": text}, folder)
    assert_true(String(bad.get("error", "")).contains("not a .npy"), "and a file that is not one says that: %s" % bad)

    assert_true(doc.active_layer.chunks.is_empty(), "no refusal allocated a chunk")
    assert_false(doc.undo_redo.has_undo(), "or recorded a step")

    doc.free()
    _clear(folder)


## The header is padded so the body starts on a 64 byte boundary, which is
## what NumPy's version 1.0 asks of a writer.
func test_the_header_ends_on_a_64_byte_boundary() -> void:
    for size: Vector2i in [Vector2i(1, 1), Vector2i(2048, 2048), Vector2i(0, 0)]:
        var header := PixelDriver.Npy.header(size)
        assert_eq(header.size() % 64, 0, "the header for %s is a multiple of 64 bytes" % size)
        assert_eq(header[header.size() - 1], 0x0A, "and ends in a newline")


func _document() -> SaDocument:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := SaDocument.new()
    doc.setup_default_document(SIZE, compositor)
    return doc


func _folder() -> String:
    var folder := OS.get_temp_dir().path_join("sara-p2-pixels-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(folder)
    return folder


func _clear(folder: String) -> void:
    for name in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(name))
    DirAccess.remove_absolute(folder)


func _filled(count: int, color: Color) -> PackedFloat32Array:
    var floats := PackedFloat32Array()
    for _i in count:
        floats.append_array([color.r, color.g, color.b, color.a])
    return floats


func _save(path: String, size: Vector2i, floats: PackedFloat32Array) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(PixelDriver.Npy.header(size))
    file.store_buffer(floats.to_byte_array())
    file.close()


## The file at *path* read by hand: the magic, the version, the header's own
## words and the body, with its shape as `[h, w, 4]`.
func _parse(path: String) -> Dictionary:
    var bytes := FileAccess.get_file_as_bytes(path)
    assert_eq(bytes.slice(0, 6), PackedByteArray([0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]), "the file opens with NumPy's magic")
    assert_eq(bytes.slice(6, 8), PackedByteArray([1, 0]), "at version 1.0")
    var length := bytes.decode_u16(8)
    var text := bytes.slice(10, 10 + length).get_string_from_ascii()
    assert_true(text.contains("'descr': '<f4'"), "the dtype is little endian float32: %s" % text)
    assert_true(text.contains("'fortran_order': False"), "in C order")
    var shape := RegEx.create_from_string("'shape': \\((\\d+), (\\d+), 4\\)").search(text)
    assert_not_null(shape, "and the shape is (h, w, 4): %s" % text)
    var body := bytes.slice(10 + length)
    var dims := [int(shape.get_string(1)), int(shape.get_string(2)), 4]
    assert_eq(body.size(), dims[0] * dims[1] * 16, "the body is four floats a texel")
    return {"shape": dims, "width": dims[1], "body": body}


func _texel_of(parsed: Dictionary, at: Vector2i) -> Color:
    var body: PackedByteArray = parsed["body"]
    var offset := (at.y * int(parsed["width"]) + at.x) * 16
    return Color(
        body.decode_float(offset), body.decode_float(offset + 4), body.decode_float(offset + 8), body.decode_float(offset + 12)
    )
