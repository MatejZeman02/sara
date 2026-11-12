## The Filter dialog hides its thumbnail while the canvas shows
## the preview.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A thumbnail above a ticked Preview on canvas wastes the space there.
## With the switch on,
## Gaussian Blur's thumbnail and its caption are hidden and the window is
## shorter by them, and off they show again. A thumbnail a filter picks a pixel
## on is kept, and so is one beside a dimmed switch and one over a layer the
## canvas does not draw.
##
## A test cannot await a frame, so the fit the open asks for a frame later is
## called by hand once the page is laid out, the way
## `test_a_filter_dialog_opens_at_its_controls.gd` calls it. The fit a click on
## the switch makes is the window's own, in the click's call. The running app
## is `scenarios/the-filter-dialog-hides-its-thumbnail-while-the-canvas-shows-the-preview.json`.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const CpuFilter = preload("res://tests/fixtures/modules/cpu-filter-fixture/cpu_filter.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"


## Invert with a click asked for, so its thumbnail takes a press while its
## switch stays live, which no filter of the base modules has both of.
class ClickedInvert:
    extends SaInvertFilter

    func title() -> String:
        return "Clicked invert"

    func build(ui: SaDialog) -> void:
        ui.click(&"seed")
        super(ui)


var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _was_embedding: bool = false
var _was_preview: bool = true

var _blur: SaFilter = null
var _clicked: SaFilter = null
var _cpu: SaFilter = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _was_preview = SaSettings.filter_preview_on_canvas
    _host = Node.new()
    _host.name = "U13TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(Vector2i(256, 256))
    _easel.document.fill_layer(Color(0.25, 0.5, 0.75, 1.0), _easel.document.active_layer)
    Bench.composite(_easel)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    _registry = SaFilterRegistry.new()
    _blur = SaGaussianBlurFilter.new()
    _clicked = ClickedInvert.new()
    _cpu = CpuFilter.new()
    for filter: SaFilter in [_blur, _clicked, _cpu]:
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
    _clicked = null
    _cpu = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


## Opens *filter* with the switch starting as *on* says, and runs the fit its
## first frame would after laying the page out, answering the window's size.
func _open(filter: SaFilter, on: bool) -> Vector2i:
    SaSettings.filter_preview_on_canvas = on
    _window.open_filter(SaFilterRegistry.key_for(OWNER, filter))
    for _pass in range(2):
        _sort_children(_window)
        _ask_again(_window)
    _window.fit_opening_size()
    return _window.size


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


## Whether the thumbnail and its caption are both drawn, and the one answer
## when they agree: a caption shown over a hidden picture is a failure too.
func _thumbnail_shown() -> bool:
    var thumbnail := _window.dialog.preview_control
    var shown := thumbnail.is_visible_in_tree()
    assert_eq(thumbnail.caption.is_visible_in_tree(), shown, "the caption goes with the picture")
    return shown


func test_on_hides_the_thumbnail_and_its_caption_and_the_window_is_shorter() -> void:
    var tall := _open(_blur, false)
    assert_false(_window.dialog.canvas_box.disabled, "Gaussian Blur's switch is live")
    assert_true(_thumbnail_shown(), "off, the thumbnail and its caption show")
    var short := _open(_blur, true)
    assert_true(_window.dialog.canvas_box.button_pressed, "the switch opens on")
    assert_false(_thumbnail_shown(), "on, the thumbnail and its caption are hidden")
    assert_true(short.y < tall.y, "and the window opens %d high where it opened %d with the switch off" % [short.y, tall.y])


func test_a_click_on_the_switch_takes_the_height_and_gives_it_back_where_the_window_stands() -> void:
    var tall := _open(_blur, false)
    var short := _open(_blur, true)
    var corner := _window.position
    var box := _window.dialog.canvas_box
    box.button_pressed = false
    assert_true(_thumbnail_shown(), "switched off, the thumbnail shows again")
    assert_eq(_window.size, tall, "at the height the dialog opens at with the switch off")
    assert_eq(_window.position, corner, "and the window keeps its corner")
    box.button_pressed = true
    assert_false(_thumbnail_shown(), "switched on, it hides")
    assert_eq(_window.size, short, "and the window gives its height back")
    assert_eq(_window.position, corner, "where it stood")


func test_a_thumbnail_that_takes_a_click_shows_with_the_switch_on() -> void:
    _open(_clicked, true)
    var box := _window.dialog.canvas_box
    assert_true(_window.dialog.preview_control.takes_clicks, "the filter picks its pixel on the thumbnail")
    assert_true(box.button_pressed and not box.disabled, "and its switch is live and on")
    assert_true(_thumbnail_shown(), "so the thumbnail stays")


func test_a_filter_whose_switch_is_dimmed_keeps_its_thumbnail() -> void:
    _open(_cpu, true)
    var box := _window.dialog.canvas_box
    assert_true(box.button_pressed and box.disabled, "a filter that shows a texture has its switch on and dimmed")
    assert_true(_thumbnail_shown(), "so the thumbnail, its one picture, stays")


func test_a_hidden_layer_keeps_the_thumbnail_and_its_note() -> void:
    _easel.document.active_layer.visible = false
    _open(_blur, true)
    assert_true(_window.dialog.canvas_box.button_pressed, "the switch is on")
    assert_not_null(
        _window.dialog.preview_control.find_child("HiddenNote", true, false), "the note says the canvas shows nothing"
    )
    assert_true(_thumbnail_shown(), "so the thumbnail is the one picture of the run and stays")
