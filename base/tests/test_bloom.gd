## The Bloom filter of the base module: a patch of linear 4.0 on black throws a
## glow within the radius and none past it and is not lowered, a layer wholly
## under the threshold comes out as it went in, the threshold is read in linear
## light on a document on the sRGB curve, and the attached form shows what the
## baked layer holds over the patch and its halo.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const BloomFilter = preload("res://modules/sara-base-modules/base/usual/bloom_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const RADIUS := 9
const CENTRE := Vector2i(128, 128)
## The patch is eight texels square, its corner at 124 and its last texel 131.
const PATCH_FIRST := 124
const PATCH_LAST := 131
const BLACK := Color(0.0, 0.0, 0.0, 1.0)
const BRIGHT := Color(4.0, 4.0, 4.0, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _filter: SaBloomFilter = null
var _key: StringName = &""


func _start(space: SaColorSpace) -> void:
    _easel = SaEasel.create_default(Vector2i(2 * SaChunk.SIZE, 2 * SaChunk.SIZE), null, space)
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _filter = BloomFilter.new()
    var filters := SaFilterRegistry.new()
    filters.register(_filter, OWNER)
    _easel.compositor.filter_chain.registry = filters
    _doc = _easel.document
    _key = SaFilterRegistry.key_for(OWNER, _filter)
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)


func after_each() -> void:
    _filter = null
    _layer = null
    _doc = null
    if _easel != null:
        _easel.free()
    _easel = null


## Writes chunk (0, 0) as *fill* with the patch, when there is one, as *patch*.
func _paint(fill: Color, patch: Color = Color(0, 0, 0, 0)) -> void:
    var chunk := _layer.get_or_create_chunk(Vector2i(0, 0))
    var texture := chunk.field(SaFieldSpec.ALBEDO)
    var values := PackedFloat32Array()
    values.resize(SaChunk.SIZE * SaChunk.SIZE * 4)
    for y in SaChunk.SIZE:
        for x in SaChunk.SIZE:
            var inside := patch.a > 0.0 and _inside_patch(x, y)
            var colour := patch if inside else fill
            var i := (y * SaChunk.SIZE + x) * 4
            values[i] = colour.r
            values[i + 1] = colour.g
            values[i + 2] = colour.b
            values[i + 3] = colour.a
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())


func _dial(threshold: float, strength: float = 1.0) -> void:
    _filter.set_parameters({"threshold": threshold, "radius": float(RADIUS), "strength": strength})


func _attach() -> void:
    SaFilterOps.new(_doc).attach(_layer, _key, _filter.parameters())
    Bench.composite(_easel)


static func _texels(texture: SaTexture) -> Callable:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var width := texture.size.x
    var format := texture.format
    return func(at: Vector2i) -> Color: return SaFieldSpec.decode_texel(bytes, format, at.y * width + at.x)


func _near(a: Color, b: Color, tolerance: float) -> bool:
    var most := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))
    return most <= tolerance


func test_a_bright_patch_throws_a_glow_within_the_radius_and_none_past_it() -> void:
    _start(SaColorSpace.linear_srgb())
    _paint(BLACK, BRIGHT)
    _dial(1.0)
    _attach()
    var read := _texels(_easel.output)
    for offset: Vector2i in [Vector2i(7, 0), Vector2i(11, 0), Vector2i(0, -11), Vector2i(-10, 6)]:
        var got: Color = read.call(CENTRE + offset)
        assert_true(got.r > 0.01 and got.g > 0.01 and got.b > 0.01, "A texel %s from the patch is raised, %s" % [offset, got])
    var past := PATCH_LAST + RADIUS + 1
    var before := PATCH_FIRST - RADIUS - 1
    for beyond: Vector2i in [
        Vector2i(past, 128), Vector2i(before, 128), Vector2i(128, past), Vector2i(128, before), Vector2i(200, 200)
    ]:
        var got: Color = read.call(beyond)
        assert_almost_eq(got.r, 0.0, 0.000001, "A texel past the radius is still black at %s, %s" % [beyond, got])
        assert_almost_eq(got.g, 0.0, 0.000001, "in every channel")
    for at: Vector2i in [CENTRE, Vector2i(PATCH_FIRST, PATCH_FIRST), Vector2i(PATCH_LAST, PATCH_LAST)]:
        var got: Color = read.call(at)
        assert_true(got.r >= BRIGHT.r - 0.0001, "The patch is not lowered at %s, %s" % [at, got])
    assert_almost_eq((read.call(Vector2i(PATCH_LAST + 1, 128)) as Color).a, 1.0, 0.0001, "and the black stays opaque")


