## Dither's levels are spaced in an encoding the painter picks,
## the document's by default, covering every
## pattern, interleaved gradient noise among them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A grey ramp across two chunks of an sRGB document is dithered to LEVELS
## levels by each of the three patterns twice, once in the document's encoding
## and once in linear light, and every texel read is held against a model of
## the kernel run here: the value taken into the encoding by
## `SaTransferFunction`'s own curves, the threshold the pattern gives its
## document pixel added to its step, the floor, and back. A texel whose step
## sits within EDGE of a level boundary is passed over, as the dithering suite
## passes over a noise of one half, because the kernel computes in floats and
## the model in doubles. The levels each run lands on are then read off the
## composite itself and their spacing measured in both encodings.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const RoundTrip = preload("res://modules/sara-base-modules/base/tests/attached_round_trip.gd")

## Real dispatches into real chunks, and a save and a load.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
## The levels every case dithers to, so a level is a quarter step.
const LEVELS := 5
## A grey above one, in encoded values, flat over both chunks.
const HOT := 1.6
## How far from a level boundary a step may sit and still be decided here.
const EDGE := 0.002
## How far a texel may sit from the model's, or a level from its even place.
const SAME := 1e-4
## The texels read of the canvas, one in STRIDE across and down.
const STRIDE := 5

var _easel: SaEasel = null
var _document: SaDocument = null
var _ops: SaFilterOps = null
var _dither_key: StringName = &""
var _tile := PackedFloat32Array()


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE * 2, SaChunk.SIZE), null, SaColorSpace.srgb())
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var registry := SaFilterRegistry.new()
    var dither := SaDitherFilter.new()
    registry.register(dither, OWNER)
    _dither_key = SaFilterRegistry.key_for(OWNER, dither)
    _easel.compositor.filter_chain.registry = registry
    _document = _easel.document
    _ops = SaFilterOps.new(_document)
    _tile = SaDitherFilter.thresholds()


func after_each() -> void:
    _ops = null
    _easel.free()
    _easel = null
    _document = null


## *value* in encoded sRGB taken into *encoding*, the curve the Encoding id
## names in `SaTransferFunction`, over linear light.
static func _into(value: float, encoding: String) -> float:
    if encoding == "document":
        return value
    return SaTransferFunction.from_id(StringName(encoding)).encode(SaTransferFunction.srgb().decode(value))


## *value* in *encoding* back into encoded sRGB.
static func _out_of(value: float, encoding: String) -> float:
    if encoding == "document":
        return value
    return SaTransferFunction.srgb().encode(SaTransferFunction.from_id(StringName(encoding)).decode(value))


## The 8 by 8 Bayer threshold at document pixel *at*, as `dither.gmacs` builds
## it from the bits of x xor y and of y.
static func _bayer(at: Vector2i) -> float:
    var x := posmod(at.x, 8)
    var y := posmod(at.y, 8)
    var index := 0
    for i in 3:
        var xb := (x >> i) & 1
        var yb := (y >> i) & 1
        index = index * 4 + absi(xb - yb) * 2 + yb
    return (float(index) + 0.5) / 64.0


## Jimenez's interleaved gradient noise at document pixel *at*, as the kernel
## computes it.
static func _gradient_noise(at: Vector2i) -> float:
    var inner := 0.06711056 * at.x + 0.00583715 * at.y
    var outer := 52.9829189 * (inner - floorf(inner))
    return outer - floorf(outer)


## The threshold *pattern* gives document pixel *at*, at full strength.
func _threshold(pattern: String, at: Vector2i) -> float:
    if pattern == "bayer":
        return _bayer(at)
    if pattern == "gradient":
        return _gradient_noise(at)
    var side := SaDitherFilter.TILE
    return _tile[posmod(at.y, side) * side + posmod(at.x, side)]


## The ramp's encoded grey at document column *x*, black at the left and white
## at the right.
func _ramp_at(x: int) -> float:
    return float(x) / float(_easel.canvas_size.x - 1)


## "Layer 1" holding, per document column, what *grey* answers for it, opaque.
func _paint(grey: Callable) -> SaLayer:
    var layer := _document.get_node("Layer 1") as SaLayer
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        var chunk := layer.get_or_create_chunk(grid_pos)
        var side := chunk.pixel_size()
        var image := Image.create(side, side, false, Image.FORMAT_RGBAF)
        for x in side:
            var v: float = grey.call(grid_pos.x * side + x)
            for y in side:
                image.set_pixel(x, y, Color(v, v, v, 1.0))
        GlobalShaderCompiler.get_rd().texture_update(chunk.albedo().rid, 0, image.get_data())
    return layer


