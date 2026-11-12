## The format, the gamut and the size once ran together with long help text
## under the toggle, and "Image, Gamut changes it" read as a broken sentence.
## The dialog now says what the file will be in a
## Result block of three short lines, sets the clipping sentence in muted type
## under the toggle it explains, writes a menu path with " > ", and points at the
## Display page, where the gamut mapping row is.
##
## Every clause is held on the dialog built the way the File menu builds it and
## read through the labels a painter reads.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice, for the canvas the dialog reads its gamut and size from.
const REQUIRES_GPU := true

const ExportDialogScript = preload("res://ui/dialogs/document/export_dialog.gd")

## Longer than this is a sentence and not a line of a result.
const SHORT_LINE := 48

var _kept_mapping: String = ""

## The skeleton's formats with the image formats module's after them, as the
## running app registers them, built again before each test.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    _kept_mapping = SaSettings.gamut_mapping
    SaSettings.gamut_mapping = SaGamutMapping.CLIP


func after_each() -> void:
    SaSettings.gamut_mapping = _kept_mapping


func _canvas_in(space: SaColorSpace, size: Vector2i = Vector2i(64, 48)) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = size
    canvas.easel = SaEasel.create_default(canvas.canvas_size, null, space)
    canvas.add_child(canvas.easel)
    canvas.document.fill_layer(Color(0.25, 0.5, 0.75, 1.0))
    canvas.easel.request_composite()
    canvas.easel.process_pending_composite()
    return canvas


func _pick_format(dialog: SaExportDialog, format_id: StringName) -> void:
    dialog.page.row(&"format").drive(ExportDialogScript.format_ids().find(format_id))


## The three lines of the Result, in the order the dialog gives them.
func _result_lines(dialog: SaExportDialog) -> Array[Label]:
    return [dialog._format_label, dialog._gamut_label, dialog._size_label]


## The result is three short lines under a heading that says Result: the format
## and its depth, the gamut, and the size, each one line and none of them help.
func test_the_result_is_three_short_lines_under_a_heading() -> void:
    var canvas := _canvas_in(SaColorSpace.srgb())
    var dialog := ExportDialogScript.new(canvas, &"png")

    assert_eq(dialog._format_label.text, "Format: PNG, 8 bits per channel", "the first line is the format and its depth")
    assert_eq(dialog._gamut_label.text, "Gamut: %s, named in the file" % SaGamut.srgb().display_name, "the second the gamut")
    assert_eq(dialog._size_label.text, "Size: 64 × 48 px", "the third the size")
    for line in _result_lines(dialog):
        assert_true(line.text.length() <= SHORT_LINE, "%s is short: %d characters" % [line.name, line.text.length()])
        assert_false(line.text.ends_with("."), "%s is a line of a list and not a sentence" % line.name)
        assert_false(line.text.contains("Image >"), "%s carries no menu path, which is help" % line.name)
        assert_false(line.text.contains("clipped"), "%s says nothing of clipping, which is help" % line.name)

    var heading := dialog.find_child("Heading", true, false) as Label
    assert_not_null(heading, "the block has a heading")
    if heading != null:
        assert_eq(heading.text, "Result", "which says Result")
    var parent := dialog._format_label.get_parent()
    assert_eq(dialog._gamut_label.get_parent(), parent, "the three lines sit in one block")
    assert_eq(dialog._size_label.get_parent(), parent, "the size with them")
    assert_true(dialog._format_label.get_index() < dialog._gamut_label.get_index(), "the format first, then the gamut")
    assert_true(dialog._gamut_label.get_index() < dialog._size_label.get_index(), "and the size after both")

    dialog.free()
    canvas.free()


