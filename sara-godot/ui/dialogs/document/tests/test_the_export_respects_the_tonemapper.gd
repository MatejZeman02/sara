## The export dialog's rolloff check starts from the view's own Tonemap
## Highlights, so a painter who rolls a highlight off on screen and then exports
## gets a file that rolled it off too.
##
## A check that "does not start from the view's own setting" would, with Tonemap
## Highlights on, export to PNG or TIFF and still clip a bright colour the view
## had rolled off until the painter ticked the box.
##
## The check is a start and not a live mirror, which this suite holds: it is
## read once per opening, and a painter who unticks it still exports a clip. The two halves below are the
## state the dialog opens in
## and the file that follows from it.
##
## The dialog is opened in a real tree with subwindows embedded, the way
## `test_a_hidden_dialog_is_not_fitted` does it: `open_for` pops the window,
## and a `Window` added to the tree without embedding maps a real OS window and
## the run blocks until the watchdog fires.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice: the export reads the canvas back and dispatches a
## kernel.
const REQUIRES_GPU := true

const DialogScript = preload("res://ui/dialogs/document/export_dialog.gd")

## One clause of each of the two sentences the note ends on, so a test that
## reads the note is reading which operator the file will be written with.
const ROLLED_CLAUSE := "rolled off the way View > Tonemap Highlights does"
const CLIP_CLAUSE := "Values below 0 or above 1 are clipped."

## A pure red stored well past the knee, which is what the rolloff moves and a
## plain clip cannot: the peak channel tops out at 255 under both operators, so
## only the channels a clip leaves at zero show which one ran.
const BRIGHT_RED := Color(4.0, 0.0, 0.0, 1.0)

var _kept_rolloff: bool = false
var _kept_mapping: String = ""
var _kept_embedding: bool = true
var _host: Node = null

## The skeleton's formats with the image formats module's after them, as the
## running app registers them, built again before each test.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    _kept_rolloff = SaSettings.tonemap_highlights
    _kept_mapping = SaSettings.gamut_mapping
    # Clip is the default and is forced here, so the two files below differ by
    # the rolloff and by nothing else.
    SaSettings.gamut_mapping = SaGamutMapping.CLIP
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _kept_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "N2ExportDialogTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaSettings.tonemap_highlights = _kept_rolloff
    SaSettings.gamut_mapping = _kept_mapping
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


## A canvas in sRGB whose one layer is a flat field of *colour*, stored as the
## number given rather than converted, so a value above 1 reaches the export the
## way the document holds it.
func _field(colour: Color) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(32, 32)
    canvas.easel = SaEasel.create_default(canvas.canvas_size, null, SaColorSpace.srgb())
    canvas.add_child(canvas.easel)
    canvas.document.fill_layer(colour)
    canvas.easel.request_composite()
    canvas.easel.process_pending_composite()
    return canvas


## The dialog opened the way File > Export opens it, on a canvas of this test's
## own. It is left in the host, and the caller frees it.
func _opened(format_id: StringName, canvas: SaCanvas) -> SaExportDialog:
    var dialog := DialogScript.new(canvas, format_id)
    _host.add_child(dialog)
    dialog.open_for(canvas)
    return dialog