## The composite with a Dither of *values* alone on *layer*, its red channel
## at every STRIDE-th texel as `[Vector2i, float]` pairs. The record is taken
## off again after the read.
func _dithered(layer: SaLayer, values: Dictionary) -> Array:
    var record := _ops.attach(layer, _dither_key, values)
    Bench.composite(_easel)
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array = []
    for y in range(0, texture.size.y, STRIDE):
        for x in range(0, texture.size.x, STRIDE):
            out.append([Vector2i(x, y), SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x).r])
    _ops.detach(layer, record)
    return out


static func _values(pattern: String, encoding: String) -> Dictionary:
    return {"levels": LEVELS, "pattern": pattern, "encoding": encoding, "strength": 100.0}


## The distinct levels *samples* hold, each read in *encoding* and sorted.
static func _levels_in(samples: Array, encoding: String) -> Array[float]:
    var seen: Dictionary[float, bool] = {}
    for sample: Array in samples:
        seen[snappedf(_into(float(sample[1]), encoding), 0.001)] = true
    var out: Array[float] = []
    out.assign(seen.keys())
    out.sort()
    return out


## How many of *levels*, read in their own encoding, sit off the even grid of
## LEVELS levels.
static func _off_even(levels: Array[float]) -> int:
    var steps := float(LEVELS - 1)
    var off := 0
    for level in levels:
        if absf(level * steps - roundf(level * steps)) / steps > 0.001:
            off += 1
    return off


## A Dither handed nothing spaces its levels in the document's encoding, and
## so does the record it files and a record that names no encoding, which is
## every record saved before the row. Each other entry is a pure power curve,
## whose exponent is what the kernel is handed in the push constant's last slot.
func test_a_dither_given_nothing_spaces_its_levels_in_the_documents_encoding() -> void:
    var filter := SaDitherFilter.new()
    filter.set_parameters({})
    assert_eq(String(filter.parameter(&"encoding")), "document", "A Dither handed nothing reads the document's encoding")
    var filed := filter.filed_as(SaFilterRegistry.key_for(OWNER, filter))
    assert_eq(String(filed.parameters.get("encoding", "")), "document", "and files a record that names it")
    assert_eq(SaDitherFilter.ENCODINGS[0], "document", "which is the Encoding row's first entry")
    assert_eq(SaDitherFilter.ENCODING_TITLES[0], "Document's encoding", "titled Document's encoding")
    var push := SaDitherFilter.push_for({"levels": 4.0, "pattern": "bayer", "strength": 100.0}, SaColorSpace.srgb())
    assert_eq(push.size(), 32, "The push constant is the 128 bytes Vulkan guarantees")
    assert_eq(push[SaDitherFilter.ENCODING_SLOT], 0.0, "A record naming no encoding hands the kernel nought")
    for encoding: String in SaDitherFilter.ENCODINGS.slice(1):
        var curve := SaTransferFunction.from_id(StringName(encoding))
        assert_not_null(curve, "%s names a curve" % encoding)
        if curve == null:
            continue
        var pure := is_equal_approx(curve.slope, 1.0) and curve.threshold == 0.0 and is_equal_approx(curve.gain, 1.0)
        assert_true(pure, "%s is a pure power curve" % encoding)
        var handed := SaDitherFilter.push_for(_values("gradient", encoding), SaColorSpace.srgb())
        var gamma := handed[SaDitherFilter.ENCODING_SLOT]
        assert_almost_eq(gamma, curve.exponent, 1e-6, "%s hands the kernel its gamma" % encoding)
    var linear := SaDitherFilter.push_for(_values("gradient", "linear"), SaColorSpace.srgb())
    assert_eq(linear[SaDitherFilter.ENCODING_SLOT], 1.0, "and linear light is the gamma of one")


