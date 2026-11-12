## The sharpens. A layer of two opaque greys side by side, dark on the left
## and light on the right, so the seam between its two chunks is a step edge,
## and the sharpen attached to it with a known parameter set. The chain's
## answer is read along one row far from the canvas's top and bottom.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const RoundTrip = preload("res://modules/sara-base-modules/base/tests/attached_round_trip.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const DARK := Color(0.3, 0.3, 0.3, 1.0)
const LIGHT := Color(0.7, 0.7, 0.7, 1.0)
## A half-covered stroke colour, beside a position no chunk holds.
const STROKE := Color(0.8, 0.3, 0.2, 0.5)
const ROW := 128
## The last dark column and the first light one.
const EDGE_DARK := SaChunk.SIZE - 1
const EDGE_LIGHT := SaChunk.SIZE
## Far from the seam and from the canvas's left edge.
const DEEP := 128

var _easel: SaEasel = null
var _layer: SaLayer = null
var _filter: SaSharpenFilter = null
var _record: SaAttachedFilter = null


func after_each() -> void:
    _release()


func _release() -> void:
    _record = null
    _layer = null
    _filter = null
    if _easel != null:
        _easel.free()
    _easel = null


## Two chunks across, *left* and *right*, the right one left unallocated when
## it is null, with the sharpen attached under *values*.
func _attach(values: Dictionary, left: Color = DARK, right: Variant = LIGHT) -> void:
    _release()
    _easel = Bench.easel(Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE))
    _filter = SaSharpenFilter.new()
    _easel.compositor.filter_chain.registry.register(_filter, OWNER)
    _layer = _easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _layer.get_or_create_chunk(Vector2i(0, 0)).clear(left)
    if right != null:
        _layer.get_or_create_chunk(Vector2i(1, 0)).clear(right as Color)
    _filter.set_parameters(values)
    var key := SaFilterRegistry.key_for(OWNER, _filter)
    _record = SaFilterOps.new(_easel.document).attach(_layer, key, _filter.parameters())
    Bench.composite(_easel)


## The chain's answer at *x* along [const ROW].
func _at(x: int) -> Color:
    var grid_pos := Vector2i(floori(float(x) / SaChunk.SIZE), 0)
    var chain := _easel.compositor.filter_chain
    var answer := chain.filtered(_layer, _layer.get_field(grid_pos), grid_pos, SaDocument.WHOLE_CHUNK)
    return Bench.texel(answer, Vector2i(x - grid_pos.x * SaChunk.SIZE, ROW))


func _values(kind: String, amount: float, threshold: float = 0.0, radius: float = 3.0) -> Dictionary:
    return {"kind": kind, "amount": amount, "threshold": threshold, "radius": radius}


func test_the_filter_answers_the_numbers_it_was_handed() -> void:
    var filter := SaSharpenFilter.new()
    var wanted := _values(SaSharpenFilter.SHARPEN, 150.0, 20.0, 7.0)
    filter.set_parameters(wanted)
    assert_eq(filter.parameters(), wanted, "Every parameter comes back as it went in")
    filter.set_parameters({"kind": "blunt"})
    assert_eq(filter.parameters()["kind"], SaSharpenFilter.DEFAULT_KIND, "and a kind nobody knows reads as the default")


func test_each_kind_records_a_neighbourhood_pass_of_its_own_reach() -> void:
    _attach(_values(SaSharpenFilter.SHARPEN, 100.0, 0.0, 9.0))
    var pass_made := _record.cached_pass as SaNeighbourhoodPass
    assert_true(pass_made != null, "Sharpen records a neighbourhood pass")
    if pass_made != null:
        assert_eq(pass_made.kernel, "sharpen", "on the five-tap kernel")
        assert_eq(pass_made.radius, 1, "reading one texel round, whatever the dimmed radius says")
    _attach(_values(SaSharpenFilter.UNSHARP_MASK, 100.0, 0.0, 9.0))
    pass_made = _record.cached_pass as SaNeighbourhoodPass
    assert_true(pass_made != null, "The unsharp mask records one too")
    if pass_made != null:
        var kernels: Array = pass_made.steps.map(func(step: SaNeighbourhoodPass.Step) -> String: return step.kernel)
        assert_eq(kernels, ["unsharp_across", "unsharp_down", "unsharp_mask"], "as a separable blur and a difference")
        assert_eq(pass_made.radius, 9, "reading as far as its radius")


func test_a_flat_field_is_unchanged_by_both_kinds_at_any_amount() -> void:
    for kind: String in [SaSharpenFilter.SHARPEN, SaSharpenFilter.UNSHARP_MASK]:
        for amount: float in [50.0, 300.0]:
            _attach(_values(kind, amount))
            var deep := _at(DEEP)
            assert_almost_eq(deep.r, DARK.r, 0.001, "%s at %d leaves flat grey alone, %s" % [kind, amount, deep])
            assert_almost_eq(deep.a, 1.0, 0.001, "and opaque, %s" % deep)


