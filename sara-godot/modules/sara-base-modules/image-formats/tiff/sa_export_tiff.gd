## Sara's own TIFF writer, since Godot has no TIFF encoder.
##
## **The depth is 32-bit float or 16-bit unsigned integer.** An 8-bit TIFF is a
## bigger PNG, so it is not offered. Thirty-two bit float (`SampleFormat` 3)
## keeps every value the canvas holds, negatives and anything above 1.0
## included. Sixteen-bit integer is what nearly every other program reads, and
## it is clamped to 0 to 1 and rounded as the PNG encoder does. Half floats are
## left out because readers handle them patchily and EXR already answers
## "smaller and still floating point".
##
## **Baseline, uncompressed, one strip.** Every reader must handle no
## compression, so none is written and there is no `Predictor` field. No tiles,
## no pyramids, no second directory, and no `Orientation` (the default of 1 is
## what this writes).
##
## The ICC profile goes in tag 34675 when the caller hands one over, because an
## unlabelled TIFF is read as sRGB and a wide-gamut document would arrive in the
## wrong colours. Date, painter and program go in tags 306, 315 and 305 from the
## `SaExportMetadata` the caller hands over, as UTF-8 (TIFF 6.0 calls it ASCII
## and every current reader takes it). A location the painter ticked goes in tag
## 700 as the XMP packet `SaExportMetadata.xmp` writes.
class_name SaExportTiff
extends RefCounted

## Little-endian, which is what "II" says, and the only byte order this writes.
## Every reader is required to handle both, and one order is one thing to test.
const BYTE_ORDER_LITTLE := 0x4949
## The number 42, which is the whole of a TIFF's version field.
const MAGIC: int = 42

## The TIFF field types this uses, by their numbers in the specification.
const TYPE_SHORT: int = 3
const TYPE_LONG: int = 4
const TYPE_RATIONAL: int = 5
const TYPE_ASCII: int = 2
## Bytes that mean nothing to TIFF itself, which is how a profile is carried.
const TYPE_UNDEFINED: int = 7
## Plain bytes, the type the XMP specification gives tag 700.
const TYPE_BYTE: int = 1

## Tags, in the order they are written. A TIFF's directory entries must be
## sorted by tag, which is what decides this list's order rather than any
## grouping by meaning.
const TAG_IMAGE_WIDTH: int = 256
const TAG_IMAGE_LENGTH: int = 257
const TAG_BITS_PER_SAMPLE: int = 258
const TAG_COMPRESSION: int = 259
const TAG_PHOTOMETRIC: int = 262
const TAG_STRIP_OFFSETS: int = 273
const TAG_SAMPLES_PER_PIXEL: int = 277
const TAG_ROWS_PER_STRIP: int = 278
const TAG_STRIP_BYTE_COUNTS: int = 279
const TAG_X_RESOLUTION: int = 282
const TAG_Y_RESOLUTION: int = 283
const TAG_PLANAR_CONFIG: int = 284
const TAG_RESOLUTION_UNIT: int = 296
const TAG_SOFTWARE: int = 305
const TAG_DATE_TIME: int = 306
const TAG_ARTIST: int = 315
const TAG_EXTRA_SAMPLES: int = 338
const TAG_SAMPLE_FORMAT: int = 339
## `XMLPacket`, the XMP of the location, only when there is one.
const TAG_XMP: int = 700
## `InterColorProfile`, written last because it is the highest, and only when
## there is a profile to write.
const TAG_ICC_PROFILE: int = 34675

