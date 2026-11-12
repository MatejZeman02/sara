## Dither is a finishing filter, so an attached chain runs it
## after every other record of its node whatever the array order, its levels
## are even steps of the encoded value, and its pattern is a function of the
## document pixel, so interleaved gradient noise does not start again at a
## chunk border.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The other record is Brightness/Contrast, because its output is off the
## dither's grid wherever it lands: a record that ran after the dither would
## leave the composite between two levels, which is what the order cases look
## for. An invert would not do, since the levels are symmetric about one half
## and an invert commutes with them.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
## Off the grid of every level count used here once brightened.
const GREY := 0.43
## How far from a level a texel may sit and still be on it.
const ON_LEVEL := 1e-4
## The texels read of a chunk, one in STRIDE across and down.
const STRIDE := 5

var _easel: SaEasel = null
var _document: SaDocument = null
var _dither_key: StringName = &""
var _brighten_key: StringName = &""


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE * 2, SaChunk.SIZE))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var registry := SaFilterRegistry.new()
    var dither := SaDitherFilter.new()
    var brighten := SaBrightnessContrastFilter.new()
    registry.register(dither, OWNER)
    registry.register(brighten, OWNER)
    _dither_key = SaFilterRegistry.key_for(OWNER, dither)
    _brighten_key = SaFilterRegistry.key_for(OWNER, brighten)
    _easel.compositor.filter_chain.registry = registry
    _document = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _document = null


## "Layer 1" holding both chunks of the canvas at *value*, opaque.
func _paint(value: float) -> SaLayer:
    var layer := _document.get_node("Layer 1") as SaLayer
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        layer.get_or_create_chunk(grid_pos).clear(Color(value, value, value, 1.0))
    return layer


func _dither_values(levels: int, pattern: String, strength: float) -> Dictionary:
    return {"levels": levels, "pattern": pattern, "strength": strength}


## The red channel of the composite at every STRIDE-th texel of the canvas,
## with its document pixel, as `[Vector2i, float]` pairs.
func _composite_samples() -> Array:
    Bench.composite(_easel)
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array = []
    for y in range(0, texture.size.y, STRIDE):
        for x in range(0, texture.size.x, STRIDE):
            var texel := SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)
            out.append([Vector2i(x, y), texel.r])
    return out


## How many of *samples* sit off every level of a grid of *levels*.
static func _off_grid(samples: Array, levels: int) -> int:
    var steps := float(levels - 1)
    var off := 0
    for sample: Array in samples:
        var scaled := float(sample[1]) * steps
        if absf(scaled - roundf(scaled)) * (1.0 / steps) > ON_LEVEL:
            off += 1
    return off


## Jimenez's interleaved gradient noise at document pixel *at*, as the kernel
## computes it, in doubles here and floats there.
static func _gradient_noise(at: Vector2i) -> float:
    var inner := 0.06711056 * at.x + 0.00583715 * at.y
    var outer := 52.9829189 * (inner - floorf(inner))
    return outer - floorf(outer)


## The brightener and the dither on *node*, in the array order *dither_first*
## says, and the composite read against the dither's grid.
func _order_case(node: SaLayer, dither_first: bool, name: String) -> void:
    var ops := SaFilterOps.new(_document)
    var brighten := {"brightness": 37.0, "contrast": 0.0}
    if dither_first:
        ops.attach(node, _dither_key, _dither_values(4, "bayer", 100.0))
        ops.attach(node, _brighten_key, brighten)
    else:
        ops.attach(node, _brighten_key, brighten)
        ops.attach(node, _dither_key, _dither_values(4, "bayer", 100.0))
    var samples := _composite_samples()
    assert_eq(_off_grid(samples, 4), 0, "Every texel is on one of four levels, %s" % name)
    var seen := {}
    for sample: Array in samples:
        seen[snappedf(float(sample[1]), 0.001)] = true
    assert_true(seen.size() >= 2, "and the pattern mixes two of them, %s: %s" % [name, seen.keys()])


## The brightener alone leaves the grey between levels, so an order case that
## finds every texel on a level found the dither last and not a lucky grey.
func test_the_brightened_grey_is_off_the_grid() -> void:
    var layer := _paint(GREY)
    SaFilterOps.new(_document).attach(layer, _brighten_key, {"brightness": 37.0, "contrast": 0.0})
    var samples := _composite_samples()
    assert_eq(_off_grid(samples, 4), samples.size(), "Brightened, no texel sits on a level")


func test_the_dither_answers_it_finishes() -> void:
    assert_true(SaDitherFilter.new().finishes(), "Dither is a finishing filter")
    assert_false(SaBrightnessContrastFilter.new().finishes(), "and Brightness/Contrast is not")


