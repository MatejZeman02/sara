## Export is one dialog, PNG, JPG and EXR through the same door, with TIFF and
## OpenRaster beside them. PNG and TIFF have a depth row each: PNG eight bits or
## sixteen, TIFF sixteen unsigned or thirty-two float, remembered per format.
## OpenRaster takes PNG's depths.
##
## **Nothing here writes a private of the dialog.** The canvas arrives as the
## constructor argument, and the format, the quality and the half switch are set
## through the controls the painter uses: the format is a page row, moved by the
## row's own `drive`, and writing a check's `button_pressed` delivers the same
## signal a hand does. Driving the controls is the stronger test as well: it
## proves the row a painter touches is wired to the field the export reads.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice, for the canvas the dialog reads back from.
const REQUIRES_GPU := true

const ExportDialogScript = preload("res://ui/dialogs/document/export_dialog.gd")

## The skeleton's formats with the image formats module's after them, as the
## running app registers them, built again before each test.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()


func _painted_canvas(color: Color) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    canvas.document.fill_layer(color)
    canvas.easel.request_composite()
    canvas.easel.process_pending_composite()
    return canvas


func _cleanup(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The three kept under one door, TIFF beside them because Sara has its own
## writer for the one format Godot cannot encode, and OpenRaster, the one that
## keeps the layers.
func test_the_arrow_menu_offers_png_jpg_exr_tiff_and_openraster() -> void:
    assert_eq(
        ExportDialogScript.format_ids(),
        [&"png", &"jpg", &"exr", &"tiff", &"ora"],
        "the three formats the note asked to keep under one door, TIFF and OpenRaster"
    )


## OpenRaster through the dialog: a zip whose first entry names the format,
## the depth row PNG's, and a line under the page naming the layer whose mode
## the file writes as normal, before the painter confirms.
func test_openraster_names_what_it_loses_and_writes_the_layers() -> void:
    var canvas := _painted_canvas(Color(0.25, 0.5, 0.75, 1.0))
    var dialog := ExportDialogScript.new(canvas, &"png")
    _pick_format(dialog, &"ora")
    assert_true(dialog.shows(&"depth"), "OpenRaster offers PNG's depths")
    assert_false(dialog._loss_label.visible, "A document with nothing to lose says nothing")
    (canvas.document.get_node("Layer 1") as SaLayer).blend_mode = &"exclusion"
    dialog._sync_options()
    assert_true(dialog._loss_label.visible, "One it loses a mode of says so")
    assert_true(dialog._loss_label.text.contains("Layer 1 (Exclusion)"), "naming the layer and its mode")

    var path := SaDataRoot.path("test_export.ora")
    dialog._export_to(path)
    SaExportInTurns.finish_all()
    var reader := ZIPReader.new()
    assert_eq(reader.open(path), OK, "the file opens as a zip")
    assert_eq(reader.get_files()[0], "mimetype", "with the mimetype first")
    assert_true(reader.file_exists("stack.xml"), "and a stack")
    reader.close()

    _cleanup(path)
    dialog.free()
    canvas.free()


func test_png_round_trips_at_8_bit() -> void:
    var canvas := _painted_canvas(Color(0.25, 0.5, 0.75, 1.0))
    var dialog := ExportDialogScript.new(canvas, &"png")
    var path := SaDataRoot.path("test_export.png")
    dialog._export_to(path)
    SaExportInTurns.finish_all()

    var back := Image.load_from_file(path)
    assert_not_null(back, "the PNG loads back")
    assert_eq(back.get_format(), Image.FORMAT_RGBA8, "PNG is the 8-bit container it always is")

    _cleanup(path)
    dialog.free()
    canvas.free()


## A higher JPG quality asks the encoder for more bytes, so the option the
## dialog exposes is not decorative.
func test_jpg_round_trips_at_the_chosen_quality() -> void:
    var canvas := _painted_canvas(Color(0.6, 0.2, 0.8, 1.0))
    var low := ExportDialogScript.new(canvas, &"jpg", 0.1)
    var low_path := SaDataRoot.path("test_export_low.jpg")
    low._export_to(low_path)
    SaExportInTurns.finish_all()

    var high := ExportDialogScript.new(canvas, &"jpg", 1.0)
    var high_path := SaDataRoot.path("test_export_high.jpg")
    high._export_to(high_path)
    SaExportInTurns.finish_all()

    var low_size := FileAccess.get_file_as_bytes(low_path).size()
    var high_size := FileAccess.get_file_as_bytes(high_path).size()
    assert_true(high_size > low_size, "quality 1.0 wrote more bytes than 0.1: %d vs %d" % [high_size, low_size])

    _cleanup(low_path)
    _cleanup(high_path)
    low.free()
    high.free()
    canvas.free()


## EXR's option is half or float precision, which `Image.save_exr`
## already took an argument for: the dialog just gives it a switch.
func test_exr_round_trips_at_full_or_half_precision() -> void:
    var canvas := _painted_canvas(Color(1.5, -0.25, 0.5, 1.0))
    var full := ExportDialogScript.new(canvas, &"exr", ExportDialogScript.DEFAULT_QUALITY, false)
    var float_path := SaDataRoot.path("test_export_float.exr")
    full._export_to(float_path)
    SaExportInTurns.finish_all()
    var float_back := Image.load_from_file(float_path)
    assert_not_null(float_back, "the float EXR loads back")
    assert_eq(float_back.get_format(), Image.FORMAT_RGBAF, "float keeps the full 32 bits, out-of-range and all")

    var half := ExportDialogScript.new(canvas, &"exr", ExportDialogScript.DEFAULT_QUALITY, true)
    var half_path := SaDataRoot.path("test_export_half.exr")
    half._export_to(half_path)
    SaExportInTurns.finish_all()
    var half_back := Image.load_from_file(half_path)
    assert_not_null(half_back, "the half EXR loads back")
    assert_eq(half_back.get_format(), Image.FORMAT_RGBAH, "half is the 16-bit option the check box offers")

    _cleanup(float_path)
    _cleanup(half_path)
    full.free()
    half.free()
    canvas.free()


## Each format shows the row that is its own and no other's: JPG its quality,
## EXR its precision check, PNG and TIFF the depth row.
func test_only_the_active_formats_option_row_shows() -> void:
    var dialog := ExportDialogScript.new()
    _pick_format(dialog, &"png")
    assert_false(dialog.shows(&"quality"), "PNG hides the JPG quality row")
    assert_false(dialog.shows(&"half"), "and the EXR half-precision row")
    assert_true(dialog.shows(&"depth"), "and shows the depth row of its own")

    _pick_format(dialog, &"jpg")
    assert_true(dialog.shows(&"quality"), "JPG shows its quality row")
    assert_false(dialog.shows(&"half"), "not EXR's")
    assert_false(dialog.shows(&"depth"), "nor a depth row, which JPEG has not")

    _pick_format(dialog, &"exr")
    assert_false(dialog.shows(&"quality"), "EXR hides JPG's row")
    assert_true(dialog.shows(&"half"), "and shows its own")
    assert_false(dialog.shows(&"depth"), "and no depth row, its check being the depth")

    _pick_format(dialog, &"tiff")
    assert_false(dialog.shows(&"quality"), "TIFF hides JPG's row")
    assert_false(dialog.shows(&"half"), "and EXR's")
    assert_true(dialog.shows(&"depth"), "and shows the depth row of its own")
    assert_true(dialog._format_label.text.contains("float"), "and says what it is instead")
    dialog.free()


# --- The depth row --------------------------------------------------------


## The two formats with more than one depth show the two their writers take, in
## the words a painter reads, and each opens on the depth it always wrote.
func test_the_depth_row_offers_each_formats_own_two() -> void:
    var dialog := ExportDialogScript.new()
    _pick_format(dialog, &"png")
    assert_eq(dialog._depth_option.choice_labels(), ["8-bit", "16-bit"], "PNG's two")
    assert_eq(dialog._depth_option.selected_value(), 8, "and opens on the eight it always wrote")

    _pick_format(dialog, &"tiff")
    assert_eq(dialog._depth_option.choice_labels(), ["16-bit integer", "32-bit float"], "TIFF's two")
    assert_eq(dialog._depth_option.selected_value(), 32, "and opens on the float every TIFF was")
    dialog.free()


## The depth is remembered per format rather than per dialog, so a painter who
## sets PNG to sixteen, looks at TIFF and comes back finds their choice where
## they left it.
func test_the_depth_is_remembered_per_format() -> void:
    var dialog := ExportDialogScript.new()
    _pick_format(dialog, &"png")
    assert_true(dialog._depth_option.pick_row(1), "the second PNG row takes the press")
    assert_eq(dialog._depth_option.selected_value(), 16, "PNG moved to sixteen")

    _pick_format(dialog, &"tiff")
    assert_eq(dialog._depth_option.selected_value(), 32, "TIFF opens on its own default, untouched")

    _pick_format(dialog, &"png")
    assert_eq(dialog._depth_option.selected_value(), 16, "and PNG still holds sixteen")
    dialog.free()


## The Result's first line follows the depth, and the sentence under the rolloff
## toggle follows it too, because sixteen bits is the finer grid and not a way
## past the clip, and only the float formats keep a value outside 0 to 1.
func test_the_result_and_the_note_follow_the_depth() -> void:
    var dialog := ExportDialogScript.new()
    _pick_format(dialog, &"png")
    assert_true(dialog._format_label.text.contains("8 bits"), "PNG at eight says which depth it is")

    dialog._depth_option.pick_row(1)
    assert_true(dialog._format_label.text.contains("16 bits"), "and at sixteen says that instead")
    assert_true(dialog._note_label.text.contains("clipped"), "and the note says it still clips")

    _pick_format(dialog, &"tiff")
    assert_true(dialog._format_label.text.contains("32-bit float"), "TIFF at thirty-two is the float one")
    dialog._depth_option.pick_row(0)
    assert_true(dialog._format_label.text.contains("16 bits"), "and at sixteen is the half-size one")
    assert_true(dialog._note_label.text.contains("half the size"), "and the note says so")
    dialog.free()


## The row reaches the file: the same canvas through the dialog at each depth
## writes a PNG whose own header says that depth.
func test_the_chosen_depth_reaches_the_file() -> void:
    var canvas := _painted_canvas(Color(0.25, 0.5, 0.75, 1.0))
    var dialog := ExportDialogScript.new(canvas, &"png")
    _pick_format(dialog, &"png")

    var eight_path := SaDataRoot.path("test_export_8.png")
    dialog._export_to(eight_path)
    SaExportInTurns.finish_all()
    var eight_bytes := FileAccess.get_file_as_bytes(eight_path)
    assert_eq(_png_bit_depth(eight_bytes), 8, "the row's eight writes an eight-bit header")

    dialog._depth_option.pick_row(1)
    var sixteen_path := SaDataRoot.path("test_export_16.png")
    dialog._export_to(sixteen_path)
    SaExportInTurns.finish_all()
    var sixteen_bytes := FileAccess.get_file_as_bytes(sixteen_path)
    assert_eq(_png_bit_depth(sixteen_bytes), 16, "and the row's sixteen writes a sixteen-bit one")
    assert_true(sixteen_bytes.size() > eight_bytes.size(), "which is the larger file")

    _cleanup(eight_path)
    _cleanup(sixteen_path)
    dialog.free()
    canvas.free()


## A PNG's bit depth is one byte of its `IHDR`: the eight byte signature, the
## header's own length and name, the width and the height, and then it.
static func _png_bit_depth(bytes: PackedByteArray) -> int:
    return bytes[24]


## Moves the format row the way a hand moves it, by the row the format is on,
## so the page's rules and the dialog's own handler both run.
func _pick_format(dialog: SaExportDialog, format_id: StringName) -> void:
    dialog.page.row(&"format").drive(ExportDialogScript.format_ids().find(format_id))
