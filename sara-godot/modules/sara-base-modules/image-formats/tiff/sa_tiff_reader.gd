## A TIFF read into a picture, the partner of `SaExportTiff`, so the file Sara
## offers as an export comes back in through File > Open, Import Picture and a
## drop.
##
## Godot has no TIFF decoder, so the reader is Sara's own. It reads the first
## image of the file in either byte order: greys or RGB with or without an
## alpha, eight or sixteen bits of unsigned integer or thirty-two of float,
## uncompressed, Deflate, LZW or PackBits, in one strip or many. LZW and PackBits
## are unpacked by [SaTiffUnpacker].
##
## **Integers become fractions and floats stay floats.** Eight bits come back as
## `FORMAT_RGBA8`, sixteen as `FORMAT_RGBAF` over the full range, and thirty-two
## bit floats are left as they are, negatives and values above one included,
## which is the no-clamp guarantee the float export makes.
##
## **What it does not read, it names.** JPEG and the other compressions, tiles,
## BigTIFF, a palette, CMYK, YCbCr, Lab and planar channels are refused through
## `SaProblems` with a sentence saying what the file is. A file whose numbers
## point past its own end is refused as unreadable.
##
## The ICC profile in tag 34675 names the gamut, and a TIFF with no profile, or
## one the profile reader refuses, is read as sRGB, which is what a reader
## assumes of an unlabelled TIFF.
##
## **The per-sample passes run in native code when they can.** Byte swapping,
## undoing the predictor, scaling and straightening an associated alpha touch
## every sample, and in GDScript a 6000 by 4000 sixteen-bit photograph held the
## window for 6.3 s. `SaTiffSamples` in the `tiff-lzw` library makes the same
## passes with the same arithmetic, found through `ClassDB`, and the GDScript
## below is the fallback, so a file reads to the same floats either way.
class_name SaTiffReader
extends RefCounted

## The header's first two bytes, `II` for little-endian and `MM` for big, read
## the same either way round because both bytes of each are equal.
const ORDER_LITTLE: int = 0x4949
const ORDER_BIG: int = 0x4D4D
## The version a classic TIFF names, and the one BigTIFF names instead.
const VERSION_CLASSIC: int = 42
const VERSION_BIG: int = 43
const HEADER_BYTES: int = 8
const ENTRY_BYTES: int = 12

## The field types a tag read here comes in, and what one value of each costs.
## Any other type on one of these tags is a field this reader skips.
const TYPE_BYTE: int = 1
const TYPE_SHORT: int = 3
const TYPE_LONG: int = 4
const TYPE_UNDEFINED: int = 7
const TYPE_BYTES := {TYPE_BYTE: 1, TYPE_SHORT: 2, TYPE_LONG: 4, TYPE_UNDEFINED: 1}

const TAG_IMAGE_WIDTH: int = 256
const TAG_IMAGE_LENGTH: int = 257
const TAG_BITS_PER_SAMPLE: int = 258
const TAG_COMPRESSION: int = 259
const TAG_PHOTOMETRIC: int = 262
const TAG_STRIP_OFFSETS: int = 273
const TAG_SAMPLES_PER_PIXEL: int = 277
const TAG_ROWS_PER_STRIP: int = 278
const TAG_STRIP_BYTE_COUNTS: int = 279
const TAG_PLANAR_CONFIG: int = 284
const TAG_PREDICTOR: int = 317
## Read only to say the file is tiled, which this reader does not unpack.
const TAG_TILE_WIDTH: int = 322
const TAG_TILE_OFFSETS: int = 324
const TAG_EXTRA_SAMPLES: int = 338
const TAG_SAMPLE_FORMAT: int = 339
const TAG_ICC_PROFILE: int = 34675
## Every tag the directory walk keeps. The rest of a directory, text, dates and
## resolutions, says nothing about the pixels.
const READ_TAGS: Array[int] = [
    TAG_IMAGE_WIDTH,
    TAG_IMAGE_LENGTH,
    TAG_BITS_PER_SAMPLE,
    TAG_COMPRESSION,
    TAG_PHOTOMETRIC,
    TAG_STRIP_OFFSETS,
    TAG_SAMPLES_PER_PIXEL,
    TAG_ROWS_PER_STRIP,
    TAG_STRIP_BYTE_COUNTS,
    TAG_PLANAR_CONFIG,
    TAG_PREDICTOR,
    TAG_TILE_WIDTH,
    TAG_TILE_OFFSETS,
    TAG_EXTRA_SAMPLES,
    TAG_SAMPLE_FORMAT,
    TAG_ICC_PROFILE,
]

