## Two finishing effects on one node run in the order they were
## placed. The maintainers' ruling of 2026-10-07, "several finishing effects per
## node, run in the order placed, which is what the chain does", which no suite
## held until this one.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Two Dithers on one layer with Brightness/Contrast between them in the array,
## one Dither of two levels on interleaved gradient noise and one of eight on
## Bayer. The chain runs the brightener first, because a finishing record runs
## after every plain one, and then the two Dithers in their array order. The
## two orders give two pictures: eight levels and then two is not two alone,
## while two and then eight is two alone, since the eight-level grid holds 0
## and 1. So each order's composite is read against a model of the kernel run
## here, in that order over the picture the brightener alone makes, and the
## two pictures are read against each other.
##
## The brightener's output is read off the composite with it alone attached
## rather than modelled, because the model this suite needs is the Dithers'
## order and not Brightness/Contrast's formula. A texel whose step sits within
## EDGE of a level boundary in either Dither is passed over, as the dithering
## suite passes over a noise of one half, because the kernel computes in floats
## and the model in doubles.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
## The ramp painted across both chunks, from LOW at the left to HIGH.
const LOW := 0.05
const HIGH := 0.95
## How far from a level boundary a step may sit and still be decided here.
const EDGE := 0.002
## How far a texel of the composite may sit from the model's.
const SAME := 1e-4
## The texels read of the canvas, one in STRIDE across and down.
const STRIDE := 5
## The two orders differ in at least this share of the texels read, under
## half the share measured on 2026-10-07, 250 of 5,356.
const APART := 0.02

const TWO := {"levels": 2, "pattern": "gradient", "strength": 100.0}
const EIGHT := {"levels": 8, "pattern": "bayer", "strength": 100.0}
const BRIGHTEN := {"brightness": 37.0, "contrast": 0.0}
const STEEPEN := {"brightness": 0.0, "contrast": 25.0}

var _easel: SaEasel = null
var _document: SaDocument = null
var _ops: SaFilterOps = null
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
    _ops = SaFilterOps.new(_document)


func after_each() -> void:
    _ops = null
    _easel.free()
    _easel = null
    _document = null


## "Layer 1" holding a grey ramp across both chunks, opaque, so the Dithers
## meet every value between LOW and HIGH rather than one grey.
func _paint() -> SaLayer:
    var layer := _document.get_node("Layer 1") as SaLayer
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        var chunk := layer.get_or_create_chunk(grid_pos)
        var side := chunk.pixel_size()
        var image := Image.create(side, side, false, Image.FORMAT_RGBAF)
        for x in side:
            var v := lerpf(LOW, HIGH, float(grid_pos.x * side + x) / float(side * 2 - 1))
            for y in side:
                image.set_pixel(x, y, Color(v, v, v, 1.0))
        GlobalShaderCompiler.get_rd().texture_update(chunk.albedo().rid, 0, image.get_data())
    return layer


## The red channel of the composite at every STRIDE-th texel, in rows.
func _composite_samples() -> PackedFloat32Array:
    Bench.composite(_easel)
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out := PackedFloat32Array()
    for y in range(0, texture.size.y, STRIDE):
        for x in range(0, texture.size.x, STRIDE):
            out.append(SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x).r)
    return out


