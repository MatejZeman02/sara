## A sixteen-bit PNG reads, through `SaImageImport.read`, exactly the floats a
## decode written a byte at a time gives, every value of a 1920 by 1080 file
## whose scanlines carry all five of PNG's filters.
##
## The decode in `SaPng16Decode` undoes each filter in a loop of its own and
## scales the samples in bands on worker threads, which is what keeps a large
## picture from holding the window for seconds. Both are places a wrong index
## or a band's edge would move a value, so the reference here is the plain
## form, PNG's own arithmetic byte after byte and one sample at a time, and the
## two are compared value by value rather than by a sum.
##
## The file is made here rather than kept: its filtered bytes are arbitrary,
## which any bytes are for a valid stream, so they are tiled from a hash, and
## each scanline names the filter `y % 5`.
extends "res://tests/test_framework.gd"

## Where the suite writes the file it reads back, under the checkout's own
## `user://`, because it is one run's output and not a fixture to commit.
static var scratch_path: String = SaDataRoot.path("sixteen-bit-every-filter.png")

const WIDTH := 1920
const HEIGHT := 1080


func test_a_1920_by_1080_rgba_file_reads_the_same_floats_value_by_value() -> void:
    var channels := 4
    var raw := _filtered_stream(WIDTH, HEIGHT, channels)
    var file := FileAccess.open(scratch_path, FileAccess.WRITE)
    file.store_buffer(_png(raw, WIDTH, HEIGHT, SaImageImport.PNG_COLOUR_TYPE_RGBA))
    file.close()

    var started := Time.get_ticks_usec()
    var read := SaImageImport.read(scratch_path)
    var took := Time.get_ticks_usec() - started
    print("A 1920 by 1080 sixteen-bit RGBA PNG read in %.0f ms" % (took / 1000.0))
    assert_not_null(read, "The file reads")
    assert_eq(read.get_size(), Vector2i(WIDTH, HEIGHT), "at its own size")
    assert_eq(read.get_format(), Image.FORMAT_RGBAF, "in full floats")

    var expected := _reference(raw, WIDTH, HEIGHT, channels, SaImageImport.PNG_COLOUR_TYPE_RGBA)
    _assert_every_value(read.get_data().to_float32_array(), expected, "the RGBA file")


## The three other colour types fill what they lack, grey copied and alpha at
## one, and a band boundary falls inside each, so the widening is graded across
## the split as well as within a band.
func test_grey_grey_with_alpha_and_colour_read_the_same_floats_across_bands() -> void:
    var width := 24
    var height := SaPng16Decode.BAND_MIN_ROWS * 3 + 7
    for colour_type: int in [
        SaImageImport.PNG_COLOUR_TYPE_GREY,
        SaImageImport.PNG_COLOUR_TYPE_GREY_ALPHA,
        SaImageImport.PNG_COLOUR_TYPE_RGB,
    ]:
        var channels := SaPng16Decode.channels_of(colour_type)
        var raw := _filtered_stream(width, height, channels)
        var expected := _reference(raw, width, height, channels, colour_type)
        var got := SaPng16Decode.of(_png(raw, width, height, colour_type), _header(width, height, colour_type))
        assert_not_null(got, "Colour type %d reads" % colour_type)
        _assert_every_value(got.get_data().to_float32_array(), expected, "colour type %d" % colour_type)


## Every value of *got* against *expected*, as one assertion that names the
## first value that differs, since eight million assertions would be the log.
func _assert_every_value(got: PackedFloat32Array, expected: PackedFloat32Array, label: String) -> void:
    assert_eq(got.size(), expected.size(), "%s has a float for every value" % label)
    var first := -1
    if got != expected:
        for i in mini(got.size(), expected.size()):
            if got[i] != expected[i]:
                first = i
                break
    var where := "" if first < 0 else ", the first differing at value %d, %f against %f" % [first, got[first], expected[first]]
    assert_eq(first, -1, "%s gives every float the byte-at-a-time decode does%s" % [label, where])


## Scanlines of arbitrary filtered bytes, each led by the filter `y % 5`. The
## bytes are a block of hashes tiled at an offset that moves each line, so no
## two neighbouring lines repeat and nothing has to be made a byte at a time.
func _filtered_stream(width: int, height: int, channels: int) -> PackedByteArray:
    var block := PackedByteArray()
    var hashed := "sara sixteen bits".sha256_buffer()
    while block.size() < 4096:
        hashed = hashed.hex_encode().sha256_buffer()
        block.append_array(hashed)
    var line_bytes := width * channels * 2
    var tiled := PackedByteArray()
    while tiled.size() < line_bytes + block.size():
        tiled.append_array(block)
    var raw := PackedByteArray()
    for y in height:
        raw.append(y % 5)
        var offset := (y * 1237) % block.size()
        raw.append_array(tiled.slice(offset, offset + line_bytes))
    return raw


