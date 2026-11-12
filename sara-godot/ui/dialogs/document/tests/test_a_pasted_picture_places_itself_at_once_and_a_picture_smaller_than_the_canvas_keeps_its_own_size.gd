## A pasted picture places itself at once, and a picture smaller than the
## canvas keeps its own size.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Pasting a 240 by 160 picture once gave one of 1620 by 1080, because the Fit
## window preselected Fit inside whenever the ratios differed, and the window was
## in the way of every paste from a browser. So the preselection follows the sizes, a paste under the
## default places at once and says so, a drop still asks, and Paste Special
## asks on purpose. The desktop clipboard is `SaShortcutCommands.desktop_picture`,
## the seam `test_paste_takes_the_desktop_picture` uses, and the screen is a
## `SubViewport` with subwindows embedded so a window the paste opens can be
## found.
extends "res://tests/test_framework.gd"

## Real uploads into real chunks.
const REQUIRES_GPU := true

const CANVAS := Vector2i(1920, 1080)
const SMALL := Vector2i(240, 160)
const LARGE := Vector2i(4000, 3000)

var _kept_reader: Callable = Callable()
var _kept_fit: String = ""
var _kept_embedding: bool = true
var _host: Node = null
var _screen: SubViewport = null
var _easel: SaEasel = null


func before_each() -> void:
    SaTestFixtures.FrontDocuments.owner_in_the_run().clipboard.clear()
    _kept_reader = SaShortcutCommands.desktop_picture
    _kept_fit = SaSettings.import_fit
    # The default a fresh profile has.
    SaSettings.import_fit = "ask"
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U486PasteHost"
    EventBus.add_child(_host)
    SaMessage.install(_host)
    _screen = SubViewport.new()
    _screen.size = Vector2i(1280, 800)
    _screen.gui_embed_subwindows = true
    _host.add_child(_screen)
    _easel = SaEasel.create_default(CANVAS)


func after_each() -> void:
    SaShortcutCommands.desktop_picture = _kept_reader
    SaSettings.import_fit = _kept_fit
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _easel != null and is_instance_valid(_easel):
        _easel.free()
    if _host != null and is_instance_valid(_host):
        _host.free()
    _easel = null
    _host = null
    _screen = null


## A solid opaque red picture of *size*, so a texel says whether it landed.
func _picture(size: Vector2i) -> Image:
    var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
    image.fill(Color(1.0, 0.0, 0.0, 1.0))
    return image


func _desktop_holds(size: Vector2i) -> void:
    var picture := SaDesktopPicture.new(_picture(size), "the engine")
    SaShortcutCommands.desktop_picture = func() -> SaDesktopPicture: return picture


func _alpha(layer: SaLayer, x: int, y: int) -> float:
    var side := SaChunk.SIZE
    var texture := layer.get_field(Vector2i(floori(float(x) / side), floori(float(y) / side)))
    if texture == null:
        return 0.0
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(posmod(x, side), posmod(y, side)).a


## The rectangle the layer's paint covers, read off its texels at the four
## edges a centred picture of *size* would have, one texel in and one out.
func _covers(layer: SaLayer, size: Vector2i, label: String) -> void:
    @warning_ignore("integer_division")
    var at := (CANVAS - size) / 2
    var last := at + size - Vector2i.ONE
    @warning_ignore("integer_division")
    var middle := at + size / 2
    assert_almost_eq(_alpha(layer, at.x, at.y), 1.0, 1e-3, "%s: paint at the top left corner" % label)
    assert_almost_eq(_alpha(layer, last.x, last.y), 1.0, 1e-3, "%s: and at the bottom right" % label)
    assert_almost_eq(_alpha(layer, at.x - 1, middle.y), 0.0, 1e-3, "%s: none left of it" % label)
    assert_almost_eq(_alpha(layer, last.x + 1, middle.y), 0.0, 1e-3, "%s: none right of it" % label)
    if at.y > 0:
        assert_almost_eq(_alpha(layer, middle.x, at.y - 1), 0.0, 1e-3, "%s: none above it" % label)
        assert_almost_eq(_alpha(layer, middle.x, last.y + 1), 0.0, 1e-3, "%s: none below it" % label)


func _fit_dialog() -> SaImportFitDialog:
    return _screen.get_node_or_null(^"ImportFitDialog") as SaImportFitDialog


func _notice_says() -> String:
    var notice := SaMessage.notice_widget()
    return notice.label.text if notice != null and notice.showing() else ""


func _paste() -> Array[SaLayer]:
    var placed: Array[SaLayer] = []
    SaShortcutCommands.paste(_easel.document, _screen, func(layer: SaLayer) -> void: placed.append(layer))
    return placed


