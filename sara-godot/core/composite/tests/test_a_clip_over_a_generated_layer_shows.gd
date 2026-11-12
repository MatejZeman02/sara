## A layer clipped to a generated layer shows where the generated layer is
## opaque.
##
## A generated layer stores no chunk, so the clip read its alpha from a field
## that was never there and the fold skipped every position under it: a red
## layer clipped over an opaque ground drew nothing. `clip_alpha` now evaluates
## a generated base's kernel at the chunk, and `SaLayerStack.clip_reaches`
## tells the fold and the stroke's gate that such a base reaches everywhere.
## Each case is read with the red one active, above the active layer, below it,
## and folded into an isolated group's cache.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const RED := Color(1, 0, 0, 1)
const GREEN := Color(0, 1, 0, 1)
const GREY := Color(0.5, 0.5, 0.5, 1)
## A texel under the half of the ground its mask keeps, one under the half it
## hides, and one in the second chunk, where the mask was never painted.
const KEPT_AT := Vector2i(40, 10)
const HIDDEN_AT := Vector2i(200, 10)
const UNPAINTED_AT := Vector2i(300, 10)
const PLACES: Array[String] = ["active", "above", "below", "folded"]


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func _assert_colour(actual: Color, expected: Color, what: String) -> void:
    assert_almost_eq(actual.r, expected.r, 0.02, what + ", red")
    assert_almost_eq(actual.g, expected.g, 0.02, what + ", green")
    assert_almost_eq(actual.b, expected.b, 0.02, what + ", blue")


## The default easel, then a green generated ground over Layer 1 and a red
## layer over both chunks clipped to it. *place* says where the pair sits
## against the active layer: the red one is it, the pair is above Layer 1 or
## below a new top layer, or the pair is an isolated group's, which folds.
func _build(place: String, half: bool) -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(512, 256))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var ground := ops.add()
    ground.name = "Ground"
    ground.generator = "background"
    ground.generator_params = {SaGeneratedLayer.PARAM_COLOR: GREEN}
    if half:
        _hide_right_half(ground)
    var red := ops.add()
    red.name = "Red"
    doc.fill_layer(RED, red)
    SaLayerStack.set_clip_to_below(doc, red, true)
    match place:
        "active":
            doc.set_active_layer(red)
        "above":
            doc.set_active_layer(doc.get_node("Layer 1") as SaLayer)
        "below":
            var top := ops.add()
            top.name = "Top"
            doc.set_active_layer(top)
        "folded":
            var group := ops.group_layers([ground, red])
            ops.set_isolated(group, true)
            doc.set_active_layer(doc.get_node("Layer 1") as SaLayer)
    assert_eq(SaLayerStack.clip_base(doc, red), ground, "The generated layer is the red one's base (%s)" % place)
    doc.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


## The ground's mask at the first chunk: one on the left half, zero on the
## right, so the ground is transparent in half its first chunk.
func _hide_right_half(layer: SaLayer) -> void:
    var texture := layer.add_mask().get_or_create(Vector2i(0, 0))
    var values := PackedFloat32Array()
    values.resize(texture.size.x * texture.size.y)
    for y in texture.size.y:
        for x in texture.size.x:
            values[y * texture.size.x + x] = 1.0 if x * 2 < texture.size.x else 0.0
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())


func test_a_red_layer_clipped_over_an_opaque_generator_shows_red() -> void:
    for place in PLACES:
        var easel := _build(place, false)
        for at: Vector2i in [KEPT_AT, HIDDEN_AT, UNPAINTED_AT]:
            _assert_colour(_texel(easel.output, at), RED, "Over the opaque ground the red shows at %s (%s)" % [at, place])
        easel.free()


func test_a_red_layer_clipped_over_a_half_transparent_generator_shows_on_its_opaque_half() -> void:
    for place in PLACES:
        var easel := _build(place, true)
        _assert_colour(_texel(easel.output, KEPT_AT), RED, "Where the ground shows, the red does (%s)" % place)
        _assert_colour(_texel(easel.output, HIDDEN_AT), GREY, "Where it is hidden, neither shows (%s)" % place)
        _assert_colour(_texel(easel.output, UNPAINTED_AT), RED, "A chunk its mask never held is opaque (%s)" % place)
        easel.free()


## Unclipped, the red covers the ground wherever the ground's mask hides it,
## which is what the clip takes away.
func test_unclipped_the_red_covers_the_hidden_half_too() -> void:
    var easel := _build("above", true)
    var red := easel.document.get_node("Red") as SaLayer
    SaLayerStack.set_clip_to_below(easel.document, red, false)
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    _assert_colour(_texel(easel.output, HIDDEN_AT), RED, "Unclipped, the red shows over the hidden half")
    easel.free()