func _cleanup(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _green_channel(path: String) -> int:
    var written := Image.load_from_file(ProjectSettings.globalize_path(path))
    assert_not_null(written, "the export wrote a file Godot can read back")
    if written == null:
        return -1
    return written.get_pixel(written.get_width() >> 1, written.get_height() >> 1).g8


## With the view rolling highlights off, the dialog opens with the check ticked
## and its sentence naming the rolloff, which an unticked-by-default check never did.
func test_the_check_is_ticked_when_the_view_rolls_the_highlight_off() -> void:
    SaSettings.tonemap_highlights = true
    var canvas := _field(Color(0.5, 0.5, 0.5, 1.0))
    var dialog := _opened(&"png", canvas)

    assert_true(dialog._rolloff, "the check opens ticked, which is the setting")
    assert_true(dialog._rolloff_check.button_pressed, "and the box a painter reads says so")
    assert_true(dialog._rolloff_check.visible, "and it is offered, eight bits of PNG clipping otherwise")
    assert_true(dialog._note_label.text.contains(ROLLED_CLAUSE), "and the note reads the rolled sentence")

    dialog.free()
    canvas.free()


## With the view clipping, the check opens unticked, so a painter who turned
## the tonemapper off, on by default, exports what the
## view shows.
func test_the_check_is_unticked_when_the_view_clips() -> void:
    SaSettings.tonemap_highlights = false
    var canvas := _field(Color(0.5, 0.5, 0.5, 1.0))
    var dialog := _opened(&"png", canvas)

    assert_false(dialog._rolloff, "the check opens unticked")
    assert_false(dialog._rolloff_check.button_pressed, "and the box says so")
    assert_true(dialog._note_label.text.contains(CLIP_CLAUSE), "and the note reads the clipping sentence")

    dialog.free()
    canvas.free()


## The formats that hold every value never roll off, so their check starts
## unticked even with the tonemapper on, and TIFF is the one format whose two
## depths differ about it.
func test_the_check_starts_unticked_where_the_format_cannot_clip() -> void:
    SaSettings.tonemap_highlights = true
    var canvas := _field(Color(0.5, 0.5, 0.5, 1.0))

    var exr := _opened(&"exr", canvas)
    assert_false(exr._rolloff, "an EXR keeps every value, so its check starts unticked")
    assert_false(exr._rolloff_check.visible, "and is not offered at all")
    exr.free()

    var tiff := _opened(&"tiff", canvas)
    assert_false(tiff._rolloff, "the 32-bit TIFF keeps every value too")
    assert_false(tiff._rolloff_check.visible, "so its check is not offered either")
    assert_false(tiff._note_label.text.contains("rolled off"), "and nothing about the note says rolled off")

    tiff._depth_option.pick_row(0)
    assert_true(tiff._rolloff_check.visible, "the 16-bit TIFF clips, so the check is offered there")
    assert_false(tiff._rolloff, "and still opens unticked until the painter asks for it")

    tiff.free()
    canvas.free()


## The painter can untick what the view ticked, and the export clips: the check
## is a start rather than a mirror of the setting.
func test_the_painter_can_untick_the_check_the_view_ticked() -> void:
    SaSettings.tonemap_highlights = true
    var canvas := _field(BRIGHT_RED)
    var dialog := _opened(&"png", canvas)
    assert_true(dialog._rolloff, "opened ticked")

    dialog._rolloff_check.button_pressed = false

    assert_false(dialog._rolloff, "the press reaches the member the export reads")
    assert_true(dialog._note_label.text.contains(CLIP_CLAUSE), "and the note follows it back to clipping")

    dialog.free()
    canvas.free()


## The file: a bright red exported through the dialog, opened with the
## tonemapper on, comes out rolled off, and the same dialog with the check
## unticked comes out clipped. The readback is the exported file's own texel,
## the eyedropper's value.
func test_the_export_rolls_the_highlight_off_when_it_opens_ticked() -> void:
    SaSettings.tonemap_highlights = true
    var canvas := _field(BRIGHT_RED)
    var dialog := _opened(&"png", canvas)

    var rolled_path := SaDataRoot.path("n2-bright-red-rolled.png")
    var clipped_path := SaDataRoot.path("n2-bright-red-clipped.png")
    dialog._export_to(rolled_path)
    SaExportInTurns.finish_all()
    dialog._rolloff_check.button_pressed = false
    dialog._export_to(clipped_path)
    SaExportInTurns.finish_all()

    var rolled := Image.load_from_file(ProjectSettings.globalize_path(rolled_path))
    var clipped := Image.load_from_file(ProjectSettings.globalize_path(clipped_path))
    assert_not_null(rolled, "the rolled export wrote a file")
    assert_not_null(clipped, "and the clipped one did too")
    if rolled == null or clipped == null:
        return
    var rolled_texel := rolled.get_pixel(rolled.get_width() >> 1, rolled.get_height() >> 1)
    var clipped_texel := clipped.get_pixel(clipped.get_width() >> 1, clipped.get_height() >> 1)

    assert_eq(clipped_texel.r8, 255, "the clipped file's red tops out at the end of the byte range")
    assert_eq(clipped_texel.g8, 0, "and the channels the document never wrote stay at zero")
    assert_eq(rolled_texel.r8, 255, "the rolled file's red tops out there too, white stays white")
    assert_true(rolled_texel.g8 > clipped_texel.g8, "and its green has risen, the chroma falling towards white")

    _cleanup(rolled_path)
    _cleanup(clipped_path)
    dialog.free()
    canvas.free()
