## Opens a picture into a new layer of a document, in any format the format
## registry holds, the skeleton's PNG, JPEG, WebP and EXR among them, and the
## TIFF and Radiance HDR of the image formats module when it is loaded. Which
## formats there are is the registry's to say, and this class keeps what no
## format owns: the fit, the placement, the upload and the depth.
##
## Import only, one loader for File > Open and for a dropped file. A sibling
## of `SaExport`, which is past the file-length gate's advisory band.
##
## **A sixteen-bit PNG is decoded here rather than by Godot.** `Image` carries
## no sixteen-bit integer format, and Godot's PNG loader answers an eight-bit
## one for a sixteen-bit file: the round trip the sixteen-bit writer makes came
## back at 128 of 255 on a value the file held as 32768, and nothing anywhere
## said so. The header's own `IHDR` is read, and the samples are scaled into
## `FORMAT_RGBAF`, which carries all sixteen bits exactly. A file this reader
## cannot unpack, an interlaced one, falls back to Godot's read and says in
## words which bits went missing.
##
## The colour is the point. An 8-bit PNG or JPEG holds sRGB-encoded values,
## so it is uploaded as sRGB and then converted into whatever the document
## stores through the same kernel Image > Convert uses, or a mid grey lands
## as 0.5 in a linear document where it should be 0.214. An EXR holds linear
## floats, which is what `SaExport.export_exr` writes, so it is read as linear
## sRGB and the same round trip brings back what was stored, negatives and
## values above one included. Alpha is straight in both, as it is in the
## chunks.
##
## A Radiance `.hdr` holds linear light as RGBE, three mantissas under a shared
## exponent, which is how a panorama of a sky with its sun in it travels. It is
## read by the image formats module's own reader, because Godot's loader
## clamps past 65,408 and refuses most of the format's layouts, and it opens as
## linear sRGB at F16, the depth the HDRI page asks for a panorama, unless a
## value in it is one a half does not keep, a sun past 65,504 above all, which
## opens it at F32.
##
## A TIFF is read by the image formats module, because Godot has no TIFF
## decoder. What its writer writes is the document's gamut through sRGB's curve with the
## gamut's profile in the file, so a TIFF opens as sRGB's curve in the gamut its
## profile names, and a TIFF from elsewhere opens as its profile says, as any
## picture carrying a profile does.
##
## The image lands on a layer named after the file, and it lands whole. Where
## it lands is the `Fit` a caller passes, the top left when it passes none. A
## picture wider or taller than the canvas keeps the part that hangs over the
## edge in its own chunks, because chunks are sparse and a later crop or a
## resize should find the paint rather than a hole. Only the chunks the image
## covers are allocated (hard rule 3), and the layer is an ordinary add, so
## one undo removes it.
##
## A paste and a drop go through the same door, which is what `place` is: an
## `Image` from anywhere, fitted to the canvas and converted from the space it
## was drawn in.
class_name SaImageImport
extends RefCounted

## The eight bytes every PNG starts with, and how much of a file is enough to
## answer what its header says: the signature, the `IHDR` chunk whole, and
## nothing after it.
const PNG_SIGNATURE: Array[int] = [137, 80, 78, 71, 13, 10, 26, 10]
const PNG_HEADER_BYTES: int = 8 + 4 + 4 + 13 + 4

## The sample width this class decodes itself. Eight goes to Godot's own loader,
## which keeps it, and sixteen is the one it does not.
const PNG_SIXTEEN_BITS: int = 16
## PNG's colour types, and the four that carry sixteen bits. A palette is one,
## two, four or eight bits by definition, so it is not among them.
const PNG_COLOUR_TYPE_GREY: int = 0
const PNG_COLOUR_TYPE_RGB: int = 2
const PNG_COLOUR_TYPE_GREY_ALPHA: int = 4
const PNG_COLOUR_TYPE_RGBA: int = 6
## The only values PNG defines for the three method bytes of its header, so a
## file naming another is not one any writer makes.
const PNG_COMPRESSION_DEFLATE: int = 0
const PNG_FILTER_METHOD_ADAPTIVE: int = 0
const PNG_INTERLACE_NONE: int = 0
## The five scanline filters, undone by `SaPng16Decode.lanes_of` rather than by the
## writer, which writes only the first.
const PNG_FILTER_NONE: int = 0
const PNG_FILTER_SUB: int = 1
const PNG_FILTER_UP: int = 2
const PNG_FILTER_AVERAGE: int = 3
const PNG_FILTER_PAETH: int = 4
## What a stored 1.0 becomes, so the whole range of the container is reachable.
## The same number `SaPng16Writer` writes against, read the other way.
const PNG_SAMPLE_MAX: int = 65535
## The picture formats a module brings, by extension, each with the name the
## refusal in [method refuses_unread] gives it when no module has registered it.
const MODULE_PICTURES: Dictionary[String, String] = {
    "tif": "TIFF",
    "tiff": "TIFF",
    "hdr": "Radiance HDR",
    "ora": "OpenRaster",
}

