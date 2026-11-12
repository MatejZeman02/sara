## The Kaleidoscope dialog fits a 1280 by 1024 screen.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## At 1280 by 1024 the Kaleidoscope
## dialog's Attach, Cancel and Apply sat below its edge and needed its scroll
## bar. The Apply row was the last row of the page inside the window's
## `ScrollContainer`, which asks for no height, so the window's fit never grew
## for it. `SaFilterDialogFrame` now pins that row under the scroll, in both
## windows a filter's page opens in.
##
## A test cannot await a frame, so this holds the structure: the buttons are
## outside the scroll, below it, and counted in the height the window fits to.
## The frame itself is `scenarios/the-kaleidoscope-dialog-fits-a-1280-by-1024-screen.json`,
## whose dumps read `buttons.shown` for the Kaleidoscope and for Box blur.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const KEY := &"sara-base-modules.threshold"


## More rows than a 640 unit window holds, the Kaleidoscope's trouble without
## its module. The threshold underneath, under its own module and its own title,
## so its key and its kernel are the threshold's and every run shows a picture.
class Tall:
    extends SaPixelFilter

    func _init() -> void:
        super(Bench.THRESHOLD_PATH, "Threshold", 0, &"tone")

    func build(ui: SaDialog) -> void:
        super.build(ui)
        for i in 14:
            ui.slider("Row %d" % i, 0.0, 1.0, 0.5)


var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "W3TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(Vector2i(256, 256))
    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    _registry = SaFilterRegistry.new()
    _registry.register(Tall.new(), &"sara-base-modules")
    _easel.compositor.filter_chain.registry = _registry

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.watch(_registry)
    _host.add_child(_window)


func after_each() -> void:
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
    _canvas = null
    _easel = null
    _registry = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


func _frame() -> SaFilterDialogFrame:
    return _window.find_child("FilterFrame", true, false) as SaFilterDialogFrame


func test_the_buttons_sit_under_the_scroll_and_not_in_it() -> void:
    _window.open_filter(KEY)
    var frame := _frame()
    assert_not_null(frame, "the dialog's content is the frame")
    var scroll := frame.find_child("FilterScroll", true, false) as ScrollContainer
    assert_not_null(scroll, "which holds the page in a scroll")
    var apply := _window.dialog.apply_button
    assert_not_null(apply, "the dialog drew Apply")
    assert_true(frame.footer.is_ancestor_of(apply), "Apply is in the pinned strip")
    assert_true(frame.footer.is_ancestor_of(_window.dialog.cancel_button), "and so is Cancel")
    assert_true(frame.footer.is_ancestor_of(_window.way_toggle), "and the way toggle over them")
    assert_false(scroll.is_ancestor_of(apply), "so no scroll position hides them")
    assert_true(frame.footer.get_index() > scroll.get_index(), "and the strip is below the page")


func test_the_window_fits_to_the_buttons_it_pins() -> void:
    _window.open_filter(KEY)
    var frame := _frame()
    var buttons := frame.footer.get_combined_minimum_size().y
    assert_true(buttons > 0.0, "the pinned strip asks for its buttons' height")
    assert_true(
        _window.content_minimum_size().y >= buttons,
        "and the height the window fits to counts it, which the scroll alone never asked for"
    )


func test_a_second_filter_leaves_one_apply_row() -> void:
    _window.open_filter(KEY)
    _window.cancel_filter()
    _window.open_filter(KEY)
    var frame := _frame()
    var live := 0
    for child in frame.footer.get_children():
        if not child.is_queued_for_deletion():
            live += 1
    assert_eq(live, 2, "the last dialog's row and way toggle are let go of when the next one opens, one of each left")
    assert_true(frame.footer.is_ancestor_of(_window.dialog.apply_button), "and the new one is the one pinned")


func test_the_describe_names_the_strip() -> void:
    _window.open_filter(KEY)
    var said := _window.describe()
    assert_true(said.has("buttons"), "the window's dump says where its buttons are")
    assert_eq((said["buttons"] as Dictionary)["rect"].size(), 4, "as a rectangle in the window")