const COMPRESSION_NONE: int = 1
const PHOTOMETRIC_RGB: int = 2
const PLANAR_CHUNKY: int = 1
const RESOLUTION_INCH: int = 2
## Alpha that has not been multiplied into the colour, which is what Sara stores
## everywhere: the compositor's own `porter_duff` multiplies by `src.a` as it
## blends, so a chunk holds a straight colour. Saying 1 here instead, associated
## alpha, would make every reader divide the colour by the alpha it finds.
const EXTRA_SAMPLE_UNASSOCIATED_ALPHA: int = 2
## IEEE floating point, which is the field the whole format choice rests on.
const SAMPLE_FORMAT_FLOAT: int = 3
## Unsigned integer, which is what the 16-bit file says instead, and what a
## reader that cannot open a float TIFF expects to find.
const SAMPLE_FORMAT_UINT: int = 1

const SAMPLES_PER_PIXEL: int = 4
## The default depth, in bits. The alternative is 16, and nothing else is
## offered.
const BITS_PER_SAMPLE: int = 32
## The only other depth this writer offers, in bits, and what a reader that will
## not open a float TIFF expects to find.
const BITS_PER_SAMPLE_SIXTEEN: int = 16
## What one sample of each depth costs in the strip. Named rather than divided
## out of the bit depths, because `bits / 8` is an integer division the lint
## reads as a truncation bug and it is one only when the depth is not a whole
## number of bytes.
const BYTES_PER_SAMPLE: int = 4
const BYTES_PER_SAMPLE_SIXTEEN: int = 2

## Twelve bytes an entry, and the count and the next-directory pointer around
## them. Written out because the offsets below are arithmetic on these numbers
## and a wrong one is a file that opens as noise rather than as an error.
const ENTRY_BYTES: int = 12
const HEADER_BYTES: int = 8

## The largest value a LONG holds, which is every offset and byte count classic
## TIFF has. A 16384 square at float is exactly 2^32 bytes of strip, one past
## it, which a LONG holds as a byte count of nought under a file the export
## would report as saved, so the size is refused instead. BigTIFF would lift the limit and is not
## written, as `SaZipStored` does not write Zip64.
const LIMIT_32: int = 0xFFFFFFFF


## Writes *image* to *path* as an RGBA TIFF at *bits* a sample. *dpi* goes into
## the resolution fields, which baseline TIFF requires and which is where a
## document that knows its own print size puts it, and *profile*, when there is
## one, into tag 34675. *metadata*, when there is one, adds the date and the
## artist.
##
## Exports the picture *easel* shows as a TIFF at *path*, the Export dialog's
## writer. The document's own DPI goes into the file, so a canvas that knows
## its print size says so, and so does its gamut. *bits* is 32 or 16.
##
## *tonemap* is the rolloff the dialog's check asks for, and only the 16-bit
## file ever sees it or *mapping*: 32 is the depth this promises keeps every
## value, so [method SaPictureFile.encoded_canvas] drops both rather than
## trusting a caller that forgot the rule. *bake_relief* reaches the float file
## as well, since the light is part of the picture, not a narrowing.
##
## The size is judged before the picture is read back off the GPU, so a
## canvas too large for the format costs no readback.
static func export(
    easel: SaEasel,
    path: String,
    bits: int = BITS_PER_SAMPLE,
    tonemap: bool = false,
    mapping: String = SaGamutMapping.CLIP,
    bake_relief: bool = false
) -> Error:
    if easel == null or easel.output == null:
        push_error("SaExportTiff.export: no easel or no picture")
        return ERR_INVALID_PARAMETER
    if refuse_size(easel.output.size, bits) != OK:
        return ERR_FILE_CANT_WRITE
    var picture := SaPictureFile.encoded_canvas(easel, bits == BITS_PER_SAMPLE, tonemap, mapping, bake_relief)
    if picture == null:
        return ERR_CANT_ACQUIRE_RESOURCE
    var space := easel.document.color_space if easel.document != null else null
    var dpi := easel.document.dpi if easel.document != null else 96.0
    return write(picture, path, dpi, SaPictureFile.profile_of(space), bits, SaExportMetadata.now())


