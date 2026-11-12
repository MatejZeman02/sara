## The lens blur of the base module: a single bright texel at radius four spreads
## into a flat disc whose rim carries a share on the axis and nothing past the
## corner, the premultiplied colour over the disc is conserved, a painted edge
## fades monotonely across the rim and keeps its colour, and nothing clamps.
## Attached through the compositor, and once one-shot through Apply, which walks
## the same record.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const LensBlurFilter = preload("res://modules/sara-base-modules/base/usual/lens_blur_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const RADIUS := 4.0
const CENTRE := Vector2i(128, 128)
## Out of range on purpose, so the flat field proves nothing clamps as well.
const FLAT := Color(-0.25, 1.75, 0.3, 1.0)
const RED := Color(1.0, 0.0, 0.0, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _filter: SaLensBlurFilter = null
var _key: StringName = &""


func before_each() -> void:
    _easel = Bench.easel(Vector2i(2 * SaChunk.SIZE, 2 * SaChunk.SIZE))
    _doc = _easel.document
    _filter = LensBlurFilter.new()
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


func test_a_bright_texel_spreads_into_a_flat_disc() -> void:
    _paint(Vector2i(0, 0), Color(0, 0, 0, 0), {CENTRE: Color(1, 1, 1, 1)})
    _attach()
    var read := _texels(_easel.output)
    var centre: Color = read.call(CENTRE)
    assert_true(centre.a > 0.0, "The centre keeps some of the texel, %s" % centre)
    assert_almost_eq(centre.r, 1.0, 0.001, "and its colour, which is straight alpha")
    var inner: Color = read.call(CENTRE + Vector2i(2, 2))
    assert_almost_eq(inner.a, centre.a, 0.000001, "Inside the disc it is flat, not a bell, %s against %s" % [inner, centre])
    var rim: Color = read.call(CENTRE + Vector2i(4, 0))
    assert_almost_eq(rim.a / centre.a, 0.5, 0.001, "The texel four out on the axis carries half a share, %s" % rim)
    var corner: Color = read.call(CENTRE + Vector2i(-4, 4))
    assert_almost_eq(corner.a, 0.0, 0.000001, "The texel six out along the diagonal carries none, %s" % corner)


func test_the_premultiplied_colour_is_conserved() -> void:
    var bright := Color(0.5, 2.0, 1.0, 0.8)
    _paint(Vector2i(0, 0), Color(0, 0, 0, 0), {CENTRE: bright})
    _attach()
    var read := _texels(_easel.output)
    var total := Color(0, 0, 0, 0)
    var reach := ceili(RADIUS)
    for dy in range(-reach, reach + 1):
        for dx in range(-reach, reach + 1):
            var got: Color = read.call(CENTRE + Vector2i(dx, dy))
            total += Color(got.r * got.a, got.g * got.a, got.b * got.a, got.a)
    var wanted := Color(bright.r * bright.a, bright.g * bright.a, bright.b * bright.a, bright.a)
    assert_true(_near(total, wanted, 0.001), "The disc sums to what went in, premultiplied, %s against %s" % [total, wanted])


func test_an_edge_fades_monotonely_and_keeps_its_colour() -> void:
    var points: Dictionary = {}
    for y in range(96, 160):
        for x in range(64, 128):
            points[Vector2i(x, y)] = RED
    _paint(Vector2i(0, 0), Color(0, 0, 0, 0), points)
    _attach()
    var read := _texels(_easel.output)
    var before := 2.0
    for x in range(120, 136):
        var got: Color = read.call(Vector2i(x, 128))
        assert_true(got.a <= before + 0.000001, "The alpha falls across the rim at x %d, %s after %s" % [x, got.a, before])
        before = got.a
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
    _filter.set_parameters({"radius": 23.5})
    assert_eq(_filter.parameters(), {"radius": 23.5}, "The record keeps the radius")
    _filter.set_parameters({"unknown": 1})
    assert_eq(_filter.parameters(), {"radius": 8.0}, "and a record naming no radius reads as the default")
    assert_eq(_filter.id(), &"lens_blur", "Its id comes from its title")
