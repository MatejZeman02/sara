## The wobble of the base module ripples a hard edge by the sine
## it declares. At no turbulence a vertical edge comes out displaced by exactly
## `amplitude * sin(TAU * y / wavelength)` on every sampled row, on a paint
## layer and on a group, across a chunk seam, and one-shot through Apply as
## attached. At no amplitude it is the identity, and turbulence moves the
## crests without passing the amplitude.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const WobbleFilter = preload("res://modules/sara-base-modules/base/usual/wobble_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
## Where the edge stands in both chunks of the left column: paint left of it.
const EDGE := 128
## The row window the edge is measured over, far wider than any shift here.
const FROM := 96
const TO := 160
const AMPLITUDE := 8.0
const WAVELENGTH := 40.0
const WHITE := Color(1.0, 1.0, 1.0, 1.0)
## Rows of both chunks of the column, crests, troughs and zeros among them.
const ROWS: Array[int] = [0, 5, 10, 17, 20, 30, 33, 100, 131, 250, 255, 256, 263, 300, 407, 511]

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _filter: SaWobbleFilter = null
var _key: StringName = &""


func before_each() -> void:
    _easel = Bench.easel(Vector2i(2 * SaChunk.SIZE, 2 * SaChunk.SIZE))
    _doc = _easel.document
    _filter = WobbleFilter.new()
    _easel.compositor.filter_chain.registry.register(_filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, _filter)
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _paint_edge(Vector2i(0, 0))
    _paint_edge(Vector2i(0, 1))


func after_each() -> void:
    _filter = null
    _layer = null
    _doc = null
    _easel.free()
    _easel = null


## Writes the chunk at *grid_pos* opaque white left of [const EDGE] and
## transparent right of it, a hard vertical edge down the whole chunk.
func _paint_edge(grid_pos: Vector2i) -> void:
    var chunk := _layer.get_or_create_chunk(grid_pos)
    var texture := chunk.field(SaFieldSpec.ALBEDO)
    var side := chunk.pixel_size()
    var values := PackedFloat32Array()
    values.resize(side * side * 4)
    for y in side:
        for x in EDGE:
            var i := (y * side + x) * 4
            values[i] = WHITE.r
            values[i + 1] = WHITE.g
            values[i + 2] = WHITE.b
            values[i + 3] = WHITE.a
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())


func _values(amplitude: float, turbulence: float, direction := "horizontal") -> Dictionary:
    return {"direction": direction, "amplitude": amplitude, "wavelength": WAVELENGTH, "turbulence": turbulence}


func _attach(node: SaLayer, values: Dictionary) -> void:
    _filter.set_parameters(values)
    SaFilterOps.new(_doc).attach(node, _key, _filter.parameters())
    Bench.composite(_easel)


## Every texel of *texture*, read back once, as an alpha reader.
static func _alphas(texture: SaTexture) -> Callable:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var width := texture.size.x
    var format := texture.format
    return func(at: Vector2i) -> float: return SaFieldSpec.decode_texel(bytes, format, at.y * width + at.x).a


## How far the edge on row *y* stands left of [const EDGE]. The coverage a
## bilinear read of a hard step leaves sums to exactly where the step was read
## from, so the sum over the window is the edge's place to float precision.
static func _shift_on(read: Callable, y: int) -> float:
    var covered := 0.0
    for x in range(FROM, TO):
        covered += float(read.call(Vector2i(x, y)))
    return float(EDGE - FROM) - covered


static func _sine(y: int) -> float:
    return AMPLITUDE * sin(TAU * float(y) / WAVELENGTH)


func _assert_the_sine(read: Callable, said: String) -> void:
    for y: int in ROWS:
        var got := _shift_on(read, y)
        var wanted := _sine(y)
        assert_almost_eq(got, wanted, 0.01, "%s: row %d moved the edge %.4f, the sine says %.4f" % [said, y, got, wanted])


func test_a_layers_edge_moves_by_the_sine() -> void:
    _attach(_layer, _values(AMPLITUDE, 0.0))
    _assert_the_sine(_alphas(_easel.output), "On the layer")


