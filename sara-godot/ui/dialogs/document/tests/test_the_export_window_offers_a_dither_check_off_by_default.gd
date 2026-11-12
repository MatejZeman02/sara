## The Export window's Dither check.
##
## An 8-bit export does not dither by default, but optionally on the export
## window. So the check is offered for every
## file of eight bits a channel, JPG and PNG and OpenRaster at 8-bit, opens
## unticked, stays as the painter left it from one opening to the next, and is
## named in the Result when it is on. Sixteen bits and float never show it.
##
## The dialog is opened in a real tree with subwindows embedded, the way
## `test_the_export_respects_the_tonemapper.gd` opens it, because `open_for`
## pops the window.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the last case exports through the dialog.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const DialogScript = preload("res://ui/dialogs/document/export_dialog.gd")

## The Result's words for eight bits dithered, the phrase `DITHERED_WORDS` is.
const DITHERED := "8 bits per channel, dithered"

var _kept_embedding: bool = true
var _host: Node = null
var _canvas: SaCanvas = null
var _written: PackedStringArray = []
## The image formats module's registries, held so TIFF and OpenRaster are in
## the format list, which they are not on a run of this suite alone.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _kept_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U35ExportDialogTestHost"
    EventBus.add_child(_host)
    # A flat 0.5, the middle of a step, which rounds to 128 everywhere
    # undithered and to 127 and 128 in about equal parts dithered.
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(64, 64)
    _canvas.easel = SaEasel.create_default(_canvas.canvas_size, null, SaColorSpace.srgb())
    _canvas.add_child(_canvas.easel)
    _canvas.document.fill_layer(Color(0.5, 0.5, 0.5, 1.0))
    _canvas.easel.request_composite()
    _canvas.easel.process_pending_composite()


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    if _canvas != null:
        _canvas.free()
        _canvas = null
    for path: String in _written:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    _written.clear()


## The dialog opened the way File > Export opens it, left in the host, which
## frees it. *dithered* is the state a painter would have left it in.
func _opened(format_id: StringName, dithered: bool = false) -> SaExportDialog:
    var dialog := DialogScript.new(_canvas, format_id, 0.9, false, {}, false, false, Color.WHITE, dithered)
    _host.add_child(dialog)
    dialog.open_for(_canvas)
    return dialog


## The format row driven the way a painter's pick drives it.
func _pick_format(dialog: SaExportDialog, format_id: StringName) -> void:
    dialog.page.row(&"format").drive(DialogScript.format_ids().find(format_id))


## Which of the two levels either side of 0.5 the red of *path* holds, as
## `[127s, 128s, others]`.
func _levels(path: String) -> Array[int]:
    var image := Image.load_from_file(ProjectSettings.globalize_path(path))
    var counts: Array[int] = [0, 0, 0]
    if image == null:
        return counts
    for y in image.get_height():
        for x in image.get_width():
            match image.get_pixel(x, y).r8:
                127:
                    counts[0] += 1
                128:
                    counts[1] += 1
                _:
                    counts[2] += 1
    return counts


func test_the_check_is_offered_unticked_wherever_the_file_is_eight_bits() -> void:
    var png := _opened(&"png")
    assert_true(png.shows(&"dither"), "PNG at its default 8-bit shows the check")
    assert_true(png._dither_check.visible, "and the box itself")
    assert_false(png._dither, "unticked on the first opening")
    assert_false(png._dither_check.button_pressed, "and the box says so")

    png._depth_option.pick_row(1)
    assert_eq(png._depth(), 16, "the depth row moves PNG to sixteen bits")
    assert_false(png.shows(&"dither"), "where the check is not offered")
    assert_false(png._dither_check.visible, "and the box inside the hidden line is hidden too")
    png._depth_option.pick_row(0)
    assert_true(png.shows(&"dither"), "back at eight bits it is again")

    var jpg := _opened(&"jpg")
    assert_true(jpg.shows(&"dither"), "JPG, always eight bits, shows it")
    var ora := _opened(&"ora")
    assert_true(ora.shows(&"dither"), "OpenRaster at its default 8-bit shows it")
    var tiff := _opened(&"tiff")
    assert_false(tiff.shows(&"dither"), "the 32-bit float TIFF does not")
    tiff._depth_option.pick_row(0)
    assert_eq(tiff._depth(), 16, "nor the 16-bit integer one")
    assert_false(tiff.shows(&"dither"), "which never dithers either")
    var exr := _opened(&"exr")
    assert_false(exr.shows(&"dither"), "nor EXR")


func test_the_check_stays_as_the_painter_left_it() -> void:
    var dialog := _opened(&"png")
    dialog._dither_check.button_pressed = true
    assert_true(dialog._dither, "ticking the box reaches the member the export reads")

    dialog.hide()
    dialog.open_for(_canvas)
    assert_true(dialog._dither, "the next opening finds it ticked")
    assert_true(dialog._dither_check.button_pressed, "and the box says so")

    _pick_format(dialog, &"tiff")
    assert_false(dialog.shows(&"dither"), "a TIFF hides it")
    _pick_format(dialog, &"jpg")
    assert_true(dialog._dither_check.button_pressed, "and coming back to an eight-bit format finds it as it was")

    var remembered := _opened(&"png", true)
    assert_true(remembered._dither, "a dialog left ticked opens ticked")


func test_the_result_names_the_dither_only_when_it_is_on() -> void:
    var dialog := _opened(&"png")
    assert_false(dialog._format_label.text.contains("dithered"), "unticked, the Result says nothing of it")
    dialog._dither_check.button_pressed = true
    assert_eq(dialog._format_label.text, "Format: PNG, %s" % DITHERED, "ticked, the first line names it")

    dialog._depth_option.pick_row(1)
    assert_eq(dialog._format_label.text, "Format: PNG, 16 bits per channel", "at sixteen bits it is not written, so not named")

    _pick_format(dialog, &"jpg")
    assert_eq(dialog._format_label.text, "Format: JPG, %s, lossy" % DITHERED, "a JPG names it too")


func test_the_file_is_dithered_only_when_the_check_is_ticked() -> void:
    var dialog := _opened(&"png")
    var plain := SaDataRoot.path("dialog-plain.png")
    var dithered := SaDataRoot.path("dialog-dithered.png")
    _written.append_array([plain, dithered])

    dialog._export_to(plain)
    SaExportInTurns.finish_all()
    var counts := _levels(plain)
    assert_eq(counts, [0, 64 * 64, 0], "unticked, a grey of 0.5 is 128 at every pixel")

    dialog._dither_check.button_pressed = true
    dialog._export_to(dithered)
    SaExportInTurns.finish_all()
    counts = _levels(dithered)
    assert_eq(counts[2], 0, "ticked, every pixel is one of the two levels either side")
    assert_true(mini(counts[0], counts[1]) * 3 > 64 * 64, "in about equal parts, %d and %d" % [counts[0], counts[1]])
