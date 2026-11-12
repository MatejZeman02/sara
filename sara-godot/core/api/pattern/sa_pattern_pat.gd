## GIMP's own pattern format, a `.pat`, read into an [Image] the picture
## loader turns into a mask.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Written from the format, not ported.** GIMP's `pattern-header.h` states a
## header of six big-endian 32-bit fields, twenty-four bytes: the header's own
## size, a version, a width, a height, a channel count and the magic word
## `GPAT`. The name follows, terminated, filling whatever the header's size
## leaves, and then the rows, top to bottom, one to four bytes a texel.
##
## Krita's bundled papers are `.pat`, and the Krita import writes only what
## [SaPatternStore] lists, so without this reader a Krita preset would arrive
## with its paper named and its paper missing.
##
## **It answers an [Image], and [SaPatternImage] takes it from there.** The
## channels become `FORMAT_RGBA8` and nothing here decides what grey means: a
## paper's polarity, luminance times alpha with white where the paint lands,
## is the picture loader's one rule and stays in one place. One channel is a
## grey, two are a grey with alpha, three are a colour read as its luminance
## and four are the same with the alpha multiplied in.
##
## **A file the header does not describe is refused with the reason named**,
## the way `sa_tip_image.gd` refuses an `.abr`. Every field is checked against
## the size of the file it came out of, because a header is a set of numbers a
## truncated or corrupt file is free to lie about and each one is an offset or
## a length. A refusal that says which field disagreed is worth more to a
## painter than a blank paper.
##
## Reading is CPU work done once, outside any stroke, and no readback of the
## canvas: a file becomes a texture before anything paints.
class_name SaPatternPat
extends RefCounted

## The six fields of the header, six big-endian words.
const HEADER_BYTES: int = 24

## `GPAT` as a big-endian word, the sixth field.
const MAGIC: int = 0x47504154

## The one version the format has had. A file claiming another is refused
## rather than read at this layout, because the layout is what the version
## numbers.
const VERSION: int = 1

## The channel counts a texel may have: grey, grey and alpha, colour, colour
## and alpha.
const MAX_CHANNELS: int = 4

## The largest tile believed, a side at a time. A paper of eight thousand
## texels a side is 256 MB at four channels, and a header saying more is a
## header being read at the wrong offset rather than a paper anyone scanned.
const MAX_SIDE: int = 8192


## One `.pat` read: the picture, the name the file carries, or the reason
## there is neither.
class Pat:
    extends RefCounted

    ## The tile as `FORMAT_RGBA8`, null when the file was refused.
    var image: Image = null

    ## The name between the header and the rows, which GIMP shows in its
    ## chooser. Sara lists a pattern under its file's stem instead, so this is
    ## read for the record and for a refusal's message rather than for the
    ## store, and a `.pat` whose name and file disagree lists under the file.
    var pat_name: String = ""

    ## Why there is no picture, empty when there is one.
    var error: String = ""

    func ok() -> bool:
        return image != null


## The `.pat` at *path*, or a refusal naming the reason.
static func read_file(path: String) -> Pat:
    var bytes := FileAccess.get_file_as_bytes(path)
    if bytes.is_empty():
        return _refuse("%s could not be read." % path.get_file())
    return read_bytes(bytes, path.get_file())


## The from-bytes door beside the from-path one, because a Krita preset
## carries its paper inside its own file and the import has bytes and a name
## rather than a file.
static func read_bytes(bytes: PackedByteArray, file_name: String) -> Pat:
    var refusal := refusal_for(bytes, file_name)
    if not refusal.is_empty():
        return _refuse(refusal)
    var header_size := _be_u32(bytes, 0)
    var pat := Pat.new()
    pat.pat_name = _pat_name(bytes, header_size, file_name)
    pat.image = _picture(bytes, header_size, _be_u32(bytes, 8), _be_u32(bytes, 12), _be_u32(bytes, 16))
    return pat


