## A filter dialog's preview reports the pixel clicked, and the
## filter runs again from it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The area aware fill is a dialog with a click, not a tool: the preview
## reports the pixel clicked and the filter reruns from it, with no tool
## variant. A filter's `build` asks with
## `ui.click(&"seed")`, and the click fixture's flood is the filter here.
##
## Windowless, because a `Window` in the tree hangs a headless run. A container places
## nothing outside a tree, so the picture is sized by hand, and the press is
## the event the picture's own `gui_input` carries. The press that finds the
## picture by the engine's hit test is the scenario's,
## `scenarios/a-filter-dialog-s-preview-reports-the-pixel-clicked-and-the-filter-runs-again-from-it.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const FloodFilter = preload("res://tests/fixtures/modules/click-fixture/flood_filter.gd")
const CpuFilter = preload("res://tests/fixtures/modules/cpu-filter-fixture/cpu_filter.gd")

## Where the preview's texture lies in the document, in document pixels.
const COVERING := Rect2i(100, 50, 200, 100)

const PAINT := Color(0.2, 0.4, 0.6, 1.0)

var _dialog: SaDialog = null
var _easel: SaEasel = null
var _window: SaFilterDialogWindow = null


func after_each() -> void:
    if _dialog != null:
        _dialog.free_unrealized()
    _dialog = null
    if _window != null:
        _window.free()
    _window = null
    if _easel != null:
        _easel.free()
    _easel = null


## A press of *button* at *point* of the picture, as the engine hands it to the
## picture's `gui_input`.
static func _press(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = button
    event.pressed = true
    event.position = point
    return event


## Shows a texture of [constant COVERING]'s size over it, and sizes the picture
## four hundred units on a side, which draws the texture twice over, 400 by
## 200, with a band a hundred high above and below.
static func _laid_out(preview: SaFilterPreview) -> void:
    preview.show_texture(SaTexture.new(COVERING.size), COVERING)
    var picture := preview._picture
    picture.size = Vector2(400.0, 400.0)


func test_a_click_on_the_picture_is_the_document_pixel_under_it_and_the_filter_s_parameter() -> void:
    var filter := FloodFilter.new()
    _dialog = SaDialog.for_filter(filter)
    var preview := _dialog.preview_control
    assert_true(preview.takes_clicks, "a build that wrote ui.click has a picture that takes a press")
    _laid_out(preview)
    assert_eq(preview._picture.size, Vector2(400, 400), "the picture is laid out inside its frame")
    assert_eq(filter.parameter(&"seed"), [-1, -1], "before a click the seed is the default the click declared")

    preview._picture.gui_input.emit(_press(Vector2(100.5, 150.5)))
    assert_eq(preview.clicked_pixel, Vector2i(150, 75), "a quarter across and down the drawn picture is that pixel")
    assert_eq(filter.parameter(&"seed"), [150, 75], "the filter reads the document pixel as its parameter")
    assert_true(_dialog.rerun_pending, "and the click asks the filter to run again")
    _dialog.flush_rerun()
    assert_eq(_dialog.runs, 1, "one click is one run")

    preview._picture.gui_input.emit(_press(Vector2(399.9, 299.9)))
    assert_eq(filter.parameter(&"seed"), [299, 149], "the far corner is the covered rectangle's last pixel")
    assert_eq(preview.clicks, 2, "the preview counts both clicks")


func test_a_press_beside_the_drawn_picture_or_of_another_button_reports_nothing() -> void:
    var filter := FloodFilter.new()
    _dialog = SaDialog.for_filter(filter)
    var preview := _dialog.preview_control
    _laid_out(preview)
    preview._picture.gui_input.emit(_press(Vector2(200.0, 50.0)))
    assert_eq(preview.clicks, 0, "a press in the empty band the kept aspect leaves is on no pixel")
    preview._picture.gui_input.emit(_press(Vector2(150.5, 150.5), MOUSE_BUTTON_RIGHT))
    assert_eq(preview.clicks, 0, "a right press is no click")
    assert_false(_dialog.rerun_pending, "and neither asks for a run")

    preview._picture.gui_input.emit(_press(Vector2(20.5, 120.5)))
    assert_eq(filter.parameter(&"seed"), [110, 60], "a press on the drawn picture is measured from its own corner")


func test_the_clicked_pixel_is_kept_in_the_record_like_any_other_value() -> void:
    var filter := FloodFilter.new()
    assert_eq(filter.parameters().get("seed"), [-1, -1], "a filter with no dialog already declares the seed, for a record")
    filter.set_parameters({"seed": [12.0, 34.0], "tolerance": 0.5})
    assert_eq(filter.parameter(&"seed"), [12.0, 34.0], "a record puts a seed back, as JSON carries it")
    assert_eq(filter.filed_as(&"click-fixture.flood_from_click").parameters.get("seed"), [12.0, 34.0], "and an attach files it")
    filter.set_parameters({})
    assert_eq(filter.parameter(&"seed"), [-1, -1], "a record that names no seed reads the default")


func test_the_filter_runs_again_from_the_clicked_pixel() -> void:
    _easel = Bench.easel(Vector2i(256, 256))
    var document := _easel.document
    document.fill_layer(PAINT, document.active_layer)
    Bench.composite(_easel)
    var filter := FloodFilter.new()
    _window = SaFilterDialogWindow.new()
    _window.filter = filter
    _window.context = SaFilterContext.new(document, document.active_layer, &"click-fixture", filter.title(), true)
    _window.dialog = SaDialog.for_filter(filter)
    _window.dialog.realize(_window._frame.rows)
    # What `open_filter` connects, which a suite cannot call for want of the
    # registries a running app fills.
    _window.dialog.rerun.connect(_window.run_filter)
    _window.run_filter()
    assert_eq(filter.floods, 0, "the run on open has no seed on the layer and floods nothing")
    var at := Vector2i(64, 200)
    assert_eq(Bench.texel(_window.context.shown, at), PAINT, "so the picture is the layer as it is")

    # The preview stands in a window, which a suite keeps out of the tree, so
    # it reports the click itself here, and the first case holds the picture's
    # half of the way.
    _window.dialog.preview_control.clicked.emit(at)
    _window.dialog.flush_rerun()
    assert_eq(_window.runs, 2, "the click ran the filter again")
    assert_eq(filter.last_seed, at, "from the pixel clicked")
    var fill := filter.parameter(&"fill") as Color
    assert_true(Bench.texel(_window.context.shown, at).is_equal_approx(fill), "and the picture shows the flood there")


func test_a_dialog_that_asks_for_no_click_is_unchanged_by_one() -> void:
    var filter := CpuFilter.new()
    _dialog = SaDialog.for_filter(filter)
    var preview := _dialog.preview_control
    assert_false(preview.takes_clicks, "a build that never wrote ui.click has a picture that takes no press")
    assert_true(preview._picture.gui_input.get_connections().is_empty(), "nothing listens to the picture's input")
    assert_eq(preview._picture.mouse_default_cursor_shape, Control.CURSOR_ARROW, "and the pointer over it is the plain arrow")
    _laid_out(preview)
    var before := filter.parameters()

    preview._picture.gui_input.emit(_press(Vector2(100.5, 150.5)))
    preview.picture_input(_press(Vector2(100.5, 150.5)))
    assert_eq(preview.clicks, 0, "the press is no click, even handed to the picture's own handler")
    assert_false(_dialog.rerun_pending, "it asks for no run")
    assert_eq(_dialog.runs, 0, "and none happened")
    assert_eq(filter.parameters(), before, "and the filter's values are as they were")
