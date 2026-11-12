## The Gaussian blur of the base module: a flat field comes out as it went in, a
## single bright texel spreads into a bell whose values at one and two standard
## deviations are the textbook ones, the premultiplied colour over the window is
## conserved, and a texel on a stroke's edge keeps its colour as its alpha
## falls. Attached through the compositor, and one-shot through Apply,
## which walks the same record.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const GaussianBlurFilter = preload("res://modules/sara-base-modules/base/usual/gaussian_blur_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
## Nine texels, so a standard deviation is three and two are six.
const RADIUS := 9.0
const CENTRE := Vector2i(128, 128)
## Out of range on purpose, so the flat field proves nothing clamps as well.
const FLAT := Color(-0.25, 1.75, 0.3, 1.0)
const RED := Color(1.0, 0.0, 0.0, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _filter: SaGaussianBlurFilter = null
var _key: StringName = &""


func before_each() -> void:
    _easel = Bench.easel(Vector2i(2 * SaChunk.SIZE, 2 * SaChunk.SIZE))
    _doc = _easel.document
    _filter = GaussianBlurFilter.new()
    _easel.compositor.filter_chain.registry.register(_filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, _filter)
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)


func after_each() -> void:
    _filter = null
    _layer = null
    _doc = null
    _easel.free()
    _easel = null


## Writes the chunk at *grid_pos* as *fill* with the texels of *points*,
## chunk-local position -> colour, on top.
func _paint(grid_pos: Vector2i, fill: Color, points: Dictionary = {}) -> void:
    var chunk := _layer.get_or_create_chunk(grid_pos)
    var texture := chunk.field(SaFieldSpec.ALBEDO)
    assert_eq(texture.format, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, "The bench document is F32")
    var values := PackedFloat32Array()
    values.resize(SaChunk.SIZE * SaChunk.SIZE * 4)
    for i in SaChunk.SIZE * SaChunk.SIZE:
        values[i * 4] = fill.r
        values[i * 4 + 1] = fill.g
        values[i * 4 + 2] = fill.b
        values[i * 4 + 3] = fill.a
    for at: Vector2i in points:
        var colour: Color = points[at]
        var i := at.y * SaChunk.SIZE + at.x
        values[i * 4] = colour.r
        values[i * 4 + 1] = colour.g
        values[i * 4 + 2] = colour.b
        values[i * 4 + 3] = colour.a
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())


func _attach() -> void:
    _filter.set_parameters({"radius": RADIUS})
    SaFilterOps.new(_doc).attach(_layer, _key, _filter.parameters())
    Bench.composite(_easel)


## Every texel of *texture*, read back once, so a window of them costs one copy.
static func _texels(texture: SaTexture) -> Callable:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var width := texture.size.x
    var format := texture.format
    return func(at: Vector2i) -> Color: return SaFieldSpec.decode_texel(bytes, format, at.y * width + at.x)


func _near(a: Color, b: Color, tolerance: float) -> bool:
    var most := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))
    return most <= tolerance


func test_a_flat_field_is_unchanged() -> void:
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
        _paint(grid_pos, FLAT)
    _attach()
    var read := _texels(_easel.output)
    for at: Vector2i in [CENTRE, Vector2i(256, 256), Vector2i(250, 261), Vector2i(384, 130)]:
        var got: Color = read.call(at)
        assert_true(_near(got, FLAT, 0.0005), "A flat field out of range is unchanged at %s, %s" % [at, got])


func test_a_bright_texel_spreads_into_the_bell() -> void:
    _paint(Vector2i(0, 0), Color(0, 0, 0, 0), {CENTRE: Color(1, 1, 1, 1)})
    _attach()
    var read := _texels(_easel.output)
    var centre: Color = read.call(CENTRE)
    assert_true(centre.a > 0.0, "The centre keeps some of the texel, %s" % centre)
    assert_almost_eq(centre.r, 1.0, 0.001, "and its colour, which is straight alpha")
    var one: Color = read.call(CENTRE + Vector2i(3, 0))
    var two: Color = read.call(CENTRE + Vector2i(0, -6))
    assert_almost_eq(one.a / centre.a, exp(-0.5), 0.01, "One standard deviation out is exp(-0.5) of the centre")
    assert_almost_eq(two.a / centre.a, exp(-2.0), 0.01, "and two out is exp(-2)")
    var past: Color = read.call(CENTRE + Vector2i(10, 0))
    assert_almost_eq(past.a, 0.0, 0.000001, "A texel past the radius reads nothing of it, %s" % past)


func test_the_premultiplied_colour_is_conserved() -> void:
    var bright := Color(0.5, 2.0, 1.0, 0.8)
    _paint(Vector2i(0, 0), Color(0, 0, 0, 0), {CENTRE: bright})
    _attach()
    var read := _texels(_easel.output)
    var total := Color(0, 0, 0, 0)
    var reach := int(RADIUS)
    for dy in range(-reach, reach + 1):
        for dx in range(-reach, reach + 1):
            var got: Color = read.call(CENTRE + Vector2i(dx, dy))
            total += Color(got.r * got.a, got.g * got.a, got.b * got.a, got.a)
    var wanted := Color(bright.r * bright.a, bright.g * bright.a, bright.b * bright.a, bright.a)
    assert_true(_near(total, wanted, 0.01), "The window sums to what went in, premultiplied, %s against %s" % [total, wanted])


func test_a_stroke_edge_keeps_its_colour() -> void:
    var points: Dictionary = {}
    for y in range(96, 160):
        for x in range(64, 128):
            points[Vector2i(x, y)] = RED
    _paint(Vector2i(0, 0), Color(0, 0, 0, 0), points)
    _attach()
    var read := _texels(_easel.output)
    var edge: Color = read.call(Vector2i(128, 128))
    assert_true(edge.a > 0.2 and edge.a < 0.8, "The first texel past the stroke is partly covered, %s" % edge)
    assert_true(_near(Color(edge.r, edge.g, edge.b, 1.0), RED, 0.001), "and it is red, not red darkened towards black, %s" % edge)


func test_the_one_shot_writes_what_the_attached_form_shows() -> void:
    _paint(Vector2i(0, 0), Color(0, 0, 0, 0), {CENTRE: Color(1, 1, 1, 1)})
    _attach()
    var shown: Color = _texels(_easel.output).call(CENTRE + Vector2i(3, 0))
    SaFilterOps.new(_doc).detach(_layer, _layer.filters[0])
    _filter.set_parameters({"radius": RADIUS})
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title(), false)
    assert_true(SaFilterApply.call_run(_filter, ctx), "The run records a pass")
    assert_true(ctx.point is SaNeighbourhoodPass, "and the pass reads its neighbours")
    assert_true(SaFilterApply.apply(ctx, _filter.title()), "which Apply walks over the layer")
    var written: Color = _texels(_layer.get_field(Vector2i(0, 0))).call(CENTRE + Vector2i(3, 0))
    assert_true(_near(written, shown, 0.0001), "The one-shot wrote %s where the attached form showed %s" % [written, shown])


func test_the_parameters_round_trip() -> void:
    _filter.set_parameters({"radius": 23.0})
    assert_eq(_filter.parameters(), {"radius": 23.0}, "The record keeps the radius")
    _filter.set_parameters({"unknown": 1})
    assert_eq(_filter.parameters(), {"radius": 10.0}, "and a record naming no radius reads as the default")
    assert_eq(_filter.id(), &"gaussian_blur", "Its id comes from its title")
