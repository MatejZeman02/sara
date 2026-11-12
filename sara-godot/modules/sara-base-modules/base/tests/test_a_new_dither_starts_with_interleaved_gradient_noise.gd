## A new Dither starts with interleaved gradient noise rather
## than Bayer, and a record saved with a
## pattern keeps the one it names.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## "A new Dither" is read three ways, because the default reaches the canvas
## three ways: the filter's own rows when nothing is handed in, which are what
## the dialog seeds and what Attach and Layer file, the push constant for a
## record that names no pattern, and the pixels such a record draws. The saved
## case goes through a real save and load, with the filter's one instance
## scrubbed to its new default in between, so a Bayer that comes back came
## back from the file.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const RoundTrip = preload("res://modules/sara-base-modules/base/tests/attached_round_trip.gd")

## A save, a load and real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
## The slot of the push constant the kernel reads the pattern's number from.
const PATTERN_SLOT := 2
## The texels read of a chunk, one in STRIDE across and down.
const STRIDE := 5

var _easel: SaEasel = null


func after_each() -> void:
    if _easel != null:
        _easel.free()
    _easel = null


## Jimenez's interleaved gradient noise at document pixel *at*, as
## `dither.gmacs` computes it.
static func _gradient_noise(at: Vector2i) -> float:
    var inner := 0.06711056 * at.x + 0.00583715 * at.y
    var outer := 52.9829189 * (inner - floorf(inner))
    return outer - floorf(outer)


## The kernel's number for the pattern *id*, its place in the choice row.
static func _number_of(id: String) -> float:
    return float(SaDitherFilter.PATTERNS.find(id))


## A fresh filter handed nothing reads interleaved gradient noise, and so does
## the record it is filed as, which is what Attach and Layer put on a node.
func test_a_dither_given_nothing_picks_interleaved_gradient_noise() -> void:
    var filter := SaDitherFilter.new()
    filter.set_parameters({})
    assert_eq(String(filter.parameter(&"pattern")), "gradient", "A Dither handed nothing reads the gradient noise")
    var key := SaFilterRegistry.key_for(OWNER, filter)
    var filed := filter.filed_as(key)
    assert_eq(String(filed.parameters.get("pattern", "")), "gradient", "and files a record that names it")
    assert_eq(
        SaDitherFilter.PATTERN_TITLES[SaDitherFilter.PATTERNS.find("gradient")],
        "Interleaved gradient noise",
        "which the dialog's Pattern row titles Interleaved gradient noise"
    )


## A record that names its levels and its strength and no pattern, as one
## written by hand or by a module would, dithers with the gradient noise, read
## through the filter's rows and through the push constant the kernel gets.
func test_a_record_naming_no_pattern_dithers_with_gradient_noise() -> void:
    var filter := SaDitherFilter.new()
    var record := SaAttachedFilter.new(SaFilterRegistry.key_for(OWNER, filter), {"levels": 4.0, "strength": 100.0})
    filter.set_parameters(record.parameters)
    assert_eq(String(filter.parameter(&"pattern")), "gradient", "The rows fill the missing pattern with the noise")
    var push := SaDitherFilter.push_for(record.parameters, SaColorSpace.srgb())
    assert_eq(push[PATTERN_SLOT], _number_of("gradient"), "and the kernel is handed the noise's number")
    var empty := SaDitherFilter.push_for({}, SaColorSpace.srgb())
    assert_eq(empty[PATTERN_SLOT], _number_of("gradient"), "as it is for a record holding nothing at all")


## Flat grey at one half over two chunks, dithered by the record a fresh Dither
## files: each texel is on the upper of its two levels exactly where the
## gradient noise of its document pixel reaches one half, which a Bayer matrix
## agrees with at about half the texels.
func test_the_record_a_fresh_dither_files_draws_gradient_noise() -> void:
    _easel = Bench.easel(Vector2i(SaChunk.SIZE * 2, SaChunk.SIZE))
    var filter := SaDitherFilter.new()
    _easel.compositor.filter_chain.registry.register(filter, OWNER)
    var key := SaFilterRegistry.key_for(OWNER, filter)
    var layer := _easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        layer.get_or_create_chunk(grid_pos).clear(Color(0.5, 0.5, 0.5, 1.0))
    filter.set_parameters({})
    var filed := filter.filed_as(key)
    SaFilterOps.new(_easel.document).attach(layer, filed.key, filed.parameters)
    Bench.composite(_easel)
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var read := 0
    var wrong := 0
    for y in range(0, texture.size.y, STRIDE):
        for x in range(0, texture.size.x, STRIDE):
            var noise := _gradient_noise(Vector2i(x, y))
            if absf(noise - 0.5) < 0.001:
                continue
            var texel := SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)
            read += 1
            if (texel.r > 0.5) != (noise >= 0.5):
                wrong += 1
    assert_true(read > 1000, "Both chunks were read: %d texels" % read)
    assert_eq(wrong, 0, "Every texel follows the gradient noise of its document pixel")


## A Dither attached with Bayer, saved, and loaded while the filter's instance
## holds the new default, reopens with Bayer and draws what it drew.
func test_a_record_saved_with_bayer_reopens_with_bayer() -> void:
    var trip := RoundTrip.new(SaDitherFilter.new(), OWNER)
    var kept := trip.attach({"levels": 4.0, "pattern": "bayer", "strength": 100.0})
    assert_eq(String(kept.get("pattern", "")), "bayer", "The record is attached with Bayer")
    var before := trip.texels()
    var loaded := trip.round_trip({})
    assert_eq(String(loaded.get("pattern", "")), "bayer", "The loaded record still names Bayer")
    trip.filter.set_parameters(loaded)
    assert_eq(String(trip.filter.parameter(&"pattern")), "bayer", "which the rows read as Bayer")
    var push := SaDitherFilter.push_for(loaded, SaColorSpace.srgb())
    assert_eq(push[PATTERN_SLOT], _number_of("bayer"), "and the kernel is handed Bayer's number")
    assert_true(RoundTrip.distance(before, trip.texels()) < 1e-5, "so it draws the texels it drew before the save")
    trip.release()
