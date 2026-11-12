## The Place button of the fit dialog stays where it is while its hint and its
## first line change.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Place button once moved 43 pixels up when the painter chose 'Fit inside the
## canvas' and the hint got shorter. The hint
## under the fit row, the first line and the space row's sentence are each held
## at the height of the tallest sentence they may carry by an `SaLineReserve`,
## so the rows below them, the buttons among them, stay put.
##
## The window is opened the way the app opens it, on a `SubViewport` screen
## with its subwindows embedded, because a `Window` added to the tree in a
## headless run maps a real one and hangs. No frame passes inside a test, so
## the layout is settled by hand as `test_every_dialog_opens_inside_the_window_at_every_size_and_scale`
## settles it.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the theme's fonts to shape. The runner skips this
## suite without one.
const REQUIRES_GPU := true

## A PNG whose `cICP` names Display P3, a plain PNG that names nothing, and a
## JPEG, which never does.
const P3_PNG := "res://tests/data/display_p3_cicp.png"
const PLAIN_PNG := "res://tests/data/import_gradient.png"
const JPEG := "res://tests/data/import_gradient.jpg"

## The two interface scales the row names.
const SCALES: Array[float] = [1.0, 2.0]

## The screen, in physical pixels.
const SCREEN := Vector2i(1920, 1080)

var _kept_scale: float = 1.0
var _kept_font_scale: float = 1.0
var _kept_theme: Theme = null
var _kept_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    _kept_scale = SaUI.user_scale
    _kept_font_scale = SaUI.user_font_scale
    _kept_theme = SaUI.shared_theme
    SaUI.user_font_scale = 1.0
    SaUI.init_global_theme(null)
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U510FitDialogHostTest"
    EventBus.add_child(_host)


func after_each() -> void:
    SaUI.user_scale = _kept_scale
    SaUI.user_font_scale = _kept_font_scale
    SaUI.shared_theme = _kept_theme
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


## A PNG and then a JPEG, on canvases whose sizes make first lines of different
## lengths, each fit chosen in turn: the Place button never moves and the window
## keeps one size, at both scales.
func test_the_place_button_stays_put_across_the_fits_and_the_opens() -> void:
    for scale: float in SCALES:
        SaUI.user_scale = scale
        var dialog := _dialog_on_a_screen(scale)
        var where := "at scale %.0f" % scale
        _open(dialog, PLAIN_PNG, Vector2i(1920, 1080))
        var place := _place_rect(dialog)
        var size := dialog.size
        assert_true(place.size.x > 0.0, "%s the Place button is laid out: %s" % [where, place])
        assert_true(Rect2(Vector2.ZERO, Vector2(size)).encloses(place), "%s and inside the window %s: %s" % [where, size, place])
        for choice: Array in SaImportFitDialog.CHOICES:
            dialog.select(choice[0])
            _settle(dialog)
            assert_eq(_place_rect(dialog), place, "%s choosing %s leaves Place where it was" % [where, choice[1]])
            assert_eq(dialog.size, size, "%s and the window its size" % where)
        dialog.hide()
        _open(dialog, JPEG, Vector2i(12000, 16000))
        assert_eq(_place_rect(dialog), place, "%s a JPEG on a large canvas opens with Place where the PNG had it" % where)
        assert_eq(dialog.size, size, "%s in a window of the same size" % where)
        for choice: Array in SaImportFitDialog.CHOICES:
            dialog.select(choice[0])
            _settle(dialog)
            assert_eq(_place_rect(dialog), place, "%s on the JPEG, choosing %s leaves Place where it was" % [where, choice[1]])
        dialog.hide()


## A file that names its gamut has a different sentence under the space row
## than one that does not, and the window is the same size for both.
func test_a_named_gamut_and_none_open_the_same_window() -> void:
    for scale: float in SCALES:
        SaUI.user_scale = scale
        var dialog := _dialog_on_a_screen(scale)
        var where := "at scale %.0f" % scale
        _open(dialog, PLAIN_PNG, Vector2i(1920, 1080))
        assert_false(dialog._said.named, "%s the plain PNG names no gamut" % where)
        var place := _place_rect(dialog)
        var size := dialog.size
        dialog.hide()
        _open(dialog, P3_PNG, Vector2i(1920, 1080))
        assert_true(dialog._said.named, "%s the cICP PNG names one" % where)
        assert_eq(dialog.size, size, "%s and opens a window of the same size" % where)
        assert_eq(_place_rect(dialog), place, "%s with Place where it was" % where)
        dialog.hide()


## The reserve is not a no-op: the three fit hints wrap to different heights in
## the width the row gives them, which is the move it would otherwise make.
func test_the_fit_hints_differ_in_height_without_the_reserve() -> void:
    SaUI.user_scale = 1.0
    var dialog := _dialog_on_a_screen(1.0)
    _open(dialog, PLAIN_PNG, Vector2i(1920, 1080))
    var reserve: SaLineReserve = dialog._reserves[1]
    var width := dialog._fit_hint.size.x
    var heights := {}
    for choice: Array in SaImportFitDialog.CHOICES:
        heights[reserve.height_of(String(choice[2]), width)] = true
    assert_true(heights.size() > 1, "The fit hints wrap to more than one height at %d wide: %s" % [width, heights.keys()])
    assert_eq(dialog._fit_hint.custom_minimum_size.y, ceilf(heights.keys().max()), "and the hint is held at the tallest")


## The dialog on a screen of its own at *scale*, freed with the suite's host.
func _dialog_on_a_screen(scale: float) -> SaImportFitDialog:
    var screen := SubViewport.new()
    screen.size = Vector2i(Vector2(SCREEN) / scale)
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    var dialog := SaImportFitDialog.new()
    screen.add_child(dialog)
    return dialog


## Opens *dialog* for the picture at *path* over a canvas of *canvas*, as `place`
## does, and lays it out.
func _open(dialog: SaImportFitDialog, path: String, canvas: Vector2i) -> void:
    var picture := Image.load_from_file(ProjectSettings.globalize_path(path))
    var named := SaImageImport.named_space_for(path)
    var source := named if named != null else SaImageImport.convention_for(path)
    dialog.configure(picture.get_size(), canvas, source, named != null)
    dialog.popup_centered()
    _settle(dialog)
    dialog.fit_opening_size()
    _settle(dialog)


func _place_rect(dialog: SaImportFitDialog) -> Rect2:
    return (dialog.find_child("PlaceButton", true, false) as Control).get_global_rect()


## Lays *window* out the way a drawn frame would, the sibling suite's way: every
## container sorted and every control asked its minimum again, twice, then a
## pixel on the window and back so a control laid out by its anchors derives
## its size again.
func _settle(window: Window) -> void:
    for _pass in range(3):
        _sort_children(window)
        _ask_again(window)
    var kept := window.size
    window.size = kept + Vector2i.ONE
    window.size = kept
    _sort_children(window)


func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


func _ask_again(node: Node) -> void:
    for child: Node in node.get_children():
        _ask_again(child)
        if child is Control:
            (child as Control).update_minimum_size()
