## Sara's picture formats that Godot reads not at all or not well enough: TIFF,
## Radiance HDR and OpenRaster, each read and the two that write written by a
## class of its own folder.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## They live outside the skeleton, which keeps the four the engine reads,
## PNG, JPEG, WebP and EXR. Each registers through
## [method SaContext.register_image_format], the call open to any module, so
## the open dialog's Image line and the Export dialog's format list name them
## only while this module is loaded, and a skeleton without it refuses
## a `.tif`, `.hdr` or `.ora` with a sentence rather than a crash.
##
## Registered after the skeleton's four, so the open dialog's extensions read
## `png`, `jpg`, `jpeg`, `webp`, `exr`, `tif`, `tiff`, `hdr` and `ora`, and the
## Export dialog lists PNG, JPG, EXR, TIFF and OpenRaster, the order both
## always had.
##
## What the readers and writers need of the skeleton, the PNG bytes, the
## colour profiles and the canvas read back for a file, they ask through
## [SaPictureFile], the door's page for a picture file. OpenRaster also walks
## the layer tree and draws each layer as the compositor does, which is the
## document's own business and not behind the door.
##
## The sentences of the Export dialog are each format's: what a value outside
## 0 to 1 becomes at the default depth, with and without the rolloff, and
## TIFF's sixteen bits apart, since that depth clips where the float does not.
extends SaModule

const CLIPPED := "Values below 0 or above 1 are clipped."
const ROLLED := "A value above 1 is rolled off the way View > Tonemap Highlights does, and a value below 0 is still clipped."
const HALF_SIZE := " The file is half the size of the float one."

## The first four bytes of a TIFF: little-endian `II` and big-endian `MM`, each
## with the version 42 in its own byte order, and the same two with BigTIFF's 43,
## which the reader refuses by name rather than leaving to "match no format".
## Plain arrays, compared with `Array(head)`, because a `PackedByteArray` built
## in a constant is not a constant expression.
const TIFF_SIGNATURES: Array = [
    [0x49, 0x49, 0x2A, 0x00],
    [0x4D, 0x4D, 0x00, 0x2A],
    [0x49, 0x49, 0x2B, 0x00],
    [0x4D, 0x4D, 0x00, 0x2B],
]


func get_id() -> StringName:
    return &"sara-image-formats"


func get_name() -> String:
    return "Sara Image Formats"


func register(ctx: SaContext) -> void:
    ctx.register_image_format(tiff())
    ctx.register_image_format(radiance())
    ctx.register_image_format(open_raster())


## The registry drops what this module registered when its context is torn
## down, so there is nothing to undo here.
func unregister(_ctx: SaContext) -> void:
    pass


## TIFF: read by `SaTiffReader`, since Godot has no TIFF decoder, and written by
## `SaExportTiff` at sixteen-bit integer or thirty-two-bit float, the integer
## file half the size and clipping where the float keeps every value.
static func tiff() -> SaImageFormat:
    var format := SaImageFormat.new(&"tiff", "TIFF")
    format.extensions = PackedStringArray(["tif", "tiff"])
    format.claims = func(head: PackedByteArray) -> bool: return head.size() >= 4 and Array(head.slice(0, 4)) in TIFF_SIGNATURES
    format.reader = func(path: String) -> Image: return SaTiffReader.read(path)
    format.named_space = func(path: String) -> SaColorSpace: return SaTiffReader.named_space_at(path)
    format.embedded_profile = func(path: String) -> PackedByteArray: return SaTiffReader.profile_at(path)
    format.writer = func(easel: SaEasel, path: String, o: SaImageFormat.Write) -> Error:
        return SaExportTiff.export(easel, path, o.depth, o.rolloff, o.mapping, o.relief)
    format.suffix = ".tiff"
    format.save_filter = "*.tif, *.tiff ; TIFF Image"
    format.depths = [{"id": 16, "label": "16-bit integer"}, {"id": 32, "label": "32-bit float"}]
    format.default_depth = 32
    format.rows = [SaImageFormat.ROW_RELIEF]
    format.names_author = true
    format.note = "Every value survives, and the file is large."
    format.depth_notes = {16: CLIPPED + HALF_SIZE}
    format.depth_notes_rolled = {16: ROLLED + HALF_SIZE}
    format.result_line = "Format: %s, %s, uncompressed"
    return format


## Radiance HDR: read only, by `SaRadianceReader`, because Godot's loader clamps
## past 65,408 and refuses most of the format's layouts. The whole first token
## and nothing longer is the claim, which is what the reader compares, so a file
## claimed as Radiance is never refused for its first line.
static func radiance() -> SaImageFormat:
    var format := SaImageFormat.new(&"hdr", "Radiance HDR")
    format.extensions = PackedStringArray(["hdr"])
    format.claims = func(head: PackedByteArray) -> bool:
        for magic: String in SaRadianceReader.MAGICS:
            var at := magic.length()
            if head.size() > at and head.slice(0, at) == magic.to_ascii_buffer() and char(head[at]) in [" ", "\t", "\r", "\n"]:
                return true
        return false
    format.reader = func(path: String) -> Image: return SaRadianceReader.read(path)
    format.linear = true
    return format


## OpenRaster: the layers as PNGs in a zip, opened as a document of its own or
## brought into the open one, and written at PNG's depths through the same
## rolloff, colour only.
static func open_raster() -> SaImageFormat:
    var format := SaImageFormat.new(&"ora", "OpenRaster")
    format.extensions = PackedStringArray(["ora"])
    format.opener = func(path: String, document: SaDocument, depth: int) -> Error:
        return SaOraReader.new(path, depth).open_into(document)
    format.importer = func(path: String, document: SaDocument) -> Array[SaLayer]:
        return SaOraReader.new(path).import_into(document)
    format.open_filter = "*.ora ; OpenRaster"
    format.writer = func(easel: SaEasel, path: String, o: SaImageFormat.Write) -> Error:
        return SaExportOra.export(easel, path, o.depth, o.rolloff, o.mapping, o.dither)
    format.suffix = ".ora"
    format.save_filter = "*.ora ; OpenRaster Image"
    format.depths = [{"id": 8, "label": "8-bit"}, {"id": 16, "label": "16-bit"}]
    format.default_depth = 8
    format.rows = [SaImageFormat.ROW_DITHER]
    format.keeps_layers = true
    format.names_author = true
    format.note = CLIPPED
    format.note_rolled = ROLLED
    format.result_line = "Format: %s, %s, with its layers"
    format.losses = func(document: SaDocument) -> PackedStringArray: return SaExportOra.losses(document)
    format.relief_loss = "OpenRaster stores colour only, so impasto is not included. It stays in the .sad file."
    return format