## A PNG of *raw* scanlines: the signature, a header, one `IDAT` and the end.
## The checksums are left at zero, which Sara's reader does not read.
func _png(raw: PackedByteArray, width: int, height: int, colour_type: int) -> PackedByteArray:
    var header := PackedByteArray()
    header.append_array(_u32(width))
    header.append_array(_u32(height))
    header.append_array(PackedByteArray([SaImageImport.PNG_SIXTEEN_BITS, colour_type, 0, 0, 0]))
    var out := PackedByteArray(SaImageImport.PNG_SIGNATURE)
    out.append_array(_chunk("IHDR", header))
    out.append_array(_chunk("IDAT", raw.compress(FileAccess.COMPRESSION_DEFLATE)))
    out.append_array(_chunk("IEND", PackedByteArray()))
    return out


func _header(width: int, height: int, colour_type: int) -> Dictionary[String, Variant]:
    return {
        "width": width,
        "height": height,
        "bit_depth": SaImageImport.PNG_SIXTEEN_BITS,
        "colour_type": colour_type,
        "compression": 0,
        "filter_method": 0,
        "interlace": 0,
    }


func _chunk(type: String, data: PackedByteArray) -> PackedByteArray:
    var out := _u32(data.size())
    out.append_array(type.to_ascii_buffer())
    out.append_array(data)
    out.append_array(_u32(0))
    return out


func _u32(value: int) -> PackedByteArray:
    return PackedByteArray([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])


## The plain decode: each byte unfiltered by PNG's rule with its neighbours
## read as the specification names them, then each sample over 65535 in
## double, stored in a float, a grey copied to three channels and a missing
## alpha at one. Slow on purpose, so it has no shortcut in common with the one
## it grades.
func _reference(filtered: PackedByteArray, width: int, height: int, channels: int, colour_type: int) -> PackedFloat32Array:
    var raw := filtered.duplicate()
    var pixel_bytes := channels * 2
    var stride := 1 + width * pixel_bytes
    for y in height:
        var line := y * stride
        var kind := raw[line]
        for i in width * pixel_bytes:
            var at := line + 1 + i
            var left := raw[at - pixel_bytes] if i >= pixel_bytes else 0
            var up := raw[at - stride] if y > 0 else 0
            var corner := raw[at - stride - pixel_bytes] if (y > 0 and i >= pixel_bytes) else 0
            var predicted := 0
            match kind:
                SaImageImport.PNG_FILTER_SUB:
                    predicted = left
                SaImageImport.PNG_FILTER_UP:
                    predicted = up
                SaImageImport.PNG_FILTER_AVERAGE:
                    predicted = (left + up) >> 1
                SaImageImport.PNG_FILTER_PAETH:
                    predicted = _paeth(left, up, corner)
            raw[at] = (raw[at] + predicted) & 0xFF
    var colour := colour_type == SaImageImport.PNG_COLOUR_TYPE_RGB or colour_type == SaImageImport.PNG_COLOUR_TYPE_RGBA
    var alpha := colour_type == SaImageImport.PNG_COLOUR_TYPE_GREY_ALPHA or colour_type == SaImageImport.PNG_COLOUR_TYPE_RGBA
    var out := PackedFloat32Array()
    out.resize(width * height * 4)
    var next := 0
    for y in height:
        for x in width:
            var at := y * stride + 1 + x * pixel_bytes
            var red := _sample(raw, at)
            out[next] = red
            out[next + 1] = _sample(raw, at + 2) if colour else red
            out[next + 2] = _sample(raw, at + 4) if colour else red
            out[next + 3] = _sample(raw, at + pixel_bytes - 2) if alpha else 1.0
            next += 4
    return out


func _sample(raw: PackedByteArray, at: int) -> float:
    return float(raw[at] * 256 + raw[at + 1]) / float(SaImageImport.PNG_SAMPLE_MAX)


## PNG's Paeth predictor walked over its three distances, left winning a tie,
## then above.
static func _paeth(left: int, up: int, corner: int) -> int:
    var estimate := left + up - corner
    var neighbours := [left, up, corner]
    var distances := [absi(estimate - left), absi(estimate - up), absi(estimate - corner)]
    var best := 0
    for i in 3:
        if distances[i] < distances[best]:
            best = i
    return neighbours[best]