## One grey ramp, each pattern, dithered in the document's encoding and in
## linear light: every decided texel is the model's, the document run's levels
## are even steps of the encoded value and the linear run's even steps of
## linear light, and neither is even in the other's.
func test_a_ramp_lands_on_levels_even_in_the_encoding_picked() -> void:
    var layer := _paint(_ramp_at)
    var steps := float(LEVELS - 1)
    for pattern: String in SaDitherFilter.PATTERNS:
        for encoding: String in ["document", "linear"]:
            var name := "%s in %s" % [pattern, encoding]
            var samples := _dithered(layer, _values(pattern, encoding))
            var decided := 0
            var wrong := 0
            for sample: Array in samples:
                var at: Vector2i = sample[0]
                var step := _into(_ramp_at(at.x), encoding) * steps + _threshold(pattern, at)
                if absf(step - roundf(step)) < EDGE:
                    continue
                decided += 1
                if absf(float(sample[1]) - _out_of(floorf(step) / steps, encoding)) > SAME:
                    wrong += 1
            assert_true(decided > samples.size() * 0.5, "%s: %d of %d texels decided" % [name, decided, samples.size()])
            assert_eq(wrong, 0, "%s: every decided texel is the model's" % name)
            var own := _levels_in(samples, encoding)
            var other := _levels_in(samples, "linear" if encoding == "document" else "document")
            assert_eq(own.size(), LEVELS, "%s lands on %d levels: %s" % [name, LEVELS, own])
            assert_eq(_off_even(own), 0, "%s: the levels are even in its own encoding" % name)
            assert_true(_off_even(other) >= 2, "%s: and not in the other, %s" % [name, other])


## A grey above one, through each entry of the Encoding row, lands on a level
## above one, a whole quarter step of that encoding, never on white.
func test_a_value_above_one_lands_on_a_level_above_one_in_every_encoding() -> void:
    var layer := _paint(func(_x: int) -> float: return HOT)
    var steps := float(LEVELS - 1)
    for encoding: String in SaDitherFilter.ENCODINGS:
        var samples := _dithered(layer, _values("gradient", encoding))
        var low := INF
        var off := 0
        for sample: Array in samples:
            var value := float(sample[1])
            low = minf(low, value)
            var spaced := _into(value, encoding) * steps
            if absf(spaced - roundf(spaced)) > SAME * steps * 10.0:
                off += 1
        assert_true(low > 1.0 + SAME, "%s: the darkest texel is %.4f, above one" % [encoding, low])
        assert_eq(off, 0, "%s: every texel sits on a level of its encoding" % encoding)
        var levels := _levels_in(samples, encoding)
        assert_true(levels.size() >= 2 and levels[0] > 1.0, "%s: on levels above one, %s" % [encoding, levels])


## A Dither attached in linear light saves, and reopens in linear light while
## the filter's instance holds the default, drawing what it drew. A record
## that names no encoding, as one saved before the row, draws as one naming the
## document's, though the instance last ran in linear light.
func test_the_encoding_saves_and_reopens() -> void:
    var trip := RoundTrip.new(SaDitherFilter.new(), OWNER)
    var kept := trip.attach(_values("gradient", "linear"))
    assert_eq(String(kept.get("encoding", "")), "linear", "The record is attached in linear light")
    var before := trip.texels()
    var loaded := trip.round_trip({})
    assert_eq(String(loaded.get("encoding", "")), "linear", "The loaded record still names linear light")
    trip.filter.set_parameters(loaded)
    assert_eq(String(trip.filter.parameter(&"encoding")), "linear", "which the rows read as linear light")
    var push := SaDitherFilter.push_for(loaded, SaColorSpace.srgb())
    assert_eq(push[SaDitherFilter.ENCODING_SLOT], 1.0, "and the kernel is handed the gamma of one")
    assert_true(RoundTrip.distance(before, trip.texels()) < 1e-5, "so it draws the texels it drew before the save")
    trip.release()
    var layer := _paint(_ramp_at)
    var named := _dithered(layer, _values("gradient", "document"))
    var linear := _dithered(layer, _values("gradient", "linear"))
    var unnamed := _dithered(layer, {"levels": LEVELS, "pattern": "gradient", "strength": 100.0})
    assert_true(_levels_in(linear, "document") != _levels_in(named, "document"), "Linear light draws apart")
    var apart := 0
    for index in named.size():
        if absf(float(named[index][1]) - float(unnamed[index][1])) > 0.0:
            apart += 1
    assert_eq(apart, 0, "A record naming no encoding draws as the document's encoding")
