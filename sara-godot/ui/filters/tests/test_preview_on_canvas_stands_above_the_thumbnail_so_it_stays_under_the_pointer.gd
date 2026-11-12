## Preview on canvas stands above the thumbnail so it stays
## under the pointer.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Preview on canvas switch lives above the otherwise hidden viewport,
## because it would jump away when toggled off. The dialog hides
## the thumbnail while the switch is on, and the switch stood under it, so
## turning it off put the picture back above it and pushed it down from under
## the pointer. `SaDialog.canvas_preview` now puts the switch right above the
## picture whatever order a `build` declares them in, so Gaussian Blur's switch
## stands at one place on screen off and on, and a filter that declares the
## picture first still has the switch above it.
##
## A test cannot await a frame, so the containers are sorted by hand after the
## open and after each click, the way the thumbnail-hiding suite lays its window out. The
## running app is `scenarios/preview-on-canvas-stands-above-the-thumbnail-so-it-stays-under-the-pointer.json`.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"


## Invert with the picture declared first and a slider between it and the
## switch, the order adjustments of the base modules declare, with
## a row of its own in the middle.
class PictureFirst:
    extends SaInvertFilter

    func title() -> String:
        return "Picture first"

    func build(ui: SaDialog) -> void:
        ui.title(title())
        ui.thumbnail()
        ui.slider("Amount", 0.0, 1.0, 0.5)
        ui.canvas_preview()
        ui.apply_cancel()


var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _was_embedding: bool = false
var _was_preview: bool = true

var _blur: SaFilter = null
var _first: SaFilter = null
var _curves: SaFilter = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _was_preview = SaSettings.filter_preview_on_canvas
    _host = Node.new()
    _host.name = "U43TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(Vector2i(256, 256))
    _easel.document.fill_layer(Color(0.25, 0.5, 0.75, 1.0), _easel.document.active_layer)
    Bench.composite(_easel)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    _registry = SaFilterRegistry.new()
    _blur = SaGaussianBlurFilter.new()
    _first = PictureFirst.new()
    _curves = SaCurvesFilter.new()
    for filter: SaFilter in [_blur, _first, _curves]:
        _registry.register(filter, OWNER)
    _easel.compositor.filter_chain.registry = _registry

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.watch(_registry)
    _host.add_child(_window)


func after_each() -> void:
    SaSettings.filter_preview_on_canvas = _was_preview
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
    _canvas = null
    _easel = null
    _registry = null
    _blur = null
    _first = null
    _curves = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


## Opens *filter* with the switch starting as *on* says, laid out as its first
## frame would lay it out.
func _open(filter: SaFilter, on: bool) -> void:
    SaSettings.filter_preview_on_canvas = on
    _window.open_filter(SaFilterRegistry.key_for(OWNER, filter))
    _lay_out()
    _window.fit_opening_size()
    _lay_out()


func _lay_out() -> void:
    for _pass in range(2):
        _sort_children(_window)
        _ask_again(_window)


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


## Where the switch stands on screen: the window's corner plus the switch's
## place in the window.
func _switch_at() -> Vector2:
    return Vector2(_window.position) + _window.dialog.canvas_box.get_global_rect().position


## A click on the switch, then the layout the next frame would make.
func _click(on: bool) -> void:
    _window.dialog.canvas_box.button_pressed = on
    _lay_out()


## The student-facing names of the dialog's rows, in order.
func _names() -> Array:
    var dialog := _window.dialog
    return dialog.rows().map(func(one: SaPageRow) -> String: return dialog.widget_name(one.key))


## With the switch off, so the picture shows: the switch's bottom edge is at or
## above the top of the picture, whose caption is its first child.
func _switch_is_above_the_picture(what: String) -> void:
    var box := _window.dialog.canvas_box
    var picture := _window.dialog.preview_control
    assert_false(box.button_pressed, "%s: the switch is off" % what)
    assert_true(
        picture.is_visible_in_tree() and picture.caption.is_visible_in_tree(), "%s: so the picture and its caption show" % what
    )
    var switch_bottom := box.get_global_rect().end.y
    assert_true(
        switch_bottom <= picture.get_global_rect().position.y,
        "%s: the switch ends at %.0f, above the picture at %.0f" % [what, switch_bottom, picture.get_global_rect().position.y]
    )
    assert_true(
        switch_bottom <= picture.caption.get_global_rect().position.y,
        "%s: and above its caption at %.0f" % [what, picture.caption.get_global_rect().position.y]
    )


func test_gaussian_blurs_switch_stands_at_one_place_off_and_on() -> void:
    _open(_blur, true)
    assert_false(_window.dialog.canvas_box.disabled, "Gaussian Blur's switch is live")
    assert_false(_window.dialog.preview_control.is_visible_in_tree(), "on, the thumbnail is hidden")
    var opened_at := _switch_at()
    assert_true(opened_at.y > 0.0, "the switch is laid out inside the window, at %s" % opened_at)
    _click(false)
    assert_true(_window.dialog.preview_control.is_visible_in_tree(), "off, the thumbnail shows again")
    assert_eq(_switch_at(), opened_at, "and the switch stands where the pointer pressed it")
    _switch_is_above_the_picture("Gaussian Blur")
    _click(true)
    assert_false(_window.dialog.preview_control.is_visible_in_tree(), "on again, the thumbnail hides")
    assert_eq(_switch_at(), opened_at, "and the switch has not moved")


func test_gaussian_blurs_switch_opened_off_stays_when_turned_on() -> void:
    _open(_blur, false)
    var opened_at := _switch_at()
    _switch_is_above_the_picture("Gaussian Blur opened off")
    _click(true)
    assert_eq(_switch_at(), opened_at, "turned on, the switch stands where it was")
    _click(false)
    assert_eq(_switch_at(), opened_at, "and turned off again too")


func test_a_spec_that_declares_the_picture_first_has_the_switch_above_it() -> void:
    _open(_first, false)
    assert_eq(
        _names(),
        ["canvas_preview", "thumbnail", "slider", "apply_cancel"],
        "the switch moves right above the picture and the slider stays under it"
    )
    _switch_is_above_the_picture("Picture first")
    var opened_at := _switch_at()
    _click(true)
    assert_eq(_switch_at(), opened_at, "and turned on, it stands where it was")


func test_curves_declares_the_picture_first_and_shows_the_switch_above_it() -> void:
    _open(_curves, false)
    var names := _names()
    assert_true(names.find("canvas_preview") >= 0, "Curves declares the switch")
    assert_eq(names.find("canvas_preview") + 1, names.find("thumbnail"), "right above its thumbnail: %s" % [names])
    _switch_is_above_the_picture("Curves")
