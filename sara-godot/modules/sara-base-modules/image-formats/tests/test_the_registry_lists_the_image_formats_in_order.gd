## The format registry lists the image formats in order.
##
## With the module loaded the registry holds the open extensions and the five
## export rows (PNG, JPG, EXR, TIFF, OpenRaster) in that order. With the
## skeleton alone it holds the four engine formats, and a `.tif` is refused with
## a sentence through `SaProblems`. Last, a small canvas goes out as a 16-bit and
## a 32-bit TIFF and a two-layer one as OpenRaster, and each comes back through
## the registry's own reader or opener with its pixels and its layers.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the canvases written and read back.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The extensions the registry opens, in the order it lists them.
const OPEN_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "exr", "tif", "tiff", "hdr", "ora"]
## The built-in Export rows: id, label, suffix, save filter, depth choices,
## default depth, whether the layers are kept and whether a painter is named.
const EXPORTED := [
    ["png", "PNG", ".png", "*.png ; PNG Image", [8, 16], 8, false, true],
    ["jpg", "JPG", ".jpg", "*.jpg, *.jpeg ; JPEG Image", [], 8, false, false],
    ["exr", "EXR", ".exr", "*.exr ; OpenEXR Image", [], 32, false, false],
    ["tiff", "TIFF", ".tiff", "*.tif, *.tiff ; TIFF Image", [16, 32], 32, false, true],
    ["ora", "OpenRaster", ".ora", "*.ora ; OpenRaster Image", [8, 16], 8, true, true],
]
## What the skeleton opens and exports with no module loaded.
const SKELETON_OPENS := ["png", "jpg", "jpeg", "webp", "exr"]
const SKELETON_EXPORTS := ["PNG", "JPG", "EXR"]

const CANVAS := Vector2i(64, 64)
const GROUND := Color(0.2, 0.4, 0.6, 1.0)
const ABOVE := Color(0.8, 0.3, 0.1, 1.0)
## The canvas's middle, which the upper layer's chunk covers.
const MIDDLE := Vector2i(32, 32)

var _scratch: Array[String] = []
var _refused: Array[String] = []


func after_each() -> void:
    for path: String in _scratch:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    _scratch.clear()
    _refused.clear()
    SaProblems.detach_sink()


func _path(file: String) -> String:
    var path := SaDataRoot.path("%s" % file)
    _scratch.append(path)
    return path


## An sRGB easel at full floats holding *colors*, one layer each from the
## bottom, with *registries*' blend modes.
func _easel(registries: SaRegistries, colors: Array[Color]) -> SaEasel:
    var easel := SaEasel.create_default(CANVAS, null, SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F32))
    easel.compositor.set_registry(registries.blend_modes)
    easel.document.fill_layer(colors[0])
    var ops := SaLayerOps.new(easel.document)
    for index in range(1, colors.size()):
        var layer := ops.add()
        layer.name = "Above %d" % index
        easel.document.fill_layer(colors[index], layer)
    _composite(easel)
    return easel


func _composite(easel: SaEasel) -> void:
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()


## The names of *document*'s layers, from the bottom: the default easel's
## background and first layer, and the layers [method _easel] added.
func _names(document: SaDocument) -> Array[String]:
    var names: Array[String] = []
    for child in document.get_children():
        if child is SaLayer:
            names.append(String(child.name))
    return names


func _near(a: Color, b: Color, tolerance: float) -> bool:
    return absf(a.r - b.r) < tolerance and absf(a.g - b.g) < tolerance and absf(a.b - b.b) < tolerance


func test_with_the_module_the_registry_holds_the_formats_in_order() -> void:
    var registries := Fixtures.make_picture_registries()
    assert_eq(Array(registries.image_formats.open_extensions()), OPEN_EXTENSIONS, "the nine extensions, in order")
    var formats := registries.image_formats.exported()
    assert_eq(formats.size(), EXPORTED.size(), "five formats, in Export's order")
    for index in mini(formats.size(), EXPORTED.size()):
        var format := formats[index]
        var row: Array = EXPORTED[index]
        assert_eq(String(format.id), row[0], "format %d is %s" % [index, row[0]])
        assert_eq(format.label, row[1], "%s is labelled %s" % [row[0], row[1]])
        assert_eq(format.suffix, row[2], "%s takes %s" % [row[0], row[2]])
        assert_eq(format.save_filter, row[3], "%s's save filter" % row[0])
        assert_eq(format.depth_ids(), row[4] as Array[int], "%s's depth choices" % row[0])
        assert_eq(format.default_depth, row[5], "%s's default depth" % row[0])
        assert_eq(format.keeps_layers, row[6], "%s keeps the layers or not" % row[0])
        assert_eq(format.names_author, row[7], "%s names the author or not" % row[0])


