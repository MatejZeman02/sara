## Film grain under Add Noise: the grain
## moves the Oklab lightness of a flat mid grey and keeps its chroma, continues
## one grain across a chunk edge, lays clumps whose neighbours are more alike at
## a larger size, agrees attached with baked, keeps a colour's hue, and leaves a
## value above one above one and an unpainted texel empty.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules/base"
## A mid grey in light, whose Oklab lightness is a little past a half, where
## the grain weighs most.
const GREY := Color(0.18, 0.18, 0.18, 1.0)
## Two chunks side by side, so one edge between them runs down the document.
const GRIDS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
const SETTINGS := {"kind": "film_grain", "monochrome": true, "amount": 60.0, "size": 4.0, "seed": 5.0}

var _easel: SaEasel = null
var _document: SaDocument = null
var _layer: SaLayer = null
var _filter: SaAddNoiseFilter = null
var _key: StringName = &""


func before_each() -> void:
    if not ModuleLoader.module_dirs.has(OWNER):
        ModuleLoader.module_dirs[OWNER] = MODULE_DIR
    _make_easel(SaColorSpace.linear_srgb())


func after_each() -> void:
    _release()


func _release() -> void:
    _layer = null
    _document = null
    _filter = null
    if _easel != null:
        _easel.free()
    _easel = null


## A document two chunks wide stored in *space*, its "Layer 1" holding the two
## chunks and nothing else, and a registry that answers Grain's key so the
## compositor can run it attached.
func _make_easel(space: SaColorSpace) -> void:
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE * GRIDS.size(), SaChunk.SIZE), null, space)
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var registry := SaFilterRegistry.new()
    _filter = SaAddNoiseFilter.new()
    registry.register(_filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, _filter)
    _easel.compositor.filter_chain.registry = registry
    _document = _easel.document
    _document.color_space = space
    _layer = _document.get_node("Layer 1") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _fill(GREY)


## Both chunks cleared to *colour*.
func _fill(colour: Color) -> void:
    for grid_pos in GRIDS:
        _layer.get_or_create_chunk(grid_pos).clear(colour)


## Film grain under Monochrome at *amount*, *size* and the seed *draw*.
static func _grain(amount: float, size: float, draw: float) -> Dictionary:
    return {"kind": "film_grain", "monochrome": true, "amount": amount, "size": size, "seed": draw}


## Runs Grain one-shot with *values* over the whole layer, as Apply does.
func _apply(values: Dictionary) -> bool:
    _filter.set_parameters(values)
    var ctx := SaFilterContext.new(_document, _layer, OWNER, _filter.title())
    if not SaFilterApply.call_run(_filter, ctx):
        return false
    assert_true(ctx.point is SaNeighbourhoodPass, "The run records a pass the neighbourhood runner takes")
    return SaFilterApply.apply(ctx, _filter.title())


## Every texel of the chunk at *grid_pos*, row by row.
func _texels(grid_pos: Vector2i) -> Array[Color]:
    var chunk := _layer.chunks[grid_pos] as SaChunk
    var texture := chunk.field(SaFieldSpec.ALBEDO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array[Color] = []
    for i in texture.size.x * texture.size.y:
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, i))
    return out


## The side of a chunk in texels, asked of the chunk (hard rule 3).
func _side() -> int:
    return (_layer.chunks[GRIDS[0]] as SaChunk).pixel_size()


static func _lab(c: Color) -> Vector3:
    return SaOklab.from_linear_srgb(Vector3(c.r, c.g, c.b))


## The Oklab lightness of every texel of *texels*, which a linear sRGB
## document stores in light.
static func _lightness(texels: Array[Color]) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    for c in texels:
        out.append(_lab(c).x)
    return out


static func _spread(values: PackedFloat32Array) -> float:
    var mean := 0.0
    for v in values:
        mean += v
    mean /= float(values.size())
    var sum := 0.0
    for v in values:
        sum += (v - mean) * (v - mean)
    return sqrt(sum / float(values.size()))


## The mean distance between each texel's lightness and its right and lower
## neighbours', over a chunk of *side* texels.
static func _neighbour_distance(lightness: PackedFloat32Array, side: int) -> float:
    var sum := 0.0
    var count := 0
    for y in side - 1:
        for x in side - 1:
            var here := lightness[y * side + x]
            sum += absf(here - lightness[y * side + x + 1]) + absf(here - lightness[(y + 1) * side + x])
            count += 2
    return sum / float(count)


func test_it_is_a_type_of_add_noise() -> void:
    assert_eq(_filter.title(), "Add Noise", "Film grain is a type of Add Noise")
    assert_true(SaAddNoiseFilter.KINDS.has("film_grain"), "which lists it")
    assert_eq(_filter.family(), &"noise", "and is listed under Noise")
    assert_false(_filter.finishes(), "and it runs where it stands in a chain")