## The format line reads every format in words a painter knows, and follows the
## switch and the depth the row is on.
func test_the_format_line_reads_each_format_and_its_depth() -> void:
    var canvas := _canvas_in(SaColorSpace.srgb())
    var dialog := ExportDialogScript.new(canvas, &"png")
    var wanted := {
        &"jpg": "Format: JPG, 8 bits per channel, lossy",
        &"exr": "Format: EXR, 32-bit float",
        &"tiff": "Format: TIFF, 32-bit float, uncompressed",
        &"ora": "Format: OpenRaster, 8 bits per channel, with its layers",
        &"png": "Format: PNG, 8 bits per channel",
    }
    for format_id: StringName in wanted:
        _pick_format(dialog, format_id)
        assert_eq(dialog._format_label.text, wanted[format_id], "%s reads as its line" % format_id)

    _pick_format(dialog, &"exr")
    (dialog.page.row(&"half").control as CheckButton).button_pressed = true
    assert_eq(dialog._format_label.text, "Format: EXR, 16-bit float", "and EXR's half switch moves it")
    _pick_format(dialog, &"tiff")
    dialog._depth_option.pick_row(0)
    assert_eq(dialog._format_label.text, "Format: TIFF, 16 bits per channel, uncompressed", "TIFF's depth row moves it")

    dialog.free()
    canvas.free()


## The clipping sentence is help: muted, smaller than a line of the result, and
## directly under the toggle it explains rather than after the whole page.
func test_the_clipping_sentence_is_muted_under_its_toggle() -> void:
    var canvas := _canvas_in(SaColorSpace.srgb())
    var dialog := ExportDialogScript.new(canvas, &"png")
    var toggle_line := dialog.page.row(&"rolloff").line

    assert_eq(dialog._note_label.get_parent(), toggle_line.get_parent(), "the sentence is in the toggle's own block")
    assert_eq(dialog._note_label.get_index(), toggle_line.get_index() + 1, "directly under the toggle")
    assert_eq(dialog._note_label.text, "Values below 0 or above 1 are clipped.", "and says what clips")
    assert_true(dialog._note_label.has_theme_color_override("font_color"), "it is drawn in a colour of its own")
    assert_eq(dialog._note_label.get_theme_color("font_color"), SaTheme.palette.get("text_muted"), "the muted one")
    assert_false(dialog._format_label.has_theme_color_override("font_color"), "a line of the result is not muted")
    assert_true(
        dialog._note_label.get_theme_font_size("font_size") < dialog._format_label.get_theme_font_size("font_size"),
        "and it is the smaller type"
    )
    assert_false(dialog._note_label.text.contains("8 bits"), "the depth is in the result and not repeated in it")

    dialog._rolloff_check.button_pressed = true
    assert_true(dialog._note_label.text.contains("rolled off"), "ticked, the same place says what rolls off")

    dialog.free()
    canvas.free()


## A menu path is written with " > " wherever the dialog writes one, and the
## pointer to the gamut mapping names the Canvas and colour page, which is
## where the row is. The sentence once ended "(Preferences, Colour Spaces)", a
## page it left, and then named Display, a page title since changed.
func test_a_path_is_written_with_a_chevron_and_the_mapping_points_at_display() -> void:
    SaSettings.gamut_mapping = SaGamutMapping.OKLAB
    var canvas := _canvas_in(SaColorSpace.srgb())
    var dialog := ExportDialogScript.new(canvas, &"png")

    assert_eq(dialog._gamut_help_label.text, "Image > Gamut changes it.", "the gamut's help is a path with a chevron")
    assert_true(dialog._note_label.text.contains("gives up chroma"), "a mapped file says what mapping does")
    assert_true(dialog._note_label.text.contains("(Preferences > Canvas and colour)"), "and names the page the row is on")
    for label: Label in [dialog._gamut_label, dialog._gamut_help_label, dialog._note_label]:
        assert_false(label.text.contains("Colour Spaces"), "%s names no page the row has left" % label.name)
        assert_false(label.text.contains("Image, "), "%s writes no path with a comma" % label.name)
        assert_false(label.text.contains("Preferences,"), "%s writes no path with a comma" % label.name)

    dialog.free()
    canvas.free()