const COMPRESSION_NONE: int = 1
## Adobe's Deflate and the older number for the same stream, both zlib framed,
## which is what `PackedByteArray.decompress` unpacks.
const COMPRESSION_DEFLATE: int = 8
const COMPRESSION_DEFLATE_OLD: int = 32946
## The two baseline schemes [SaTiffUnpacker] unpacks.
const COMPRESSION_LZW: int = SaTiffUnpacker.LZW
const COMPRESSION_PACK_BITS: int = SaTiffUnpacker.PACK_BITS
## What the compressions this does not unpack are called, so the refusal names
## the one the file uses.
const COMPRESSION_NAMES := {
    2: "CCITT run-length coding",
    3: "CCITT fax coding",
    4: "CCITT fax coding",
    6: "JPEG",
    7: "JPEG",
    34712: "JPEG 2000",
    34925: "LZMA",
    50000: "Zstandard",
    50001: "WebP",
}

const PHOTOMETRIC_BLACK_IS_ZERO: int = 1
const PHOTOMETRIC_RGB: int = 2
## How the other photometric interpretations hold their colours, for the same
## refusal.
const PHOTOMETRIC_NAMES := {
    0: "greys with white at zero",
    3: "a palette",
    4: "a transparency mask",
    5: "CMYK",
    6: "YCbCr",
    8: "CIE Lab",
    9: "ICC Lab",
    10: "ITU Lab",
    32844: "LogL",
    32845: "LogLuv",
}

const PLANAR_CHUNKY: int = 1
const PREDICTOR_NONE: int = 1
const PREDICTOR_HORIZONTAL: int = 2
const PREDICTOR_FLOAT: int = 3
## Alpha that has been multiplied into the colour, which Sara divides back out
## because a chunk holds a straight colour. Unassociated and unspecified alpha
## are read as straight, which is what `SaExportTiff` writes.
const EXTRA_ASSOCIATED_ALPHA: int = 1
const SAMPLE_FORMAT_UINT: int = 1
const SAMPLE_FORMAT_INT: int = 2
const SAMPLE_FORMAT_FLOAT: int = 3

## What a stored 1.0 is at each integer depth, the numbers `SaExportTiff` and
## `SaPng16Writer` write against, read the other way.
const EIGHT_MAX: float = 255.0
const SIXTEEN_MAX: float = 65535.0
## The native sample passes' class, asked for by name.
const LIBRARY := &"SaTiffSamples"

## The ICC profile tag 34675 carries, empty when the file has none. Read by
## [method space_of].
var profile := PackedByteArray()

var _bytes: PackedByteArray
## The name the painter knows the file by, which every refusal starts with.
var _source: String
var _big := false
## The first directory's fields this reader keeps, by tag, their values as
## integers.
var _fields: Dictionary[int, PackedInt64Array] = {}
var _width := 0
var _height := 0
## Samples a pixel, the colour and any extras after it.
var _samples := 1
var _bits := 8
## RGB rather than grey.
var _colour := false
var _associated := false
var _deflate := false
## LZW or PackBits, which [SaTiffUnpacker] unpacks, 0 for any other file.
var _unpacked := 0
var _predicted := false
## Why [method picture] cannot build the picture, as the whole sentence the
## painter reads, "" while it can.
var _reason := ""
## The class the sample passes run in, `SaTiffSamples`, or empty when Godot
## has none by the name asked for and the GDScript runs them.
var _library := &""


## Reads the header and the first directory of *bytes*, which *source* names.
## Nothing is reported until [method picture] is asked, so a caller after the
## profile alone reads a file it cannot decode in silence. *library* names the
## native sample passes' class, and a name Godot has no class for is how a
## suite reads through the GDScript.
func _init(bytes: PackedByteArray, source: String, library: StringName = LIBRARY) -> void:
    _bytes = bytes
    _source = source
    if ClassDB.class_exists(library):
        _library = library
    _reason = _read_directory()
    if _reason.is_empty():
        _reason = _read_layout()