func test_a_mid_grey_varies_in_lightness_and_keeps_its_chroma() -> void:
    assert_true(_apply(SETTINGS), "Grain applies")
    var texels := _texels(GRIDS[0])
    var lightness := _lightness(texels)
    var spread := _spread(lightness)
    assert_true(spread > 0.02, "The lightness varies, by a spread of %f" % spread)
    var widest := 0.0
    for c in texels:
        var lab := _lab(c)
        widest = maxf(widest, Vector2(lab.y, lab.z).length())
        if c.a != 1.0:
            assert_true(false, "and no alpha is written, %s" % c)
            return
    var grey := _lab(GREY)
    var before := Vector2(grey.y, grey.z).length()
    assert_true(absf(widest - before) < 1e-3, "and the chroma stays within a thousandth of the grey's, at %f" % widest)


func test_the_grain_continues_across_a_chunk_edge() -> void:
    assert_true(_apply(_grain(60.0, 6.0, 5.0)), "Grain applies")
    var side := _side()
    var left := _lightness(_texels(GRIDS[0]))
    var right := _lightness(_texels(GRIDS[1]))
    var across := 0.0
    var within := 0.0
    var repeated := 0
    for y in side:
        across += absf(left[y * side + side - 1] - right[y * side])
        within += absf(left[y * side + side - 2] - left[y * side + side - 1])
        within += absf(right[y * side] - right[y * side + 1])
        if right[y * side] == left[y * side]:
            repeated += 1
    across /= float(side)
    within /= float(2 * side)
    assert_true(within > 0.0, "The grain moves from one texel to the next")
    assert_true(across < 1.5 * within, "and steps across the chunk edge as it steps beside it, %f against %f" % [across, within])
    assert_true(repeated * 4 < side, "and the second chunk is not the first's grain again, %d rows alike" % repeated)


func test_neighbours_are_more_alike_at_size_six_than_at_size_one() -> void:
    var side := _side()
    assert_true(_apply(_grain(60.0, 1.0, 9.0)), "Grain at Size 1 applies")
    var fine := _lightness(_texels(GRIDS[0]))
    _document.undo()
    assert_true(_apply(_grain(60.0, 6.0, 9.0)), "Grain at Size 6 applies")
    var coarse := _lightness(_texels(GRIDS[0]))
    var fine_step := _neighbour_distance(fine, side)
    var coarse_step := _neighbour_distance(coarse, side)
    var steps := [coarse_step, fine_step]
    assert_true(coarse_step < 0.5 * fine_step, "Neighbours are more alike at Size 6, %f against %f at Size 1" % steps)
    var fine_spread := _spread(fine)
    var coarse_spread := _spread(coarse)
    assert_true(
        absf(coarse_spread - fine_spread) < 0.3 * fine_spread,
        "and the grain is as strong at either size, a spread of %f against %f" % [coarse_spread, fine_spread]
    )


## Size is in document pixels: a layer at twice the document's resolution
## reads at twice a place the grain the layer at the document's resolution
## reads at that place.
func test_the_size_is_in_document_pixels_on_a_double_resolution_layer() -> void:
    assert_true(_apply(SETTINGS), "Grain applies at the document's resolution")
    var single := _lightness(_texels(GRIDS[0]))
    var single_side := _side()
    _layer = SaLayerOps.new(_document).add(&"", null, 2.0)
    _layer.get_or_create_chunk(GRIDS[0]).clear(GREY)
    assert_true(_apply(SETTINGS), "and on a layer at twice the resolution")
    var double := _lightness(_texels(GRIDS[0]))
    var side := _side()
    assert_eq(side, 2 * single_side, "whose chunk holds twice the texels across the same document pixels")
    var worst := 0.0
    for y in range(0, side, 2):
        for x in range(0, side, 2):
            worst = maxf(worst, absf(double[y * side + x] - single[(y >> 1) * single_side + (x >> 1)]))
    assert_true(worst < 1e-5, "The grain at twice the resolution is the same grain, off by %f at most" % worst)
    var step := _neighbour_distance(double, side)
    var steps := [step, _neighbour_distance(single, single_side)]
    assert_true(step < 0.75 * steps[1], "and its clumps span twice the texels, a step of %f against %f" % steps)


func test_one_seed_repeats_and_another_differs() -> void:
    _apply(_grain(60.0, 3.0, 7.0))
    var first := _texels(GRIDS[0])
    _document.undo()
    _apply(_grain(60.0, 3.0, 7.0))
    var again := _texels(GRIDS[0])
    _document.undo()
    _apply(_grain(60.0, 3.0, 8.0))
    var other := _texels(GRIDS[0])
    assert_true(first == again, "The same seed lays the same grain")
    assert_true(first != other, "and another seed lays another")


