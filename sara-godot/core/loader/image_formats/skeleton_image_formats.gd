## The skeleton's picture formats, the four Godot's own `Image` reads,
## registered through the call a module makes,
## [method SaContext.register_image_format].
##
## Four, in the order the registry keeps: PNG, JPEG, WebP and EXR. The Export
## dialog lists the three of them that write, PNG, JPG and EXR, and the open
## dialog's Image line names `png`, `jpg`, `jpeg`, `webp` and `exr`. Each claim
## is a header test of the file's first bytes, so a WebP
## called `.jpg` still reaches the WebP reader.
##
## WebP is among them because Godot decodes it already, Sara's own note images
## are written in it, and refusing the extension was refusing a format the
## engine reads. TIFF, Radiance HDR and OpenRaster, which Sara reads and writes
## with code of its own, are the image formats module's of the base modules,
## registered after these four so both lists keep the
## order they always had.
##
## The Export dialog's sentences are each format's, the words the dialog's
## tables held: what a value outside 0 to 1 becomes, with and without the
## rolloff.
extends RefCounted

## The skeleton module's id, which a registry built with no app registers under.
const MODULE_ID := &"sara-skeleton"

const CLIPPED := "Values below 0 or above 1 are clipped."
const ROLLED := "A value above 1 is rolled off the way View > Tonemap Highlights does, and a value below 0 is still clipped."
## PNG's depth rows.
const BYTE_OR_SIXTEEN: Array = [{"id": 8, "label": "8-bit"}, {"id": 16, "label": "16-bit"}]


static func register(ctx: SaContext) -> void:
    ctx.register_image_format(_png())
    ctx.register_image_format(_jpeg())
    ctx.register_image_format(_webp())
    ctx.register_image_format(_exr())


## PNG: eight bits through Godot's encoder or sixteen through `SaPng16Writer`,
## named for its gamut by a `cICP` chunk, and read back with all sixteen bits.
## Written over frames where the caller asks so, `SaExportInTurns`.
static func _png() -> SaImageFormat:
    var png := SaImageFormat.new(&"png", "PNG")
    png.extensions = PackedStringArray(["png"])
    png.claims = func(head: PackedByteArray) -> bool:
        return head.size() >= 8 and head.slice(0, 8) == PackedByteArray(SaImageImport.PNG_SIGNATURE)
    png.reader = func(path: String) -> Image: return SaImageImport.read_png(path)
    png.named_space = func(path: String) -> SaColorSpace:
        return SaExportGamut.space_for_primaries(SaExportGamut.png_primaries_at(path))
    # Below the `cICP` chunk, which wins over an `iCCP` as the PNG specification asks.
    png.embedded_profile = func(path: String) -> PackedByteArray: return SaEmbeddedProfile.png(path)
    png.writer = func(easel: SaEasel, path: String, o: SaImageFormat.Write) -> Error:
        return SaExport.export_png(easel, path, o.depth, o.rolloff, o.mapping, o.relief, o.dither, o.stops)
    png.writer_in_turns = func(easel: SaEasel, path: String, o: SaImageFormat.Write, then: Callable) -> void:
        SaExport.export_png_in_turns(easel, path, o, then)
    png.suffix = ".png"
    png.save_filter = "*.png ; PNG Image"
    png.depths = BYTE_OR_SIXTEEN
    png.default_depth = 8
    png.rows = [SaImageFormat.ROW_DITHER, SaImageFormat.ROW_RELIEF]
    png.names_author = true
    png.note = CLIPPED
    png.note_rolled = ROLLED
    return png