## The TIFF at *path* as a picture, or null with the reason reported.
static func read(path: String) -> Image:
    return SaTiffReader.new(FileAccess.get_file_as_bytes(path), path).picture()


## The space the TIFF at *path* was written in. See [method space_of].
static func space_at(path: String) -> SaColorSpace:
    return space_of(SaTiffReader.new(FileAccess.get_file_as_bytes(path), path).profile)


## The space the TIFF at *path* names in its own profile, or null when it names
## none Sara knows. See [method named_space_of].
static func named_space_at(path: String) -> SaColorSpace:
    return named_space_of(SaTiffReader.new(FileAccess.get_file_as_bytes(path), path).profile)


## The ICC profile the TIFF at *path* carries in tag 34675, empty when it has
## none. Sara reads a profile from elsewhere through
## [member SaImageFormat.embedded_profile], primaries, white and curve, or says
## why it cannot, so a TIFF from a camera's raw converter in Adobe RGB opens in
## Adobe RGB.
static func profile_at(path: String) -> PackedByteArray:
    return SaTiffReader.new(FileAccess.get_file_as_bytes(path), path).profile


## sRGB's curve with the gamut *icc* names, when its bytes are one of the
## profiles Sara's exports write, and sRGB otherwise.
##
## Equal bytes rather than a parse of the profile's primaries, because the
## question here is whether Sara wrote it, which answers before any reading. A
## profile from elsewhere is read by [method profile_at]'s reader, which takes
## its curve and refuses a table.
static func space_of(icc: PackedByteArray) -> SaColorSpace:
    var named := named_space_of(icc)
    return named if named != null else SaColorSpace.srgb()


## What [method space_of] answers when it has a profile to go on, and null when
## it has none. The two cases look the same in `space_of`'s answer, sRGB, and
## the Import Fit window has to tell a file that said sRGB from one that said
## nothing.
static func named_space_of(icc: PackedByteArray) -> SaColorSpace:
    if icc.is_empty():
        return null
    return SaPictureFile.space_of_profile(icc)


## The sentence the painter reads when the file is refused, translated whole
## where the reason was found, so there is nothing more to look up, and empty
## while the file reads. `refusal` is the name the refusal sweep reads as a sentence
## already translated.
func refusal() -> String:
    return _reason.strip_edges()


## The picture, as `FORMAT_RGBA8` for eight bits and `FORMAT_RGBAF` for
## sixteen and thirty-two, or null with the reason reported.
##
## Two kinds of sentence, each a message of its own so a language can order its
## words as it needs. One is for a file Sara chooses not to read, "'x.tif' is
## compressed with JPEG, which Sara does not read yet.", and the other for a
## file whose numbers do not hold together, "Could not read 'x.tif' as an image
## because it names no picture size."
func picture() -> Image:
    var image := _decoded() if _reason.is_empty() else null
    if image != null:
        return image
    SaProblems.refuse("SaTiffReader", self.refusal())
    return null


## The header and the first directory, or the refusal they earn. Fields this
## reader keeps go into `_fields` and the profile into `profile`.
func _read_directory() -> String:
    if _bytes.size() < HEADER_BYTES:
        return _broken("Could not read '%s' as an image because it is shorter than a TIFF's header.")
    var order := _bytes.decode_u16(0)
    if order != ORDER_LITTLE and order != ORDER_BIG:
        return _broken("Could not read '%s' as an image because it does not begin as a TIFF does.")
    _big = order == ORDER_BIG
    var version := _u16(2)
    if version == VERSION_BIG:
        return _unread("'%s' is a BigTIFF, which Sara does not read yet.")
    if version != VERSION_CLASSIC:
        return _broken("Could not read '%s' as an image because it does not begin as a TIFF does.")
    var at := _u32(4)
    if at + 2 > _bytes.size() or at + 2 + _u16(at) * ENTRY_BYTES > _bytes.size():
        return _broken("Could not read '%s' as an image because its directory points past the end of the file.")
    for i in _u16(at):
        var entry := at + 2 + i * ENTRY_BYTES
        var tag := _u16(entry)
        var type := _u16(entry + 2)
        if not READ_TAGS.has(tag) or not TYPE_BYTES.has(type):
            continue
        var count := _u32(entry + 4)
        var length: int = count * TYPE_BYTES[type]
        # A value of four bytes or fewer sits in the entry itself, and anything
        # longer is somewhere else in the file with its offset here.
        var where := entry + 8 if length <= 4 else _u32(entry + 8)
        if where + length > _bytes.size():
            return _broken("Could not read '%s' as an image because its directory points past the end of the file.")
        if tag == TAG_ICC_PROFILE:
            profile = _bytes.slice(where, where + length)
        else:
            _fields[tag] = _integers(type, where, count)
    return ""