## Why *bytes* are not a `.pat`, or empty when they are one.
##
## The header alone, so the Krita import can ask before it writes a preset's
## embedded paper into the painter's folder: a `.pat` the reader would refuse
## is a preset whose paper did not carry, and writing it anyway would leave a
## named pattern that paints nothing and a file nobody asked for.
static func refusal_for(bytes: PackedByteArray, file_name: String) -> String:
    if bytes.size() < HEADER_BYTES:
        return "%s is %d bytes, too short for a .pat header of %d." % [file_name, bytes.size(), HEADER_BYTES]
    var header_size := _be_u32(bytes, 0)
    var version := _be_u32(bytes, 4)
    var width := _be_u32(bytes, 8)
    var height := _be_u32(bytes, 12)
    var channels := _be_u32(bytes, 16)

    if _be_u32(bytes, 20) != MAGIC:
        return "%s does not carry GPAT where a .pat carries its magic word." % file_name
    if version != VERSION:
        return "%s says version %d, and the .pat format has only version %d." % [file_name, version, VERSION]
    if width <= 0 or height <= 0 or width > MAX_SIDE or height > MAX_SIDE:
        return "%s says it is %d × %d px, which is not a valid pattern size." % [file_name, width, height]
    if channels < 1 or channels > MAX_CHANNELS:
        return "%s has %d channels, a .pat file has 1 to %d." % [file_name, channels, MAX_CHANNELS]
    if header_size < HEADER_BYTES or header_size > bytes.size():
        return "%s has a header of %d bytes in a file of %d." % [file_name, header_size, bytes.size()]
    var needed := header_size + width * height * channels
    if needed > bytes.size():
        return "%s wants %d bytes of pattern after its header and the file holds %d." % [file_name, needed, bytes.size()]
    return ""


## The rows as `FORMAT_RGBA8`, whatever the channel count, so the picture
## loader's one mask rule reads every flavour the same way.
##
## Built as a byte array and handed to `Image.create_from_data` in one go
## rather than through `set_pixel`, which builds a [Color] per texel: a paper
## is commonly 512 by 512, and a quarter of a million Colors to read a file is
## work nobody asked for.
static func _picture(bytes: PackedByteArray, at: int, width: int, height: int, channels: int) -> Image:
    var count := width * height
    var rgba := PackedByteArray()
    rgba.resize(count * 4)
    for i in count:
        var source := at + i * channels
        var target := i * 4
        var grey := bytes[source]
        match channels:
            1:
                rgba[target] = grey
                rgba[target + 1] = grey
                rgba[target + 2] = grey
                rgba[target + 3] = 255
            2:
                rgba[target] = grey
                rgba[target + 1] = grey
                rgba[target + 2] = grey
                rgba[target + 3] = bytes[source + 1]
            3:
                rgba[target] = grey
                rgba[target + 1] = bytes[source + 1]
                rgba[target + 2] = bytes[source + 2]
                rgba[target + 3] = 255
            _:
                rgba[target] = grey
                rgba[target + 1] = bytes[source + 1]
                rgba[target + 2] = bytes[source + 2]
                rgba[target + 3] = bytes[source + 3]
    return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba)


## The name between the header's six fields and the rows: UTF-8, terminated,
## which is why the length is one short of the gap. A header with no room for
## a name, which is what a `.pat` written without one has, leaves the file's
## own stem.
static func _pat_name(bytes: PackedByteArray, header_size: int, file_name: String) -> String:
    var length := header_size - HEADER_BYTES - 1
    if length <= 0:
        return file_name.get_basename()
    var raw := bytes.slice(HEADER_BYTES, HEADER_BYTES + length)
    var text := raw.get_string_from_utf8()
    return text if not text.is_empty() else file_name.get_basename()


static func _refuse(reason: String) -> Pat:
    var pat := Pat.new()
    pat.error = reason
    return pat


static func _be_u32(bytes: PackedByteArray, at: int) -> int:
    if at + 4 > bytes.size():
        return 0
    return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]