## JPEG: always eight bits and lossy, laid over one colour where it is
## transparent, since the file has no alpha.
static func _jpeg() -> SaImageFormat:
    var jpeg := SaImageFormat.new(&"jpg", "JPG")
    jpeg.extensions = PackedStringArray(["jpg", "jpeg"])
    jpeg.claims = func(head: PackedByteArray) -> bool:
        return head.size() >= 3 and head[0] == 0xFF and head[1] == 0xD8 and head[2] == 0xFF
    jpeg.reader = func(path: String) -> Image:
        var picture := SaImageImport.read_with_engine(
            path, func(image: Image, bytes: PackedByteArray) -> Error: return image.load_jpg_from_buffer(bytes)
        )
        if picture != null:
            Orientation.upright(picture, Orientation.of(path))
        return picture
    jpeg.embedded_profile = func(path: String) -> PackedByteArray: return SaEmbeddedProfile.jpeg(path)
    jpeg.writer = func(easel: SaEasel, path: String, o: SaImageFormat.Write) -> Error:
        return SaExport.export_jpg(easel, path, o.quality, o.rolloff, o.mapping, o.relief, o.flatten, o.dither)
    jpeg.suffix = ".jpg"
    jpeg.save_filter = "*.jpg, *.jpeg ; JPEG Image"
    jpeg.default_depth = 8
    jpeg.rows = [SaImageFormat.ROW_QUALITY, SaImageFormat.ROW_FLATTEN, SaImageFormat.ROW_DITHER, SaImageFormat.ROW_RELIEF]
    jpeg.note = CLIPPED
    jpeg.note_rolled = ROLLED
    jpeg.result_line = "Format: %s, %s, lossy"
    return jpeg


## WebP: read only, `RIFF` then the chunk length then `WEBP`.
static func _webp() -> SaImageFormat:
    var webp := SaImageFormat.new(&"webp", "WebP")
    webp.extensions = PackedStringArray(["webp"])
    webp.claims = func(head: PackedByteArray) -> bool:
        return (
            head.size() >= 12 and head.slice(0, 4) == "RIFF".to_ascii_buffer() and head.slice(8, 12) == "WEBP".to_ascii_buffer()
        )
    webp.reader = func(path: String) -> Image:
        return SaImageImport.read_with_engine(
            path, func(image: Image, bytes: PackedByteArray) -> Error: return image.load_webp_from_buffer(bytes)
        )
    webp.embedded_profile = func(path: String) -> PackedByteArray: return SaEmbeddedProfile.webp(path)
    return webp


## OpenEXR: linear floats, written in linear sRGB whatever the document's gamut,
## at full float or at half, which its own switch chooses, and read in the gamut
## its `chromaticities` attribute names when it carries one.
static func _exr() -> SaImageFormat:
    var exr := SaImageFormat.new(&"exr", "EXR")
    exr.extensions = PackedStringArray(["exr"])
    exr.claims = func(head: PackedByteArray) -> bool:
        return head.size() >= 4 and head.slice(0, 4) == PackedByteArray([0x76, 0x2F, 0x31, 0x01])
    exr.reader = func(path: String) -> Image:
        return SaImageImport.read_with_engine(
            path, func(image: Image, bytes: PackedByteArray) -> Error: return image.load_exr_from_buffer(bytes)
        )
    exr.linear = true
    exr.named_space = func(path: String) -> SaColorSpace: return SaEmbeddedProfile.exr_space(path)
    exr.writer = func(easel: SaEasel, path: String, o: SaImageFormat.Write) -> Error:
        return SaExport.export_exr(easel, path, o.half, o.relief)
    exr.suffix = ".exr"
    exr.save_filter = "*.exr ; OpenEXR Image"
    exr.default_depth = 32
    exr.rows = [SaImageFormat.ROW_HALF, SaImageFormat.ROW_RELIEF]
    exr.note = "Every value survives, negatives and highlights included."
    return exr


