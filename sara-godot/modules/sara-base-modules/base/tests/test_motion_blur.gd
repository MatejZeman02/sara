## The motion blur of the base module: a single bright texel is smeared along
## the declared angle and nowhere across it, the smear holds the texel's own
## premultiplied colour, and a length of one is the identity. Attached through
## the compositor, and once one-shot through Apply, which walks the same
## record.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const MotionBlurFilter = preload("res://modules/sara-base-modules/base/usual/motion_blur.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const CENTRE := Vector2i(128, 128)
## Odd, so every sample of a horizontal line lands on a whole texel.
const LENGTH := 9.0
const WHITE := Color(1.0, 1.0, 1.0, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _filter: SaMotionBlurFilter = null
var _key: StringName = &""


func before_each() -> void:
    _easel = Bench.easel(Vector2i(2 * SaChunk.SIZE, 2 * SaChunk.SIZE))
    _doc = _easel.document
    _filter = MotionBlurFilter.new()
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


## Writes the chunk at *grid_pos* as transparent black with the texels of
## *points*, chunk-local position -> colour, on top.
func _paint(grid_pos: Vector2i, points: Dictionary) -> void:
    var chunk := _layer.get_or_create_chunk(grid_pos)
    var texture := chunk.field(SaFieldSpec.ALBEDO)
    assert_eq(texture.format, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, "The bench document is F32")
    var values := PackedFloat32Array()
    values.resize(SaChunk.SIZE * SaChunk.SIZE * 4)
    for at: Vector2i in points:
        var colour: Color = points[at]
        var i := at.y * SaChunk.SIZE + at.x
        values[i * 4] = colour.r
        values[i * 4 + 1] = colour.g
        values[i * 4 + 2] = colour.b
        values[i * 4 + 3] = colour.a
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())


func _attach(angle: float, length: float) -> void:
    _filter.set_parameters({"angle": angle, "length": length})
    SaFilterOps.new(_doc).attach(_layer, _key, _filter.parameters())
    Bench.composite(_easel)


## Every texel of *texture*, read back once, so a window of them costs one copy.
static func _texels(texture: SaTexture) -> Callable:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var width := texture.size.x
    var format := texture.format
    return func(at: Vector2i) -> Color: return SaFieldSpec.decode_texel(bytes, format, at.y * width + at.x)


## The premultiplied colour summed over the square of *reach* around the centre.
static func _window(read: Callable, reach: int) -> Color:
    var total := Color(0, 0, 0, 0)
    for dy in range(-reach, reach + 1):
        for dx in range(-reach, reach + 1):
            var got: Color = read.call(CENTRE + Vector2i(dx, dy))
            total += Color(got.r * got.a, got.g * got.a, got.b * got.a, got.a)
    return total


func _near(a: Color, b: Color, tolerance: float) -> bool:
    var most := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))
    return most <= tolerance


func test_a_horizontal_line_smears_along_x_only() -> void:
    _paint(Vector2i(0, 0), {CENTRE: WHITE})
    _attach(0.0, LENGTH)
    var read := _texels(_easel.output)
    for dx in range(-4, 5):
        var got: Color = read.call(CENTRE + Vector2i(dx, 0))
        assert_almost_eq(got.a, 1.0 / LENGTH, 0.0005, "A ninth of the texel at %d along the line, %s" % [dx, got])
        assert_almost_eq(got.r, 1.0, 0.0005, "in its own colour, straight alpha")
    for at: Vector2i in [CENTRE + Vector2i(5, 0), CENTRE + Vector2i(-5, 0), CENTRE + Vector2i(0, 1), CENTRE + Vector2i(0, -1)]:
        var none: Color = read.call(at)
        assert_almost_eq(none.a, 0.0, 0.000001, "Nothing past the line's end or across it, at %s, %s" % [at, none])


func test_a_vertical_line_smears_along_y_only() -> void:
    _paint(Vector2i(0, 0), {CENTRE: WHITE})
    _attach(90.0, LENGTH)
    var read := _texels(_easel.output)
    for dy in range(-4, 5):
        var got: Color = read.call(CENTRE + Vector2i(0, dy))
        assert_almost_eq(got.a, 1.0 / LENGTH, 0.0005, "A ninth of the texel at %d down the line, %s" % [dy, got])
    for at: Vector2i in [CENTRE + Vector2i(1, 0), CENTRE + Vector2i(-1, 0), CENTRE + Vector2i(0, 5)]:
        var none: Color = read.call(at)
        assert_almost_eq(none.a, 0.0, 0.000001, "Nothing across a vertical line, at %s, %s" % [at, none])


