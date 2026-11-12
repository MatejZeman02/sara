## A change of interface scale keeps the painting's size on screen.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The zoom is in logical units, so a zoom kept across scale 1 to 2 doubled the
## picture in device pixels. What is stated here is the size in device pixels,
## the zoom times the window's factor times the document, read the same after 1
## to 2 and back, and a view whose last move was a Fit fitted again rather than
## divided. The canvas is in the root viewport, because the main canvas is the
## one that follows the scale. The shots are
## `scenarios/a-scale-change-keeps-the-paintings-size-on-screen.json`.
extends "res://tests/test_framework.gd"

## A real SaCanvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

const SIZE := Vector2i(512, 384)

var _host: Control = null
var _previous_scale: float = 1.0


## Parented to an autoload, which sits in the root viewport, for the reason
## `test_canvas_view.gd` gives: the runner calls a suite from its own `_ready`.
func before_each() -> void:
    _previous_scale = EventBus.get_window().content_scale_factor
    _host = Control.new()
    _host.name = "N64TestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    _scale_to(_previous_scale)


func test_the_painting_keeps_its_size_in_pixels_from_one_to_two_and_back() -> void:
    _scale_to(1.0)
    var canvas := _canvas()
    var view := SaCanvasView.for_canvas(canvas)
    # Somewhere a painter left it, which is not a fit.
    view.set_zoom(0.75)
    view.set_pan(Vector2(40.0, 30.0))
    var before := _on_screen(canvas)
    var middle := view.screen_to_document(view.get_viewport_size() * 0.5)

    _scale_to(2.0)
    assert_almost_eq(view.get_zoom(), 0.375, 1e-5, "The zoom is halved at twice the scale")
    assert_almost_eq(_on_screen(canvas).x, before.x, 1e-3, "so the painting is as wide in pixels")
    assert_almost_eq(_on_screen(canvas).y, before.y, 1e-3, "and as high")
    var still := view.screen_to_document(view.get_viewport_size() * 0.5)
    assert_almost_eq(still.x, middle.x, 1e-2, "The point in the middle stays in the middle across")
    assert_almost_eq(still.y, middle.y, 1e-2, "and down")

    _scale_to(1.0)
    assert_almost_eq(view.get_zoom(), 0.75, 1e-5, "Back at one the zoom is where the painter left it")
    assert_almost_eq(_on_screen(canvas).x, before.x, 1e-3, "and so is the size in pixels")


func test_a_fitted_view_is_fitted_again() -> void:
    _scale_to(1.0)
    var canvas := _canvas()
    var view := SaCanvasView.for_canvas(canvas)
    view.fit(SIZE)
    assert_true(view._fitted, "A Fit is remembered as the last move")

    _scale_to(2.0)
    var area := view.get_free_rect()
    var zoom := minf(area.size.x / SIZE.x, area.size.y / SIZE.y)
    assert_almost_eq(view.get_zoom(), zoom, 1e-5, "At twice the scale the view is the fit of the new area")
    assert_almost_eq(canvas.position.x + SIZE.x * zoom * 0.5, area.get_center().x, 1e-3, "centred in it")
    assert_true(view._fitted, "and still a fit")

    _scale_to(1.0)
    area = view.get_free_rect()
    zoom = minf(area.size.x / SIZE.x, area.size.y / SIZE.y)
    assert_almost_eq(view.get_zoom(), zoom, 1e-5, "and back at one it is fitted again")


func test_any_other_move_forgets_the_fit() -> void:
    _scale_to(1.0)
    var canvas := _canvas()
    var view := SaCanvasView.for_canvas(canvas)
    view.fit(SIZE)
    view.zoom_by(SaView.ZOOM_STEP, view.get_viewport_size() * 0.5)
    assert_false(view._fitted, "A wheel notch after the Fit is the last move")
    var zoom := view.get_zoom()

    _scale_to(2.0)
    assert_almost_eq(view.get_zoom(), zoom * 0.5, 1e-5, "so the scale change divides the zoom instead of fitting")


## Every route asks the canvas for its one view, so a Fit made through any of
## them is the one the scale change reads.
func test_every_view_over_a_canvas_is_one() -> void:
    var canvas := _canvas()
    var first := SaCanvasView.for_canvas(canvas)
    var second := SaCanvasView.for_canvas(canvas)
    assert_true(first == second, "One canvas, one view")


func _canvas() -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = SIZE
    _host.add_child(canvas)
    return canvas


## The painting's size in device pixels.
func _on_screen(canvas: SaCanvas) -> Vector2:
    return Vector2(SIZE) * absf(canvas.scale.x) * canvas.get_window().content_scale_factor


## What a scale change does in the app: the window takes the factor, and the
## bus says so. Written here because the suite stands in for `SaUI`, as
## `test_canvas_at_a_fractional_scale.gd` does.
func _scale_to(factor: float) -> void:
    var window := EventBus.get_window()
    if is_equal_approx(window.content_scale_factor, factor):
        return
    window.content_scale_factor = factor
    EventBus.ui_scale_changed.emit(factor)
