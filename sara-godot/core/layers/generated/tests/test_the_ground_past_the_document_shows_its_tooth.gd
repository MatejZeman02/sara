## The ground beyond the document shows its tooth lit, as the ground inside
## does. A painter, of the paper round the document on Windows: it "never
## shows tooth". Inside, the relief stands the ground's grain up as height and
## the view lights it. Beyond, the paper and the canvas were drawn flat. This
## suite draws both grounds' view shaders in one grey, so every difference
## between two pixels is the light, and holds that the light shows the grain
## when the relief is on and nothing when it is off or the tooth is nought.
extends "res://tests/test_framework.gd"

## The shaders draw into a viewport.
const REQUIRES_GPU := true

const PAPER := "res://shaders/canvas/paper.gdshader"
const CANVAS := "res://shaders/canvas/canvas.gdshader"

## The side of the strip drawn, in screen pixels, at 100 percent.
const SIDE := 128

## Away from the origin, as the rect beyond the document is.
const ORIGIN := Vector2(3000.0, 5000.0)

const GREY := Color(0.6, 0.6, 0.6, 1.0)

## A millimetre of tooth, about what a new paper opens with, at 300 dpi.
const TOOTH := 1.0
const PIXEL_MM := 25.4 / 300.0


## *shader* drawn in one grey with the relief *lit* over a tooth of *tooth*.
func _strip(shader: String, lit: bool, tooth: float) -> Image:
    var material := ShaderMaterial.new()
    material.shader = load(shader)
    material.set_shader_parameter("color_a", GREY)
    material.set_shader_parameter("color_b", GREY)
    material.set_shader_parameter("scale", 8.0)
    material.set_shader_parameter("rect_origin", ORIGIN)
    material.set_shader_parameter("rect_size", Vector2(SIDE, SIDE))
    material.set_shader_parameter("texels_per_pixel", 1.0)
    material.set_shader_parameter("relief_enabled", lit)
    material.set_shader_parameter("relief_light", SaReliefLight.new().toward())
    material.set_shader_parameter("relief_strength", 2.0)
    material.set_shader_parameter("tooth", tooth)
    material.set_shader_parameter("tooth_weight", 1.0)
    material.set_shader_parameter("pixel_mm", PIXEL_MM)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(SIDE, SIDE)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, material.get_rid())
    RenderingServer.canvas_item_add_rect(item, Rect2(Vector2.ZERO, Vector2(SIDE, SIDE)), Color.WHITE)
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    return image


## How far apart the darkest and the lightest pixel are, 0 to 1.
func _spread(image: Image) -> float:
    var lowest := 1.0
    var highest := 0.0
    for y in image.get_height():
        for x in image.get_width():
            var value := image.get_pixel(x, y).r
            lowest = minf(lowest, value)
            highest = maxf(highest, value)
    return highest - lowest


func test_the_paper_beyond_shows_its_grain_lit() -> void:
    var spread := _spread(_strip(PAPER, true, TOOTH))
    assert_true(spread > 0.05, "The paper's tooth catches the light beyond the document: %.3f" % spread)
    assert_almost_eq(_spread(_strip(PAPER, false, TOOTH)), 0.0, 1e-6, "and with the relief off the grey is flat")
    assert_almost_eq(_spread(_strip(PAPER, true, 0.0)), 0.0, 1e-6, "as it is with no tooth")


func test_the_canvas_beyond_shows_its_threads_lit() -> void:
    var spread := _spread(_strip(CANVAS, true, TOOTH))
    assert_true(spread > 0.05, "The canvas's threads catch the light beyond the document: %.3f" % spread)
    assert_almost_eq(_spread(_strip(CANVAS, false, TOOTH)), 0.0, 1e-6, "and with the relief off the grey is flat")
    assert_almost_eq(_spread(_strip(CANVAS, true, 0.0)), 0.0, 1e-6, "as it is with no tooth")


## The view hands the shader what the relief inside reads: the document's
## light, its strength and resolution, and the ground's opacity as the weight.
func test_the_view_tells_the_shader_the_documents_light() -> void:
    var host := Node.new()
    EventBus.add_child(host)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(400, 300)
    host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(128, 128)
    viewport.add_child(canvas)
    var doc := canvas.document
    doc.dpi = 150.0
    doc.relief_light.strength = 3.0
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaLayerOps.new(doc).remove(doc.get_node("Background") as SaLayer)
    var ground := SaLayerOps.new(doc).add(&"background", registries.layer_types)
    SaLayerOps.new(doc).move(ground, -1)
    doc.update_caches()
    ground.opacity = 0.5
    var rect := ColorRect.new()
    SaGeneratedLayer.apply_view(rect, doc)
    var material := rect.material as ShaderMaterial
    assert_not_null(material, "The rect draws through the ground's view shader")
    if material != null:
        assert_almost_eq(float(material.get_shader_parameter("relief_strength")), 3.0, 1e-6, "with the document's strength")
        assert_almost_eq(float(material.get_shader_parameter("tooth_weight")), 0.5, 1e-6, "the ground's opacity")
        assert_almost_eq(float(material.get_shader_parameter("pixel_mm")), 25.4 / 150.0, 1e-6, "and its resolution")
        assert_eq(material.get_shader_parameter("relief_light"), doc.relief_light.toward(), "and its light")
    var before := SaGeneratedLayer.view_state(doc)
    doc.relief_light.strength = 1.0
    assert_true(before != SaGeneratedLayer.view_state(doc), "A new light is a new state the view redraws for")
    rect.free()
    host.free()
