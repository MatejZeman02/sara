## A TIFF compressed with LZW or PackBits opens.
##
## The reader refused both by name, and LZW is what Photoshop's TIFF options
## offer first. Each picture here is written three ways, uncompressed and with
## the suite's own PackBits and LZW encoders, so the reader is checked against
## encoders that are not its own unpacker turned round, and each compressed file
## must read back byte for byte as its uncompressed twin does. The encoders
## follow TIFF 6.0: PackBits runs of at most 128, LZW most significant bit
## first with the early change, a clear code first and another before the table
## fills.
extends "res://tests/test_framework.gd"

const NONE: int = 1
const LZW: int = 5
const PACK_BITS: int = 32773

## Tags the hand-built files carry as LONG, the rest going in as SHORT.
const LONG_TAGS: Array[int] = [256, 257, 273, 278, 279]

var _problems: Array[String] = []


func before_each() -> void:
    _problems.clear()
    # A refusal is a push_error while it announces, and a deliberate one fails
    # the run, so the lines come to the suite instead.
    SaProblems.announce = false
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: _problems.append(line))
    _problems.clear()


func after_each() -> void:
    SaProblems.detach_sink()
    SaProblems.announce = true


# --- Each scheme reads back as its uncompressed twin -------------------------------


func test_an_rgb_and_a_grey_picture_in_each_scheme_read_back_as_written_plain() -> void:
    var checked := 0
    for samples: int in [3, 1]:
        var raw := _picture(13, 9, samples, 1, 0)
        for compression: int in [PACK_BITS, LZW]:
            for rows_per_strip: int in [9, 2]:
                for predicted: bool in [false, true]:
                    _same_as_plain(raw, 13, 9, samples, 8, compression, rows_per_strip, predicted)
                    checked += 1
    assert_eq(checked, 16, "two pictures, two schemes, one strip and many, with and without the predictor")


## Sixty by fifty of noise is 9000 bytes, enough for LZW's codes to grow to
## twelve bits and for the table to fill and be cleared, and sixteen bits a
## sample in big-endian order is where the swap and the predictor must agree.
func test_a_large_noisy_picture_and_a_sixteen_bit_one_read_back() -> void:
    var noise := _picture(60, 50, 3, 1, 7919)
    for compression: int in [PACK_BITS, LZW]:
        _same_as_plain(noise, 60, 50, 3, 8, compression, 50, false)
        _same_as_plain(noise, 60, 50, 3, 8, compression, 7, true)
    var deep := _picture(9, 6, 4, 2, 31)
    for compression: int in [PACK_BITS, LZW]:
        _same_as_plain(deep, 9, 6, 4, 16, compression, 4, true, true)


# --- What does not unpack is damaged, and says so ----------------------------------


func test_a_packbits_strip_running_past_its_end_is_damaged_and_named() -> void:
    var fields := {256: [4], 257: [1], 258: [8], 259: [PACK_BITS], 262: [1], 277: [1]}
    assert_null(SaTiffReader.new(_tiff(fields, [PackedByteArray([5, 1, 2])]), "runs-past.tif").picture(), "A cut run is not read")
    _assert_damaged("runs-past.tif", "PackBits pixels are damaged")


func test_an_lzw_strip_naming_a_code_the_table_lacks_is_damaged_and_named() -> void:
    var fields := {256: [4], 257: [1], 258: [8], 259: [LZW], 262: [1], 277: [1]}
    var codes := _codes_at_nine_bits([256, 65, 300, 257])
    assert_null(SaTiffReader.new(_tiff(fields, [codes]), "bad-code.tif").picture(), "An unknown code is not read")
    _assert_damaged("bad-code.tif", "LZW pixels are damaged")


