## Add noise, its kinds over a flat grey document, the seed, and the rule
## that stops the noise crawling, that it is drawn from the document pixel and
## not from the pixel of the region a dispatch happened to cover.
extends "res://tests/test_framework.gd"

const AddNoiseFilter = preload("res://modules/sara-base-modules/base/usual/add_noise_filter.gd")

const REQUIRES_GPU := true

const MODULE_ID: StringName = &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules/base"
const GREY := Color(0.5, 0.5, 0.5, 1.0)
## Two chunks side by side, both grey, so a texel of the first and the texel at
## the same chunk-local pixel of the second differ only by where they sit.
const GRIDS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]

var _easel: SaEasel = null
var _layer: SaLayer = null


func before_each() -> void:
    if not ModuleLoader.module_dirs.has(MODULE_ID):
        ModuleLoader.module_dirs[MODULE_ID] = MODULE_DIR
    _easel = SaEasel.create_default(Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE))
    _layer = _easel.document.active_layer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    for grid_pos in GRIDS:
        _layer.get_or_create_chunk(grid_pos).clear(GREY)


func after_each() -> void:
    _layer = null
    _easel.free()
    _easel = null


## Runs the filter one-shot with *values* over the whole layer, as Apply does.
func _apply(values: Dictionary) -> bool:
    var filter := AddNoiseFilter.new()
    filter.set_parameters(values)
    var ctx := SaFilterContext.new(_easel.document, _layer, MODULE_ID, "Add Noise")
    filter.run(ctx)
    assert_true(ctx.point is SaNeighbourhoodPass, "The run records a pass the neighbourhood runner takes")
    return SaFilterApply.apply(ctx, "Add Noise")


## Every texel of the chunk at *grid_pos*.
func _texels(grid_pos: Vector2i) -> Array[Color]:
    var texture := (_layer.chunks[grid_pos] as SaChunk).field(SaFieldSpec.ALBEDO)
    return _read(texture)


func _read(texture: SaTexture) -> Array[Color]:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array[Color] = []
    for i in texture.size.x * texture.size.y:
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, i))
    return out


static func _mean(texels: Array[Color]) -> Color:
    var sum := Color(0.0, 0.0, 0.0, 0.0)
    for c in texels:
        sum += c
    return sum / float(texels.size())


static func _widest(texels: Array[Color]) -> float:
    var most := 0.0
    for c in texels:
        most = maxf(most, maxf(absf(c.r - GREY.r), maxf(absf(c.g - GREY.g), absf(c.b - GREY.b))))
    return most


func _assert_zero_mean(kind: String, monochrome: bool = false) -> void:
    var values := {"kind": kind, "monochrome": monochrome, "amount": 20.0, "seed": 1.0}
    assert_true(_apply(values), "%s applies" % kind)
    var texels := _texels(GRIDS[0])
    var mean := _mean(texels)
    # Over a whole chunk and not over sixteen texels: a uniform draw of a fifth
    # either way has a spread of about 0.115, so the mean of sixteen wanders by
    # a few hundredths however fair the draw is, and of 65536 by under 0.0005.
    for channel: float in [mean.r, mean.g, mean.b]:
        assert_true(absf(channel - GREY.r) < 0.002, "%s is zero mean: %s against 0.5" % [kind, channel])
    assert_true(_widest(texels) > 0.15, "and it moved the texels, by %s at most" % _widest(texels))
    assert_almost_eq(mean.a, 1.0, 1e-6, "and wrote no alpha")


## A record's numbers reach the rows a dialog built, and through them the control
## each row draws, which is what a painter reads the number off. The order is the
## panel's and the editor's: `build`, then `set_parameters`, then the page is
## realized.
func test_a_records_numbers_reach_the_rows_and_their_controls() -> void:
    var filter := AddNoiseFilter.new()
    var dialog := SaDialog.for_filter(filter)
    var host := VBoxContainer.new()
    filter.set_parameters({"kind": "cmos", "amount": 55, "seed": 42})
    dialog.realize(host)

    assert_eq(String(dialog.row(&"kind").read()), "cmos", "The record's kind is on the row, by its word")
    var amount := dialog.row(&"amount")
    assert_eq(float(amount.read()), 55.0, "The record's amount is on the row")
    assert_eq((amount.custom_control as FactorSlider).value, 55.0, "and on the control it built")
    var seed_row := dialog.row(&"seed")
    assert_eq(float(seed_row.read()), 42.0, "The record's seed is on the row")
    assert_eq((seed_row.custom_control as FactorSlider).value, 42.0, "and on the control it built")
    host.free()


func test_white_is_zero_mean() -> void:
    _assert_zero_mean("white")
    var texels := _texels(GRIDS[0])
    var coloured := 0
    for c in texels:
        if absf(c.r - c.g) > 1e-4:
            coloured += 1
    assert_true(coloured * 2 > texels.size(), "and draws each channel apart, %d texels coloured" % coloured)


func test_monochrome_white_is_zero_mean_and_the_same_in_every_channel() -> void:
    _assert_zero_mean("white", true)
    for c in _texels(GRIDS[0]):
        if absf(c.r - c.g) > 1e-6 or absf(c.g - c.b) > 1e-6:
            assert_true(false, "Monochrome White draws once for all three channels, and %s does not" % c)
            return