## The EXIF orientation of a JPEG, which a phone or a camera writes instead of
## turning the pixels: a portrait photograph is stored as landscape pixels with
## a 6 or an 8, and Godot's decoder hands the pixels back as stored. Every
## viewer turns them, so a picture that opens on its side is Sara's fault.
##
## The tag sits in the APP1 segment, which comes before the scan and is at most
## 64 KiB long, so only the file's head is read. A file with no EXIF, or one
## whose tag cannot be followed inside its segment, answers 1 and reads as
## stored, since a guess would turn a good picture.
class Orientation:
    ## Enough for any APP1 segment and the few segments before it.
    const HEAD_BYTES := 1 << 17
    ## The TIFF tag of the orientation, in IFD0.
    const TAG := 0x0112
    const SHORT := 3
    const AS_STORED := 1
    ## An APP1 segment of EXIF starts with this word and two zero bytes.
    const EXIF := "Exif"
    const EXIF_HEADER := 6

    ## The orientation the JPEG at *path* asks for, 1 to 8, or 1.
    static func of(path: String) -> int:
        var file := FileAccess.open(path, FileAccess.READ)
        if file == null:
            return AS_STORED
        var head := file.get_buffer(HEAD_BYTES)
        return in_bytes(head)

    ## The orientation in a JPEG's first bytes *head*.
    static func in_bytes(head: PackedByteArray) -> int:
        if head.size() < 4 or head[0] != 0xFF or head[1] != 0xD8:
            return AS_STORED
        var at := 2
        while at + 4 <= head.size():
            if head[at] != 0xFF:
                return AS_STORED
            var marker := head[at + 1]
            if marker == 0xFF:
                # Fill bytes may stand before a marker.
                at += 1
                continue
            # The scan starts, and nothing before it named an orientation.
            if marker == 0xDA or marker == 0xD9:
                return AS_STORED
            var length := (head[at + 2] << 8) | head[at + 3]
            if length < 2:
                return AS_STORED
            var body := at + 4
            var end := mini(at + 2 + length, head.size())
            if marker == 0xE1 and _is_exif(head.slice(body, end)):
                var found := _in_tiff(head.slice(body + EXIF_HEADER, end))
                if found != AS_STORED:
                    return found
            at += 2 + length
        return AS_STORED

    static func _is_exif(segment: PackedByteArray) -> bool:
        if segment.size() < EXIF_HEADER or segment[4] != 0 or segment[5] != 0:
            return false
        return segment.slice(0, 4).get_string_from_ascii() == EXIF

    ## The orientation in the TIFF block *tiff* of an APP1 segment, read only
    ## inside the block, so a cut or damaged one answers 1.
    static func _in_tiff(tiff: PackedByteArray) -> int:
        if tiff.size() < 8:
            return AS_STORED
        var big: bool
        if tiff[0] == 0x4D and tiff[1] == 0x4D:
            big = true
        elif tiff[0] == 0x49 and tiff[1] == 0x49:
            big = false
        else:
            return AS_STORED
        if _number(tiff, 2, 2, big) != 42:
            return AS_STORED
        var ifd := _number(tiff, 4, 4, big)
        if ifd < 8 or ifd + 2 > tiff.size():
            return AS_STORED
        var count := _number(tiff, ifd, 2, big)
        for i in count:
            var entry := ifd + 2 + i * 12
            if entry + 12 > tiff.size():
                return AS_STORED
            if _number(tiff, entry, 2, big) != TAG:
                continue
            if _number(tiff, entry + 2, 2, big) != SHORT:
                return AS_STORED
            var value := _number(tiff, entry + 8, 2, big)
            return value if value >= 1 and value <= 8 else AS_STORED
        return AS_STORED

    static func _number(bytes: PackedByteArray, at: int, size: int, big: bool) -> int:
        var value := 0
        for i in size:
            var byte := bytes[at + i] if big else bytes[at + size - 1 - i]
            value = (value << 8) | byte
        return value

    ## Turns and mirrors *image* in place from how it was stored to how the
    ## *orientation* says it is shown.
    static func upright(image: Image, orientation: int) -> void:
        match orientation:
            2:
                image.flip_x()
            3:
                image.rotate_180()
            4:
                image.flip_y()
            5:
                image.rotate_90(CLOCKWISE)
                image.flip_x()
            6:
                image.rotate_90(CLOCKWISE)
            7:
                image.rotate_90(CLOCKWISE)
                image.flip_y()
            8:
                image.rotate_90(COUNTERCLOCKWISE)
