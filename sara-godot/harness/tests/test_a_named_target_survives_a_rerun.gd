## Every target a door step names follows one rule, a layer of
## that name is used again and one is made above the active layer only when
## there is none, so a notebook cell run twice leaves one layer of that name.
##
## Each case runs one target twice with the same name and different pixels,
## and holds one layer of that name after, holding the second run's pixels.
## The steps are static or take the document, so the cases drive them on an
## easel of their own, and a pixel is read back the way an export does, the one
## readback hard rule 1 permits a test.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, because every target writes into chunks.
const REQUIRES_GPU := true

const PixelDriver := preload("res://harness/scenario/sa_scenario_pixels.gd")
const KernelDriver := preload("res://harness/sa_kernel_driver.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const SaExportScript = preload("res://core/export/sa_export.gd")

## A kernel that writes its param as the colour, so each run's pixels are its own.
const FLAT := """kernel flat

image src: readonly
image dst

params:
    float level

def flat():
    image_store(dst, pixel, vec4(level, level, level, 1.0))
"""

const FIRST := Color(0.25, 0.5, 0.75, 1.0)
const SECOND := Color(2.0, 0.5, 0.125, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _folder := ""


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _folder = OS.get_temp_dir().path_join("sara-d63-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    for name in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))
    DirAccess.remove_absolute(_folder)


## `write_pixels` with `new_layer`: the second run writes into the first's
## layer, which it makes active as the add did, rather than adding one Godot
## names `@Node@3`.
func test_new_layer_twice_is_one_layer_holding_the_second_array() -> void:
    var count := _layers().size()
    for color: Color in [FIRST, SECOND]:
        _save_npy("spectrum.npy", Vector2i(4, 4), color)
        var answer := PixelDriver.write_from(
            _doc, {"new_layer": "Spectrum", "rect": [8, 8, 4, 4], "file": "spectrum.npy"}, _folder
        )
        assert_false(answer.has("error"), "the write answers without a refusal: %s" % answer)
        assert_eq(answer["layer"], "Spectrum", "and names the layer it wrote")
    assert_eq(_named("Spectrum"), 1, "one layer called Spectrum")
    assert_eq(_layers().size(), count + 1, "and only the one added")
    assert_eq(String(_doc.active_layer.name), "Spectrum", "which is active")
    assert_true(_near(_texel(_layer("Spectrum"), Vector2i(9, 9)), SECOND), "holding the second array, unclamped")


## The layer step's `add`: the second run keeps the layer rather than adding
## one Godot renames "Paint2".
func test_add_twice_is_one_layer_and_the_second_fill_lands_in_it() -> void:
    var count := _layers().size()
    var first := SaCaptureLayers.run(_doc, {"add": "Paint", "fill": [FIRST.r, FIRST.g, FIRST.b, FIRST.a]})
    var second := SaCaptureLayers.run(_doc, {"add": "Paint", "fill": [SECOND.r, SECOND.g, SECOND.b, SECOND.a]})
    assert_true(first.contains("added Paint"), "the first run adds: %s" % first)
    assert_true(second.contains("kept Paint"), "the second keeps: %s" % second)
    assert_eq(_named("Paint"), 1, "one layer called Paint")
    assert_eq(_layers().size(), count + 1, "and only the one added")
    assert_true(_near(_texel(_layer("Paint"), Vector2i(3, 3)), SECOND), "holding the second fill")


## The kernel's `into`: a name no layer has is made, where it was refused, and
## the second run writes into it. A run that names no `into` keeps the layer
## named after the kernel the same way.
func test_a_kernel_into_a_new_name_twice_is_one_layer() -> void:
    var paint := _doc.active_layer
    paint.get_or_create_chunk(Vector2i(0, 0)).clear(FIRST)
    var driver := KernelDriver.new(null)
    var count := _layers().size()
    for level: float in [0.25, 0.75]:
        var spec := {"source": FLAT, "name": "flat", "layer": String(paint.name), "into": "Result", "params": {"level": level}}
        var verdict := driver.run_on(_doc, spec)
        assert_true(bool(verdict["ok"]), "the kernel ran: %s" % [verdict])
        assert_eq(verdict["into"], "Result", "into the layer it named")
    assert_eq(_named("Result"), 1, "one layer called Result")
    assert_true(_near(_texel(_layer("Result"), Vector2i(5, 5)), Color(0.75, 0.75, 0.75, 1.0)), "holding the second run")

    for level: float in [0.25, 0.5]:
        var verdict := driver.run_on(
            _doc, {"source": FLAT, "name": "flat", "layer": String(paint.name), "params": {"level": level}}
        )
        assert_true(bool(verdict["ok"]), "the kernel ran with no into: %s" % [verdict])
    assert_eq(_named("flat"), 1, "one layer called after the kernel")
    assert_eq(_layers().size(), count + 2, "and the two names made two layers in all")
    assert_true(_near(_texel(_layer("flat"), Vector2i(5, 5)), Color(0.5, 0.5, 0.5, 1.0)), "holding the second run")


## An index names a layer that has to exist, because there is no name to make.
func test_a_kernel_into_a_missing_index_is_refused() -> void:
    var count := _layers().size()
    var verdict := KernelDriver.new(null).run_on(_doc, {"source": FLAT, "name": "flat", "into": 40, "params": {"level": 0.5}})
    assert_false(bool(verdict["ok"]), "refused: %s" % [verdict])
    assert_eq(_layers().size(), count, "and nothing was added")


## The import: the second picture of one name takes the first's place and name,
## where it would otherwise add "chart 2", and holds what the same file holds imported
## under a name of its own.
func test_an_import_twice_is_one_layer_holding_the_second_file() -> void:
    var count := _layers().size()
    var chart := _folder.path_join("chart.png")
    _save_png(chart, Color(0.0, 0.0, 0.0, 1.0))
    assert_true(StepTable.import_named(_doc, chart) is SaLayer, "the first import lands")
    var below := _layers().find(_layer("chart"))
    _save_png(chart, Color(1.0, 0.5, 0.0, 1.0))
    var again: Variant = StepTable.import_named(_doc, chart)
    assert_true(again is SaLayer, "and so does the second")
    assert_eq(_named("chart"), 1, "one layer called chart")
    assert_eq(_layers().size(), count + 1, "and only the one added")
    assert_eq(_layers().find(_layer("chart")), below, "standing where the first did")

    var other := _folder.path_join("other.png")
    _save_png(other, Color(1.0, 0.5, 0.0, 1.0))
    StepTable.import_named(_doc, other)
    assert_true(
        _near(_texel(_layer("chart"), Vector2i(2, 2)), _texel(_layer("other"), Vector2i(2, 2))), "holding the second file"
    )


## A locked layer of the name is refused rather than replaced.
func test_an_import_over_a_locked_layer_is_refused() -> void:
    var chart := _folder.path_join("chart.png")
    _save_png(chart, Color(0.0, 0.0, 0.0, 1.0))
    StepTable.import_named(_doc, chart)
    SaLayerOps.new(_doc).set_locked(_layer("chart"), true)
    var count := _layers().size()
    assert_true(StepTable.import_named(_doc, chart) is String, "the second import is refused")
    assert_eq(_layers().size(), count, "and adds nothing")


func _layers() -> Array[SaLayer]:
    return SaLayerOps.new(_doc).layers()


func _layer(layer_name: String) -> SaLayer:
    return PixelDriver.named_target(_doc, layer_name)


func _named(layer_name: String) -> int:
    return _layers().filter(func(layer: SaLayer) -> bool: return String(layer.name) == layer_name).size()


## The texel at *at* of *layer*'s first chunk, where every case reads.
func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var image := SaExportScript.get_texture_image_float(layer.chunks[Vector2i.ZERO].field(SaFieldSpec.ALBEDO))
    return image.get_pixel(at.x, at.y)


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 1e-3 and absf(a.g - b.g) < 1e-3 and absf(a.b - b.b) < 1e-3 and absf(a.a - b.a) < 1e-3


func _save_npy(file_name: String, size: Vector2i, color: Color) -> void:
    var floats := PackedFloat32Array()
    for _i in size.x * size.y:
        floats.append_array([color.r, color.g, color.b, color.a])
    var file := FileAccess.open(_folder.path_join(file_name), FileAccess.WRITE)
    file.store_buffer(PixelDriver.Npy.header(size))
    file.store_buffer(floats.to_byte_array())
    file.close()


func _save_png(path: String, color: Color) -> void:
    var image := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
    image.fill(color)
    image.save_png(path)