## Attached over a layer painted in two colours either side of the chunk edge,
## and then baked into the same layer in a fresh easel: the composite reads
## the same texels from both.
func test_the_grain_attached_is_the_grain_baked() -> void:
    _paint_halves()
    var plain := _composite()
    SaFilterOps.new(_document).attach(_layer, _key, _filter_values())
    var attached := _composite()
    _release()
    _make_easel(SaColorSpace.linear_srgb())
    _paint_halves()
    assert_true(_apply(SETTINGS), "Apply bakes the grain into the layer")
    var baked := _composite()
    var worst := 0.0
    var moved := 0
    for i in attached.size():
        var a: Color = attached[i]
        var b: Color = baked[i]
        worst = maxf(worst, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
        if absf(a.r - (plain[i] as Color).r) > 1e-3:
            moved += 1
    assert_true(worst < 1e-4, "The attached composite is the baked layer's, off by %f" % worst)
    var counts := [moved, attached.size()]
    assert_true(moved * 2 > attached.size(), "and the grain is there to agree on, %d texels of %d moved" % counts)


## A colour keeps its Oklab hue and chroma under the grain, so the grain does
## not tint a painting.
func test_a_colour_keeps_its_hue() -> void:
    var colour := Color(0.35, 0.12, 0.05, 1.0)
    _fill(colour)
    assert_true(_apply(SETTINGS), "Grain applies over the colour")
    var lab := _lab(colour)
    var hue := atan2(lab.z, lab.y)
    var chroma := Vector2(lab.y, lab.z).length()
    var worst_hue := 0.0
    var worst_chroma := 0.0
    var lightness := PackedFloat32Array()
    for c in _texels(GRIDS[0]):
        var moved := _lab(c)
        worst_hue = maxf(worst_hue, absf(atan2(moved.z, moved.y) - hue))
        worst_chroma = maxf(worst_chroma, absf(Vector2(moved.y, moved.z).length() - chroma))
        lightness.append(moved.x)
    assert_true(_spread(lightness) > 0.02, "The colour's lightness varies")
    assert_true(worst_hue < 2e-3, "and its hue stays, off by %f radians at most" % worst_hue)
    assert_true(worst_chroma < 1e-3, "and its chroma, off by %f at most" % worst_chroma)


## On an Oklab document the grain moves the stored L and leaves the stored a
## and b exactly as they were.
func test_an_oklab_document_keeps_its_a_and_b() -> void:
    _release()
    _make_easel(SaColorSpace.oklab())
    var stored := Color(0.6, 0.05, -0.03, 1.0)
    _fill(stored)
    assert_true(_apply(SETTINGS), "Grain applies over an Oklab document")
    var lightness := PackedFloat32Array()
    var worst := 0.0
    for c in _texels(GRIDS[0]):
        lightness.append(c.r)
        worst = maxf(worst, maxf(absf(c.g - stored.g), absf(c.b - stored.b)))
    assert_true(_spread(lightness) > 0.02, "The stored lightness varies")
    assert_true(worst < 1e-4, "and a and b stay as they were, off by %f at most" % worst)


func test_a_value_above_one_stays_above_one() -> void:
    _fill(Color(4.0, 4.0, 4.0, 1.0))
    assert_true(_apply(_grain(100.0, 2.0, 3.0)), "Grain applies at its full amount")
    var lowest := INF
    for c in _texels(GRIDS[0]):
        lowest = minf(lowest, minf(c.r, minf(c.g, c.b)))
    assert_true(lowest > 1.0, "A value above one stays above one, the lowest channel at %f" % lowest)


func test_an_unpainted_texel_stays_empty() -> void:
    _layer.get_or_create_chunk(GRIDS[1]).clear(Color(0.0, 0.0, 0.0, 0.0))
    assert_true(_apply(_grain(100.0, 2.0, 3.0)), "Grain applies")
    for c in _texels(GRIDS[1]):
        if c != Color(0.0, 0.0, 0.0, 0.0):
            assert_true(false, "An unpainted texel stays empty, and one reads %s" % c)
            return
    assert_true(true, "An unpainted texel stays empty")


## The left chunk the grey and the right a warm colour, so the layer is not one
## flat colour and the edge between them is the chunk edge.
func _paint_halves() -> void:
    _layer.get_or_create_chunk(GRIDS[0]).clear(GREY)
    _layer.get_or_create_chunk(GRIDS[1]).clear(Color(0.5, 0.25, 0.1, 1.0))


## What the Filter menu attaches, the filter's own parameters after
## [const SETTINGS] went in.
func _filter_values() -> Dictionary:
    _filter.set_parameters(SETTINGS)
    return _filter.parameters()


## The composite, every texel of the document, row by row.
func _composite() -> Array[Color]:
    Bench.composite(_easel)
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array[Color] = []
    for i in texture.size.x * texture.size.y:
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, i))
    return out