func test_a_layers_dither_runs_last_when_it_is_first() -> void:
    _order_case(_paint(GREY), true, "layer, dither first")


func test_a_layers_dither_runs_last_when_it_is_last() -> void:
    _order_case(_paint(GREY), false, "layer, dither last")


func test_a_groups_dither_runs_last_when_it_is_first() -> void:
    var group := SaLayerOps.new(_document).group_layers([_paint(GREY)])
    _order_case(group, true, "group, dither first")


func test_a_groups_dither_runs_last_when_it_is_last() -> void:
    var group := SaLayerOps.new(_document).group_layers([_paint(GREY)])
    _order_case(group, false, "group, dither last")


## The array keeps the order the painter gave it: the chain reads it, and the
## docker still lists the dither first.
func test_the_array_keeps_the_painters_order() -> void:
    var layer := _paint(GREY)
    var ops := SaFilterOps.new(_document)
    var dither := ops.attach(layer, _dither_key, _dither_values(4, "bayer", 100.0))
    ops.attach(layer, _brighten_key, {"brightness": 37.0, "contrast": 0.0})
    Bench.composite(_easel)
    assert_eq(layer.filters[0], dither, "The dither stays first in the array")


## A ramp across both chunks, dithered to five levels: every texel is a quarter
## step of the encoded value, and a value above one lands on a level above one.
func test_the_levels_are_even_encoded_steps() -> void:
    var layer := _paint(0.0)
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        var image := Image.create(SaChunk.SIZE, SaChunk.SIZE, false, Image.FORMAT_RGBAF)
        for x in SaChunk.SIZE:
            var v := float(grid_pos.x * SaChunk.SIZE + x) / float(SaChunk.SIZE * 2 - 1) * 1.4
            for y in SaChunk.SIZE:
                image.set_pixel(x, y, Color(v, v, v, 1.0))
        var albedo := layer.get_or_create_chunk(grid_pos).albedo()
        GlobalShaderCompiler.get_rd().texture_update(albedo.rid, 0, image.get_data())
    SaFilterOps.new(_document).attach(layer, _dither_key, _dither_values(5, "blue", 100.0))
    var samples := _composite_samples()
    assert_eq(_off_grid(samples, 5), 0, "Every texel sits on a quarter step")
    var seen := {}
    for sample: Array in samples:
        seen[snappedf(float(sample[1]), 0.25)] = true
    for level: float in [0.0, 0.25, 0.5, 0.75, 1.0, 1.25]:
        assert_true(seen.has(level), "The ramp reaches the level %.2f" % level)
    assert_false(seen.has(-0.25), "and none below black")


## Flat grey at one half over two chunks, dithered to two levels by
## interleaved gradient noise at full strength: each texel is white exactly
## where the noise of its document pixel reaches one half. The second chunk's
## texels follow its document pixels and not its local ones, so the pattern
## does not repeat across the border.
func test_gradient_noise_does_not_repeat_across_a_chunk_border() -> void:
    var layer := _paint(0.5)
    SaFilterOps.new(_document).attach(layer, _dither_key, _dither_values(2, "gradient", 100.0))
    var samples := _composite_samples()
    var by_place := {}
    for sample: Array in samples:
        by_place[sample[0]] = float(sample[1])
    var wrong := 0
    var repeated := 0
    var across := 0
    for sample: Array in samples:
        var at: Vector2i = sample[0]
        var noise := _gradient_noise(at)
        if absf(noise - 0.5) < 0.001:
            continue
        var white := float(sample[1]) > 0.5
        if white != (noise >= 0.5):
            wrong += 1
        if at.x >= SaChunk.SIZE:
            across += 1
            var twin: Variant = by_place.get(at - Vector2i(SaChunk.SIZE, 0))
            if twin != null and (float(twin) > 0.5) == white:
                repeated += 1
    assert_eq(wrong, 0, "Every texel follows the noise of its document pixel")
    assert_true(across > 0, "The second chunk was read")
    assert_true(repeated < across * 0.75, "and does not repeat the first chunk: %d of %d alike" % [repeated, across])


## The tile ships, is 64 square, and holds every grey sixteen times, which is
## what the void and cluster ranks scaled to a byte are.
func test_the_blue_noise_tile_ships_whole() -> void:
    var values := SaDitherFilter.thresholds()
    assert_eq(values.size(), SaDitherFilter.TILE * SaDitherFilter.TILE, "The tile is 64 by 64")
    var counts := {}
    for value in values:
        counts[value] = int(counts.get(value, 0)) + 1
    assert_eq(counts.size(), 256, "with every grey")
    assert_eq(counts.values().max(), 16, "sixteen times each")