func test_a_diagonal_reads_anticlockwise_and_nothing_across() -> void:
    _paint(Vector2i(0, 0), {CENTRE: WHITE})
    _attach(45.0, LENGTH)
    var read := _texels(_easel.output)
    # Forty-five degrees anticlockwise is up and to the right on a canvas whose
    # y grows downwards, so the smear runs from the lower left to the upper right.
    var along: Color = read.call(CENTRE + Vector2i(2, -2))
    var back: Color = read.call(CENTRE + Vector2i(-2, 2))
    assert_true(along.a > 0.01, "The line reaches up and to the right, %s" % along)
    assert_true(back.a > 0.01, "and down and to the left, %s" % back)
    for at: Vector2i in [CENTRE + Vector2i(1, 1), CENTRE + Vector2i(-1, -1), CENTRE + Vector2i(2, 2), CENTRE + Vector2i(-2, -2)]:
        var none: Color = read.call(at)
        assert_almost_eq(none.a, 0.0, 0.000001, "Nothing across the diagonal, at %s, %s" % [at, none])


func test_the_line_holds_the_texels_energy() -> void:
    var bright := Color(0.5, 2.0, -0.25, 0.8)
    var wanted := Color(bright.r * bright.a, bright.g * bright.a, bright.b * bright.a, bright.a)
    for angle: float in [0.0, 30.0, 135.0]:
        _paint(Vector2i(0, 0), {CENTRE: bright})
        _attach(angle, 12.0)
        var total := _window(_texels(_easel.output), 8)
        var said := "At %s degrees the line sums to what went in, %s against %s" % [angle, total, wanted]
        assert_true(_near(total, wanted, 0.001), said)
        SaFilterOps.new(_doc).detach(_layer, _layer.filters[0])


func test_a_length_of_one_is_the_identity() -> void:
    var points: Dictionary = {}
    for y in range(96, 160):
        for x in range(64, 128):
            points[Vector2i(x, y)] = Color(0.9, 0.5, 0.1, 1.0)
    points[CENTRE] = Color(-0.5, 1.5, 0.25, 0.6)
    _paint(Vector2i(0, 0), points)
    _attach(37.0, 1.0)
    var read := _texels(_easel.output)
    for at: Vector2i in [CENTRE, Vector2i(64, 96), Vector2i(127, 159), Vector2i(128, 100)]:
        var wanted: Color = points.get(at, Color(0, 0, 0, 0))
        var got: Color = read.call(at)
        assert_true(_near(got, wanted, 0.0005), "A length of one leaves %s as it was, %s against %s" % [at, got, wanted])


func test_the_one_shot_writes_what_the_attached_form_shows() -> void:
    _paint(Vector2i(0, 0), {CENTRE: WHITE})
    _attach(20.0, LENGTH)
    var shown: Color = _texels(_easel.output).call(CENTRE + Vector2i(3, -1))
    assert_true(shown.a > 0.0, "The attached form shows the smear there, %s" % shown)
    SaFilterOps.new(_doc).detach(_layer, _layer.filters[0])
    _filter.set_parameters({"angle": 20.0, "length": LENGTH})
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title(), false)
    assert_true(SaFilterApply.call_run(_filter, ctx), "The run records a pass")
    assert_true(ctx.point is SaNeighbourhoodPass, "and the pass reads its neighbours")
    assert_true(SaFilterApply.apply(ctx, _filter.title()), "which Apply walks over the layer")
    var written: Color = _texels(_layer.get_field(Vector2i(0, 0))).call(CENTRE + Vector2i(3, -1))
    assert_true(_near(written, shown, 0.0001), "The one-shot wrote %s where the attached form showed %s" % [written, shown])


func test_the_reach_covers_the_line() -> void:
    assert_eq(MotionBlurFilter.reach(1.0), 2, "A length of one reaches one texel and the bilinear one more")
    assert_eq(MotionBlurFilter.reach(10.0), 6, "Ten reaches five each way and one more")
    assert_eq(MotionBlurFilter.reach(500.0), 251, "The hard maximum stays under a chunk")


func test_the_parameters_round_trip() -> void:
    _filter.set_parameters({"angle": 210.0, "length": 42.0})
    assert_eq(_filter.parameters(), {"angle": 210.0, "length": 42.0}, "The record keeps the angle and the length")
    _filter.set_parameters({"unknown": 1})
    assert_eq(_filter.parameters(), {"angle": 0.0, "length": 10.0}, "and a record naming neither reads as the defaults")
    assert_eq(_filter.id(), &"motion_blur", "Its id comes from its title")