## How a picture whose size differs from the canvas is placed. The four the
## dialog offers, and the one it does not: a caller that asks for nothing
## gets what an import has always done.
enum Fit {
    ## Its own pixels at the document's top left.
    ORIGIN,
    ## Resized to the canvas, ratio and all.
    STRETCH,
    ## Its own pixels, centred, with whatever hangs over the edge kept.
    ACTUAL,
    ## The largest that fits inside the canvas with its ratio kept, centred.
    INSIDE,
    ## The canvas grown about its middle until the picture fits, then the
    ## picture's own pixels centred on it.
    GROW,
}


## Whether *path* names a picture a registered format opens as one layer.
## What File > Open lists beside .sad, and what a dropped file may be, is the
## format registry's, [SaImageFormatRegistry], which the skeleton fills from
## `core/loader/image_formats` as a module would.
static func is_image_path(path: String) -> bool:
    return formats().flat_named(path) != null


## The registry this class asks, the app's or the skeleton's own.
static func formats() -> SaImageFormatRegistry:
    return SaImageFormatRegistry.shared()


## The file dialog filter line for the formats above.
static func dialog_filter() -> String:
    return formats().image_filter("Image")


## What the first bytes of *path* say the file really is, the id of the format
## that claims them, `png`, `jpg`, `webp`, `exr`, `tiff` or `hdr` among the
## skeleton's, and "" when nothing recognises them or the file cannot be opened.
##
## `Image.load` picks a decoder by extension, so a WebP called `.jpg` reached
## the JPEG decoder, which refused it and returned `ERR_FILE_CORRUPT`. The
## dialog then said "File corrupt" about a file every viewer opens, because a
## viewer sniffs the bytes. Each format says how its header claims a file, and
## sixteen bytes are enough for all of the skeleton's.
static func sniff_format(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    return format_of_header(file.get_buffer(SaImageFormatRegistry.HEAD_BYTES))


## The format *head* begins with, split from `sniff_format` so it can be tested
## without a file on disk.
static func format_of_header(head: PackedByteArray) -> String:
    var format := formats().claiming(head)
    return String(format.id) if format != null else ""


## The format *path*'s own name claims, in the spelling `sniff_format` answers
## in, so the two can be compared. "" for anything this class does not import.
static func claimed_format(path: String) -> String:
    var format := formats().flat_named(path)
    return String(format.id) if format != null else ""


## Reads *path*, or null with the reason reported. Split from `open_into` so a
## caller that has to ask how to fit the picture can measure it first.
##
## The format the file's own bytes claim reads it, whatever its name says, and
## the one its name claims when no format recognises the bytes. Each reader says
## in its own words why a file it cannot unpack is refused.
static func read(path: String) -> Image:
    var format := _format_at(path)
    if format != null:
        return format.reader.call(path)
    if refuses_unread(path):
        return null
    # `TranslationServer.translate` rather than a bare `tr`, which is a method on
    # `Object` and cannot be reached from a static function. The placeholders are
    # filled after the lookup, so the phrase a translator sees is the whole
    # sentence rather than a path and a reason spliced into it.
    var reason := error_string(ERR_FILE_UNRECOGNIZED) + ", and its first bytes match no format Sara reads"
    SaProblems.refuse("SaImageImport", TranslationServer.translate("Could not read '%s' as an image (%s).") % [path, reason])
    return null


## Whether *path* names a picture format Sara reads only through a module that
## is not loaded, refused through `SaProblems` with a sentence saying so when
## it is. False for every other path, a `.sad` above all, which the caller
## goes on to open.
##
## The skeleton reads the four formats Godot decodes, and TIFF, Radiance HDR
## and OpenRaster are the image formats module's of the base modules, so a
## Sara run without it would otherwise hand a `.tif` to the `.sad` loader and
## say only that the file is corrupt.
static func refuses_unread(path: String) -> bool:
    var extension := path.get_extension().to_lower()
    if not MODULE_PICTURES.has(extension):
        return false
    var registry := formats()
    if registry.flat_named(path) != null or registry.layered_named(path) != null:
        return false
    SaProblems.refuse(
        "SaImageImport",
        (
            TranslationServer.translate("'%s' is a %s picture, and Sara reads %s only with the image formats module loaded.")
            % [path.get_file(), MODULE_PICTURES[extension], MODULE_PICTURES[extension]]
        )
    )
    return true


## A PNG at *path*, the PNG format's reader. A sixteen-bit one is decoded here,
## for the reason at the top, and one this class cannot unpack is read at eight
## by Godot's loader and says which bits went missing.
static func read_png(path: String) -> Image:
    return read_png_decoded(path, decode_png16(path))


## The pixels of the sixteen-bit PNG at *path*, or null when it is not one, or
## is one this class cannot unpack. Touches no registry and reports nothing,
## so a worker thread may run it and hand the answer to [method read_png_decoded].
static func decode_png16(path: String) -> Image:
    var header := png_header(path)
    if not png16_unpacks(header):
        return null
    return SaPng16Decode.of(FileAccess.get_file_as_bytes(path), header)


## Whether *path* holds a PNG of sixteen bits [method decode_png16] unpacks,
## which is the file a caller that cannot wait seconds reads off its thread.
static func reads_png16(path: String) -> bool:
    return sniff_format(path) == "png" and png16_unpacks(png_header(path))


## Whether the PNG *header* names sixteen bits this class can unpack.
static func png16_unpacks(header: Dictionary[String, Variant]) -> bool:
    return SaTyped.int_at(header, "bit_depth", 0) == PNG_SIXTEEN_BITS and _png16_refusal(header).is_empty()


## The PNG at *path* given *decoded*, what [method decode_png16] answered for
## it, so the decode can run where it does not hold the window and the rest,
## which reports, runs where the caller is. Null *decoded* reads the file at
## eight bits through Godot's loader, saying so when it carried sixteen.
static func read_png_decoded(path: String, decoded: Image) -> Image:
    if decoded != null:
        return decoded
    var header := png_header(path)
    var lost := ""
    if SaTyped.int_at(header, "bit_depth", 0) == PNG_SIXTEEN_BITS:
        lost = _png16_refusal(header)
        if lost.is_empty():
            lost = "its pixel stream could not be unpacked"
    var decode := func(image: Image, bytes: PackedByteArray) -> Error: return image.load_png_from_buffer(bytes)
    return read_with_engine(path, decode, lost)


## *path* through Godot's own loader, the reader of a format Godot decodes.
## *decode* is `func(image: Image, bytes: PackedByteArray) -> Error`, the
## loader for the format whose bytes the file holds, used only when they
## disagree with its name, so a correctly named file takes Godot's own loader
## alone. Trying `load` first and falling back would print Godot's own
## decoder error to the console for a file that then opens perfectly well.
## *lost* is what a sixteen-bit PNG read at eight gave up, said once it opens.
static func read_with_engine(path: String, decode: Callable, lost: String = "") -> Image:
    var image := Image.new()
    var actual := sniff_format(path)
    var claimed := claimed_format(path)
    var mislabelled := actual != "" and actual != claimed
    var err := image.load(path)
    if mislabelled:
        var bytes := FileAccess.get_file_as_bytes(path)
        err = decode.call(image, bytes) if not bytes.is_empty() else ERR_FILE_CANT_READ
    if err == OK and not image.is_empty():
        if not lost.is_empty():
            # Sixteen bits of the file were there to keep and are not, and a
            # painter is told rather than handed the narrower picture in silence.
            SaProblems.refuse(
                "SaImageImport",
                (
                    TranslationServer.translate(
                        "'%s' carries sixteen bits a channel and %s, so it was read at eight and the extra bits are lost."
                    )
                    % [path, lost]
                )
            )
        return image

    var reason := error_string(err)
    if mislabelled:
        reason += ", and its contents are %s rather than the %s its name claims" % [actual.to_upper(), claimed.to_upper()]
    elif actual == "":
        reason += ", and its first bytes match no format Sara reads"
    SaProblems.refuse("SaImageImport", TranslationServer.translate("Could not read '%s' as an image (%s).") % [path, reason])
    return null


## The PNG in *bytes* as an image, or null with the reason reported against
## *source*, the name the painter knows it by. The bytes entry to the decoder
## [method read] runs on a file, for a PNG that is not a file of its own: a
## layer of an OpenRaster zip. A sixteen-bit one keeps its sixteen bits, and one
## this class cannot unpack is read at eight and says so, as a file would.
static func read_png_bytes(bytes: PackedByteArray, source: String) -> Image:
    var header := png_of(bytes)
    if header.is_empty():
        SaProblems.refuse("SaImageImport", TranslationServer.translate("'%s' is not a PNG.") % source)
        return null
    var lost := ""
    if SaTyped.int_at(header, "bit_depth", 0) == PNG_SIXTEEN_BITS:
        lost = _png16_refusal(header)
        if lost.is_empty():
            var decoded := SaPng16Decode.of(bytes, header)
            if decoded != null:
                return decoded
            lost = "its pixel stream could not be unpacked"
    var image := Image.new()
    var err := image.load_png_from_buffer(bytes)
    if err != OK or image.is_empty():
        SaProblems.refuse(
            "SaImageImport", TranslationServer.translate("Could not read '%s' as an image (%s).") % [source, error_string(err)]
        )
        return null
    if not lost.is_empty():
        SaProblems.refuse(
            "SaImageImport",
            (
                TranslationServer.translate(
                    "'%s' carries sixteen bits a channel and %s, so it was read at eight and the extra bits are lost."
                )
                % [source, lost]
            )
        )
    return image


## What an 8-bit PNG, JPEG or WebP holds against what an EXR holds. See the note
## at the top: the wrong one lands a mid grey at 0.5 where it should be 0.214.
##
## From the bytes rather than from the extension, for the reason `read` gives:
## a file whose name lies about its format lies about its colour space with it,
## and an EXR called `.jpg` would otherwise be read as sRGB now that the reader
## opens it. The extension is the fallback for a file that cannot be opened, so
## the answer is the old one whenever there is nothing better.
##
## A PNG that names its gamut in a `cICP` chunk opens as that gamut through
## sRGB's curve, which is what Sara writes. Without the chunk a P3 export
## opened as sRGB, and its red came back duller than it went out. A picture
## that carries an ICC profile, a PNG, a JPEG, a WebP or a TIFF, opens in the
## gamut and the curve the profile names, and an EXR in the gamut of its
## `chromaticities`.
##
## [method named_space_for] is the half of this the file decided, and
## [method convention_for] the half the format's habit did. The Import Fit
## window shows the two apart.
static func space_for(path: String) -> SaColorSpace:
    var named := named_space_for(path)
    return named if named != null else convention_for(path)


## The gamut the file at *path* names itself, or null when it names none.
##
## The format's own `named_space` first: a PNG's `cICP` chunk, which wins over
## its `iCCP` as the PNG specification asks, an EXR's `chromaticities`, and a
## TIFF's profile when it is one Sara writes. Then the ICC profile the file
## carries, [method profile_for], when Sara can read it. So a null here is "the
## file did not say, or said it in a profile Sara cannot use", which is not the
## same as the file saying sRGB, and the Import Fit window words the cases apart.
static func named_space_for(path: String) -> SaColorSpace:
    var format := _format_at(path)
    if format == null:
        return null
    if format.named_space.is_valid():
        var named: SaColorSpace = format.named_space.call(path)
        if named != null:
            return named
    var profile := _embedded(format, path)
    if profile == null or profile.space == null:
        return null
    return SaEmbeddedProfile.as_preset(profile.space)


## The ICC profile the file at *path* carries, read, or null when it carries
## none or its format's own `named_space` answered first. A profile Sara cannot
## use comes back with its `problem` said and no `space`, which the Import Fit
## window shows.
static func profile_for(path: String) -> SaIccProfile:
    var format := _format_at(path)
    if format == null or (format.named_space.is_valid() and format.named_space.call(path) != null):
        return null
    return _embedded(format, path)


static func _embedded(format: SaImageFormat, path: String) -> SaIccProfile:
    if not format.embedded_profile.is_valid():
        return null
    var icc: PackedByteArray = format.embedded_profile.call(path)
    if icc.is_empty():
        return null
    var profile := SaIccProfile.parse(icc)
    if profile.name.is_empty():
        profile.name = path.get_file()
    return profile


## What the format's convention says about the file at *path*, for a file that
## names no gamut of its own: linear sRGB for a format that holds light, an EXR
## and a Radiance HDR, and sRGB for everything else. Read
## from the bytes before the extension, for the reason `read` gives.
##
## A Radiance file holds light rather than a curve, as an EXR does, so the two
## share the convention. Its header may carry a `PRIMARIES` line, which
## the module's reader reads past, so the file is taken in sRGB's primaries, as
## Blender and Godot take one.
static func convention_for(path: String) -> SaColorSpace:
    var format := _format_at(path)
    return SaColorSpace.linear_srgb() if format != null and format.linear else SaColorSpace.srgb()


## The flat format the bytes of *path* claim, or the one its name does when
## no format recognises them or the file cannot be opened.
static func _format_at(path: String) -> SaImageFormat:
    var actual := sniff_format(path)
    return formats().find(StringName(actual)) if actual != "" else formats().flat_named(path)


## Which storage depth *image* names of its own accord, or -1 when it names
## none.
##
## The sibling of `space_for` above, and asked the same way round: the gamut is
## a convention about the format and this is a fact about the pixels. Godot's
## EXR decoder keeps the file's own channel width, half or full, so a float file
## has already answered and nothing should overrule it. An 8-bit PNG, JPEG or
## WebP has no float width to report, and reading one at F32 would be a default
## dressed as an answer.
##
## -1 rather than F32, because "the file did not say" and "the file said 32" are
## different states and only the first one is a question to ask a painter.
##
## **A sixteen-bit PNG answers F32 and does not ask.** It names sixteen bits of
## integer rather than a float width, and Sara has no integer storage to offer
## it, so the choice is between a half that carries eleven bits of the sixteen
## and a float that carries all of them. Nothing is being decided for the
## painter that the file did not decide first, and the row is still theirs to
## move.
##
## A TIFF answers the same way through the format its reader hands back: a
## float or a sixteen-bit file is full floats and answers F32, and an eight-bit
## one is bytes and answers -1, as an eight-bit PNG does. A Radiance file
## answers F16 or F32 through the halves or the floats its reader hands
## back, whichever keeps every value the file holds.
static func depth_for(image: Image) -> int:
    if image == null:
        return -1
    match image.get_format():
        Image.FORMAT_RH, Image.FORMAT_RGH, Image.FORMAT_RGBH, Image.FORMAT_RGBAH:
            return SaColorSpace.Depth.F16
        Image.FORMAT_RF, Image.FORMAT_RGF, Image.FORMAT_RGBF, Image.FORMAT_RGBAF:
            return SaColorSpace.Depth.F32
    return -1


## What the PNG at *path* says about itself, or an empty dictionary when the
## file is not a PNG or its bytes do not open with a whole `IHDR`. See
## [method png_of], which is the walk itself.
static func png_header(path: String) -> Dictionary[String, Variant]:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var head := file.get_buffer(mini(file.get_length(), PNG_HEADER_BYTES))
    file.close()
    return png_of(head)


## What the PNG in *bytes* says about itself: `width`, `height`, `bit_depth`,
## `colour_type`, `interlace`, the two method bytes, its pixel data under
## `idat`, and under `cicp_primaries` the gamut code a `cICP` chunk names
## through sRGB's curve, -1 when it names none. An empty dictionary when the
## bytes are not a PNG or do not open with a whole `IHDR`.
##
## **One walk for the two questions the reader asks.** Handed the first
## `PNG_HEADER_BYTES` of a file it answers the header and finds no `IDAT`, which
## is what decides whether the pixels are decoded here, and handed the whole
## file it also carries the stream to the decoder. It reads no further than the
## bytes it was given, so a truncated buffer ends the walk rather than indexing
## past it.
##
## Sixty-four bits of length would be a file larger than any disk, and PNG caps
## a chunk at 2^31-1, so the four bytes are read as a plain integer.
static func png_of(bytes: PackedByteArray) -> Dictionary[String, Variant]:
    if bytes.size() < PNG_HEADER_BYTES or bytes.slice(0, 8) != PackedByteArray(PNG_SIGNATURE):
        return {}
    var at := 8
    var out: Dictionary[String, Variant] = {}
    var idat := PackedByteArray()
    var out_cicp := -1
    while at + 12 <= bytes.size():
        var length := _u32_be(bytes, at)
        if at + 12 + length > bytes.size():
            break
        var type := bytes.slice(at + 4, at + 8).get_string_from_ascii()
        if type == "IHDR" and length == 13:
            out = {
                "width": _u32_be(bytes, at + 8),
                "height": _u32_be(bytes, at + 12),
                "bit_depth": bytes[at + 16],
                "colour_type": bytes[at + 17],
                "compression": bytes[at + 18],
                "filter_method": bytes[at + 19],
                "interlace": bytes[at + 20],
            }
        elif type == "cICP" and length == 4:
            # The gamut a PNG Sara wrote names, kept only through sRGB's curve
            # and full range, the one pairing `SaExportGamut` writes and reads.
            var srgb_curve := bytes[at + 9] == SaExportGamut.CICP_TRANSFER_SRGB and bytes[at + 10] == 0
            out_cicp = bytes[at + 8] if srgb_curve else -1
        elif type == "IDAT":
            idat.append_array(bytes.slice(at + 8, at + 8 + length))
        elif type == "IEND":
            break
        at += 12 + length
    if out.is_empty():
        return {}
    out["idat"] = idat
    out["cicp_primaries"] = out_cicp
    return out


## Why the sixteen-bit PNG *header* names cannot be unpacked here, as a clause
## that follows "and" in the refusal [method read] reports, or "" when it can.
static func _png16_refusal(header: Dictionary[String, Variant]) -> String:
    if SaTyped.int_at(header, "interlace", 1) != PNG_INTERLACE_NONE:
        return "its scanlines are interlaced, which this reader does not unpack"
    if SaTyped.int_at(header, "compression", 1) != PNG_COMPRESSION_DEFLATE:
        return "its header names a compression PNG does not have"
    if SaTyped.int_at(header, "filter_method", 1) != PNG_FILTER_METHOD_ADAPTIVE:
        return "its header names a filter PNG does not have"
    if SaPng16Decode.channels_of(SaTyped.int_at(header, "colour_type", -1)) == 0:
        return "its samples are neither colour nor grey"
    return ""


static func _u32_be(bytes: PackedByteArray, at: int) -> int:
    return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


## Loads *path* into a new layer above the active one. Null, with the reason
## reported, when the file cannot be read.
static func open_into(document: SaDocument, path: String, fit: Fit = Fit.ORIGIN) -> SaLayer:
    if document == null:
        return null
    var image := read(path)
    if image == null:
        return null
    return place(document, image, path.get_file().get_basename(), space_for(path), fit)


## Puts *image* down as a new layer named after *layer_name*, fitted, and
## converted from *source*. The one door for a file, a drop and a paste.
## *step* is the history's row for it, "Place Picture" for a file or a drop
## and "Paste" for a picture off the clipboard, which the painter reads in the
## Undo History docker rather than the "Add Layer" underneath.
static func place(
    document: SaDocument,
    image: Image,
    layer_name: String,
    source: SaColorSpace,
    fit: Fit = Fit.ORIGIN,
    step: String = "Place Picture"
) -> SaLayer:
    if document == null or image == null or image.is_empty():
        return null
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        SaProblems.report("SaImageImport", TranslationServer.translate("No rendering device to upload a picture to."))
        return null
    if fit == Fit.GROW:
        # The canvas grows and the picture lands in one step, so one Ctrl+Z
        # takes back what one Place did.
        var put: Array[SaLayer] = []
        var work := func() -> void:
            grow_to_hold(document, image.get_size())
            put.append(place(document, image, layer_name, source, Fit.ACTUAL, step))
        if document.history != null:
            document.history.as_one(step, work)
        else:
            work.call()
        return put[0] if not put.is_empty() else null

    var at := fit_image(image, document.canvas_size, fit)
    # At 1.0 whatever the Double Resolution switch says, since the picture is
    # uploaded at the document's density.
    var layer := SaLayerOps.new(document).add(&"", null, 1.0, step)
    layer.take_name(_free_name(document, layer_name))
    upload(document, layer, image, at)

    # Converted only where the document stores something else, which is what
    # the kernel already decides from the two descriptors.
    SaColorConversion.new(document).convert_layer(layer, source)

    document.modified = true
    document.invalidate_all_allocated_chunks()
    # Through set_active_layer rather than update_caches alone: the layer was
    # renamed after the add that announced it, and nothing announces a rename,
    # so the layers docker would show "Layer 3" for a file called otherwise until
    # the next rebuild. Pointing the document at the layer again rebuilds it.
    document.set_active_layer(layer)
    return layer


## Grows *document*'s canvas about its middle until it holds *wanted*, a side
## at a time and never smaller, as one Canvas Size step. False when it already
## held it. The Grow the canvas fit, for a desktop picture and a Sara paste.
static func grow_to_hold(document: SaDocument, wanted: Vector2i) -> bool:
    var grown := document.canvas_size.max(wanted).min(Vector2i(SaResample.MAX_DIMENSION, SaResample.MAX_DIMENSION))
    if grown == document.canvas_size:
        return false
    return SaCrop.new(document).resize_to(grown, Vector2i(1, 1))


## Resizes *image* for *fit* and answers where its top left goes. Negative on
## an axis a picture larger than the canvas hangs over, which is a coordinate
## the sparse chunks hold and the compositor never reaches.
static func fit_image(image: Image, canvas_size: Vector2i, fit: Fit) -> Vector2i:
    match fit:
        Fit.STRETCH:
            image.resize(canvas_size.x, canvas_size.y, Image.INTERPOLATE_BILINEAR)
        Fit.INSIDE:
            var factor := minf(float(canvas_size.x) / float(image.get_width()), float(canvas_size.y) / float(image.get_height()))
            image.resize(
                maxi(1, roundi(float(image.get_width()) * factor)),
                maxi(1, roundi(float(image.get_height()) * factor)),
                Image.INTERPOLATE_BILINEAR
            )
        Fit.ORIGIN:
            return Vector2i.ZERO
    @warning_ignore("integer_division")
    return (canvas_size - image.get_size()) / 2


## Uploads *image* into *layer*'s chunks at the document's depth, allocating a
## chunk only where the image reaches, including where it reaches past the
## canvas.
static func upload(document: SaDocument, layer: SaLayer, image: Image, at: Vector2i = Vector2i.ZERO) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        return
    if image.is_compressed():
        image.decompress()
    var half := document.color_space.depth == SaColorSpace.Depth.F16
    image.convert(Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)

    # The whole picture, not the part that fits. The compositor draws the
    # document rectangle and ignores the rest, so the overhang costs chunks and
    # nothing else until something crops or resizes.
    var covered := Rect2i(at, image.get_size())
    if covered.size.x <= 0 or covered.size.y <= 0:
        return
    # The chunk edge is the layer's to declare rather than 256 (hard rule 3),
    # and the chunk asked for it is one the picture covers: a probe at the
    # origin would allocate a chunk a centred picture never reaches.
    var pixel := layer.get_or_create_chunk(_grid_of(covered.position, SaChunk.SIZE)).pixel_size()
    var first := _grid_of(covered.position, pixel)
    var last := _grid_of(covered.end - Vector2i.ONE, pixel)
    for gy in range(first.y, last.y + 1):
        for gx in range(first.x, last.x + 1):
            var grid_pos := Vector2i(gx, gy)
            var chunk := layer.get_or_create_chunk(grid_pos)
            var origin := grid_pos * pixel
            var part := Rect2i(origin, Vector2i(pixel, pixel)).intersection(covered)
            var tile := Image.create_empty(pixel, pixel, false, image.get_format())
            tile.blit_rect(image, Rect2i(part.position - at, part.size), part.position - origin)
            rd.texture_update(chunk.albedo().rid, 0, tile.get_data())
            layer.mark_unresolved(grid_pos)


## The chunk a document pixel is in. Its own function because integer division
## truncates towards zero, so -1 / 256 is 0 and the chunk left of the canvas
## would be the chunk on it.
static func _grid_of(pixel_pos: Vector2i, pixel: int) -> Vector2i:
    return Vector2i(floori(float(pixel_pos.x) / float(pixel)), floori(float(pixel_pos.y) / float(pixel)))


static func _free_name(document: SaDocument, wanted: String) -> String:
    var taken: Dictionary[String, bool] = {}
    for child in document.get_children():
        taken[str(child.name)] = true
    var base := wanted if not wanted.is_empty() else "Image"
    var candidate := base
    var number := 2
    while taken.has(candidate.validate_node_name()):
        candidate = "%s %d" % [base, number]
        number += 1
    return candidate