## The preselection the window opens on and a paste lands with: actual size
## when the picture fits on both sides, Fit inside when it is larger on either,
## and never Stretch, a picture the canvas's shape included.
func test_the_preselection_follows_the_sizes() -> void:
    var actual := SaImageImport.Fit.ACTUAL
    var inside := SaImageImport.Fit.INSIDE
    assert_eq(SaImportFitDialog.preselected_fit(SMALL, CANVAS), actual, "240 by 160 keeps its size")
    assert_eq(SaImportFitDialog.preselected_fit(Vector2i(1600, 900), CANVAS), actual, "so does a smaller 16:9")
    assert_eq(SaImportFitDialog.preselected_fit(LARGE, CANVAS), inside, "4000 by 3000 fits inside")
    assert_eq(SaImportFitDialog.preselected_fit(Vector2i(2000, 100), CANVAS), inside, "and so does one wider only")
    assert_eq(SaImportFitDialog.preselected_fit(Vector2i(100, 1200), CANVAS), inside, "or taller only")
    var dialog := SaImportFitDialog.new()
    dialog.configure(SMALL, CANVAS)
    assert_eq(dialog.chosen_fit(), actual, "The window opens on Place at actual size for a small picture")
    dialog.configure(LARGE, CANVAS)
    assert_eq(dialog.chosen_fit(), inside, "and on Fit inside for a large one")
    dialog.configure(Vector2i(3840, 2160), CANVAS)
    assert_eq(dialog.chosen_fit(), inside, "and a larger one of the canvas's shape is not stretched")
    dialog.free()


## The finding itself: 240 by 160 pasted on 1920 by 1080 under the default is a
## layer of 240 by 160, centred, put down with no window.
func test_a_small_picture_pastes_at_its_own_size() -> void:
    _desktop_holds(SMALL)
    var before := _easel.document.get_child_count()
    var placed := _paste()
    assert_null(_fit_dialog(), "No window was shown")
    assert_eq(_easel.document.get_child_count(), before + 1, "A layer was added at once")
    assert_eq(placed.size(), 1, "and handed over")
    if placed.is_empty():
        return
    _covers(placed[0], SMALL, "240 by 160")
    assert_eq(_notice_says(), SaImportFitDialog.placed_line(SaImageImport.Fit.ACTUAL), "The message bar says what it did")
    assert_true(_notice_says().contains("Paste Special"), "and where the painter is asked instead")


## 4000 by 3000 is larger than the canvas both ways, and lands fitted inside it,
## 1440 by 1080 in the middle.
func test_a_large_picture_pastes_fitted_inside() -> void:
    _desktop_holds(LARGE)
    var placed := _paste()
    assert_null(_fit_dialog(), "No window was shown")
    assert_eq(placed.size(), 1, "A layer was handed over")
    if placed.is_empty():
        return
    _covers(placed[0], Vector2i(1440, 1080), "4000 by 3000")
    assert_eq(_notice_says(), SaImportFitDialog.placed_line(SaImageImport.Fit.INSIDE), "The message bar says it was fitted")


## One undo takes the pasted layer away again.
func test_one_undo_removes_the_pasted_layer() -> void:
    _desktop_holds(SMALL)
    var before := _easel.document.get_child_count()
    var placed := _paste()
    assert_eq(placed.size(), 1, "A layer was pasted")
    assert_true(_easel.document.undo(), "One undo")
    assert_eq(_easel.document.get_child_count(), before, "and the layer is gone")


## Paste Special asks, under the default and under a stored fit alike, and
## opens on the preselection. Nothing lands before Place.
func test_paste_special_asks() -> void:
    _desktop_holds(SMALL)
    for stored: String in ["ask", "stretch"]:
        SaSettings.import_fit = stored
        var before := _easel.document.get_child_count()
        var placed: Array[SaLayer] = []
        SaShortcutCommands.paste(_easel.document, _screen, func(layer: SaLayer) -> void: placed.append(layer), true)
        var dialog := _fit_dialog()
        assert_not_null(dialog, "Paste Special opened the window under %s" % stored)
        if dialog == null:
            return
        assert_true(dialog.visible, "on screen under %s" % stored)
        assert_eq(dialog.chosen_fit(), SaImageImport.Fit.ACTUAL, "on Place at actual size")
        assert_eq(_easel.document.get_child_count(), before, "and nothing landed yet")
        (dialog.find_child("PlaceButton", true, false) as Button).pressed.emit()
        assert_eq(placed.size(), 1, "Place puts it down under %s" % stored)


## A stored fit still answers for a paste, so the Files page keeps its say.
func test_a_stored_fit_answers_for_a_paste() -> void:
    SaSettings.import_fit = "stretch"
    _desktop_holds(SMALL)
    var placed := _paste()
    assert_null(_fit_dialog(), "No window")
    assert_eq(placed.size(), 1, "A layer")
    if placed.is_empty():
        return
    assert_almost_eq(_alpha(placed[0], 0, 0), 1.0, 1e-3, "stretched to the corner, as the setting says")
    assert_eq(_notice_says(), "", "and no line, since nothing was decided for the painter")