## Writes *texture* as a TIFF at *path*, *space* what it stores, or null for
## the stored numbers unlabelled. *tonemap* is the rolloff's push constant and
## *mapping* the gamut mapping, both dropped at 32 bits as [method export]
## drops them, and *metadata* the record the file names, an export made now
## when null.
static func export_texture(
    texture: SaTexture,
    path: String,
    dpi: float = 96.0,
    space: SaColorSpace = null,
    bits: int = BITS_PER_SAMPLE,
    tonemap: PackedFloat32Array = PackedFloat32Array(),
    mapping: String = SaGamutMapping.CLIP,
    metadata: SaExportMetadata = null,
) -> Error:
    if texture != null and refuse_size(texture.size, bits) != OK:
        return ERR_FILE_CANT_WRITE
    var keeps_range := bits == BITS_PER_SAMPLE
    var rolloff := tonemap if not keeps_range else PackedFloat32Array()
    var picture := SaPictureFile.encoded_image(texture, space, rolloff, SaGamutMapping.for_export(mapping, keeps_range))
    if picture == null:
        return ERR_CANT_ACQUIRE_RESOURCE
    var record := metadata if metadata != null else SaExportMetadata.now()
    return write(picture, path, dpi, SaPictureFile.profile_of(space), bits, record)


## *bits* is 32, the default, for float samples, or 16 for unsigned integer
## ones. Nothing else is written and nothing else is guessed at: a caller that
## asks for 8 gets an error and no file rather than a file that lies about what
## it holds. A picture whose strip passes `LIMIT_32` bytes is refused the same
## way, through [method refuse_size], and leaves no file.
##
## The image is converted to `FORMAT_RGBAF` first if it is not already, which is
## lossless from RGBAH and is what makes an F16 document export at the same
## precision as an F32 one, exactly as EXR export does.
static func write(
    image: Image,
    path: String,
    dpi: float = 96.0,
    profile: PackedByteArray = PackedByteArray(),
    bits: int = BITS_PER_SAMPLE,
    metadata: SaExportMetadata = null,
) -> Error:
    if image == null:
        push_error("SaExportTiff.write: image is null")
        return ERR_INVALID_PARAMETER
    if image.get_width() <= 0 or image.get_height() <= 0:
        push_error("SaExportTiff.write: an image with no pixels cannot be written")
        return ERR_INVALID_PARAMETER
    if not _depth_is_offered(bits):
        push_error("SaExportTiff.write: %d bits a sample is neither 32 nor 16" % bits)
        return ERR_INVALID_PARAMETER
    var too_large := refuse_size(Vector2i(image.get_width(), image.get_height()), bits)
    if too_large != OK:
        return too_large
    # Encoded before the file is opened, so a picture `encode` still refuses
    # leaves no empty file behind under the painter's name.
    var bytes := encode(image, dpi, profile, bits, metadata)
    if bytes.is_empty():
        return ERR_FILE_CANT_WRITE
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_error("SaExportTiff.write: could not open '%s' (err %d)" % [path, FileAccess.get_open_error()])
        return FileAccess.get_open_error()
    file.store_buffer(bytes)
    file.close()
    return OK


## Whether a picture of *size* at *bytes_per_sample* fits classic TIFF's LONG
## fields: its strip's byte count, and *strip_offset*, where the strip starts,
## both at most `LIMIT_32`. Arithmetic on the numbers alone, so a caller asks it
## before a four gigabyte picture is read back off the GPU, and a suite asks it
## of a 16384 square without allocating one.
static func strip_fits(size: Vector2i, bytes_per_sample: int, strip_offset: int = 0) -> bool:
    var strip_bytes := size.x * size.y * SAMPLES_PER_PIXEL * bytes_per_sample
    return strip_bytes <= LIMIT_32 and strip_offset <= LIMIT_32


