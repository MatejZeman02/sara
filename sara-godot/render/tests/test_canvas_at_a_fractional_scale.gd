## A hundred per cent on an interface scale that is not one.
##
## The old backlog asked that fractional window scaling not blur or artifact the
## viewport, and nothing had ever shot it. Two scalings stack between a texel
## and a device pixel, the view's zoom and `Window.content_scale_factor`, and a
## zoom of one only means one texel per pixel when the second is one. G8's shots
## of a one-texel checkerboard measured what the other scales did: at 0.9 the
## picture came back in ten shades of grey where there are two colours, at 1.25
## in runs of one and two pixels counted 420 to 140, at 1.5 counted 234 to 233.
##
## What the tests below pin is the answer, one texel per device pixel at every
## interface scale, against the scale rather than against a constant.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## The scales a painter actually meets: GNOME's fractional steps, a Wayland
## compositor that reports 0.9, and the whole numbers either side of them.
const SCALES: Array[float] = [0.5, 0.9, 1.0, 1.1, 1.25, 1.35, 1.5, 1.75, 2.0]

var _host: Node = null


## Parented to an autoload rather than to the root, for the reason
## test_canvas_view.gd gives: the runner calls this mid-`_ready`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "G8TestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func _canvas_in_viewport() -> SaCanvas:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(800, 600)
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    viewport.add_child(canvas)
    return canvas


## A view with no window behind it has no interface scale to divide out, which
## is every headless test's view and the base class's own answer.
func test_a_view_without_a_window_zooms_to_one() -> void:
    var view := SaView.new()
    assert_almost_eq(view.get_content_scale(), 1.0, 1e-9, "No window, no scale")
    assert_almost_eq(view.actual_pixel_zoom(), 1.0, 1e-9, "so its hundred per cent is one")


## A canvas view reads the scale off the window `SaUI.apply_to_window` wrote it
## on, and the product is one device pixel per texel at every one of them.
func test_a_texel_covers_one_device_pixel_at_every_scale() -> void:
    var canvas := _canvas_in_viewport()
    var view := SaCanvasView.for_canvas(canvas)
    var window := canvas.get_window()
    var previous := window.content_scale_factor
    for scale_factor in SCALES:
        window.content_scale_factor = scale_factor
        var at := "at %.2f" % scale_factor
        assert_almost_eq(view.get_content_scale(), scale_factor, 1e-6, "The view reads the window's own factor " + at)
        view.zoom_to_actual_pixels(view.get_viewport_size() * 0.5)
        assert_almost_eq(canvas.pixels_per_texel(), 1.0, 1e-5, "and a hundred per cent is one device pixel per texel " + at)
        assert_eq(
            SaCanvas.filter_for(canvas.pixels_per_texel()),
            CanvasItem.TEXTURE_FILTER_NEAREST,
            "which is a square texel rather than a blur " + at
        )
    window.content_scale_factor = previous


## The zoom itself, so a reader can see it is the reciprocal and not a table.
func test_the_zoom_is_one_over_the_scale() -> void:
    var canvas := _canvas_in_viewport()
    var view := SaCanvasView.for_canvas(canvas)
    var window := canvas.get_window()
    var previous := window.content_scale_factor
    for scale_factor in SCALES:
        window.content_scale_factor = scale_factor
        assert_almost_eq(view.actual_pixel_zoom(), 1.0 / scale_factor, 1e-6, "One over %.2f" % scale_factor)
    window.content_scale_factor = previous


## The round trip through a Control's float32 scale lands a hair under one at
## some interface scales, 0.99999998 at 1.35 and 0.99999999 at 1.1, and a bare
## `>= 1.0` read that as a minification and blurred what had just been made
## square. The epsilon is what keeps the two halves of the fix agreeing.
func test_the_filter_forgives_the_float_round_trip() -> void:
    assert_eq(SaCanvas.filter_for(1.0 - 1e-8), CanvasItem.TEXTURE_FILTER_NEAREST, "A hair under one is one")
    assert_eq(SaCanvas.filter_for(1.0 - 1e-6), CanvasItem.TEXTURE_FILTER_NEAREST, "and so is a bigger hair")
    assert_eq(SaCanvas.filter_for(0.999), CanvasItem.TEXTURE_FILTER_LINEAR, "A tenth of a per cent under it is a zoom out")
    assert_eq(SaCanvas.filter_for(0.9), CanvasItem.TEXTURE_FILTER_LINEAR, "and so is nine tenths")
    assert_true(SaCanvas.FILTER_EPSILON < 1.0e-3, "The forgiveness is far below anything an eye can see")


## The anchor is kept, the way every other zoom route keeps it, so a painter
## who was looking at a corner is still looking at it at a hundred per cent.
func test_the_anchored_point_stays_under_the_anchor() -> void:
    var canvas := _canvas_in_viewport()
    var view := SaCanvasView.for_canvas(canvas)
    var window := canvas.get_window()
    var previous := window.content_scale_factor
    window.content_scale_factor = 1.25
    view.set_zoom(4.0)
    view.set_pan(Vector2(-300.0, -200.0))
    var anchor := Vector2(310.0, 240.0)
    var before := view.screen_to_document(anchor)
    view.zoom_to_actual_pixels(anchor)
    assert_almost_eq(view.get_zoom(), 0.8, 1e-6, "The zoom is one over the interface scale")
    var after := view.screen_to_document(anchor)
    assert_almost_eq((after - before).length(), 0.0, 1e-3, "and the document point under the anchor did not move")
    window.content_scale_factor = previous
