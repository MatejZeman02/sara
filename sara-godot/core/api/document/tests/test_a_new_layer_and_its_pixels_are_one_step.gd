## `write_pixels` with `new_layer` adds the layer and fills it
## as one undo step, so the Fourier lab's spectrum goes with one Ctrl+Z.
##
## The pixel step's arithmetic is static, so the cases drive it on a document
## of their own, as `test_pixels_cross_the_door_as_a_file.gd` does, and
## count the steps on the document's own UndoRedo.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const TexelProbe = preload("res://harness/report/sa_texel_probe.gd")

## Needs a RenderingDevice, because the write uploads into chunks.
const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)

## A value no clamp would leave alone.
const BRIGHT := Color(2.0, 0.5, 0.25, 1.0)


## The layer lands above the active one with the array's texels, the history
## grows by one step carrying the request's name, one undo leaves the stack as
## it was and one redo brings the layer back with its pixels.
func test_the_add_and_the_write_are_one_step() -> void:
    var doc := _document()
    var folder := _folder()
    _save(folder.path_join("bright.npy"), Vector2i(4, 4), _filled(16, BRIGHT))
    var before := _names(doc)
    var active := doc.active_layer
    var steps := doc.undo_redo.get_history_count()

    var answer := PixelDriver.write_from(
        doc, {"new_layer": "Spectrum", "rect": [300, 10, 4, 4], "file": "bright.npy", "name": "Fourier magnitude"}, folder
    )
    assert_false(answer.has("error"), "the write answers without a refusal: %s" % answer)
    assert_eq(answer["layer"], "Spectrum", "it names the layer it added")
    assert_eq(String(doc.active_layer.name), "Spectrum", "the new layer is active")
    assert_eq(doc.active_layer.get_index(), active.get_index() + 1, "and stands above the one that was")
    assert_eq(_texel(doc, Vector2i(301, 11)), BRIGHT, "holding the array's texels, unclamped")
    assert_eq(doc.undo_redo.get_history_count(), steps + 1, "the add and the write are one step")
    assert_eq(doc.undo_redo.get_current_action_name(), "Fourier magnitude", "called what the request said")

    assert_true(doc.undo_redo.undo(), "one undo")
    assert_eq(_names(doc), before, "leaves the stack as it was")
    assert_eq(doc.active_layer, active, "with the old layer active again")

    assert_true(doc.undo_redo.redo(), "one redo")
    assert_eq(String(doc.active_layer.name), "Spectrum", "brings the layer back")
    assert_eq(_texel(doc, Vector2i(301, 11)), BRIGHT, "with its pixels")

    doc.free()
    _clear(folder)


## A request the write refuses adds no layer and records no step.
func test_a_refused_write_adds_nothing() -> void:
    var doc := _document()
    var folder := _folder()
    _save(folder.path_join("small.npy"), Vector2i(2, 2), _filled(4, BRIGHT))
    var before := _names(doc)
    var steps := doc.undo_redo.get_history_count()

    var shape := PixelDriver.write_from(doc, {"new_layer": "Spectrum", "rect": [0, 0, 3, 2], "file": "small.npy"}, folder)
    assert_true(shape.has("error"), "a shape that does not fit is refused: %s" % shape)
    var nameless := PixelDriver.write_from(doc, {"new_layer": "", "rect": [0, 0, 2, 2], "file": "small.npy"}, folder)
    assert_true(String(nameless.get("error", "")).contains("name"), "so is a layer with no name: %s" % nameless)
    assert_eq(_names(doc), before, "and neither added a layer")
    assert_eq(doc.undo_redo.get_history_count(), steps, "or recorded a step")

    doc.free()
    _clear(folder)


func _texel(doc: SaDocument, at: Vector2i) -> Color:
    var texel: Dictionary = TexelProbe._read_point(doc, null, at)["layer"]
    return Color(texel["r"], texel["g"], texel["b"], texel["a"])


func _names(doc: SaDocument) -> PackedStringArray:
    var names := PackedStringArray()
    for layer: SaLayer in SaLayerOps.new(doc).layers():
        names.append(String(layer.name))
    return names


func _document() -> SaDocument:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := SaDocument.new()
    doc.setup_default_document(SIZE, compositor)
    return doc


func _folder() -> String:
    var folder := OS.get_temp_dir().path_join("sara-a2-pixels-%d" % OS.get_process_id())
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
