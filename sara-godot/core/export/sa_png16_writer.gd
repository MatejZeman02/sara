## Sara's own 16-bit PNG encoder.
##
## Sixteen bits sit between the 8-bit and the float exports, because a
## stranger's other programs read neither float TIFF nor EXR. Godot's
## `Image.save_png_to_buffer` writes eight bits and takes no depth argument at
## all, so there is no bit depth control to build in the export dialog until Sara
## writes the file itself. This is that writer.
##
## **Sixteen bits, and nothing else.** Eight is what Godot's encoder already
## does and a second eight-bit writer would be a copy of it. Every sample is two
## bytes, big-endian, which is what PNG requires and what no little-endian
## shortcut can be talked into.
##
## **Rounded to the nearest step, not truncated**. The float path set the rule
## and the float exports keep it: a stored 0.5 becomes 32768 rather than
## 32767, exactly as it becomes 128 rather than 127 at eight bits. A
## truncating writer puts every value on the step below it, as the engine's
## own eight-bit narrowing does.
##
## **Filter 0 on every scanline.** PNG's five filters and its Paeth predictor
## buy compression, and a wrong predictor is a file that opens as noise rather
## than as an error, so every scanline says it is unfiltered and every sample is
## written as it stands. The only compression here is the zlib stream an `IDAT`
## carries, which `PackedByteArray.compress(COMPRESSION_DEFLATE)` produces: its
## Deflate mode keeps zlib's own header and checksum, which is what the format
## wants and what `SaExportGamut` already relies on for its `iCCP` chunk.
##
## The `IHDR` is written first and is thirteen bytes long, which is not a
## coincidence: `SaExportGamut.png_with_gamut` splices the document's gamut in
## straight after it, and that splice assumes exactly this shape.
class_name SaPng16Writer
extends RefCounted

## The eight bytes every PNG starts with, which is how a reader knows the rest is
## a PNG at all.
const PNG_SIGNATURE: Array[int] = [137, 80, 78, 71, 13, 10, 26, 10]

## PNG's colour types. Six carries alpha, two does not, and they are the only two
## this writes: every pixel is RGB or RGBA.
const COLOUR_TYPE_RGB: int = 2
const COLOUR_TYPE_RGBA: int = 6

const BIT_DEPTH: int = 16
## Deflate, and no interlacing or filtering beyond the filter byte below. The
## values are PNG's own numbers for "none of the optional things".
const COMPRESSION_METHOD: int = 0
const FILTER_METHOD: int = 0
const INTERLACE_NONE: int = 0
## The filter byte in front of every scanline. Zero is "as they stand".
const FILTER_NONE: int = 0
## What a stored 1.0 becomes, so the full range of the container is reachable and
## nothing in it is a value the document did not hold.
const SAMPLE_MAX: int = 65535


## Writes *image* to *path* as a 16-bit PNG, with an alpha channel unless *alpha*
## is false.
##
## The image is converted to `FORMAT_RGBAF` first when it is not already, which
## is lossless from RGBAH and is what lets an F16 document export through the
## same path as an F32 one, exactly as the TIFF writer does.
static func write(image: Image, path: String, alpha: bool = true) -> Error:
    if image == null:
        push_error("SaPng16Writer.write: image is null")
        return ERR_INVALID_PARAMETER
    if image.get_width() <= 0 or image.get_height() <= 0:
        push_error("SaPng16Writer.write: an image with no pixels cannot be written")
        return ERR_INVALID_PARAMETER
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_error("SaPng16Writer.write: could not open '%s' (err %d)" % [path, FileAccess.get_open_error()])
        return FileAccess.get_open_error()
    file.store_buffer(encode(image, alpha))
    file.close()
    return OK


## The whole file as bytes, so `write` is one `store_buffer` and a test can read
## what was written without a filesystem.
##
## Values outside 0 to 1 are clipped here rather than anywhere earlier, because a
## 16-bit sample is a fixed point between two bounds and there is no third
## choice. It is the same clip PNG at eight bits does, one step finer, and it is
## why a document that has to keep a negative exports as EXR or TIFF instead.
static func encode(image: Image, alpha: bool = true) -> PackedByteArray:
    var source := image
    if source.get_format() != Image.FORMAT_RGBAF:
        source = Image.new()
        source.copy_from(image)
        source.convert(Image.FORMAT_RGBAF)

    var channels := 4 if alpha else 3
    var out := PackedByteArray(PNG_SIGNATURE)

    var header := PackedByteArray()
    _put_u32_be(header, source.get_width())
    _put_u32_be(header, source.get_height())
    header.append(BIT_DEPTH)
    header.append(COLOUR_TYPE_RGBA if alpha else COLOUR_TYPE_RGB)
    header.append(COMPRESSION_METHOD)
    header.append(FILTER_METHOD)
    header.append(INTERLACE_NONE)
    out.append_array(_chunk("IHDR", header))

    out.append_array(_chunk("IDAT", _compressed_scanlines(source, channels)))
    # A PNG with no other chunk, which is everything the format requires of one.
    out.append_array(_chunk("IEND", PackedByteArray()))
    return out


## Every scanline of *source*, filter byte first and samples big-endian, as one
## zlib stream.
##
## The floats come back in one C++ conversion rather than through a `get_pixel`
## per texel, which for a document-sized picture is millions of Variant calls and
## seconds of the main thread. `get_data` is the same sixteen bytes a texel the
## TIFF writer already copies whole.
static func _compressed_scanlines(source: Image, channels: int) -> PackedByteArray:
    var width := source.get_width()
    var height := source.get_height()
    var floats := source.get_data().to_float32_array()

    var raw := PackedByteArray()
    raw.resize((1 + width * channels * 2) * height)
    var at := 0
    for y in height:
        raw[at] = FILTER_NONE
        at += 1
        var texel := y * width * 4
        for x in width:
            for channel in channels:
                var sample := roundi(clampf(floats[texel + channel], 0.0, 1.0) * SAMPLE_MAX)
                raw[at] = (sample >> 8) & 0xFF
                raw[at + 1] = sample & 0xFF
                at += 2
            texel += 4
    return raw.compress(FileAccess.COMPRESSION_DEFLATE)


## One chunk: its length, its type, its data and the CRC over the last two.
static func _chunk(type: String, data: PackedByteArray) -> PackedByteArray:
    var typed := type.to_ascii_buffer()
    typed.append_array(data)
    var out := PackedByteArray()
    _put_u32_be(out, data.size())
    out.append_array(typed)
    _put_u32_be(out, SaExportGamut.crc32(typed))
    return out


static func _put_u32_be(into: PackedByteArray, value: int) -> void:
    into.append((value >> 24) & 0xFF)
    into.append((value >> 16) & 0xFF)
    into.append((value >> 8) & 0xFF)
    into.append(value & 0xFF)
