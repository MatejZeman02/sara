## What a picture format's reader and writer ask of the skeleton: a canvas
## read back in the numbers a file stores, a PNG's bytes named for its gamut,
## the ICC profile a gamut is written with, and a layer filled from a decoded
## picture.
##
## TIFF, Radiance HDR and OpenRaster live in the image formats module of the
## base modules, not in `core`, and a module sees the door only. These are the small, general questions those writers asked of
## `core/export` and `core/image` by name, put where a stranger's format can
## ask them too. Each is a call through to the class that answers it, so the
## numbers a module's file holds are the very numbers PNG and EXR write.
## [SaExportMetadata] sits in this folder beside it, the record of who wrote
## a picture and when, which every writer that names its author carries.
class_name SaPictureFile
extends RefCounted


## Writes *easel*'s whole picture out of any layer Isolate Active Layer hides,
## which every export does before it reads the composite back, with the live
## colour rounded first as a save rounds it, `SaExport.flush_for_export`.
static func flush(easel: SaEasel) -> void:
    SaExport.flush_for_export(easel)


## The composite *easel* shows, read back as floats in the numbers a file of
## its document's gamut stores, ready for an encoder. *keeps_range* is a file
## that keeps every value, a float one, which never takes the rolloff and
## whose gamut mapping is dropped as `SaGamutMapping.for_export` says.
## *tonemap* is the rolloff the Export dialog's check asks for, *mapping* the
## painter's gamut mapping and *bake_relief* the lit relief under the
## document's own light. Null when nothing could be read back.
static func encoded_canvas(
    easel: SaEasel, keeps_range: bool, tonemap: bool = false, mapping: String = SaGamutMapping.CLIP, bake_relief: bool = false
) -> Image:
    if easel == null:
        return null
    flush(easel)
    var relief := SaExport.relief_of(easel, bake_relief)
    var params := tonemap_of(easel, tonemap and not keeps_range)
    var space := easel.document.color_space if easel.document != null else null
    return SaExportGamut.encoded_image(easel.output, space, params, SaGamutMapping.for_export(mapping, keeps_range), relief)


## The rolloff's push constant for *easel* when *enabled*, empty otherwise,
## the one every flat export rolls a highlight off with.
static func tonemap_of(easel: SaEasel, enabled: bool) -> PackedFloat32Array:
    return SaExport.tonemap_of(easel, enabled)


## *texture* read back as floats in the numbers a file of *space* stores,
## through the rolloff *tonemap* and the gamut *mapping*.
static func encoded_image(
    texture: SaTexture, space: SaColorSpace, tonemap: PackedFloat32Array, mapping: String = SaGamutMapping.CLIP
) -> Image:
    return SaExportGamut.encoded_image(texture, space, tonemap, mapping)


## The same at eight bits a channel, rounded through the dither when
## *dither* is on, *origin* where *texture*'s corner sits in the picture so
## the dither's pattern meets the next tile's.
static func encoded_byte_image(
    texture: SaTexture,
    space: SaColorSpace,
    tonemap: PackedFloat32Array,
    mapping: String = SaGamutMapping.CLIP,
    dither: bool = false,
    origin: Vector2i = Vector2i.ZERO
) -> Image:
    return SaExportGamut.encoded_byte_image(texture, space, null, tonemap, mapping, null, dither, origin)


## The whole PNG the PNG export writes of *texture*, as bytes, at *bits* 8 or
## 16, named for *space* and carrying *metadata*. Empty when nothing could be
## read back.
static func png_bytes(
    texture: SaTexture,
    space: SaColorSpace,
    bits: int = 8,
    tonemap: PackedFloat32Array = PackedFloat32Array(),
    mapping: String = SaGamutMapping.CLIP,
    metadata: SaExportMetadata = null,
    dither: bool = false
) -> PackedByteArray:
    return SaExport.png_bytes(texture, space, bits, tonemap, mapping, metadata, null, dither)


## *image*, a float picture, encoded as a PNG of sixteen bits a channel.
static func png16(image: Image) -> PackedByteArray:
    return SaExport.png16(image)


## *png*, as an encoder wrote it, named for *space*'s gamut and carrying
## *metadata*, or an export made now when that is null.
static func named_png(png: PackedByteArray, space: SaColorSpace, metadata: SaExportMetadata) -> PackedByteArray:
    return SaExport.named_png(png, space, metadata)


## The ICC profile a file of *space* is written with, empty for a gamut Sara
## ships no profile for.
static func profile_of(space: SaColorSpace) -> PackedByteArray:
    return SaExportGamut.profile_for(SaExportGamut.gamut_named(space))


## The space whose shipped ICC profile is byte for byte *icc*, through sRGB's
## curve as Sara writes it, or null for a profile Sara did not write.
static func space_of_profile(icc: PackedByteArray) -> SaColorSpace:
    if icc.is_empty():
        return null
    for gamut_id: StringName in SaExportGamut.PROFILE_FILES:
        var gamut := SaGamut.from_id(gamut_id)
        if SaExportGamut.profile_for(gamut) == icc:
            return SaColorSpace.srgb().with_gamut(gamut)
    return null


## The space a PNG's `cICP` colour primaries *code* names, or null for a code
## Sara has no gamut for.
static func space_for_primaries(code: int) -> SaColorSpace:
    return SaExportGamut.space_for_primaries(code)


## The CRC-32 a PNG chunk and a zip entry are checked by.
static func crc32(bytes: PackedByteArray) -> int:
    return SaExportGamut.crc32(bytes)


## Whether *bytes* begin as a PNG does.
static func is_png(bytes: PackedByteArray) -> bool:
    return SaImageImport.format_of_header(bytes.slice(0, SaImageFormatRegistry.HEAD_BYTES)) == "png"


## *bytes*, a whole PNG, decoded at all sixteen bits where it has them, or
## null with the reason reported against *source*.
static func read_png_bytes(bytes: PackedByteArray, source: String) -> Image:
    return SaImageImport.read_png_bytes(bytes, source)


## The `cICP` primaries code a PNG's *bytes* carry, -1 for none.
static func png_primaries(bytes: PackedByteArray) -> int:
    return SaTyped.int_at(SaImageImport.png_of(bytes), "cicp_primaries", -1)


## Fills *layer* of *document* with *image*, its corner at *at*, then converts
## it from *source*, the space the picture's numbers are in, to the
## document's.
static func fill_layer(document: SaDocument, layer: SaLayer, image: Image, at: Vector2i, source: SaColorSpace) -> void:
    SaImageImport.upload(document, layer, image, at)
    SaColorConversion.new(document).convert_layer(layer, source)
