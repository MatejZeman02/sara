## The door's three pixel steps meet a layer at resolution 2.0
## as a layer at 2.0, not as 256 texels over 256 document pixels.
##
## `write_pixels` and `kernel` refuse to make a chunk at 2.0, since the copy
## they make is a texel for a document pixel, and the refusal names the
## layer's scale. `reduce` weighs each texel by the document area it covers,
## so a double layer answers the mean and the count of the plain one.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const KernelDriver := preload("res://harness/sa_kernel_driver.gd")

const REQUIRES_GPU := true

## Four chunks across and down, so a run can land away from the origin.
const SIZE := Vector2i(1024, 1024)

## A kernel that copies its source, so the result is the paint it read.
const COPY := """kernel copy

image src: readonly
image dst

def copy():
    image_store(dst, pixel, image_load(src, pixel))
"""

const RED := Color(1.0, 0.0, 0.0, 1.0)
const GREY := Color(0.5, 0.5, 0.5, 0.5)


## A 64 pixel square written at (256, 256) into a double layer holding no
## chunk there is refused by the layer's scale, and nothing is allocated.
func test_a_write_into_a_double_layer_is_refused_by_its_scale() -> void:
    var doc := _document()
    var double := SaLayerOps.new(doc).add(&"", null, 2.0)
    double.name = "Double"
    var folder := _folder()
    _save(folder.path_join("red.npy"), Vector2i(64, 64), RED)
    var steps_before := doc.undo_redo.get_history_count()

    var answer := PixelDriver.write_from(doc, {"layer": "Double", "rect": [256, 256, 64, 64], "file": "red.npy"}, folder)
    assert_true(answer.has("error"), "the write is refused: %s" % answer)
    assert_true(String(answer.get("error", "")).contains("resolution 2"), "by the layer's scale: %s" % answer)
    assert_true(double.chunks.is_empty(), "and the layer holds no chunk")
    assert_eq(doc.undo_redo.get_history_count(), steps_before, "and no history step was made")

    # The same write into a plain layer lands, so the refusal is the scale's.
    var plain := SaLayerOps.new(doc).add(&"")
    plain.name = "Plain"
    var landed := PixelDriver.write_from(doc, {"layer": "Plain", "rect": [256, 256, 64, 64], "file": "red.npy"}, folder)
    assert_false(landed.has("error"), "the plain layer takes it: %s" % landed)
    doc.free()
    _clear(folder)


## A kernel run at (600, 600) into a double layer holding no chunk there is
## refused by the layer's scale before it writes anything.
func test_a_kernel_into_a_double_layer_is_refused_by_its_scale() -> void:
    var easel := SaEasel.create_default(SIZE)
    var doc := easel.document
    var read := doc.active_layer
    read.name = "Read"
    read.get_or_create_chunk(Vector2i(2, 2)).clear(RED)
    var double := SaLayerOps.new(doc).add(&"", null, 2.0)
    double.name = "Double"
    var steps_before := doc.undo_redo.get_history_count()

    var verdict := KernelDriver.new(null).run_on(
        doc, {"source": COPY, "name": "copy", "layer": "Read", "into": "Double", "rect": [600, 600, 64, 64]}
    )
    assert_false(bool(verdict["ok"]), "the run is refused: %s" % [verdict])
    assert_true(String(verdict.get("error", "")).contains("resolution 2"), "by the layer's scale: %s" % [verdict])
    assert_true(double.chunks.is_empty(), "and the layer holds no chunk")
    assert_eq(doc.undo_redo.get_history_count(), steps_before, "and no history step was made")
    easel.free()


## One chunk of 0.5 grey answers the same count and mean on a double layer as
## on a plain one, and a rectangle over two chunks counts the empty one as
## zeros in document pixels.
func test_a_reduce_over_a_double_layer_is_the_documents() -> void:
    var doc := _document()
    var plain := doc.active_layer
    plain.get_or_create_chunk(Vector2i.ZERO).clear(GREY)
    var double := SaLayerOps.new(doc).add(&"", null, 2.0)
    double.get_or_create_chunk(Vector2i.ZERO).clear(GREY)
    assert_eq(double.chunks[Vector2i.ZERO].pixel_size(), 512, "the double layer's chunk is 512 texels across")

    for layer: SaLayer in [plain, double]:
        var chunk := SaReduce.new(layer).reduce(Rect2i(0, 0, 256, 256))
        var label := "at %s" % layer.resolution_scale
        assert_eq(chunk["texels"], 65536, "the chunk is 65536 document pixels %s" % label)
        assert_eq(chunk["allocated"], 65536, "and all of them held %s" % label)
        _assert_near(chunk["mean"], 0.5, "the mean is the grey's %s" % label)
        _assert_near(chunk["sum"], 32768.0, "the sum is by document pixels %s" % label)

        var two := SaReduce.new(layer).reduce(Rect2i(0, 0, 512, 256))
        assert_eq(two["allocated"], 65536, "two chunks with one held count one %s" % label)
        _assert_near(two["mean"], 0.25, "and the empty one is zeros %s" % label)

        var cut := SaReduce.new(layer).reduce(Rect2i(64, 64, 32, 32))
        assert_eq(cut["allocated"], 1024, "a rectangle inside the chunk counts its own area %s" % label)
        _assert_near(cut["mean"], 0.5, "and means the grey %s" % label)
    doc.free()


func _assert_near(channels: Variant, expected: float, message: String) -> void:
    var ok := channels is Array and (channels as Array).size() == 4
    if ok:
        for value: Variant in channels:
            ok = ok and absf(float(value) - expected) < 1e-3 * maxf(1.0, absf(expected))
    assert_true(ok, "%s: %s" % [message, channels])


func _document() -> SaDocument:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := SaDocument.new()
    doc.setup_default_document(SIZE, compositor)
    return doc


func _folder() -> String:
    var folder := OS.get_temp_dir().path_join("sara-d18-pixels-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(folder)
    return folder


func _clear(folder: String) -> void:
    for name in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(name))
    DirAccess.remove_absolute(folder)


func _save(path: String, size: Vector2i, color: Color) -> void:
    var floats := PackedFloat32Array()
    for _i in size.x * size.y:
        floats.append_array([color.r, color.g, color.b, color.a])
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(PixelDriver.Npy.header(size))
    file.store_buffer(floats.to_byte_array())
    file.close()