func test_a_groups_edge_moves_by_the_sine() -> void:
    var group := SaLayerOps.new(_doc).group_layers([_layer])
    assert_true(group != null and group.is_group, "The layer is grouped")
    _attach(group, _values(AMPLITUDE, 0.0))
    _assert_the_sine(_alphas(_easel.output), "On the group")


func test_no_amplitude_leaves_the_edge_where_it_was() -> void:
    _attach(_layer, _values(0.0, 60.0))
    var read := _alphas(_easel.output)
    for y: int in ROWS:
        for x: int in [EDGE - 2, EDGE - 1, EDGE, EDGE + 1]:
            var wanted := 1.0 if x < EDGE else 0.0
            var got: float = read.call(Vector2i(x, y))
            assert_eq(got, wanted, "No amplitude keeps %s as it was" % Vector2i(x, y))


func test_turbulence_moves_the_crests_within_the_amplitude() -> void:
    _attach(_layer, _values(AMPLITUDE, 100.0))
    var read := _alphas(_easel.output)
    var apart := 0.0
    for y in range(0, 2 * SaChunk.SIZE, 3):
        var got := _shift_on(read, y)
        assert_true(absf(got) <= AMPLITUDE + 0.01, "Row %d moved %.3f, inside the amplitude" % [y, got])
        apart = maxf(apart, absf(got - _sine(y)))
    assert_true(apart > 1.0, "and the noise pushed the crests off the pure sine, by up to %.3f" % apart)


func test_vertical_ripples_leave_a_vertical_edge_standing() -> void:
    _attach(_layer, _values(AMPLITUDE, 0.0, "vertical"))
    var read := _alphas(_easel.output)
    for y: int in ROWS:
        assert_almost_eq(_shift_on(read, y), 0.0, 0.0001, "A shift along the edge does not move it, row %d" % y)


func test_the_one_shot_writes_what_the_attached_form_shows() -> void:
    _attach(_layer, _values(AMPLITUDE, 30.0))
    var shown := _alphas(_easel.output)
    var rows: Array[float] = []
    for y: int in ROWS:
        rows.append(_shift_on(shown, y))
    SaFilterOps.new(_doc).detach(_layer, _layer.filters[0])
    _filter.set_parameters(_values(AMPLITUDE, 30.0))
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, _filter.title(), false)
    assert_true(SaFilterApply.call_run(_filter, ctx), "The run records a pass")
    assert_true(ctx.point is SaNeighbourhoodPass, "and the pass reads its neighbours")
    assert_eq((ctx.point as SaNeighbourhoodPass).radius, WobbleFilter.reach(AMPLITUDE), "as far as the amplitude")
    assert_true(SaFilterApply.apply(ctx, _filter.title()), "which Apply walks over the layer")
    for index in ROWS.size():
        var y: int = ROWS[index]
        var written := _alphas(_layer.get_field(Vector2i(0, floori(float(y) / SaChunk.SIZE))))
        var got := _shift_on(func(at: Vector2i) -> float: return written.call(Vector2i(at.x, at.y % SaChunk.SIZE)), y)
        assert_almost_eq(got, rows[index], 0.0001, "The one-shot moved row %d as the attached form showed" % y)


func test_the_reach_covers_the_amplitude() -> void:
    assert_eq(WobbleFilter.reach(0.0), 1, "No amplitude still reaches the bilinear texel")
    assert_eq(WobbleFilter.reach(8.0), 9, "Eight reaches eight and one more")
    assert_eq(WobbleFilter.reach(7.5), 9, "A fraction rounds up")


func test_the_parameters_round_trip_and_default_to_ripples() -> void:
    _filter.set_parameters(_values(12.0, 25.0, "vertical"))
    assert_eq(_filter.parameters(), _values(12.0, 25.0, "vertical"), "The record keeps all four")
    _filter.set_parameters({"unknown": 1})
    var defaults := _filter.parameters()
    assert_eq(defaults.get("direction"), "horizontal", "and a record naming none reads horizontal ripples")
    assert_eq(_filter.id(), &"wobble", "Its id comes from its title")
    assert_eq(_filter.family(), &"distort", "It sits under Distort")