func test_a_step_edge_overshoots_on_both_sides_and_more_with_the_amount() -> void:
    for kind: String in [SaSharpenFilter.SHARPEN, SaSharpenFilter.UNSHARP_MASK]:
        _attach(_values(kind, 100.0))
        var low_dark := _at(EDGE_DARK).r
        var low_light := _at(EDGE_LIGHT).r
        _attach(_values(kind, 300.0))
        var high_dark := _at(EDGE_DARK).r
        var high_light := _at(EDGE_LIGHT).r
        assert_true(low_dark < DARK.r - 0.01, "%s darkens the dark side of the edge, %f" % [kind, low_dark])
        assert_true(low_light > LIGHT.r + 0.01, "%s lightens the light side, %f" % [kind, low_light])
        assert_true(high_dark < low_dark - 0.01, "%s undershoots further at 300, %f against %f" % [kind, high_dark, low_dark])
        assert_true(high_light > low_light + 0.01, "%s overshoots further at 300, %f against %f" % [kind, high_light, low_light])
    # The five-tap arithmetic, exactly: one light neighbour of four is 0.4 above.
    _attach(_values(SaSharpenFilter.SHARPEN, 100.0))
    assert_almost_eq(_at(EDGE_DARK).r, DARK.r - 0.1, 0.001, "Sharpen at 100 is s + (4s - around) / 4")


func test_the_separable_unsharp_mask_draws_the_bells_own_sum() -> void:
    # The texels across the edge, against the sum the unsharp mask stands for,
    # taken here on the CPU. Every row is alike, so a texel's blur is the dark
    # grey and the step times the share of one row's weights that lands on the
    # light side. The bell goes to nought one texel past its reach, and the sum
    # follows the bell.
    var columns := [240, 250, 253, 254, 255, 256, 257, 258, 261, 270]
    for setting: Vector2 in [Vector2(3, 100), Vector2(12, 250)]:
        var radius := int(setting.x)
        _attach(_values(SaSharpenFilter.UNSHARP_MASK, setting.y, 0.0, setting.x))
        for column: int in columns:
            var source := DARK.r if column < EDGE_LIGHT else LIGHT.r
            var blurred := DARK.r + (LIGHT.r - DARK.r) * _lit_share(radius, column)
            var wanted := source + setting.y / 100.0 * (source - blurred)
            assert_almost_eq(_at(column).r, wanted, 0.0001, "Radius %d at %d%%, column %d" % [radius, setting.y, column])


## The share of one row's weights a texel at *column* takes from the light
## side, under the bell of `gaussian.gmacs` at *radius*: sigma a third of it,
## and the bell lowered by its own height one texel past it.
static func _lit_share(radius: int, column: int) -> float:
    var sigma := maxf(radius / 3.0, 0.001)
    var spread := 2.0 * sigma * sigma
    var past := 3.0 * sigma + 1.0
    var lowered := exp(-past * past / spread)
    var line := 0.0
    var lit := 0.0
    for offset in range(-radius, radius + 1):
        var weight := exp(-float(offset * offset) / spread) - lowered
        line += weight
        if column + offset >= EDGE_LIGHT:
            lit += weight
    return lit / line


func test_a_threshold_above_the_edges_contrast_leaves_the_edge_alone() -> void:
    for kind: String in [SaSharpenFilter.SHARPEN, SaSharpenFilter.UNSHARP_MASK]:
        _attach(_values(kind, 300.0, 100.0))
        assert_almost_eq(_at(EDGE_DARK).r, DARK.r, 0.001, "%s under a full threshold keeps the dark side" % kind)
        assert_almost_eq(_at(EDGE_LIGHT).r, LIGHT.r, 0.001, "%s under a full threshold keeps the light side" % kind)


func test_a_texel_on_a_strokes_edge_keeps_its_colour_as_its_alpha_moves() -> void:
    for kind: String in [SaSharpenFilter.SHARPEN, SaSharpenFilter.UNSHARP_MASK]:
        _attach(_values(kind, 200.0), STROKE, null)
        var edge := _at(EDGE_DARK)
        assert_true(edge.a > STROKE.a + 0.01, "%s lifts the stroke's alpha at its edge, %s" % [kind, edge])
        assert_almost_eq(edge.r, STROKE.r, 0.002, "%s keeps its red, %s" % [kind, edge])
        assert_almost_eq(edge.g, STROKE.g, 0.002, "%s keeps its green, %s" % [kind, edge])
        assert_almost_eq(edge.b, STROKE.b, 0.002, "%s keeps its blue, %s" % [kind, edge])


func test_the_radius_row_is_dimmed_for_sharpen() -> void:
    var filter := SaSharpenFilter.new()
    var host := VBoxContainer.new()
    var dialog := SaDialog.for_filter(filter)
    dialog.realize(host)
    dialog.apply_rules()
    var radius := dialog.row(&"radius")
    assert_true(SaOptionSpec.row_reads_enabled(radius.line), "The unsharp mask, the default, reads its radius")
    dialog.row(&"kind").drive(SaSharpenFilter.SHARPEN)
    assert_false(SaOptionSpec.row_reads_enabled(radius.line), "and Sharpen dims it")
    host.free()


func test_attached_it_survives_a_save_and_a_load() -> void:
    var trip := RoundTrip.new(SaSharpenFilter.new(), OWNER)
    var kept := trip.attach(_values(SaSharpenFilter.UNSHARP_MASK, 250.0, 5.0, 6.0))
    var before := trip.texels()
    assert_eq(trip.round_trip(), kept, "The loaded record keeps the numbers it was attached with")
    assert_true(RoundTrip.distance(before, trip.texels()) < 1e-5, "and draws the same texels")
    trip.release()
