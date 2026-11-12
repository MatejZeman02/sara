## A TIFF reads to the same floats with its samples walked natively.
##
## [SaTiffReader] turns a big-endian file's bytes, undoes the predictor, scales
## integers and makes an associated alpha straight in `SaTiffSamples`, the
## native library of the base modules' `tiff-lzw` folder, when Godot loaded
## it, and in its GDScript when it did not. The same files are read both ways,
## the GDScript asked for by a class name Godot does not have, and every value
## of the two pictures is compared as the bits it is: sixteen-bit RGB with the
## predictor in either byte order, eight-bit RGBA with its alpha multiplied in,
## and the rarer shapes the same passes take, greys, extra samples and
## big-endian floats. Noise for the samples, so the predictor's sums wrap and
## an associated alpha meets colour larger than itself.
extends "res://tests/test_framework.gd"

const Encoders = preload("test_a_tiff_compressed_with_lzw_or_packbits_opens.gd")

## A class name no build registers, which is how the reader is told to walk
## its samples in GDScript as it does when the library is not there.
const ABSENT := &"SaTiffSamplesLeftOut"
const WIDTH: int = 259
const HEIGHT: int = 67
const ROWS_PER_STRIP: int = 16
const DEFLATE: int = 8
const NONE: int = 1
## How much faster the native passes read a 1920 by 1080 file than the
## GDScript at the least. About forty times was measured.
const SPEEDUP: float = 4.0


func test_sixteen_bit_rgb_with_the_predictor_reads_the_same_in_either_byte_order() -> void:
    if not _built():
        return
    for big: bool in [false, true]:
        var fields := _fields(3, [16, 16, 16], DEFLATE)
        fields[317] = [2]
        _same(_file(fields, 3 * 2, big, 701 + int(big)), "sixteen-bit RGB with the predictor, big-endian %s" % big)


func test_eight_bit_rgba_with_an_associated_alpha_reads_the_same() -> void:
    if not _built():
        return
    var fields := _fields(4, [8, 8, 8, 8], NONE)
    fields[338] = [1]
    _same(_file(fields, 4, false, 703), "eight-bit RGBA with an associated alpha")
    fields[317] = [2]
    fields[259] = [DEFLATE]
    _same(_file(fields, 4, true, 704), "the same with the predictor and Deflate, big-endian")


func test_greys_extras_and_big_endian_floats_read_the_same() -> void:
    if not _built():
        return
    var grey := _fields(3, [16, 16, 16], NONE)
    grey[262] = [1]
    grey[338] = [1, 0]
    _same(_file(grey, 3 * 2, true, 705), "sixteen-bit grey, an associated alpha and an extra, big-endian")
    var extras := _fields(5, [8, 8, 8, 8, 8], NONE)
    extras[338] = [2, 0]
    _same(_file(extras, 5, false, 706), "eight-bit RGBA with a straight alpha and an extra")
    var floats := _fields(4, [32, 32, 32, 32], DEFLATE)
    floats[339] = [3, 3, 3, 3]
    floats[317] = [2]
    floats[338] = [1]
    _same(_file(floats, 4 * 4, true, 707), "float RGBA with the predictor and an associated alpha, big-endian")
    var plain := _fields(1, [16], NONE)
    plain[262] = [1]
    _same(_file(plain, 2, true, 708), "sixteen-bit grey alone, big-endian")


func test_the_native_passes_read_a_full_hd_file_faster_than_the_gdscript() -> void:
    if not _built():
        return
    var width := 1920
    var height := 1080
    var raw := PackedByteArray()
    raw.resize(width * height * 4)
    for i in range(0, raw.size(), 61):
        raw[i] = (i * 7) & 0xFF
    var fields := {256: [width], 257: [height], 258: [8, 8, 8, 8], 259: [NONE], 262: [2], 277: [4], 278: [height]}
    fields[338] = [1]
    var bytes: PackedByteArray = Encoders.new()._tiff(fields, [raw])
    var started := Time.get_ticks_usec()
    var native := SaTiffReader.new(bytes, "native.tif").picture()
    var native_ms := (Time.get_ticks_usec() - started) / 1000.0
    started = Time.get_ticks_usec()
    var script := SaTiffReader.new(bytes, "script.tif", ABSENT).picture()
    var script_ms := (Time.get_ticks_usec() - started) / 1000.0
    print(
        (
            "  h701: eight-bit RGBA with an associated alpha at 1920 by 1080, %.0f ms native, %.0f ms in GDScript"
            % [native_ms, script_ms]
        )
    )
    assert_true(native != null and script != null, "both reads give a picture")
    assert_true(
        native_ms * SPEEDUP < script_ms,
        "the native read, %.0f ms, is %.0f times faster than the GDScript's %.0f ms" % [native_ms, SPEEDUP, script_ms]
    )


## Whether `SaTiffSamples` is loaded, skipping the suite when it is not, since
## the GDScript would then be compared with itself.
func _built() -> bool:
    if ClassDB.class_exists(SaTiffReader.LIBRARY):
        return true
    skip("the tiff-lzw library is not built, packaging/build.sh modules builds it")
    return false


func _fields(samples: int, bits: Array, compression: int) -> Dictionary:
    return {
        256: [WIDTH],
        257: [HEIGHT],
        258: bits,
        259: [compression],
        262: [2],
        277: [samples],
        278: [ROWS_PER_STRIP],
    }


## A file of *fields* whose strips are noise, *pixel_bytes* to a pixel, packed
## as the fields' compression says, in the byte order *big* names.
func _file(fields: Dictionary, pixel_bytes: int, big: bool, seed_value: int) -> PackedByteArray:
    var random := RandomNumberGenerator.new()
    random.seed = seed_value
    var strips := []
    for top in range(0, HEIGHT, ROWS_PER_STRIP):
        var strip := PackedByteArray()
        strip.resize(mini(ROWS_PER_STRIP, HEIGHT - top) * WIDTH * pixel_bytes)
        for i in strip.size():
            strip[i] = random.randi() & 0xFF
        if (fields[259] as Array)[0] == DEFLATE:
            strip = strip.compress(FileAccess.COMPRESSION_DEFLATE)
        strips.append(strip)
    return Encoders.new()._tiff(fields, strips, big)


## *bytes* read natively and in GDScript, the two pictures compared value by
## value as bits, so a NaN or a negative zero has to match too.
func _same(bytes: PackedByteArray, what: String) -> void:
    var native := SaTiffReader.new(bytes, "native.tif").picture()
    var script := SaTiffReader.new(bytes, "script.tif", ABSENT).picture()
    assert_true(native != null and script != null, "%s reads both ways" % what)
    if native == null or script == null:
        return
    assert_eq(native.get_format(), script.get_format(), "%s comes back in one format" % what)
    var a := native.get_data()
    var b := script.get_data()
    var size := 1 if native.get_format() == Image.FORMAT_RGBA8 else 4
    var differ := 0
    var first := ""
    for at in range(0, mini(a.size(), b.size()), size):
        var left := a[at] if size == 1 else a.decode_u32(at)
        var right := b[at] if size == 1 else b.decode_u32(at)
        if left != right:
            differ += 1
            if first.is_empty():
                first = ", the first at value %d, %x natively and %x in GDScript" % [at >> (size >> 1), left, right]
    assert_eq(a.size(), b.size(), "%s holds as many values both ways" % what)
    assert_eq(differ, 0, "%s reads to the same values to the bit%s" % [what, first])