func test_salt_and_pepper_sets_texels_to_exactly_nought_and_one() -> void:
    assert_true(_apply({"kind": "salt_and_pepper", "amount": 20.0, "seed": 1.0}), "Salt and pepper applies")
    var salt := 0
    var pepper := 0
    var kept := 0
    for c in _texels(GRIDS[0]):
        if c.r == 1.0 and c.g == 1.0 and c.b == 1.0:
            salt += 1
        elif c.r == 0.0 and c.g == 0.0 and c.b == 0.0:
            pepper += 1
        elif c == GREY:
            kept += 1
    var total := SaChunk.SIZE * SaChunk.SIZE
    assert_true(salt > 0 and pepper > 0, "Some texels are salt, %d, and some pepper, %d" % [salt, pepper])
    assert_eq(salt + pepper + kept, total, "and every other texel is left as it was")
    assert_true(absf(float(salt + pepper) / float(total) - 0.2) < 0.02, "and the amount is the share replaced")


func test_cmos_grows_with_the_signal_and_carries_a_column_pattern() -> void:
    _layer.get_or_create_chunk(GRIDS[1]).clear(Color(0.05, 0.05, 0.05, 1.0))
    assert_true(_apply({"kind": "cmos", "amount": 50.0, "seed": 1.0}), "CMOS applies")
    var bright := _texels(GRIDS[0])
    var dark := _texels(GRIDS[1])
    assert_true(_spread(bright) > _spread(dark), "Shot noise is wider over grey than over near black")
    # The fixed pattern is one draw per column, so the columns' means scatter
    # more than a column's own texels would on their own.
    var columns: Array[float] = []
    for x in SaChunk.SIZE:
        var sum := 0.0
        for y in SaChunk.SIZE:
            sum += bright[y * SaChunk.SIZE + x].r
        columns.append(sum / float(SaChunk.SIZE))
    var lowest: float = columns.min()
    var highest: float = columns.max()
    assert_true(highest - lowest > 0.02, "and the columns differ, by %s" % (highest - lowest))


static func _spread(texels: Array[Color]) -> float:
    var mean := _mean(texels).r
    var sum := 0.0
    for c in texels:
        sum += (c.r - mean) * (c.r - mean)
    return sqrt(sum / float(texels.size()))


func test_one_seed_repeats_and_another_differs() -> void:
    _apply({"kind": "white", "amount": 20.0, "seed": 7.0})
    var first := _texels(GRIDS[0])
    _easel.document.undo()
    _apply({"kind": "white", "amount": 20.0, "seed": 7.0})
    var again := _texels(GRIDS[0])
    _easel.document.undo()
    _apply({"kind": "white", "amount": 20.0, "seed": 8.0})
    var other := _texels(GRIDS[0])
    assert_eq(first, again, "The same seed draws the same texels")
    assert_true(first != other, "and another seed draws others")


func test_an_unpainted_texel_stays_empty() -> void:
    _layer.get_or_create_chunk(GRIDS[1]).clear(Color(0.0, 0.0, 0.0, 0.0))
    for kind: String in AddNoiseFilter.KINDS:
        _apply({"kind": kind, "amount": 100.0, "seed": 3.0})
        var empty := _texels(GRIDS[1])
        assert_eq(_widest_from(empty, Color(0.0, 0.0, 0.0, 0.0)), 0.0, "%s leaves an empty texel empty" % kind)
        _easel.document.undo()


static func _widest_from(texels: Array[Color], from: Color) -> float:
    var most := 0.0
    for c in texels:
        most = maxf(most, maxf(maxf(absf(c.r - from.r), absf(c.g - from.g)), maxf(absf(c.b - from.b), absf(c.a - from.a))))
    return most


## The crawl the seed rule prevents: an attached filter is evaluated over one
## dirty rectangle and then another, and a texel must read the same whichever
## rectangle it was drawn in. And the second chunk is not the first again, which
## is what noise drawn from the chunk-local pixel would be.
func test_a_texel_reads_the_same_from_two_regions() -> void:
    var filter := AddNoiseFilter.new()
    filter.set_parameters({"kind": "white", "amount": 20.0, "seed": 1.0})
    var ctx := SaFilterContext.new(_easel.document, _layer, MODULE_ID, "Add Noise")
    filter.run(ctx)
    var recorded := ctx.point as SaNeighbourhoodPass
    var compute := ctx.kernel(recorded.shader)
    var runner := SaNeighbourhoodPass.Runner.new()
    var mask := _easel.document.selection.texture_for(GRIDS[0])
    var whole := SaTexture.new(Vector2i(SaChunk.SIZE, SaChunk.SIZE), _layer.get_field(GRIDS[0]).format)
    var part := SaTexture.new(whole.size, whole.format)
    var beside := SaTexture.new(whole.size, whole.format)
    runner.run(recorded, compute, whole, _layer.get_field(GRIDS[0]), _layer.get_field, GRIDS[0], Rect2i(0, 0, 256, 256), mask)
    runner.run(recorded, compute, part, _layer.get_field(GRIDS[0]), _layer.get_field, GRIDS[0], Rect2i(96, 96, 40, 24), mask)
    runner.run(recorded, compute, beside, _layer.get_field(GRIDS[1]), _layer.get_field, GRIDS[1], Rect2i(0, 0, 256, 256), mask)
    var at := 110 * SaChunk.SIZE + 120
    var from_whole := _read(whole)[at]
    var from_part := _read(part)[at]
    assert_eq(from_part, from_whole, "The texel drawn over a small region is the one drawn over the chunk")
    assert_true(from_whole != GREY, "and it is noise")
    assert_true(_read(beside)[at] != from_whole, "while the same local pixel of the next chunk draws another")