## The shape of the pixels the directory names, or the refusal it earns. Every
## field a baseline reader may assume is defaulted the way TIFF 6.0 says.
func _read_layout() -> String:
    _width = _field(TAG_IMAGE_WIDTH, 0)
    _height = _field(TAG_IMAGE_LENGTH, 0)
    if _width <= 0 or _height <= 0:
        return _broken("Could not read '%s' as an image because it names no picture size.")
    if _fields.has(TAG_TILE_WIDTH) or _fields.has(TAG_TILE_OFFSETS):
        return _unread("'%s' is stored in tiles, which Sara does not read yet.")
    var compression := _field(TAG_COMPRESSION, COMPRESSION_NONE)
    _deflate = compression == COMPRESSION_DEFLATE or compression == COMPRESSION_DEFLATE_OLD
    if compression == COMPRESSION_LZW or compression == COMPRESSION_PACK_BITS:
        _unpacked = compression
    if not _deflate and _unpacked == 0 and compression != COMPRESSION_NONE:
        if COMPRESSION_NAMES.has(compression):
            return _unread("'%s' is compressed with %s, which Sara does not read yet.", [COMPRESSION_NAMES[compression]])
        return _unread("'%s' is compressed with method %s, which Sara does not read yet.", [compression])
    _samples = _field(TAG_SAMPLES_PER_PIXEL, 1)
    # A file that names no interpretation is read by its samples, which is what
    # every reader that opens one does.
    var photometric := _field(TAG_PHOTOMETRIC, PHOTOMETRIC_RGB if _samples >= 3 else PHOTOMETRIC_BLACK_IS_ZERO)
    if photometric != PHOTOMETRIC_RGB and photometric != PHOTOMETRIC_BLACK_IS_ZERO:
        return _photometric_refusal(photometric)
    _colour = photometric == PHOTOMETRIC_RGB
    if _samples > 1 and _field(TAG_PLANAR_CONFIG, PLANAR_CHUNKY) != PLANAR_CHUNKY:
        return _unread("'%s' keeps each channel in a plane of its own, which Sara does not read yet.")
    if _samples < _base():
        return _broken("Could not read '%s' as an image because it carries fewer samples a pixel than its colours need.")
    _bits = _shared(TAG_BITS_PER_SAMPLE, 1)
    if _bits < 0:
        return _unread("'%s' carries samples of different widths, which Sara does not read yet.")
    var why := _sample_refusal(_shared(TAG_SAMPLE_FORMAT, SAMPLE_FORMAT_UINT))
    if not why.is_empty():
        return why
    var predictor := _field(TAG_PREDICTOR, PREDICTOR_NONE)
    if predictor == PREDICTOR_FLOAT:
        return _unread("'%s' uses the floating point predictor, which Sara does not read yet.")
    if predictor != PREDICTOR_NONE and predictor != PREDICTOR_HORIZONTAL:
        return _unread("'%s' names predictor %s, which Sara does not read yet.", [predictor])
    _predicted = predictor == PREDICTOR_HORIZONTAL
    _associated = _samples > _base() and _field(TAG_EXTRA_SAMPLES, 0) == EXTRA_ASSOCIATED_ALPHA
    if not _fields.has(TAG_STRIP_OFFSETS):
        return _broken("Could not read '%s' as an image because it holds no strip of pixels.")
    return ""


## The refusal for a sample of *kind* at `_bits` that cannot be read, or "" when
## it can: eight or sixteen bits unsigned, or thirty-two of float.
func _sample_refusal(kind: int) -> String:
    match kind:
        SAMPLE_FORMAT_UINT:
            if _bits == 8 or _bits == 16:
                return ""
            return _unread("'%s' carries %s-bit integer samples, which Sara does not read yet.", [_bits])
        SAMPLE_FORMAT_FLOAT:
            if _bits == 32:
                return ""
            return _unread("'%s' carries %s-bit float samples, which Sara does not read yet.", [_bits])
        SAMPLE_FORMAT_INT:
            return _unread("'%s' carries signed integer samples, which Sara does not read yet.")
        -1:
            return _unread("'%s' carries samples of different kinds, which Sara does not read yet.")
    return _unread("'%s' names sample format %s, which Sara does not read yet.", [kind])