## OK when a picture of *size* at *bits* a sample, its strip at
## *strip_offset*, fits a classic TIFF, and otherwise a refusal the painter sees
## in the canvas corner and `ERR_FILE_CANT_WRITE`, the error `SaZipStored` gives
## its own limit. A refusal and not a fault, because nothing is broken: the
## picture is too big for the format, and a smaller one, or the 16-bit depth
## when the refused one was float, is the next move.
static func refuse_size(size: Vector2i, bits: int, strip_offset: int = 0) -> Error:
    if strip_fits(size, _bytes_per_sample(bits), strip_offset):
        return OK
    var text := (
        "A %d by %d picture at %d bits is past the four gigabytes a TIFF can hold. Export it smaller or at 16 bits."
        if bits == BITS_PER_SAMPLE
        else "A %d by %d picture at %d bits is past the four gigabytes a TIFF can hold. Export it smaller."
    )
    SaProblems.refuse("SaExportTiff", TranslationServer.translate(text) % [size.x, size.y, bits])
    return ERR_FILE_CANT_WRITE


## The whole file as bytes, so a test can read what was written without a
## filesystem and so `write` is one `store_buffer`.
static func encode(
    image: Image,
    dpi: float = 96.0,
    profile: PackedByteArray = PackedByteArray(),
    bits: int = BITS_PER_SAMPLE,
    metadata: SaExportMetadata = null,
) -> PackedByteArray:
    if not _depth_is_offered(bits):
        push_error("SaExportTiff.encode: %d bits a sample is neither 32 nor 16" % bits)
        return PackedByteArray()

    # The widening is here rather than in `write`, because the strip below is
    # `get_data()` and a half-float image handed straight to it writes half the
    # bytes under a header that promises 32-bit floats: a file that opens as
    # noise. Lossless from RGBAH, which is what lets an F16 document export at
    # the same precision as an F32 one, exactly as EXR export does.
    var source := image
    if source.get_format() != Image.FORMAT_RGBAF:
        source = Image.new()
        source.copy_from(image)
        source.convert(Image.FORMAT_RGBAF)

    var width := source.get_width()
    var height := source.get_height()
    var texts := _texts(metadata)
    var has_profile := not profile.is_empty()
    var xmp := (metadata.xmp() if metadata != null else "").to_utf8_buffer()

    # Everything an entry cannot hold in its own four bytes lives after the
    # directory, and every offset below is the running total of what came before
    # it. A LONG or a single SHORT fits inline, four SHORTs and a RATIONAL do
    # not, which is the whole of why this block exists.
    var entry_count := 15 + texts.size() + (1 if has_profile else 0) + (0 if xmp.is_empty() else 1)
    var directory_bytes := 2 + entry_count * ENTRY_BYTES + 4
    var bits_offset := HEADER_BYTES + directory_bytes
    var sample_format_offset := bits_offset + SAMPLES_PER_PIXEL * 2
    var x_resolution_offset := sample_format_offset + SAMPLES_PER_PIXEL * 2
    var y_resolution_offset := x_resolution_offset + 8
    # The texts follow the resolutions one after the other, each with its
    # closing zero, which is what an ASCII field's count includes. One of four
    # bytes or fewer, an author called Jo, sits in its entry instead, which the
    # format requires, so its value is the bytes themselves and not an offset.
    var text_values: Array[int] = []
    var text_end := y_resolution_offset + 8
    for text: Array in texts:
        var bytes: PackedByteArray = text[1]
        if bytes.size() <= 4:
            text_values.append(_inline(bytes))
        else:
            text_values.append(text_end)
            text_end += bytes.size()
    # The packet follows the texts. It is far over four bytes when there is one.
    var xmp_offset := text_end
    text_end += xmp.size()
    # The profile and the strip each start on an even offset, which the
    # specification asks of every value past the directory and which costs at
    # most a byte apiece.
    var profile_offset := text_end
    if profile_offset % 2 == 1:
        profile_offset += 1
    var strip_offset := profile_offset + profile.size()
    if strip_offset % 2 == 1:
        strip_offset += 1
    var sample_format := SAMPLE_FORMAT_FLOAT if bits == BITS_PER_SAMPLE else SAMPLE_FORMAT_UINT
    var bytes_per_sample := _bytes_per_sample(bits)
    var strip_bytes := width * height * SAMPLES_PER_PIXEL * bytes_per_sample
    # `write` asked with no offset, and this asks again with the real one,
    # because a caller of `encode` alone would otherwise write the wrapped count.
    if refuse_size(Vector2i(width, height), bits, strip_offset) != OK:
        return PackedByteArray()

    var out := PackedByteArray()
    _put_u16(out, BYTE_ORDER_LITTLE)
    _put_u16(out, MAGIC)
    _put_u32(out, HEADER_BYTES)

    _put_u16(out, entry_count)
    _entry(out, TAG_IMAGE_WIDTH, TYPE_LONG, 1, width)
    _entry(out, TAG_IMAGE_LENGTH, TYPE_LONG, 1, height)
    _entry(out, TAG_BITS_PER_SAMPLE, TYPE_SHORT, SAMPLES_PER_PIXEL, bits_offset)
    _entry(out, TAG_COMPRESSION, TYPE_SHORT, 1, COMPRESSION_NONE)
    _entry(out, TAG_PHOTOMETRIC, TYPE_SHORT, 1, PHOTOMETRIC_RGB)
    _entry(out, TAG_STRIP_OFFSETS, TYPE_LONG, 1, strip_offset)
    _entry(out, TAG_SAMPLES_PER_PIXEL, TYPE_SHORT, 1, SAMPLES_PER_PIXEL)
    # One strip for the whole image. A reader is allowed to want several and
    # none is required to, and one keeps the offsets above a straight line.
    _entry(out, TAG_ROWS_PER_STRIP, TYPE_LONG, 1, height)
    _entry(out, TAG_STRIP_BYTE_COUNTS, TYPE_LONG, 1, strip_bytes)
    _entry(out, TAG_X_RESOLUTION, TYPE_RATIONAL, 1, x_resolution_offset)
    _entry(out, TAG_Y_RESOLUTION, TYPE_RATIONAL, 1, y_resolution_offset)
    _entry(out, TAG_PLANAR_CONFIG, TYPE_SHORT, 1, PLANAR_CHUNKY)
    _entry(out, TAG_RESOLUTION_UNIT, TYPE_SHORT, 1, RESOLUTION_INCH)
    for i in texts.size():
        var tag: int = texts[i][0]
        var text_bytes: PackedByteArray = texts[i][1]
        _entry(out, tag, TYPE_ASCII, text_bytes.size(), text_values[i])
    _entry(out, TAG_EXTRA_SAMPLES, TYPE_SHORT, 1, EXTRA_SAMPLE_UNASSOCIATED_ALPHA)
    _entry(out, TAG_SAMPLE_FORMAT, TYPE_SHORT, SAMPLES_PER_PIXEL, sample_format_offset)
    if not xmp.is_empty():
        _entry(out, TAG_XMP, TYPE_BYTE, xmp.size(), xmp_offset)
    if has_profile:
        _entry(out, TAG_ICC_PROFILE, TYPE_UNDEFINED, profile.size(), profile_offset)
    # No second directory. A file this writes is one image.
    _put_u32(out, 0)

    for i in SAMPLES_PER_PIXEL:
        _put_u16(out, bits)
    for i in SAMPLES_PER_PIXEL:
        _put_u16(out, sample_format)
    # A RATIONAL is two LONGs, and a whole number of dots per inch is that
    # number over one. Rounded rather than carried as a fraction, because the
    # field is metadata and no pixel depends on it.
    var dots := maxi(1, roundi(dpi))
    _put_u32(out, dots)
    _put_u32(out, 1)
    _put_u32(out, dots)
    _put_u32(out, 1)
    for text: Array in texts:
        var bytes: PackedByteArray = text[1]
        if bytes.size() > 4:
            out.append_array(bytes)
    out.append_array(xmp)
    while out.size() < profile_offset:
        out.append(0)
    out.append_array(profile)
    while out.size() < strip_offset:
        out.append(0)

    if bits == BITS_PER_SAMPLE:
        out.append_array(source.get_data())
    else:
        out.append_array(_uint16_strip(source, width * height))
    return out