func test_a_strip_unpacking_to_fewer_or_more_bytes_than_its_rows_is_damaged() -> void:
    var fields := {256: [4], 257: [2], 258: [8], 259: [PACK_BITS], 262: [1], 277: [1], 278: [1]}
    var short := [_pack_bits(PackedByteArray([1, 2])), _pack_bits(PackedByteArray([3, 4, 5, 6]))]
    assert_null(SaTiffReader.new(_tiff(fields, short), "short.tif").picture(), "A short strip is not read")
    _assert_damaged("short.tif", "fewer bytes than their rows")
    var long := [_pack_bits(PackedByteArray([1, 2, 3, 4, 5, 6])), _pack_bits(PackedByteArray([3, 4, 5, 6]))]
    _problems.clear()
    assert_null(SaTiffReader.new(_tiff(fields, long), "long.tif").picture(), "A long strip is not read")
    _assert_damaged("long.tif", "PackBits pixels are damaged")
    fields[259] = [LZW]
    var lzw_long := [_lzw(PackedByteArray([1, 2, 3, 4, 5, 6])), _lzw(PackedByteArray([3, 4, 5, 6]))]
    _problems.clear()
    assert_null(SaTiffReader.new(_tiff(fields, lzw_long), "lzw-long.tif").picture(), "A long LZW strip is not read")
    _assert_damaged("lzw-long.tif", "LZW pixels are damaged")


func test_an_lzw_file_with_the_floating_point_predictor_is_still_refused() -> void:
    var fields := {256: [1], 257: [1], 258: [32], 259: [LZW], 262: [1], 277: [1], 317: [3], 339: [3]}
    var strip := _lzw(PackedByteArray([0, 0, 128, 63]))
    assert_null(SaTiffReader.new(_tiff(fields, [strip]), "float-lzw.tif").picture(), "The float predictor is not read")
    var line := _problems[0] if not _problems.is_empty() else ""
    assert_true(line.contains("the floating point predictor") and line.contains("does not read yet"), "and is named: %s" % line)


# --- Helpers ------------------------------------------------------------------------


## Writes *raw* plain and compressed with *compression*, reads both and checks
## the compressed one comes back byte for byte as the plain one did.
func _same_as_plain(
    raw: PackedByteArray,
    width: int,
    height: int,
    samples: int,
    bits: int,
    compression: int,
    rows_per_strip: int,
    predicted: bool,
    big: bool = false
) -> void:
    var size := bits >> 3
    var row_bytes := width * samples * size
    var stored := _swapped(raw, size) if big else raw
    var bits_field := []
    for i in samples:
        bits_field.append(bits)
    var fields := {
        256: [width], 257: [height], 258: bits_field, 262: [2 if samples >= 3 else 1], 277: [samples], 278: [rows_per_strip]
    }
    if samples == 4:
        fields[338] = [2]
    var plain_strips := []
    var packed_strips := []
    var differenced := _differenced(raw, width, samples, size)
    for top in range(0, height, rows_per_strip):
        var end := mini(top + rows_per_strip, height) * row_bytes
        plain_strips.append(stored.slice(top * row_bytes, end))
        var strip := differenced.slice(top * row_bytes, end) if predicted else raw.slice(top * row_bytes, end)
        if big:
            strip = _swapped(strip, size)
        packed_strips.append(_pack_bits(strip) if compression == PACK_BITS else _lzw(strip))
    var label := (
        "%s, %d channel%s, %d bit, %d rows a strip%s"
        % [
            "PackBits" if compression == PACK_BITS else "LZW",
            samples,
            "" if samples == 1 else "s",
            bits,
            rows_per_strip,
            ", predicted" if predicted else "",
        ]
    )
    var plain_fields: Dictionary = fields.duplicate()
    plain_fields[259] = [NONE]
    var plain := SaTiffReader.new(_tiff(plain_fields, plain_strips, big), "plain.tif").picture()
    fields[259] = [compression]
    if predicted:
        fields[317] = [2]
    var packed := SaTiffReader.new(_tiff(fields, packed_strips, big), "packed.tif").picture()
    assert_not_null(plain, "%s: the plain twin opens" % label)
    assert_not_null(packed, "%s: opens" % label)
    if plain == null or packed == null:
        return
    assert_eq(packed.get_size(), plain.get_size(), "%s: at the plain twin's size" % label)
    assert_eq(packed.get_format(), plain.get_format(), "%s: in its format" % label)
    assert_true(packed.get_data() == plain.get_data(), "%s: every pixel equal to the plain twin's" % label)
    assert_true(_problems.is_empty(), "%s: with nothing to report: %s" % [label, _problems])