## The picture out of the strips, or null with `_reason` saying why.
func _decoded() -> Image:
    var raw := _strips()
    if raw.is_empty():
        return null
    var size := _bits >> 3
    if not _library.is_empty():
        raw = ClassDB.class_call_static(_library, &"undone", raw, _width, _height, _samples, size, _big, _predicted)
    else:
        if _big and size > 1:
            _swap(raw, size)
        if _predicted:
            _undo_predictor(raw, size)
    if _bits == 8:
        return _byte_image(raw)
    # Little-endian by now whatever the file was, which is the order
    # `to_float32_array` reads in on every machine Sara is built for.
    return _float_image(raw.to_float32_array() if _bits == 32 else _sixteen(raw))


## The refusal for a photometric interpretation this reader does not read. The
## colour models named by their standard names keep them in every language, and
## the three that are described in words are sentences of their own.
func _photometric_refusal(photometric: int) -> String:
    match photometric:
        0:
            return _unread("'%s' holds its greys with white at zero, which Sara does not read yet.")
        3:
            return _unread("'%s' holds its colours in a palette, which Sara does not read yet.")
        4:
            return _unread("'%s' holds a transparency mask, which Sara does not read yet.")
    if PHOTOMETRIC_NAMES.has(photometric):
        return _unread("'%s' holds its colours as %s, which Sara does not read yet.", [PHOTOMETRIC_NAMES[photometric]])
    return _unread("'%s' holds its colours as interpretation %s, which Sara does not read yet.", [photometric])


## Every row of the picture, unpacked and in order, or empty with `_reason`
## saying why.
##
## A strip holds `RowsPerStrip` rows and the last one what is left, and a
## compressed strip is unpacked to at most a whole strip's worth, so a stream
## that claims to be larger than its strip is refused rather than allocated. An
## LZW or PackBits strip is held to the rows it carries: fewer bytes or more is
## a damaged file. The last strip alone may run to a whole strip's worth,
## because a writer may pad it, and the rows past the picture are dropped.
func _strips() -> PackedByteArray:
    var row_bytes := _width * _samples * (_bits >> 3)
    var rows_per_strip := _field(TAG_ROWS_PER_STRIP, _height)
    if rows_per_strip <= 0 or rows_per_strip > _height:
        rows_per_strip = _height
    var offsets: PackedInt64Array = _fields[TAG_STRIP_OFFSETS]
    var counts: PackedInt64Array = _fields.get(TAG_STRIP_BYTE_COUNTS, PackedInt64Array())
    var out := PackedByteArray()
    for strip in offsets.size():
        var rows := mini(rows_per_strip, _height - strip * rows_per_strip)
        if rows <= 0:
            break
        var wanted := rows * row_bytes
        # An uncompressed file that leaves the counts out has said them anyway,
        # through its size and its depth.
        var length := counts[strip] if strip < counts.size() else (wanted if _plain() else 0)
        var start := offsets[strip]
        if length <= 0 or start + length > _bytes.size():
            _reason = _broken("Could not read '%s' as an image because its pixels end before the picture does.")
            return PackedByteArray()
        var piece := _bytes.slice(start, start + length)
        if _deflate:
            piece = piece.decompress_dynamic(rows_per_strip * row_bytes, FileAccess.COMPRESSION_DEFLATE)
        elif _unpacked != 0:
            var last := strip == offsets.size() - 1 or rows < rows_per_strip
            var unpacker := SaTiffUnpacker.new(piece, _unpacked, rows_per_strip * row_bytes if last else wanted)
            if not unpacker.fault.is_empty():
                _reason = _unpack_refusal()
                return PackedByteArray()
            piece = unpacker.bytes
            if piece.size() < wanted:
                _reason = _broken(
                    "Could not read '%s' as an image because its compressed pixels unpack to fewer bytes than their rows."
                )
                return PackedByteArray()
        if piece.size() < wanted:
            if _plain():
                _reason = _broken("Could not read '%s' as an image because its pixels end before the picture does.")
            else:
                _reason = _broken("Could not read '%s' as an image because its compressed pixels do not unpack.")
            return PackedByteArray()
        out.append_array(piece.slice(0, wanted))
    if out.size() != _height * row_bytes:
        _reason = _broken("Could not read '%s' as an image because its strips hold fewer rows than the picture.")
        return PackedByteArray()
    return out