## The ASCII fields as tag and bytes, the closing zero included, in the order
## of their tags: `Software` always, and `DateTime` and `Artist` when
## *metadata* has them.
static func _texts(metadata: SaExportMetadata) -> Array:
    var software := metadata.software if metadata != null else SaExportMetadata.new().software
    var out: Array = [[TAG_SOFTWARE, _ascii(software)]]
    if metadata != null:
        out.append([TAG_DATE_TIME, _ascii(metadata.tiff_date_time())])
        if not metadata.author.is_empty():
            out.append([TAG_ARTIST, _ascii(metadata.author)])
    return out


## *text* as UTF-8 with its closing zero.
static func _ascii(text: String) -> PackedByteArray:
    var bytes := text.to_utf8_buffer()
    bytes.append(0)
    return bytes


## Up to four bytes as the value field holds them inline: the first byte lowest,
## which is where a little-endian reader looks for it.
static func _inline(bytes: PackedByteArray) -> int:
    var value := 0
    for i in bytes.size():
        value |= bytes[i] << (8 * i)
    return value


## The 16-bit strip, packed by hand from the widened floats: every sample is
## clamped to 0 to 1, scaled over 65535 and rounded, which is the rule the PNG
## encoder uses and the same clause. Little-endian, like every other number in
## the file.
##
## The floats are read through `to_float32_array` rather than `decode_float` a
## sample at a time, because the array is one call and the loop's per-sample
## cost is then arithmetic alone. An export is the one place a whole canvas
## comes back off the GPU, so a loop over its texels is the hot path of this
## file and worth the shape that reads faster.
static func _uint16_strip(source: Image, texels: int) -> PackedByteArray:
    var samples := source.get_data().to_float32_array()
    var strip := PackedByteArray()
    strip.resize(texels * SAMPLES_PER_PIXEL * 2)
    for i in samples.size():
        var value := roundi(clampf(samples[i], 0.0, 1.0) * 65535.0)
        strip[i * 2] = value & 0xFF
        strip[i * 2 + 1] = (value >> 8) & 0xFF
    return strip


