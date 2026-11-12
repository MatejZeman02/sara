## Liquify shrinks the paint
## under the brush towards its centre and grows it out again.
##
## Each case paints a disc centred on the brush and reads its radius from its
## area, and its centre from where its paint sits. The disc lies inside the
## brush's flat core at every size it takes, where a scale at full strength
## is exactly the factor asked for.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SessionScript = preload("res://modules/sara-base-modules/base/liquify/sa_liquify_session.gd")
const StateScript = preload("res://modules/sara-base-modules/base/liquify/state_liquify.gd")

const CANVAS := Vector2i(1024, 512)
const RED := Color(0.9, 0.1, 0.1, 1.0)
const CENTRE := Vector2(128.0, 128.0)
const RADIUS: float = 40.0
## The brush's width, whose flat core reaches 100 pixels out, past the
## largest disc a case grows.
const BRUSH: float = 400.0

var _surface: SaSurface = null
var _machine: ToolMachine = null


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A fresh document with an active layer holding a disc of `RADIUS` at
## `CENTRE` in chunk (0, 0).
func _disc() -> SaLayer:
    _surface = Fixtures.make_surface(CANVAS)
    _machine = Fixtures.make_bound_machine(_surface)
    var doc := _surface.get_document()
    var layer := SaLayerOps.new(doc).add(&"", null, 1.0)
    doc.active_layer = layer
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    var edge := chunk.pixel_size()
    var texture := chunk.albedo()
    var image := Image.create_empty(edge, edge, false, _image_format(texture))
    for y in edge:
        for x in edge:
            var inside := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(CENTRE) < RADIUS
            image.set_pixel(x, y, RED if inside else Color(0.0, 0.0, 0.0, 0.0))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    layer.mark_unresolved(Vector2i.ZERO)
    doc.invalidate_chunks([Vector2i.ZERO])
    return layer


## The disc's radius from its area, and its centre, alpha weighted.
static func _measure(layer: SaLayer) -> Dictionary:
    var texture: SaTexture = layer.chunks[Vector2i.ZERO].albedo()
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var texels := Image.create_from_data(texture.size.x, texture.size.y, false, _image_format(texture), bytes)
    var area := 0.0
    var moment := Vector2.ZERO
    for y in texels.get_height():
        for x in texels.get_width():
            var alpha := texels.get_pixel(x, y).a
            area += alpha
            moment += alpha * (Vector2(x, y) + Vector2(0.5, 0.5))
    return {"radius": sqrt(area / PI), "centre": moment / area if area > 0.0 else Vector2(-1.0, -1.0)}


func test_a_shrink_and_a_grow_scale_the_disc_about_its_centre() -> void:
    var layer := _disc()
    assert_almost_eq(float(_measure(layer).radius), RADIUS, 0.5, "The disc starts at its own radius")
    var session: Variant = SessionScript.new(_surface.get_document())
    session.begin(layer)
    session.shrink(CENTRE, BRUSH, 1.0, log(2.0))
    var shrunk := _measure(layer)
    assert_almost_eq(float(shrunk.radius), RADIUS / 2.0, 0.5, "A shrink by ln 2 halves the disc")
    assert_true((shrunk.centre as Vector2).distance_to(CENTRE) < 0.25, "Its centre unmoved: %s" % shrunk.centre)
    session.grow(CENTRE, BRUSH, 1.0, log(4.0))
    var grown := _measure(layer)
    assert_almost_eq(float(grown.radius), RADIUS * 2.0, 0.75, "A grow by ln 4 takes the half back to twice the start")
    assert_true((grown.centre as Vector2).distance_to(CENTRE) < 0.25, "Its centre unmoved: %s" % grown.centre)
    assert_true(session.commit(), "Both are one session")


func test_half_the_strength_scales_by_half_the_amount() -> void:
    var layer := _disc()
    var session: Variant = SessionScript.new(_surface.get_document())
    session.begin(layer)
    session.grow(CENTRE, BRUSH, 0.5, log(4.0))
    assert_almost_eq(float(_measure(layer).radius), RADIUS * 2.0, 0.75, "Half of ln 4 doubles it")
    session.shrink(CENTRE, BRUSH, 0.5, log(4.0))
    assert_almost_eq(float(_measure(layer).radius), RADIUS, 0.5, "And the same shrink brings it back")


func test_the_tools_held_shrink_and_alt_grow() -> void:
    var layer := _disc()
    _machine.set_active_tool(&"liquify")
    var tool: Variant = _machine.active_tool
    tool.settings.mode = StateScript.SHRINK
    tool.settings.size = BRUSH
    tool.settings.strength = 1.0
    tool.press(CENTRE)
    # A second held at full strength halves the paint under the core.
    tool.hold(1.0)
    tool.release()
    assert_almost_eq(float(_measure(layer).radius), RADIUS / 2.0, 0.5, "A held shrink halves the disc in a second")
    var alt := InputEventKey.new()
    alt.keycode = KEY_ALT
    alt.alt_pressed = true
    alt.pressed = true
    tool.handle_input(alt)
    tool.press(CENTRE)
    tool.hold(2.0)
    tool.release()
    assert_almost_eq(float(_measure(layer).radius), RADIUS * 2.0, 0.75, "With Alt the shrink grows, two seconds to twice")
    assert_true(tool.commit_session(), "Both are one session")


func test_grow_mode_grows_without_alt() -> void:
    var layer := _disc()
    _machine.set_active_tool(&"liquify")
    var tool: Variant = _machine.active_tool
    tool.settings.mode = StateScript.GROW
    tool.settings.size = BRUSH
    tool.settings.strength = 1.0
    tool.press(CENTRE)
    tool.hold(0.5)
    tool.release()
    assert_almost_eq(float(_measure(layer).radius), RADIUS * sqrt(2.0), 0.5, "Half a second grows it by the root of two")