## A picture of *width* by *height* pixels of *samples* samples, each *size*
## bytes little-endian. Flat runs and steps for PackBits to find, then a stretch
## of noise from *from_seed* so literals and long LZW strings both turn up.
func _picture(width: int, height: int, samples: int, size: int, from_seed: int) -> PackedByteArray:
    var out := PackedByteArray()
    var state := from_seed
    for y in height:
        for x in width:
            for s in samples:
                var value: int
                if from_seed == 0 and x < width >> 1:
                    value = (y * 37 + s * 90) & 0xFF
                else:
                    state = (state * 1103515245 + 12345) & 0x7FFFFFFF
                    value = (state >> 8) & (0xFF if from_seed == 0 or from_seed % 2 == 1 else 0x3F)
                for b in size:
                    out.append((value * (b * 7 + 1)) & 0xFF)
    return out


## *raw* with TIFF's horizontal differencing applied, in little-endian samples
## of *size* bytes.
func _differenced(raw: PackedByteArray, width: int, samples: int, size: int) -> PackedByteArray:
    var out := raw.duplicate()
    var step := samples * size
    var row_bytes := width * step
    var mask := (1 << (8 * size)) - 1
    for row in range(0, raw.size(), row_bytes):
        for at in range(row + step, row + row_bytes, size):
            var here := 0
            var left := 0
            for b in size:
                here |= raw[at + b] << (8 * b)
                left |= raw[at - step + b] << (8 * b)
            var difference := (here - left) & mask
            for b in size:
                out[at + b] = (difference >> (8 * b)) & 0xFF
    return out


## *raw* with each sample of *size* bytes turned round.
func _swapped(raw: PackedByteArray, size: int) -> PackedByteArray:
    var out := raw.duplicate()
    for at in range(0, raw.size(), size):
        for b in size:
            out[at + b] = raw[at + size - 1 - b]
    return out


## *raw* in PackBits: a run of three or more equal bytes as a repeat, at most
## 128 long, and what lies between as literals of at most 128.
func _pack_bits(raw: PackedByteArray) -> PackedByteArray:
    var out := PackedByteArray()
    var at := 0
    var literal := PackedByteArray()
    while at < raw.size():
        var run := 1
        while at + run < raw.size() and run < 128 and raw[at + run] == raw[at]:
            run += 1
        if run >= 3:
            _flush_literal(out, literal)
            out.append(257 - run)
            out.append(raw[at])
            at += run
            continue
        literal.append(raw[at])
        at += 1
        if literal.size() == 128:
            _flush_literal(out, literal)
    _flush_literal(out, literal)
    return out


func _flush_literal(out: PackedByteArray, literal: PackedByteArray) -> void:
    if literal.is_empty():
        return
    out.append(literal.size() - 1)
    out.append_array(literal)
    literal.clear()


## *raw* in TIFF's LZW: a clear code first, strings found in a dictionary keyed
## by the prefix's code and the next byte, codes widening when the next entry
## reaches the width's limit, which sits one entry past the decoder's because
## the decoder makes each entry one code later, and a clear before the table's
## last two entries, as libtiff writes.
func _lzw(raw: PackedByteArray) -> PackedByteArray:
    var writer := _BitWriter.new()
    var width := 9
    var next := 258
    var table := {}
    writer.put(256, width)
    var current := -1
    for byte in raw:
        if current < 0:
            current = byte
            continue
        var key := current * 256 + byte
        if table.has(key):
            current = table[key]
            continue
        writer.put(current, width)
        table[key] = next
        next += 1
        if next >= (1 << width) and width < 12:
            width += 1
        if next >= 4094:
            writer.put(256, width)
            table.clear()
            next = 258
            width = 9
        current = byte
    if current >= 0:
        writer.put(current, width)
        next += 1
        if next >= (1 << width) and width < 12:
            width += 1
    writer.put(257, width)
    return writer.finished()


