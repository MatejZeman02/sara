## Closing a filter window cancels the filter, clears the canvas preview,
## disconnects the dialog, and writes nothing to history.
##
## Verified across window close button, close_requested, and Escape key. Escape
## takes the step `ShortcutRouter` gives it once it reaches a dialog, which is
## the one reader of the key.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const PAINT := Color(0.25, 0.5, 0.75, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
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
    _host.name = "R6TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(Vector2i(512, 512))
    _doc = _easel.document
    _doc.fill_layer(PAINT, _doc.active_layer)
    Bench.composite(_easel)

    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    _registry = SaFilterRegistry.new()
    _registry.register(Bench.threshold(), &"sara-base-modules")

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.watch(_registry)
    _host.add_child(_window)


func after_each() -> void:
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
    _canvas = null
    _easel = null
    _doc = null
    _registry = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


static func _escape() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_ESCAPE
    key.physical_keycode = KEY_ESCAPE
    key.pressed = true
    return key


func test_close_button_cancels_filter_and_clears_point_preview() -> void:
    var initial_history := _doc.history.step_count()
    _window.open_filter(&"sara-base-modules.threshold")

    assert_true(_window.visible, "The filter window opened")
    assert_not_null(_window.dialog, "The dialog was built")
    assert_not_null(_window.context, "The filter context was created")
    assert_not_null(_window.context.point, "Threshold recorded a point pass")
    assert_not_null(_easel.compositor.point_preview.for_document(_doc), "The compositor holds the point preview for the document")

    _window.close_button.pressed.emit()

    assert_false(_window.visible, "The window is hidden after clicking close button")
    assert_null(_window.dialog, "The dialog was cleaned up")
    assert_null(_easel.compositor.point_preview.for_document(_doc), "The compositor holds no point preview after window close")
    assert_eq(_doc.history.step_count(), initial_history, "Document history depth is unchanged across open and close")
    assert_true(_doc.active_layer.filters.is_empty(), "No filter was attached")


func test_close_requested_cancels_filter_and_clears_point_preview() -> void:
    var initial_history := _doc.history.step_count()
    _window.open_filter(&"sara-base-modules.threshold")

    assert_true(_window.visible, "The filter window opened")
    assert_not_null(_easel.compositor.point_preview.for_document(_doc), "The compositor holds the point preview for the document")

    _window.close_requested.emit()

    assert_false(_window.visible, "The window is hidden after close requested")
    assert_null(_window.dialog, "The dialog was cleaned up")
    assert_null(_easel.compositor.point_preview.for_document(_doc), "The compositor holds no point preview after close requested")
    assert_eq(_doc.history.step_count(), initial_history, "Document history depth is unchanged across open and close requested")
    assert_true(_doc.active_layer.filters.is_empty(), "No filter was attached")


func test_escape_cancels_filter_and_clears_point_preview() -> void:
    var initial_history := _doc.history.step_count()
    _window.open_filter(&"sara-base-modules.threshold")

    assert_true(_window.visible, "The filter window opened")
    assert_not_null(_easel.compositor.point_preview.for_document(_doc), "The compositor holds the point preview for the document")

    ShortcutRouter.escape_in_a_dialog(_escape(), _window)

    assert_false(_window.visible, "The window is hidden after escape")
    assert_null(_window.dialog, "The dialog was cleaned up")
    assert_null(_easel.compositor.point_preview.for_document(_doc), "The compositor holds no point preview after escape")
    assert_eq(_doc.history.step_count(), initial_history, "Document history depth is unchanged across open and escape")
    assert_true(_doc.active_layer.filters.is_empty(), "No filter was attached")


func test_closing_leaves_layer_pixels_untouched() -> void:
    var sample_pos := Vector2i(100, 100)
    var before_texel := Bench.texel(_doc.active_layer.get_field(Vector2i.ZERO), sample_pos)

    _window.open_filter(&"sara-base-modules.threshold")
    var level_row := _window.dialog.row(&"level")
    assert_not_null(level_row, "Threshold has a level row")
    level_row.drive(0.8)
    _window.dialog.flush_rerun()

    assert_not_null(_easel.compositor.point_preview.for_document(_doc), "Preview is live on compositor")

    _window.close_button.pressed.emit()

    Bench.composite(_easel)
    var after_texel := Bench.texel(_doc.active_layer.get_field(Vector2i.ZERO), sample_pos)
    assert_almost_eq(after_texel.r, before_texel.r, 1e-5, "Red channel untouched after close")
    assert_almost_eq(after_texel.g, before_texel.g, 1e-5, "Green channel untouched after close")
    assert_almost_eq(after_texel.b, before_texel.b, 1e-5, "Blue channel untouched after close")
    assert_almost_eq(after_texel.a, before_texel.a, 1e-5, "Alpha channel untouched after close")


func test_escape_while_slider_editing_cancels_slider_not_filter() -> void:
    _window.open_filter(&"sara-base-modules.threshold")

    var row := _window.dialog.row(&"level")
    assert_not_null(row, "Threshold has a level row")
    var slider := row.custom_control as FactorSlider
    assert_not_null(slider, "Level row is a FactorSlider")

    slider.start_editing()
    assert_true(slider._line_edit.visible, "Slider is editing text")

    slider._on_line_edit_gui_input(_escape())
    assert_false(slider._line_edit.visible, "Slider stopped editing text on escape")
    assert_true(_window.visible, "Filter window stayed open after first escape")
    assert_not_null(_easel.compositor.point_preview.for_document(_doc), "Preview remains live on compositor")

    ShortcutRouter.escape_in_a_dialog(_escape(), _window)
    assert_false(_window.visible, "Filter window closed on second escape")
    assert_null(_easel.compositor.point_preview.for_document(_doc), "Compositor point preview cleared on second escape")