func test_the_skeleton_alone_holds_the_four_engine_formats() -> void:
    var registries := Fixtures.make_registries()
    assert_eq(Array(registries.image_formats.open_extensions()), SKELETON_OPENS, "PNG, JPEG, WebP and EXR open")
    var labels := registries.image_formats.exported().map(func(format: SaImageFormat) -> String: return format.label)
    assert_eq(labels, SKELETON_EXPORTS, "and PNG, JPG and EXR export")
    assert_false(SaImageImport.dialog_filter().contains("*.tif"), "the open filter offers no TIFF")


func test_the_skeleton_alone_refuses_a_tiff_with_a_sentence() -> void:
    var formats := Fixtures.make_registries()
    assert_eq(SaImageImport.formats(), formats.image_formats, "the formats asked are the ones these registries installed")
    SaProblems.attach_sink(
        func(line: String, kind: SaProblems.Kind) -> void:
            if kind == SaProblems.Kind.REFUSAL:
                _refused.append(line)
    )
    var path := _path("refused.tif")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(PackedByteArray([0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0]))
    file.close()
    assert_null(SaImageImport.read(path), "a .tif reads as no picture")
    assert_eq(_refused.size(), 1, "and is refused once")
    var sentence := _refused[0] if not _refused.is_empty() else ""
    assert_true(sentence.contains("TIFF"), "naming the format: %s" % sentence)
    assert_true(sentence.contains("image formats module"), "and the module it needs: %s" % sentence)
    for other: String in ["hdr", "ora"]:
        assert_true(SaImageImport.refuses_unread(_path("refused.%s" % other)), "a .%s is refused the same way" % other)
    assert_false(SaImageImport.refuses_unread(_path("kept.sad")), "and a .sad is left to the document loader")


func test_a_tiff_at_sixteen_and_thirty_two_bits_reads_back_through_the_registry() -> void:
    var registries := Fixtures.make_picture_registries()
    var easel := _easel(registries, [GROUND] as Array[Color])
    var tiff := registries.image_formats.find(&"tiff")
    assert_not_null(tiff, "the module registered the TIFF")
    for bits: int in [16, 32]:
        var path := _path("%d.tif" % bits)
        assert_eq(Fixtures.export_through(&"tiff", easel, path, bits), OK, "the %d-bit TIFF is written" % bits)
        var picture: Image = tiff.reader.call(path) if tiff != null else null
        assert_not_null(picture, "and the %d-bit file reads back through the registry" % bits)
        if picture == null:
            continue
        assert_eq(picture.get_size(), CANVAS, "at the canvas's size")
        var read := picture.get_pixel(MIDDLE.x, MIDDLE.y)
        var tolerance := 0.00002 if bits == 16 else 0.0000001
        assert_true(_near(read, _as_saved(GROUND), tolerance), "holding the paint at %d bits: %s" % [bits, read])
    easel.free()


## *colour* as a save the painter asks for holds it, each channel a float32
## rounded to 12 significant bits, which an export rounds the live colour to
## first.
static func _as_saved(colour: Color) -> Color:
    var bytes := PackedByteArray()
    bytes.resize(4)
    for i in 4:
        bytes.encode_float(0, colour[i])
        bytes.encode_u32(0, SaSadSnapshot.round_bits(bytes.decode_u32(0)))
        colour[i] = bytes.decode_float(0)
    return colour


func test_a_two_layer_openraster_reads_back_through_the_registry() -> void:
    var registries := Fixtures.make_picture_registries()
    var easel := _easel(registries, [GROUND, ABOVE] as Array[Color])
    var path := _path("two.ora")
    var written := _names(easel.document)
    assert_eq(Fixtures.export_through(&"ora", easel, path, 16), OK, "the two painted layers are written as OpenRaster")
    easel.free()
    var ora := registries.image_formats.find(&"ora")
    assert_not_null(ora, "the module registered OpenRaster")
    if ora == null:
        return
    var opened := SaEasel.create_default(CANVAS, null, SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F32))
    opened.compositor.set_registry(registries.blend_modes)
    assert_eq(ora.opener.call(path, opened.document, SaColorSpace.Depth.F32), OK, "and open through the registry")
    var names := _names(opened.document)
    assert_eq(names, written, "as the layers written, in order: %s" % [names])
    assert_true(names.has("Above 1"), "the upper paint keeping its name")
    _composite(opened)
    var read := SaExport.get_easel_image_float(opened).get_pixel(MIDDLE.x, MIDDLE.y)
    assert_true(_near(read, ABOVE, 0.0001), "and the canvas is the upper paint: %s" % read)
    opened.free()
