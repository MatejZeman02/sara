## How the canvas samples its texels at each zoom.
##
## A `TextureRect` inherits a linear sampler with no mip levels, so a painting
## zoomed past 100 percent was a blur between texels, and one zoomed well below
## it shimmered: four texels read per screen pixel out of the eleven a pixel
## covers, and a different four at every fractional zoom. The view shader now
## covers the footprint itself, and the sampler is chosen for what the screen
## shows, which is the zoom times the window's content scale factor.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

var _host: Node = null


## Parented to an autoload rather than to the root, for the reason
## test_canvas_view.gd gives: the runner calls this mid-`_ready`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "CanvasSamplingTestHost"
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


func test_nearest_from_one_pixel_per_texel_and_linear_below() -> void:
    assert_eq(SaCanvas.filter_for(1.0), CanvasItem.TEXTURE_FILTER_NEAREST, "At 100 percent a texel is a square")
    assert_eq(SaCanvas.filter_for(4.0), CanvasItem.TEXTURE_FILTER_NEAREST, "and stays one however far in")
    assert_eq(SaCanvas.filter_for(0.99), CanvasItem.TEXTURE_FILTER_LINEAR, "Below it each tap averages four texels")
    assert_eq(SaCanvas.filter_for(0.1), CanvasItem.TEXTURE_FILTER_LINEAR, "at every zoom out")


## The choice follows the zoom as the user changes it, without the tool that
## changed it having to know a sampler exists.
func test_the_sampler_follows_the_zoom() -> void:
    var canvas := _canvas_in_viewport()
    canvas.scale = Vector2(3.0, 3.0)
    canvas._sync_sampling()
    assert_eq(canvas.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "Zoomed in: nearest")

    canvas.scale = Vector2(0.3, 0.3)
    canvas._sync_sampling()
    assert_eq(canvas.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR, "Zoomed out: linear under the shader's taps")

    canvas.scale = Vector2(1.0, 1.0)
    canvas._sync_sampling()
    assert_eq(canvas.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "and back at 100 percent, nearest again")


## Two scalings stack. At a 1.25 desktop scale a 90 percent zoom is 1.125
## pixels per texel, which is a square texel and wants nearest, and reading the
## zoom alone would have chosen the blur.
func test_the_content_scale_factor_counts() -> void:
    var canvas := _canvas_in_viewport()
    canvas.scale = Vector2(0.9, 0.9)
    var window := canvas.get_window()
    var previous := window.content_scale_factor
    window.content_scale_factor = 1.25
    assert_almost_eq(canvas.pixels_per_texel(), 1.125, 1e-6, "Zoom times the window's scale")
    assert_eq(SaCanvas.filter_for(canvas.pixels_per_texel()), CanvasItem.TEXTURE_FILTER_NEAREST, "which is nearest")
    window.content_scale_factor = previous


## The view asks to be drawn when something it shows moved and not once a
## frame. A redraw a frame is a rendered frame a frame
## whatever the low-processor mode says, so an idle Sara on a 4K display
## drew a hundred frames a second for nothing.
func test_the_view_redraws_on_a_composite_and_not_on_a_still_frame() -> void:
    var canvas := _canvas_in_viewport()
    assert_eq(canvas.process_priority, 1, "The view is processed after the easel it holds")
    assert_true(canvas.view_changed(), "The first frame draws")
    assert_false(canvas.view_changed(), "and a still frame does not")
    canvas.easel.request_full_composite()
    canvas.easel.process_pending_composite()
    assert_true(canvas.view_changed(), "A composite this frame is a draw this frame")
    assert_false(canvas.view_changed(), "once")
    canvas.easel.request_composite()
    canvas.easel.process_pending_composite()
    assert_false(canvas.view_changed(), "and a request with nothing dirty composited nothing and draws nothing")