## Whether the strips hold their pixels as they are, so a missing byte count
## can be worked out from the picture.
func _plain() -> bool:
    return not _deflate and _unpacked == 0


## Big-endian samples of *size* bytes turned little-endian in place.
func _swap(raw: PackedByteArray, size: int) -> void:
    for at in range(0, raw.size(), size):
        for i in size >> 1:
            var first := raw[at + i]
            raw[at + i] = raw[at + size - 1 - i]
            raw[at + size - 1 - i] = first


## TIFF's horizontal differencing undone in place: each sample was stored as its
## difference from the same sample of the pixel to its left, wrapping at its
## own width, so one pass left to right adds them back. A float file is
## differenced as integers of the same width, which is what libtiff writes.
##
## One loop a width rather than one loop asking the width of every sample,
## because this is the slowest pass a Deflate file takes: a 1920 by 1080 RGB
## file from `magick` took 812 ms with the question inside the loop and 279
## without it.
func _undo_predictor(raw: PackedByteArray, size: int) -> void:
    var row_bytes := _width * _samples * size
    var step := _samples * size
    for y in _height:
        var row := y * row_bytes
        if size == 1:
            for at in range(row + step, row + row_bytes):
                raw[at] = (raw[at] + raw[at - step]) & 0xFF
        elif size == 2:
            for at in range(row + step, row + row_bytes, 2):
                raw.encode_u16(at, (raw.decode_u16(at) + raw.decode_u16(at - step)) & 0xFFFF)
        else:
            for at in range(row + step, row + row_bytes, 4):
                raw.encode_u32(at, (raw.decode_u32(at) + raw.decode_u32(at - step)) & 0xFFFFFFFF)


## Sixteen-bit samples as fractions of their full range.
func _sixteen(raw: PackedByteArray) -> PackedFloat32Array:
    if not _library.is_empty():
        return ClassDB.class_call_static(_library, &"fractions", raw, 2)
    var values := PackedFloat32Array()
    values.resize(raw.size() >> 1)
    for i in values.size():
        values[i] = float(raw.decode_u16(i * 2)) / SIXTEEN_MAX
    return values


## Eight-bit samples as an `FORMAT_RGBA8` picture.
##
## Grey, grey and alpha, RGB and RGBA each have an `Image` format of their own,
## so the bytes go in as they are and Godot's conversion widens them, which is
## exact at eight bits. A file with more extras than an alpha, or with its alpha
## multiplied in, goes through the float path and is rounded back, because
## `Image.convert` to eight bits truncates and would land a 1.0 on 254.
func _byte_image(raw: PackedByteArray) -> Image:
    if _samples <= _base() + 1 and not _associated:
        var format := Image.FORMAT_RGBA8
        if not _colour:
            format = Image.FORMAT_LA8 if _samples == 2 else Image.FORMAT_L8
        elif _samples == 3:
            format = Image.FORMAT_RGB8
        var image := Image.create_from_data(_width, _height, false, format, raw)
        image.convert(Image.FORMAT_RGBA8)
        return image
    if not _library.is_empty():
        var fractions: PackedFloat32Array = ClassDB.class_call_static(_library, &"fractions", raw, 1)
        var straight: PackedFloat32Array = ClassDB.class_call_static(
            _library, &"straight", fractions, _width * _height, _samples, _colour, _associated
        )
        var rounded: PackedByteArray = ClassDB.class_call_static(_library, &"rounded", straight)
        return Image.create_from_data(_width, _height, false, Image.FORMAT_RGBA8, rounded)
    var values := PackedFloat32Array()
    values.resize(raw.size())
    for i in raw.size():
        values[i] = float(raw[i]) / EIGHT_MAX
    var floats := _float_image(values).get_data().to_float32_array()
    var bytes := PackedByteArray()
    bytes.resize(floats.size())
    for i in floats.size():
        bytes[i] = roundi(clampf(floats[i], 0.0, 1.0) * EIGHT_MAX)
    return Image.create_from_data(_width, _height, false, Image.FORMAT_RGBA8, bytes)


