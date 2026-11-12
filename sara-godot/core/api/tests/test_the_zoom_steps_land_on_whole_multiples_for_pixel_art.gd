## The zoom steps land on whole multiples for pixel art.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## With `SaSettings.integer_zoom` on, a notch in from 100% goes to 200%, 300%,
## 400%, then 800% and 1600%, and a notch out walks the same stops back. 100%
## is actual pixels, so on an interface scale of 2 the stops are halves of a
## logical zoom. Off, a notch is ZOOM_STEP as before. The arithmetic is on
## SaView and runs against the fake view, so no tree and no GPU. The running
## app's chord is `scenarios/the-zoom-steps-land-on-whole-multiples-for-pixel-art.json`.
extends "res://tests/test_framework.gd"

const STOPS: Array[float] = [1.0, 2.0, 3.0, 4.0, 8.0, 16.0, 32.0, 64.0]


## A fake view on a window with an interface scale.
class ScaledView:
    extends SaTestFixtures.FakeView

    var content_scale: float = 1.0

    func get_content_scale() -> float:
        return content_scale


var _saved: bool = false


func before_each() -> void:
    _saved = SaSettings.integer_zoom


func after_each() -> void:
    SaSettings.integer_zoom = _saved


func _view(content_scale: float) -> ScaledView:
    var view := ScaledView.new()
    view.viewport_size = Vector2(1000, 800)
    view.content_scale = content_scale
    view.zoom = view.actual_pixel_zoom()
    return view


func test_zoom_in_from_100_per_cent_steps_on_whole_multiples() -> void:
    SaSettings.integer_zoom = true
    var view := _view(1.0)
    var anchor := Vector2(500, 400)
    for stop: float in STOPS.slice(1):
        SaView.Steps.notch(view, 1.0, true, anchor)
        assert_almost_eq(view.zoom, stop, 1e-6, "A notch in lands on %d00%%" % int(stop))
        assert_almost_eq(view.zoom, roundf(view.zoom), 1e-6, "which is a whole multiple")


func test_zoom_out_walks_the_same_stops_back_to_100_per_cent() -> void:
    SaSettings.integer_zoom = true
    var view := _view(1.0)
    view.zoom = 64.0
    var anchor := Vector2(500, 400)
    var back := STOPS.duplicate()
    back.reverse()
    for stop: float in back.slice(1):
        SaView.Steps.notch(view, 1.0, false, anchor)
        assert_almost_eq(view.zoom, stop, 1e-6, "A notch out lands on %d00%%" % int(stop))


func test_a_zoom_between_stops_goes_to_the_next_one() -> void:
    SaSettings.integer_zoom = true
    var view := _view(1.0)
    view.zoom = 2.5
    SaView.Steps.notch(view, 1.0, true, Vector2.ZERO)
    assert_almost_eq(view.zoom, 3.0, 1e-6, "2.5 in is 3")
    view.zoom = 2.5
    SaView.Steps.notch(view, 1.0, false, Vector2.ZERO)
    assert_almost_eq(view.zoom, 2.0, 1e-6, "2.5 out is 2")
    view.zoom = 5.5
    SaView.Steps.notch(view, 1.0, true, Vector2.ZERO)
    assert_almost_eq(view.zoom, 8.0, 1e-6, "5.5 in is 8")
    view.zoom = 5.5
    SaView.Steps.notch(view, 1.0, false, Vector2.ZERO)
    assert_almost_eq(view.zoom, 4.0, 1e-6, "5.5 out is 4")


func test_a_step_in_from_under_100_per_cent_stops_on_it() -> void:
    SaSettings.integer_zoom = true
    var view := _view(1.0)
    view.zoom = 0.9
    SaView.Steps.notch(view, 1.0, true, Vector2.ZERO)
    assert_almost_eq(view.zoom, 1.0, 1e-6, "0.9 times ZOOM_STEP passes 1, so the step stops on 100%")
    view.zoom = 0.5
    SaView.Steps.notch(view, 1.0, true, Vector2.ZERO)
    assert_almost_eq(view.zoom, 0.5 * SaView.ZOOM_STEP, 1e-6, "and further out a step is ZOOM_STEP")
    view.zoom = 1.0
    SaView.Steps.notch(view, 1.0, false, Vector2.ZERO)
    assert_almost_eq(view.zoom, 1.0 / SaView.ZOOM_STEP, 1e-6, "as is a step out from 100%")


func test_the_stops_are_multiples_of_actual_pixels_on_a_scaled_window() -> void:
    SaSettings.integer_zoom = true
    var view := _view(2.0)
    for stop: float in STOPS.slice(1, 4):
        SaView.Steps.notch(view, 1.0, true, Vector2.ZERO)
        assert_almost_eq(view.zoom * view.get_content_scale(), stop, 1e-6, "Device pixels a texel is %d" % int(stop))


func test_off_a_notch_is_zoom_step_as_before() -> void:
    SaSettings.integer_zoom = false
    var view := _view(1.0)
    SaView.Steps.notch(view, 1.0, true, Vector2.ZERO)
    assert_almost_eq(view.zoom, SaView.ZOOM_STEP, 1e-6, "One notch in is one step")
    SaView.Steps.notch(view, 1.0, false, Vector2.ZERO)
    assert_almost_eq(view.zoom, 1.0, 1e-6, "and one out is back")


func test_the_step_keeps_the_point_under_the_anchor() -> void:
    SaSettings.integer_zoom = true
    var view := _view(1.0)
    view.pan = Vector2(30, 20)
    var anchor := Vector2(700, 450)
    var before := (anchor - view.pan) / view.zoom
    SaView.Steps.notch(view, 1.0, true, anchor)
    var after := (anchor - view.pan) / view.zoom
    assert_almost_eq(after.x, before.x, 1e-4, "The anchored point stays in x")
    assert_almost_eq(after.y, before.y, 1e-4, "and in y")
