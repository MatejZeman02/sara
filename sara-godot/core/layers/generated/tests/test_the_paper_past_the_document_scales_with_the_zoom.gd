## The paper beyond the document knows the zoom.
##
## Inside the rectangle the ground is a kernel's texels, which the view draws
## square at 100 percent and above and averages below it. Beyond it the ground
## is a shader on a rect a million pixels wide, which read the noise at every
## screen pixel and so, once a pixel covered several texels, showed a coarse
## speckle where the document beside it went smooth. The shader fades the grain
## it cannot resolve by how many document pixels a screen pixel covers, and this
## suite holds that the canvas tells it, at every zoom and at either interface
## scale, and that a zoom is a change the view redraws for. What the shader does
## with the number is held by the scenario of the same name, which photographs
## the edge.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## The four zooms that matter.
const ZOOMS: Array[float] = [0.12, 0.5, 1.0, 4.0]

var _host: Node = null


## Parented to an autoload rather than to the root, for the reason
## test_canvas_view.gd gives: the runner calls this mid-`_ready`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "PaperZoomTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


## A canvas over a document whose bottom layer is a generated background, which
## is what the view draws beyond the rectangle.
func _canvas_over_a_ground() -> SaCanvas:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(800, 600)
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    viewport.add_child(canvas)
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var doc := canvas.document
    SaLayerOps.new(doc).remove(doc.get_node("Background") as SaLayer)
    var ground := SaLayerOps.new(doc).add(&"background", registries.layer_types)
    SaLayerOps.new(doc).move(ground, -1)
    doc.update_caches()
    return canvas


func _told(canvas: SaCanvas) -> float:
    canvas.view_changed()
    var rect := canvas.get_node("BackgroundBeyond") as ColorRect
    var material := rect.material as ShaderMaterial
    assert_not_null(material, "The rect draws through the generator's view shader")
    return float(material.get_shader_parameter("texels_per_pixel"))


## The four zooms: the shader is told the reciprocal of what the
## screen shows, so 12 percent is eight and a third document pixels a pixel and
## 400 percent is a quarter of one.
func test_the_shader_is_told_how_many_texels_a_pixel_covers_at_every_zoom() -> void:
    var canvas := _canvas_over_a_ground()
    for zoom: float in ZOOMS:
        canvas.scale = Vector2(zoom, zoom)
        assert_almost_eq(_told(canvas), 1.0 / zoom, 1e-4, "At %d percent a pixel covers 1 / zoom texels" % roundi(zoom * 100.0))


## A texel's size on screen is the zoom times the window's interface scale, the
## product the view's own sampler and its detail view are chosen by, so a 12
## percent zoom at scale 2 is a pixel over four texels and not eight.
func test_the_interface_scale_counts() -> void:
    var canvas := _canvas_over_a_ground()
    var window := canvas.get_window()
    var previous := window.content_scale_factor
    window.content_scale_factor = 2.0
    for zoom: float in ZOOMS:
        canvas.scale = Vector2(zoom, zoom)
        assert_almost_eq(_told(canvas), 1.0 / (zoom * 2.0), 1e-4, "At scale 2 and %d percent" % roundi(zoom * 100.0))
    window.content_scale_factor = previous


## The flip rides on the sign of the canvas's scale, and a pixel covers as many
## texels in a mirror as outside one.
func test_a_flipped_view_covers_as_many_texels() -> void:
    var canvas := _canvas_over_a_ground()
    canvas.scale = Vector2(-0.25, 0.25)
    assert_almost_eq(_told(canvas), 4.0, 1e-4, "A mirrored view at 25 percent is four texels a pixel")


## A zoom moves nothing the document holds, so only the view's own compare can
## notice it, and a still frame after it has to draw nothing.
func test_a_zoom_redraws_the_ground_once() -> void:
    var canvas := _canvas_over_a_ground()
    canvas.view_changed()
    assert_false(canvas.view_changed(), "A still frame draws nothing")
    canvas.scale = Vector2(0.5, 0.5)
    assert_true(canvas.view_changed(), "A zoom is a draw")
    assert_false(canvas.view_changed(), "once")


## What `apply_view` would set is what the canvas compares, so the zoom has to
## be in it, and a caller that does not know one is at 100 percent.
func test_the_view_state_carries_the_zoom() -> void:
    var canvas := _canvas_over_a_ground()
    var doc := canvas.document
    assert_true(SaGeneratedLayer.view_state(doc, 1.0) != SaGeneratedLayer.view_state(doc, 0.125), "Two zooms are two states")
    assert_eq(SaGeneratedLayer.view_state(doc, 0.125), SaGeneratedLayer.view_state(doc, 0.125), "and one zoom is one")
    assert_eq(SaGeneratedLayer.view_state(doc), SaGeneratedLayer.view_state(doc, 1.0), "A caller naming none is at 100 percent")
    var rect := ColorRect.new()
    SaGeneratedLayer.apply_view(rect, doc)
    var material := rect.material as ShaderMaterial
    assert_almost_eq(float(material.get_shader_parameter("texels_per_pixel")), 1.0, 1e-6, "and its rect is told one texel")
    SaGeneratedLayer.apply_view(rect, doc, 0.25)
    assert_almost_eq(float(material.get_shader_parameter("texels_per_pixel")), 4.0, 1e-6, "until it is told another")
    rect.free()