## Samples already scaled, `_samples` a pixel, as an `FORMAT_RGBAF` picture.
##
## RGBA with a straight alpha, which is every float file Sara writes, is the
## samples as they are, and RGB is widened by Godot, which makes it opaque. The
## rest is walked a pixel at a time: a grey is copied into three channels, a
## file with no alpha is opaque, extras after the alpha are dropped, and an
## alpha multiplied in is divided back out.
func _float_image(values: PackedFloat32Array) -> Image:
    if _colour and _samples == 4 and not _associated:
        return Image.create_from_data(_width, _height, false, Image.FORMAT_RGBAF, values.to_byte_array())
    if _colour and _samples == 3:
        var image := Image.create_from_data(_width, _height, false, Image.FORMAT_RGBF, values.to_byte_array())
        image.convert(Image.FORMAT_RGBAF)
        return image
    if not _library.is_empty():
        var straight: PackedFloat32Array = ClassDB.class_call_static(
            _library, &"straight", values, _width * _height, _samples, _colour, _associated
        )
        return Image.create_from_data(_width, _height, false, Image.FORMAT_RGBAF, straight.to_byte_array())
    var base := _base()
    var out := PackedFloat32Array()
    out.resize(_width * _height * 4)
    for pixel in _width * _height:
        var at := pixel * _samples
        var red := values[at]
        var green := values[at + 1] if _colour else red
        var blue := values[at + 2] if _colour else red
        var alpha := values[at + base] if _samples > base else 1.0
        if _associated and alpha > 0.0:
            red /= alpha
            green /= alpha
            blue /= alpha
        out[pixel * 4] = red
        out[pixel * 4 + 1] = green
        out[pixel * 4 + 2] = blue
        out[pixel * 4 + 3] = alpha
    return Image.create_from_data(_width, _height, false, Image.FORMAT_RGBAF, out.to_byte_array())


## The samples the colour takes, before any alpha.
func _base() -> int:
    return 3 if _colour else 1


## *count* values of *type* at *at*, in the file's byte order.
func _integers(type: int, at: int, count: int) -> PackedInt64Array:
    var out := PackedInt64Array()
    out.resize(count)
    for i in count:
        match type:
            TYPE_SHORT:
                out[i] = _u16(at + i * 2)
            TYPE_LONG:
                out[i] = _u32(at + i * 4)
            _:
                out[i] = _bytes[at + i]
    return out


## The first value of *tag*, or *fallback* when the directory leaves it out.
func _field(tag: int, fallback: int) -> int:
    var values: PackedInt64Array = _fields.get(tag, PackedInt64Array())
    return values[0] if not values.is_empty() else fallback


## The value every sample's entry of *tag* holds, *fallback* when the directory
## leaves it out, and -1 when the samples differ. One value for every sample is
## allowed too, and some writers write it so.
func _shared(tag: int, fallback: int) -> int:
    var values: PackedInt64Array = _fields.get(tag, PackedInt64Array())
    if values.is_empty():
        return fallback
    for value in values:
        if value != values[0]:
            return -1
    return values[0]


func _u16(at: int) -> int:
    if _big:
        return (_bytes[at] << 8) | _bytes[at + 1]
    return _bytes.decode_u16(at)


func _u32(at: int) -> int:
    if _big:
        return (_bytes[at] << 24) | (_bytes[at + 1] << 16) | (_bytes[at + 2] << 8) | _bytes[at + 3]
    return _bytes.decode_u32(at)


## The sentence for *message*, naming a file this reader chooses not to read.
## The message is translated whole, the file's name its first value and
## *values* the rest.
func _unread(message: String, values: Array = []) -> String:
    return tr(message) % ([_source] + values)


## The sentence for *message*, saying why a file's own numbers do not hold
## together, made the way [method _unread] makes its own.
func _broken(message: String, values: Array = []) -> String:
    return tr(message) % ([_source] + values)


## The refusal for a compressed strip the unpacker could not unpack. The
## unpacker's own clause says where it stopped and stays on its `fault`, which
## the native library words too, so the painter's sentence names only the scheme.
func _unpack_refusal() -> String:
    if _unpacked == SaTiffUnpacker.PACK_BITS:
        return _broken("Could not read '%s' as an image because its PackBits pixels are damaged.")
    return _broken("Could not read '%s' as an image because its LZW pixels are damaged.")
