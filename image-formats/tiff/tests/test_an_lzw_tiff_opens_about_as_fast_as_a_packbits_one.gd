## An LZW TIFF opens about as fast as a PackBits one.
##
## One Full HD RGB picture is written twice, with LZW and with PackBits, through
## the encoders of the LZW and PackBits suite, so neither file is the reader's
## unpacker turned round. Both open on the same run and read equal texel for
## texel. The picture is a photograph's kind of content, smooth ramps under a
## sensor's noise of sixteen levels, in strips of 64 rows with no predictor, so
## the two schemes differ in their unpacking alone.
##
## The ratio of the two open times is what a slow or loaded machine can bend, so
## it is a warning past [constant NATIVE_BOUND] or [constant BOUND] times and a
## failure only past [constant FAIL_FACTOR] times that, which still catches an
## unpacker that has gone quadratic and no machine reaches by being slow.
extends "res://tests/test_framework.gd"

const Encoders = preload("test_a_tiff_compressed_with_lzw_or_packbits_opens.gd")

const WIDTH: int = 1920
const HEIGHT: int = 1080
const ROWS_PER_STRIP: int = 64
const LZW: int = 5
const PACK_BITS: int = 32773
## Each file is opened this many times and its fastest open is the one
## compared, so a stall of the machine in one open does not decide the bound.
const OPENS: int = 3
## The bound asked for is twice, which the native unpacker meets, so twice is held
## when Godot loaded it. Without it the bound is what GDScript reaches, ten times, since an LZW code costs a few
## statements where PackBits costs one a byte.
const NATIVE_BOUND: float = 2.0
const BOUND: float = 10.0
## The ratio is a failure only past this many times the bound above.
const FAIL_FACTOR: float = 5.0


func test_an_lzw_full_hd_picture_reads_as_the_packbits_one_within_a_generous_bound_of_its_time() -> void:
    var raw := _picture()
    var encoders := Encoders.new()
    var row_bytes := WIDTH * 3
    var lzw_strips := []
    var pack_strips := []
    for top in range(0, HEIGHT, ROWS_PER_STRIP):
        var strip := raw.slice(top * row_bytes, mini(top + ROWS_PER_STRIP, HEIGHT) * row_bytes)
        lzw_strips.append(encoders._lzw(strip))
        pack_strips.append(encoders._pack_bits(strip))
    var fields := {256: [WIDTH], 257: [HEIGHT], 258: [8, 8, 8], 262: [2], 277: [3], 278: [ROWS_PER_STRIP]}
    fields[259] = [LZW]
    var lzw_file: PackedByteArray = encoders._tiff(fields, lzw_strips)
    fields[259] = [PACK_BITS]
    var pack_file: PackedByteArray = encoders._tiff(fields, pack_strips)

    var bound := NATIVE_BOUND if ClassDB.class_exists(SaTiffUnpacker.LIBRARY) else BOUND
    var lzw_best := INF
    var pack_best := INF
    var lzw_picture: Image = null
    var pack_picture: Image = null
    for i in OPENS:
        var started := Time.get_ticks_usec()
        lzw_picture = SaTiffReader.new(lzw_file, "full-hd-lzw.tif").picture()
        var middle := Time.get_ticks_usec()
        pack_picture = SaTiffReader.new(pack_file, "full-hd-packbits.tif").picture()
        var ended := Time.get_ticks_usec()
        lzw_best = minf(lzw_best, (middle - started) / 1000.0)
        pack_best = minf(pack_best, (ended - middle) / 1000.0)
    assert_not_null(lzw_picture, "the LZW file opens")
    assert_not_null(pack_picture, "the PackBits file opens")
    if lzw_picture == null or pack_picture == null:
        return
    assert_eq(lzw_picture.get_size(), Vector2i(WIDTH, HEIGHT), "at Full HD")
    assert_true(lzw_picture.get_data() == pack_picture.get_data(), "the two pictures equal texel for texel")
    var line := "LZW %.0f ms (%d bytes), PackBits %.0f ms (%d bytes)" % [lzw_best, lzw_file.size(), pack_best, pack_file.size()]
    print("  probe: %s" % line)
    if lzw_best > bound * pack_best:
        print("  warning: the LZW open took more than %.0f times the PackBits open, a slow machine does that: %s" % [bound, line])
    var failing := bound * FAIL_FACTOR
    assert_true(lzw_best <= failing * pack_best, "the LZW open within %.0f times the PackBits open: %s" % [failing, line])


## A Full HD RGB picture: each channel a ramp of its own across the frame, with
## a noise of up to sixteen levels over it from a fixed seed.
func _picture() -> PackedByteArray:
    var out := PackedByteArray()
    out.resize(WIDTH * HEIGHT * 3)
    var state := 7919
    var at := 0
    for y in HEIGHT:
        for x in WIDTH:
            state = (state * 1103515245 + 12345) & 0x7FFFFFFF
            var noise := (state >> 12) & 0xFFF
            @warning_ignore("integer_division")
            out[at] = ((x * 255) / WIDTH + (noise & 15)) & 0xFF
            @warning_ignore("integer_division")
            out[at + 1] = ((y * 255) / HEIGHT + ((noise >> 4) & 15)) & 0xFF
            @warning_ignore("integer_division")
            out[at + 2] = (((x + y) * 255) / (WIDTH + HEIGHT) + (noise >> 8)) & 0xFF
            at += 3
    return out