## *codes* written nine bits each, for a strip the encoder would never make.
func _codes_at_nine_bits(codes: Array) -> PackedByteArray:
    var writer := _BitWriter.new()
    for code: int in codes:
        writer.put(code, 9)
    return writer.finished()


func _assert_damaged(name: String, clause: String) -> void:
    var line := _problems[0] if not _problems.is_empty() else ""
    assert_true(line.contains("Could not read '%s'" % name), "naming the file as unreadable: %s" % line)
    assert_true(line.contains(clause), "saying %s: %s" % [clause, line])
    assert_false(line.contains("does not read yet"), "rather than as a scheme Sara has yet to learn: %s" % line)


## A whole TIFF: *fields* by tag, each a list of values, and *strips* the pixel
## strips, whose offsets and byte counts are worked out here, the same builder
## `test_sara_opens_tiff.gd` uses.
func _tiff(fields: Dictionary, strips: Array, big: bool = false) -> PackedByteArray:
    var all: Dictionary = fields.duplicate()
    var counts: Array = []
    for strip: PackedByteArray in strips:
        counts.append(strip.size())
    all[273] = counts.duplicate()
    all[279] = counts
    var tags: Array = all.keys()
    tags.sort()
    var at := 8 + 2 + tags.size() * 12 + 4
    var placed := {}
    for tag: int in tags:
        var length := (all[tag] as Array).size() * (4 if LONG_TAGS.has(tag) else 2)
        if length > 4:
            placed[tag] = at
            at += length
    var offsets: Array = []
    for strip: PackedByteArray in strips:
        offsets.append(at)
        at += strip.size()
    all[273] = offsets

    var out := ("MM" if big else "II").to_ascii_buffer()
    _put(out, 42, 2, big)
    _put(out, 8, 4, big)
    _put(out, tags.size(), 2, big)
    for tag: int in tags:
        var values: Array = all[tag]
        var width := 4 if LONG_TAGS.has(tag) else 2
        _put(out, tag, 2, big)
        _put(out, 4 if width == 4 else 3, 2, big)
        _put(out, values.size(), 4, big)
        if placed.has(tag):
            _put(out, placed[tag], 4, big)
            continue
        var field := PackedByteArray()
        for value: int in values:
            _put(field, value, width, big)
        while field.size() < 4:
            field.append(0)
        out.append_array(field)
    _put(out, 0, 4, big)
    for tag: int in tags:
        if placed.has(tag):
            for value: int in all[tag]:
                _put(out, value, 4 if LONG_TAGS.has(tag) else 2, big)
    for strip: PackedByteArray in strips:
        out.append_array(strip)
    return out


func _put(into: PackedByteArray, value: int, width: int, big: bool) -> void:
    for i in width:
        var shift := 8 * (width - 1 - i) if big else 8 * i
        into.append((value >> shift) & 0xFF)


## Codes packed most significant bit first, the order TIFF's LZW reads.
class _BitWriter:
    var _bytes := PackedByteArray()
    var _held := 0
    var _count := 0

    func put(code: int, width: int) -> void:
        _held = (_held << width) | code
        _count += width
        while _count >= 8:
            _count -= 8
            _bytes.append((_held >> _count) & 0xFF)
        _held &= (1 << _count) - 1

    ## Everything put, the last byte filled out with zeros.
    func finished() -> PackedByteArray:
        var out := _bytes.duplicate()
        if _count > 0:
            out.append((_held << (8 - _count)) & 0xFF)
        return out
