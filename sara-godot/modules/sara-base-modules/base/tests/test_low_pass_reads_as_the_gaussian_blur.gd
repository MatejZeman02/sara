## The Low Pass filter of the base module is the Gaussian blur under another
## name: attached at one radius over the same painted layer, the two read the
## same texels, across a chunk's edge as well. A broad block brighter than white
## keeps its value above one, and a checker of single texels comes out as the
## grey between its two colours, the fine detail dropped. Its radius is the halo
## the pass declares, and the Filter menu lists it under Blur.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const GaussianBlurFilter = preload("res://modules/sara-base-modules/base/usual/gaussian_blur_filter.gd")
const LowPassFilter = preload("res://modules/sara-base-modules/base/usual/low_pass_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const RADIUS := 9.0
## Above white in red and blue, so the block proves nothing clamps.
const BRIGHT := Color(2.5, 0.4, 1.25, 1.0)
## The broad block, which straddles the edge between chunks (0, 0) and (1, 0).
const BLOCK := Rect2i(200, 100, 112, 96)
## The fine detail, a checker of single texels well away from the block.
const CHECKER := Rect2i(64, 300, 64, 64)
## Where the two filters are read: inside the block, on its edges, just past
## it on both sides of the chunks' edge, inside the checker, and on empty paint.
const PROBES: Array[Vector2i] = [
    Vector2i(256, 148),
    Vector2i(255, 148),
    Vector2i(200, 148),
    Vector2i(311, 100),
    Vector2i(196, 120),
    Vector2i(315, 190),
    Vector2i(260, 98),
    Vector2i(96, 332),
    Vector2i(64, 300),
    Vector2i(30, 30),
]

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _blur: SaGaussianBlurFilter = null
var _low_pass: SaLowPassFilter = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(2 * SaChunk.SIZE, 2 * SaChunk.SIZE))
    _doc = _easel.document
    _blur = GaussianBlurFilter.new()
    _low_pass = LowPassFilter.new()
    _easel.compositor.filter_chain.registry.register(_blur, OWNER)
    _easel.compositor.filter_chain.registry.register(_low_pass, OWNER)
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _paint()


func after_each() -> void:
    _blur = null
    _low_pass = null
    _layer = null
    _doc = null
    _easel.free()
    _easel = null


## Writes the block and the checker into the chunks they cover, transparent
## everywhere else, in document texels.
func _paint() -> void:
    var side := SaChunk.SIZE
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
        var chunk := _layer.get_or_create_chunk(grid_pos)
        var texture := chunk.field(SaFieldSpec.ALBEDO)
        assert_eq(texture.format, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, "The bench document is F32")
        var values := PackedFloat32Array()
        values.resize(side * side * 4)
        for y in side:
            for x in side:
                var colour := _painted(grid_pos * side + Vector2i(x, y))
                var i := (y * side + x) * 4
                values[i] = colour.r
                values[i + 1] = colour.g
                values[i + 2] = colour.b
                values[i + 3] = colour.a
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())


## What the layer holds at document texel *at*.
static func _painted(at: Vector2i) -> Color:
    if BLOCK.has_point(at):
        return BRIGHT
    if CHECKER.has_point(at):
        return Color(1, 1, 1, 1) if (at.x + at.y) % 2 == 0 else Color(0, 0, 0, 1)
    return Color(0, 0, 0, 0)


## *filter* attached to the layer at the radius, composited, and the texels of
## the output at every probe, after which the record is taken off again.
func _read_through(filter: SaFilter) -> Dictionary:
    var key := SaFilterRegistry.key_for(OWNER, filter)
    filter.set_parameters({"radius": RADIUS})
    var ops := SaFilterOps.new(_doc)
    ops.attach(_layer, key, filter.parameters())
    Bench.composite(_easel)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(_easel.output.rid, 0)
    var read := {}
    for at: Vector2i in PROBES:
        read[at] = SaFieldSpec.decode_texel(bytes, _easel.output.format, at.y * _easel.output.size.x + at.x)
    ops.detach(_layer, _layer.filters[0])
    return read


func _near(a: Color, b: Color, tolerance: float) -> bool:
    var most := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))
    return most <= tolerance


func test_low_pass_reads_the_texels_the_gaussian_blur_reads() -> void:
    var blurred := _read_through(_blur)
    var low := _read_through(_low_pass)
    for at: Vector2i in PROBES:
        var want: Color = blurred[at]
        var got: Color = low[at]
        assert_true(_near(got, want, 0.000001), "Low Pass reads %s at %s where the blur reads %s" % [got, at, want])
    var edge: Color = low[Vector2i(196, 120)]
    assert_true(edge.a > 0.0 and edge.a < 1.0, "and past the block's edge it is the blur's soft edge, %s" % edge)


func test_a_value_above_one_is_kept_above_one() -> void:
    var low := _read_through(_low_pass)
    var inside: Color = low[Vector2i(256, 148)]
    assert_true(inside.r > 1.0 and inside.b > 1.0, "The broad block reads above white inside, %s" % inside)
    assert_true(_near(inside, BRIGHT, 0.0005), "and is the block's own colour, nothing clamped, %s" % inside)


func test_the_fine_detail_is_dropped() -> void:
    var low := _read_through(_low_pass)
    var grey: Color = low[Vector2i(96, 332)]
    assert_almost_eq(grey.r, 0.5, 0.02, "The checker inside reads the grey between its colours, %s" % grey)
    assert_almost_eq(grey.a, 1.0, 0.0005, "and stays opaque")


func test_its_radius_is_the_halo_it_declares() -> void:
    _low_pass.set_parameters({"radius": 23.0})
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, _low_pass.title(), false)
    assert_true(SaFilterApply.call_run(_low_pass, ctx), "The run records a pass")
    assert_true(ctx.point is SaNeighbourhoodPass, "which reads its neighbours")
    assert_eq((ctx.point as SaNeighbourhoodPass).radius, 23, "as far as the radius")
    assert_eq(_low_pass.family(), &"blur", "It is listed under Blur")
    assert_eq(_low_pass.id(), &"low_pass", "and its id comes from its title")
    assert_true(_low_pass.sentence().contains("Gaussian blur"), "Its sentence names the blur it is")