## Whether *bits* a sample is one of the two depths this writer offers. A depth
## it cannot write is refused rather than rounded to one it can, because the
## header would otherwise promise the caller something the strip does not hold.
static func _depth_is_offered(bits: int) -> bool:
    return bits == BITS_PER_SAMPLE or bits == BITS_PER_SAMPLE_SIXTEEN


## What one sample of *bits* costs in the strip, for the two depths offered.
static func _bytes_per_sample(bits: int) -> int:
    return BYTES_PER_SAMPLE if bits == BITS_PER_SAMPLE else BYTES_PER_SAMPLE_SIXTEEN


static func _entry(into: PackedByteArray, tag: int, type: int, count: int, value: int) -> void:
    _put_u16(into, tag)
    _put_u16(into, type)
    _put_u32(into, count)
    # A SHORT that fits inline sits in the low half of the value field, which is
    # where a little-endian reader looks for it. Writing it as a LONG puts it
    # there, so the two cases are one line rather than two.
    _put_u32(into, value)


static func _put_u16(into: PackedByteArray, value: int) -> void:
    into.append(value & 0xFF)
    into.append((value >> 8) & 0xFF)


static func _put_u32(into: PackedByteArray, value: int) -> void:
    into.append(value & 0xFF)
    into.append((value >> 8) & 0xFF)
    into.append((value >> 16) & 0xFF)
    into.append((value >> 24) & 0xFF)