func test_a_layer_under_the_threshold_is_unchanged() -> void:
    _start(SaColorSpace.linear_srgb())
    _paint(Color(0.2, 0.5, 0.9, 1.0), Color(0.9, 0.9, 0.9, 1.0))
    _dial(1.0)
    _attach()
    var read := _texels(_easel.output)
    var worst := 0.0
    for y in SaChunk.SIZE:
        for x in SaChunk.SIZE:
            var wanted := Color(0.9, 0.9, 0.9, 1.0) if _inside_patch(x, y) else Color(0.2, 0.5, 0.9, 1.0)
            var got: Color = read.call(Vector2i(x, y))
            worst = maxf(
                worst,
                maxf(maxf(absf(got.r - wanted.r), absf(got.g - wanted.g)), maxf(absf(got.b - wanted.b), absf(got.a - wanted.a)))
            )
    assert_true(worst <= 0.0001, "Every texel of the layer reads as it went in, worst %f" % worst)


static func _inside_patch(x: int, y: int) -> bool:
    return x >= PATCH_FIRST and x <= PATCH_LAST and y >= PATCH_FIRST and y <= PATCH_LAST


func test_the_threshold_is_read_in_linear_light_on_the_srgb_curve() -> void:
    _start(SaColorSpace.srgb())
    # Stored 0.8 is linear 0.604, under a threshold of 0.7 in light though over
    # it as a stored number.
    _paint(Color(0.8, 0.8, 0.8, 1.0))
    _dial(0.7)
    _attach()
    var got: Color = _texels(_easel.output).call(CENTRE)
    assert_true(_near(got, Color(0.8, 0.8, 0.8, 1.0), 0.0001), "Stored 0.8 is under 0.7 of light and does not glow, %s" % got)
    SaFilterOps.new(_doc).detach(_layer, _layer.filters[0])
    _dial(0.5)
    _attach()
    got = _texels(_easel.output).call(CENTRE)
    assert_true(got.r > 0.8 + 0.01, "and over a threshold of 0.5 of light it does, %s" % got)


func test_the_attached_form_shows_what_the_baked_layer_holds() -> void:
    _start(SaColorSpace.linear_srgb())
    _paint(BLACK, BRIGHT)
    _dial(1.0)
    _attach()
    var shown := _texels(_easel.output)
    var rows: Dictionary = {}
    for y in range(PATCH_FIRST - RADIUS, PATCH_LAST + RADIUS + 2):
        for x in range(PATCH_FIRST - RADIUS, PATCH_LAST + RADIUS + 2):
            rows[Vector2i(x, y)] = shown.call(Vector2i(x, y))
    SaFilterOps.new(_doc).detach(_layer, _layer.filters[0])
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title(), false)
    assert_true(SaFilterApply.call_run(_filter, ctx), "The run records a pass")
    assert_true(ctx.point is SaNeighbourhoodPass, "and the pass reads its neighbours")
    assert_eq((ctx.point as SaNeighbourhoodPass).radius, RADIUS, "by the radius, which is the halo")
    assert_true(SaFilterApply.apply(ctx, _filter.title()), "which Apply walks over the layer")
    var baked := _texels(_layer.get_field(Vector2i(0, 0)))
    var worst := 0.0
    for at: Vector2i in rows:
        var a: Color = rows[at]
        var b: Color = baked.call(at)
        worst = maxf(worst, maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))))
    assert_true(worst <= 0.0001, "The composite equals the baked layer over the patch and its halo, worst %f" % worst)


func test_the_parameters_round_trip() -> void:
    _start(SaColorSpace.linear_srgb())
    _filter.set_parameters({"threshold": 2.5, "radius": 23.0, "strength": 0.5})
    assert_eq(_filter.parameters(), {"threshold": 2.5, "radius": 23.0, "strength": 0.5}, "The record keeps the three")
    _filter.set_parameters({"unknown": 1})
    var defaults := {"threshold": 1.0, "radius": 20.0, "strength": 1.0}
    assert_eq(_filter.parameters(), defaults, "and a record naming none reads as the defaults")
    assert_eq(_filter.id(), &"bloom", "Its id comes from its title")
