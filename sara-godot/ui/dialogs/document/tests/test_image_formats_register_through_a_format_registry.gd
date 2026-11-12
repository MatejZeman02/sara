## The picture formats register through a format registry.
##
## The import's extension list, OpenRaster's and the Export dialog's six
## tables were three spellings of one list, so a format a module brought had
## nowhere to stand. Each built-in now registers an `SaImageFormat` through the
## module door, and every caller asks the registry. This suite holds the
## registry to what the old tables said, copied here as literals, registers a
## stranger's format through a scoped module context and takes it away again,
## and writes a small canvas in each of the five Export formats through the
## registry and reads each back.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the canvas the exports read back from.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ExportDialogScript = preload("res://ui/dialogs/document/export_dialog.gd")

## The old import list and the OpenRaster reader's one extension, in that order.
const OPEN_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "exr", "tif", "tiff", "hdr", "ora"]
## The old `FORMATS`, `FORMAT_LABELS`, `FORMAT_SUFFIXES`, `FORMAT_FILTERS`,
## `DEPTH_CHOICES`, `DEFAULT_DEPTHS`, `LAYERED_FORMATS` and `AUTHOR_FORMATS` of
## the Export dialog, one row a format. A format with no depth row had no entry
## in `DEFAULT_DEPTHS`, and its depth is the one its writer always used.
const EXPORTED := [
    ["png", "PNG", ".png", "*.png ; PNG Image", [8, 16], 8, false, true],
    ["jpg", "JPG", ".jpg", "*.jpg, *.jpeg ; JPEG Image", [], 8, false, false],
    ["exr", "EXR", ".exr", "*.exr ; OpenEXR Image", [], 32, false, false],
    ["tiff", "TIFF", ".tiff", "*.tif, *.tiff ; TIFF Image", [16, 32], 32, false, true],
    ["ora", "OpenRaster", ".ora", "*.ora ; OpenRaster Image", [8, 16], 8, true, true],
]
const STRANGER := &"stranger"
const PAINT := Color(0.2, 0.4, 0.6, 1.0)

var _registries: SaRegistries


func before_each() -> void:
    _registries = Fixtures.make_picture_registries()


func after_each() -> void:
    _registries = null


func test_the_registry_opens_what_the_old_lists_opened() -> void:
    assert_eq(Array(_registries.image_formats.open_extensions()), OPEN_EXTENSIONS, "the old eight and ora, in order")
    assert_eq(SaImageImport.formats(), _registries.image_formats, "and the static import asks the app's registry")


func test_the_registry_exports_what_the_old_tables_said() -> void:
    var formats := _registries.image_formats.exported()
    assert_eq(formats.size(), EXPORTED.size(), "five formats, in Export's order")
    for index in mini(formats.size(), EXPORTED.size()):
        var format := formats[index]
        var old: Array = EXPORTED[index]
        assert_eq(String(format.id), old[0], "format %d is %s" % [index, old[0]])
        assert_eq(format.label, old[1], "%s is labelled %s" % [old[0], old[1]])
        assert_eq(format.suffix, old[2], "%s takes %s" % [old[0], old[2]])
        assert_eq(format.save_filter, old[3], "%s's save filter" % old[0])
        assert_eq(format.depth_ids(), old[4] as Array[int], "%s's depth choices" % old[0])
        assert_eq(format.default_depth, old[5], "%s's default depth" % old[0])
        assert_eq(format.keeps_layers, old[6], "%s keeps the layers or not" % old[0])
        assert_eq(format.names_author, old[7], "%s names the author or not" % old[0])


func test_a_strangers_format_comes_and_goes_with_its_module() -> void:
    var canvas := _canvas()
    var dialog := ExportDialogScript.new(canvas, &"png")
    var context := _registries.context.for_module(STRANGER)
    assert_true(context.register_image_format(_stranger()), "a module registers a format through its context")
    assert_true(SaImageImport.dialog_filter().contains("*.strn"), "the open filter lists it")
    assert_true(SaImageImport.is_image_path("/a/b/picture.STRN"), "a file of it is a picture")
    assert_true(_offered(dialog).has(&"strn"), "and the open Export dialog lists it")
    assert_true(ExportDialogScript.format_ids().has(&"strn"), "as does a dialog opened after it")
    _registries.image_formats.unregister_module(STRANGER)
    assert_false(SaImageImport.dialog_filter().contains("*.strn"), "taken away, the open filter forgets it")
    assert_false(SaImageImport.is_image_path("picture.strn"), "a file of it is a picture no longer")
    assert_false(_offered(dialog).has(&"strn"), "and the Export dialog lists it no longer")
    dialog.free()
    canvas.free()


func test_a_module_cannot_take_a_built_in_formats_id() -> void:
    var context := _registries.context.for_module(STRANGER)
    var impostor := _stranger()
    impostor.id = &"png"
    assert_false(context.register_image_format(impostor), "PNG is the skeleton's")
    assert_eq(_registries.image_formats.find(&"png").label, "PNG", "and stays as it was")


func test_each_export_format_writes_through_the_registry_and_reads_back() -> void:
    var canvas := _canvas()
    for format in _registries.image_formats.exported():
        var path := SaDataRoot.path("round_trip" + format.suffix)
        var options := SaImageFormat.Write.new()
        options.depth = format.default_depth
        assert_eq(format.writer.call(canvas.easel, path, options), OK, "%s writes" % format.label)
        var expected := PAINT.srgb_to_linear() if format.linear else PAINT
        var middle := _read_back(format, path)
        assert_true(_near(middle, expected), "%s reads back the paint: %s against %s" % [format.label, middle, expected])
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    canvas.free()


## The middle texel of *path* read back through *format*'s own route: the
## flat reader, or the layered opener into a document of its own.
func _read_back(format: SaImageFormat, path: String) -> Color:
    if format.reads():
        var image: Image = format.reader.call(path)
        return image.get_pixel(image.get_width() >> 1, image.get_height() >> 1) if image != null else Color.BLACK
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var color := Color.BLACK
    if format.opener.call(path, easel.document, SaColorSpace.Depth.F32) == OK:
        easel.request_composite()
        easel.process_pending_composite()
        var image := SaExport.get_easel_image_float(easel)
        color = image.get_pixel(32, 32) if image != null else color
    easel.free()
    return color


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 0.03 and absf(a.g - b.g) < 0.03 and absf(a.b - b.b) < 0.03


## The ids the Export dialog's format row offers.
func _offered(dialog: SaExportDialog) -> Array:
    return dialog.page.row(&"format").choices.map(func(choice: Dictionary) -> StringName: return choice["id"])


## A format no built-in knows: a flat file under `.strn` that reads as a small
## grey picture and writes nothing but a marker, which is all a registry asks.
func _stranger() -> SaImageFormat:
    var stranger := SaImageFormat.new(&"strn", "Stranger")
    stranger.extensions = PackedStringArray(["strn"])
    stranger.reader = func(_path: String) -> Image: return Image.create(2, 2, false, Image.FORMAT_RGBAF)
    stranger.writer = func(_easel: SaEasel, path: String, _options: SaImageFormat.Write) -> Error:
        var file := FileAccess.open(path, FileAccess.WRITE)
        return OK if file != null else FileAccess.get_open_error()
    stranger.suffix = ".strn"
    stranger.save_filter = "*.strn ; Stranger"
    stranger.note = "Every value survives."
    return stranger


func _canvas() -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    canvas.document.fill_layer(PAINT)
    canvas.easel.request_composite()
    canvas.easel.process_pending_composite()
    return canvas