## The red channel of *layer*'s own pixels at the texels `_composite_samples`
## reads, which is what a flatten wrote into it.
func _pixel_samples(layer: SaLayer) -> PackedFloat32Array:
    var size := _easel.output.size
    var rows: Dictionary[Vector2i, PackedByteArray] = {}
    var formats: Dictionary[Vector2i, int] = {}
    var side := 0
    for grid_pos: Vector2i in layer.chunks:
        var albedo := layer.chunks[grid_pos].albedo()
        side = layer.chunks[grid_pos].pixel_size()
        rows[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(albedo.rid, 0)
        formats[grid_pos] = albedo.format
    var out := PackedFloat32Array()
    for y in range(0, size.y, STRIDE):
        for x in range(0, size.x, STRIDE):
            var grid_pos := Vector2i(floori(float(x) / side), floori(float(y) / side))
            var local := Vector2i(x % side, y % side)
            out.append(SaFieldSpec.decode_texel(rows[grid_pos], formats[grid_pos], local.y * side + local.x).r)
    return out


## The document pixel of the sample at *index* of a STRIDE grid read in rows.
func _place_of(index: int) -> Vector2i:
    var across := ceili(float(_easel.output.size.x) / float(STRIDE))
    return Vector2i(index % across, floori(float(index) / across)) * STRIDE


## Jimenez's interleaved gradient noise at document pixel *at*, as the kernel
## computes it.
static func _gradient_noise(at: Vector2i) -> float:
    var inner := 0.06711056 * at.x + 0.00583715 * at.y
    var outer := 52.9829189 * (inner - floorf(inner))
    return outer - floorf(outer)


## The 8 by 8 Bayer threshold at document pixel *at*, the bits of x xor y and
## of y interleaved from the lowest up, as the kernel builds it.
static func _bayer(at: Vector2i) -> float:
    var x := posmod(at.x, 8)
    var y := posmod(at.y, 8)
    var index := 0
    for i in 3:
        var xb := (x >> i) & 1
        var yb := (y >> i) & 1
        index = index * 4 + absi(xb - yb) * 2 + yb
    return (float(index) + 0.5) / 64.0


## *value* quantised by the Dither *values* at document pixel *at*, as
## `dither.gmacs` does at full strength, or NAN when the step sits within EDGE
## of a level boundary and floats could fall either side of it.
static func _dithered(value: float, values: Dictionary, at: Vector2i) -> float:
    var steps := float(values["levels"]) - 1.0
    var threshold := _gradient_noise(at) if values["pattern"] == "gradient" else _bayer(at)
    var step := value * steps + threshold
    var off := step - floorf(step)
    if off < EDGE or off > 1.0 - EDGE:
        return NAN
    return floorf(step) / steps


## *plain* run through *first* and then *second* texel by texel, NAN where
## either step is too close to call.
func _model(plain: PackedFloat32Array, first: Dictionary, second: Dictionary) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    for index in plain.size():
        var at := _place_of(index)
        var once := _dithered(plain[index], first, at)
        out.append(NAN if is_nan(once) else _dithered(once, second, at))
    return out


## How many texels of *found* sit further than SAME from *expected*, and how
## many *expected* decided at all.
static func _misses(found: PackedFloat32Array, expected: PackedFloat32Array) -> Vector2i:
    var missed := 0
    var decided := 0
    for index in expected.size():
        if is_nan(expected[index]):
            continue
        decided += 1
        if absf(found[index] - expected[index]) > SAME:
            missed += 1
    return Vector2i(missed, decided)


## How many texels *a* and *b* hold apart.
static func _apart(a: PackedFloat32Array, b: PackedFloat32Array) -> int:
    var count := 0
    for index in a.size():
        if absf(a[index] - b[index]) > SAME:
            count += 1
    return count


## The two Dithers either side of the brightener: the composite is the
## brightener and then the two in their array order, the swap puts the other
## order on the canvas, and the two pictures differ.
func test_two_dithers_run_in_their_array_order_after_the_plain_record() -> void:
    var layer := _paint()
    var brighten := _ops.attach(layer, _brighten_key, BRIGHTEN)
    var plain := _composite_samples()
    var two := _ops.attach(layer, _dither_key, TWO, 0)
    var eight := _ops.attach(layer, _dither_key, EIGHT)
    assert_eq(_ops.filters_of(layer), [two, brighten, eight] as Array[SaAttachedFilter], "Two, the brightener, eight")

    var placed := _composite_samples()
    var two_then_eight := _model(plain, TWO, EIGHT)
    var missed := _misses(placed, two_then_eight)
    assert_true(missed.y > placed.size() * 0.5, "Most texels are decided: %d of %d" % [missed.y, placed.size()])
    assert_eq(missed.x, 0, "The composite is the brightener, then two levels, then eight")

    assert_true(_ops.reorder(layer, eight, 0), "Eight moves to the bottom")
    assert_true(_ops.reorder(layer, two, 2), "and two to the top")
    assert_eq(_ops.filters_of(layer), [eight, brighten, two] as Array[SaAttachedFilter], "Eight, the brightener, two")

    var swapped := _composite_samples()
    var eight_then_two := _model(plain, EIGHT, TWO)
    missed = _misses(swapped, eight_then_two)
    assert_true(missed.y > swapped.size() * 0.5, "Most texels are decided, swapped: %d of %d" % [missed.y, swapped.size()])
    assert_eq(missed.x, 0, "The composite is the brightener, then eight levels, then two")

    var apart := _apart(placed, swapped)
    var said := "The two orders are two pictures: %d of %d texels apart" % [apart, swapped.size()]
    assert_true(apart >= swapped.size() * APART, said)


## A plain record placed after both Dithers is flattened: the flatten takes the
## two plain records the chain runs first and leaves the two Dithers attached,
## in their order, still the last the chain runs, so not one texel moves and
## the layer's own pixels are the plain picture.
func _flatten_case(two_first: bool) -> void:
    var name := "two levels first" if two_first else "eight levels first"
    var layer := _paint()
    var brighten := _ops.attach(layer, _brighten_key, BRIGHTEN)
    var steepen := _ops.attach(layer, _brighten_key, STEEPEN)
    var plain := _composite_samples()
    var first := _ops.attach(layer, _dither_key, TWO if two_first else EIGHT, 0)
    var second := _ops.attach(layer, _dither_key, EIGHT if two_first else TWO, 2)
    assert_eq(
        _ops.filters_of(layer),
        [first, brighten, second, steepen] as Array[SaAttachedFilter],
        "A Dither, the brightener, a Dither, and the steepener after both, %s" % name
    )
    var before := _composite_samples()
    var expected := _model(plain, TWO if two_first else EIGHT, EIGHT if two_first else TWO)
    assert_eq(_misses(before, expected).x, 0, "The composite is the plain records and then the Dithers in order, %s" % name)

    var said := _ops.flatten_sentence(layer, steepen)
    assert_true(said.contains("2 filters"), "The sentence names the two plain records, %s: %s" % [name, said])
    assert_true(_ops.flatten(layer, steepen), "The flatten runs, %s" % name)
    var left := _ops.filters_of(layer)
    assert_eq(left, [first, second] as Array[SaAttachedFilter], "The two Dithers are left, in their order, %s" % name)
    assert_eq(_apart(_pixel_samples(layer), plain), 0, "The layer's pixels are the plain picture, no Dither in them, %s" % name)
    assert_eq(_apart(_composite_samples(), before), 0, "and the Dithers still run last: no texel moves, %s" % name)


func test_flattening_a_record_after_both_leaves_two_levels_first() -> void:
    _flatten_case(true)


func test_flattening_a_record_after_both_leaves_eight_levels_first() -> void:
    _flatten_case(false)