## The gamut line is still true in each of its four cases, and only the named one
## carries the pointer to where it changes.
func test_the_gamut_line_and_its_help_follow_what_the_file_can_name() -> void:
    var canvas := _canvas_in(SaColorSpace.display_p3())
    var dialog := ExportDialogScript.new(canvas, &"png")
    assert_eq(dialog._gamut_label.text, "Gamut: %s, named in the file" % SaGamut.display_p3().display_name, "a named gamut")
    assert_true(dialog._gamut_help_label.visible, "has its help shown")

    _pick_format(dialog, &"exr")
    var p3_name := SaGamut.display_p3().display_name
    assert_eq(dialog._gamut_label.text, "Written as linear sRGB, from %s" % p3_name, "an EXR says what it converts to")
    assert_eq(dialog._gamut_help_label.text, "", "and has no help")
    assert_false(dialog._gamut_help_label.visible, "which is hidden, not an empty line")
    dialog.free()
    canvas.free()

    canvas = _canvas_in(SaColorSpace.acescg())
    dialog = ExportDialogScript.new(canvas, &"png")
    assert_true(dialog._gamut_label.text.ends_with("not named in the file"), "a gamut Sara has no profile for is not named")
    assert_eq(dialog._gamut_help_label.text, "Sara has no profile for it.", "and the help says why")
    _pick_format(dialog, &"exr")
    assert_true(dialog._gamut_label.text.begins_with("Written as linear sRGB, from "), "and an EXR converts it all the same")
    dialog.free()
    canvas.free()

    canvas = _canvas_in(SaColorSpace.unspecified())
    dialog = ExportDialogScript.new(canvas, &"png")
    assert_eq(dialog._gamut_label.text, "Gamut: unspecified, not named in the file", "a document with none says so")
    assert_false(dialog._gamut_help_label.visible, "and has no help")
    _pick_format(dialog, &"exr")
    var taken := "Written as linear sRGB, from an unspecified gamut taken as sRGB"
    assert_eq(dialog._gamut_label.text, taken, "and an EXR says what it took")
    dialog.free()
    canvas.free()


## OpenRaster's losses are help as well: muted, under the result, and only there
## when there is something to lose.
func test_the_openraster_loss_line_is_muted_and_sits_after_the_result() -> void:
    var canvas := _canvas_in(SaColorSpace.srgb())
    var dialog := ExportDialogScript.new(canvas, &"ora")
    assert_false(dialog._loss_label.visible, "a document with nothing to lose says nothing")
    (canvas.document.get_node("Layer 1") as SaLayer).blend_mode = &"exclusion"
    dialog._sync_options()
    assert_true(dialog._loss_label.visible, "one it loses a mode of says so")
    assert_eq(dialog._loss_label.get_theme_color("font_color"), SaTheme.palette.get("text_muted"), "in the muted colour")
    assert_true(dialog._loss_label.get_index() > dialog._size_label.get_index(), "after the three lines of the result")
    dialog.free()
    canvas.free()


## The middle of the dialog scrolls where the host is shorter than it, so its
## buttons stay on the screen at 1280 by 800 and an interface scale of 2, where
## they once measured 354 of 335.
func test_the_middle_scrolls_so_the_buttons_stay_on_the_screen() -> void:
    var dialog := ExportDialogScript.new(_canvas_in(SaColorSpace.srgb()), &"png")
    assert_not_null(dialog.scrolling_body, "the page is in a scroll the fit can shorten")
    assert_true(dialog.scrolling_body.is_ancestor_of(dialog.page.row(&"format").line), "which holds the rows")
    assert_false(dialog.scrolling_body.is_ancestor_of(dialog.default_button), "and leaves the buttons outside it")
    assert_true(dialog.scrolling_body.is_ancestor_of(dialog._size_label), "the result scrolls with the rows")
    dialog._canvas.free()
    dialog.free()
