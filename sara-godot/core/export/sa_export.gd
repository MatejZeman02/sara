## Writing a document, or the canvas showing it, out to a file.
##
## Supported formats:
##   • PNG: flat composite of the canvas texture, at 8 bits through Godot's own
##             encoder or 16 through SaPng16Writer, which is the depth
##             Godot's `save_png_to_buffer` has no argument for
##   • JPG: flat composite with configurable quality, laid over one colour
##             where it is transparent, since a JPEG has no alpha
##   • .sad: the custom binary container, which is [SaSadFile]'s page
##
## A PNG also names who painted it, when and with what, which is
## [SaExportMetadata]. TIFF and OpenRaster are the image formats module's, in
## the base modules, and reach what they share with these through
## [SaPictureFile].
##
## A class of statics rather than an autoload, because it holds no state, and
## a call through the class name reads as `SaExport.save_sad(...)` either way.
##
## Every form that takes a canvas takes the [SaEasel] instead, because the
## easel owns the document and the output and the view owns neither, and
## `core` never names `render`.
class_name SaExport
extends RefCounted

## The float storage formats a texture is read back from, and the image format
## of the same bytes. F16 is a document depth, not a lesser path: an F16 chunk
## read back as RGBAH and widened to RGBAF is exact, because every half has a
## float that equals it. Rejecting it here is what would have made EXR export
## fail on precisely the documents that chose the smaller depth.
const FLOAT_IMAGE_FORMATS := {
    RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT: Image.FORMAT_RGBAF,
    RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT: Image.FORMAT_RGBAH,
}
## The exports written over frames, named through the facade so a save that
## waits for them sees the door only.
const InTurns := preload("res://core/export/sa_export_in_turns.gd")
## The bytes a texel takes in each of those image formats.
const FLOAT_TEXEL_BYTES := {Image.FORMAT_RGBAF: 16, Image.FORMAT_RGBAH: 8}

# ---------------------------------------------------------------------------
# Canvas image extraction
# ---------------------------------------------------------------------------


## Reads the GPU composite texture back to CPU memory and returns an RGBA8 Image.
## Returns null and pushes an error if the easel or its output is unavailable.
static func get_canvas_image(easel: SaEasel) -> Image:
    if easel == null:
        push_error("SaExport.get_canvas_image: easel is null")
        return null
    if easel.output == null:
        push_error("SaExport.get_canvas_image: the easel has no output")
        return null

    # Through the float reader rather than straight from the bytes, because an
    # RGBAF image built from whatever comes back is only right at F32: an F16
    # document hands back half the bytes per texel and Image rejects the
    # buffer. One place decides how a texel is laid out, and this is not it.
    #
    # Rounded to the nearest step rather than by the engine's narrowing, which
    # puts every value on the step below it. The stored numbers are written as they
    # are: a caller that wants the document's gamut asks
    # `SaExportGamut.encoded_byte_image` for it.
    #
    # What the window left unshown is composited first, as every reader of the
    # whole picture does, and every visible layer with it while Isolate Active
    # Layer leaves some out of the canvas.
    SaLocalView.flush_whole(easel)
    return SaExportGamut.byte_image(easel.output)


## The picture a person sees, for the preview a `.sad` carries and the
## recent-files grid draws from it.
##
## `get_canvas_image` above writes the document's stored numbers as they are,
## which is what a PNG named for the document's gamut wants and is wrong for
## anything a painter looks at: a default document stores Oklab, so its mid grey
## is `L 0.6, a 0, b 0` and narrowed straight to eight bits that is a dark red.
## This converts from the document's own space into plain sRGB first, the way a
## recorded frame does through `SaRecorder.display_image`.
static func get_preview_image(easel: SaEasel) -> Image:
    if easel == null:
        push_error("SaExport.get_preview_image: easel is null")
        return null
    if easel.output == null:
        push_error("SaExport.get_preview_image: the easel has no output")
        return null
    if easel.document == null:
        push_error("SaExport.get_preview_image: the easel has no document")
        return null
    SaLocalView.flush_whole(easel)
    return SaExportGamut.encoded_byte_image(easel.output, easel.document.color_space, SaColorSpace.srgb())


## The picture [method get_preview_image] answers, taken on the card now and
## read over the frames after, for a save in the background. Null when the
## easel has nothing to take.
static func take_preview(easel: SaEasel) -> PreviewShot:
    if easel == null or easel.output == null or easel.document == null or not easel.output.rid.is_valid():
        return null
    SaLocalView.flush_whole(easel)
    var shot := PreviewShot.new(easel.output, easel.document.color_space)
    return shot if shot.picture != null else null


## The preview of a save, as [method get_preview_image] makes it, without the
## wait in the frame of the key.
##
## **Why.** That read waited for the card once a cell, 135 times on a 3840 by
## 2160 picture, and narrowed eight million texels on the main thread, a
## quarter of a second in the frame that took the snapshot.
##
## **How.** The output is copied whole on the card when this is made, one copy
## and no dispatch, so the picture is the one the painter saw at the key. A
## save then asks for its cells a few a frame, [method cell] putting each
## through the conversion and the rounding of `SaExportGamut` on a scratch of
## its own, and its worker builds the picture of their bytes with [method
## image_of]. The kernels, their order and their numbers are those of
## `SaExportGamut.encoded_byte_image`, so the picture is the same to the byte.
## Off the main device, where no answer comes back as a frame is drawn,
## [method read_now] reads it as that does, over the copy.
class PreviewShot:
    extends RefCounted

    ## The output as it stood, null once let go of.
    var picture: SaTexture = null
    ## The picture's size, and its cells in the order [method image_of] takes
    ## their bytes in.
    var size := Vector2i.ZERO
    var cells: Array[Rect2i] = []
    ## The document's space, which the cells are converted from into sRGB.
    var space: SaColorSpace = null
    var _convert_params := PackedFloat32Array()
    var _rounding: SaExportGamut.Rounding = null
    var _converter: SaCompute = null
    var _rounder: SaCompute = null

    func _init(output: SaTexture, from: SaColorSpace) -> void:
        space = from
        var copy := SaTexture.new(output.size, output.format)
        if not copy.rid.is_valid():
            return
        var whole := Vector3(output.size.x, output.size.y, 1)
        output.rd.texture_copy(output.rid, copy.rid, Vector3.ZERO, Vector3.ZERO, whole, 0, 0, 0, 0)
        picture = copy
        size = output.size
        cells = SaExportGamut.cells_of(size)
        var srgb := SaColorSpace.srgb()
        if from != null and not from.matches(srgb):
            _convert_params = from.to_conversion_push_constant(srgb)
        _rounding = SaExportGamut.Rounding.new(false, Vector2i.ZERO)

    ## Cell *index* of the picture on a scratch of its own, converted and
    ## rounded as an export of it would be, for its asker to read back. Null
    ## once the picture is let go of or the card refused the scratch.
    func cell(index: int) -> SaTexture:
        if picture == null or index < 0 or index >= cells.size():
            return null
        var at := cells[index]
        var scratch := SaTexture.new(Vector2i(SaChunk.SIZE, SaChunk.SIZE), picture.format)
        if not scratch.rid.is_valid():
            return null
        var corner := Vector3(at.position.x, at.position.y, 0)
        picture.rd.texture_copy(picture.rid, scratch.rid, corner, Vector3.ZERO, Vector3(at.size.x, at.size.y, 1), 0, 0, 0, 0)
        if not _convert_params.is_empty():
            if _converter == null:
                _converter = SaCompute.new(SaExportGamut.CONVERT_KERNEL)
            _run(_converter, SaExportGamut.CONVERT_KERNEL, scratch, at, _convert_params)
        if _rounder == null:
            _rounder = SaCompute.new(SaExportGamut.ROUND_KERNEL)
        _run(_rounder, SaExportGamut.ROUND_KERNEL, scratch, at, _rounding.params(at))
        return scratch

    ## Lets go of the copy of the output once every cell is on its scratch.
    func let_go() -> void:
        picture = null

    ## The whole picture read at once and narrowed, for a save off the main
    ## device.
    func read_now() -> Image:
        if picture == null:
            return null
        return SaExportGamut.encoded_byte_image(picture, space, SaColorSpace.srgb())

    ## *kernel* over *scratch* for the cell *at*, as `SaExportGamut` runs it.
    static func _run(compute: SaCompute, kernel: String, scratch: SaTexture, at: Rect2i, params: PackedFloat32Array) -> void:
        compute.use_storage_format(scratch.format)
        compute.set_texture(0, scratch.rid)
        compute.set_push_constant_float_array(params)
        compute.dispatch_kernel(kernel, SaCompute.groups_for(at.size.x), SaCompute.groups_for(at.size.y), 1)

    ## The picture of *bytes*, each the read of a cell's scratch in the order of
    ## [member cells], narrowed to eight bits as `SaExportGamut` narrows it.
    ## Touches no device, so a save's worker calls it. Null when a cell is
    ## missing or not a scratch's size.
    static func image_of(whole: Vector2i, regions: Array[Rect2i], format: int, bytes: Array[PackedByteArray]) -> Image:
        if regions.is_empty() or bytes.size() != regions.size():
            return null
        var image := Image.create_empty(whole.x, whole.y, false, Image.FORMAT_RGBAF)
        var pitch := Vector2i(SaChunk.SIZE, SaChunk.SIZE)
        for index in regions.size():
            var read := SaExport.image_from_bytes(pitch, format, bytes[index])
            if read == null:
                return null
            image.blit_rect(read, Rect2i(Vector2i.ZERO, regions[index].size), regions[index].position)
        image.convert(Image.FORMAT_RGBA8)
        return image


## Reads any RGBA32F SaTexture back as a 32-bit float Image, keeping every value
## exactly as the GPU wrote it.
##
## This is the readback that must never narrow. `get_canvas_image` converts to
## RGBA8, which silently destroys negatives and anything above 1.0, fine for a
## PNG, fatal for the promise that nothing clamps.
## Anything that has to survive the paint -> composite -> export path in full
## precision goes through here instead.
static func get_texture_image_float(texture: SaTexture) -> Image:
    if texture == null:
        push_error("SaExport.get_texture_image_float: texture is null")
        return null
    if not FLOAT_IMAGE_FORMATS.has(texture.format):
        push_error("SaExport.get_texture_image_float: expected a float format, got %d" % texture.format)
        return null

    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        push_error("SaExport.get_texture_image_float: RenderingDevice unavailable")
        return null
    if not texture.rid.is_valid():
        push_error("SaExport.get_texture_image_float: texture RID is invalid")
        return null

    var bytes := rd.texture_get_data(texture.rid, 0)
    if bytes.is_empty():
        push_error("SaExport.get_texture_image_float: texture_get_data returned empty buffer")
        return null
    return texture_image_from_bytes(texture, bytes)


## Asks the card for *texture*'s bytes without waiting for them, and *answer*
## is called with them once the frame the ask went into comes round again.
## Answers whether it was asked, which it is not off the main device, because
## only that one hands an answer back as a frame is drawn, and only as one is.
## The bytes become a picture through [method texture_image_from_bytes].
##
## **The answer is a method of the asker, never a lambda, and binds plain
## values only.** The device keeps *answer* until the frame comes round, and
## one still owed at quit it drops only in the engine's teardown, after
## GDScript is gone. A lambda, or a script's object bound into the callable,
## then frees its script there and aborts the quit (the pitfall
## "Quitting with a read of the card still owed aborts the engine's
## teardown"). A method holds its object by id alone, which also keeps an asker
## let go meanwhile from being kept for the answer. Every
## `buffer_get_data_async` in the tree hands its answer over the same way.
static func ask_texture_bytes(texture: SaTexture, answer: Callable) -> bool:
    if texture == null or not FLOAT_IMAGE_FORMATS.has(texture.format) or not texture.rid.is_valid():
        return false
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null or rd != RenderingServer.get_rendering_device():
        return false
    return rd.texture_get_data_async(texture.rid, 0, answer) == OK


## *bytes*, the whole of *texture* as the card handed it back, as a 32-bit float
## Image. Null when they are not that texture's size.
##
## Created in the storage format, so this is a reinterpretation of the same
## bytes rather than a conversion. The widening afterwards is the only
## conversion, it is lossless, and it means every caller gets RGBAF whatever
## depth the document chose. A read at once and a read the card answered later
## both come through here, so the two are the same picture to the byte.
static func texture_image_from_bytes(texture: SaTexture, bytes: PackedByteArray) -> Image:
    if texture == null:
        return null
    return image_from_bytes(texture.size, texture.format, bytes)


## *bytes* of a texture of *size* at the storage *format*, as [method
## texture_image_from_bytes] reads them. Touches no device, so a worker calls
## it with the shape of a texture it never holds.
static func image_from_bytes(size: Vector2i, format: int, bytes: PackedByteArray) -> Image:
    if not FLOAT_IMAGE_FORMATS.has(format):
        return null
    var image_format: int = FLOAT_IMAGE_FORMATS[format]
    var texel_bytes: int = FLOAT_TEXEL_BYTES[image_format]
    if bytes.size() != size.x * size.y * texel_bytes:
        push_error("SaExport.texture_image_from_bytes: %d bytes for a texture of %s" % [bytes.size(), size])
        return null
    var image := Image.create_from_data(size.x, size.y, false, image_format, bytes)
    if image_format != Image.FORMAT_RGBAF:
        image.convert(Image.FORMAT_RGBAF)
    return image


## Composites *easel* for an export. The live colour is rounded first as a
## save the painter asks for rounds the file, `SaSadSnapshot.round_live`, so the export
## equals one of the same document saved and opened again, and then the whole
## picture is written out of any layer Isolate Active Layer hides.
static func flush_for_export(easel: SaEasel) -> void:
    # A file still opening is read whole first, or the export draws its holes.
    if easel != null:
        SaSadFile.finish_opening(easel.document)
    # What the rounding marked is composited now, rather than at the next
    # frame, since the read comes before it.
    if easel != null and SaSadSnapshot.round_live(easel.document) > 0:
        easel.process_pending_composite()
    SaLocalView.flush_whole(easel)


## The composited output of *easel* as a 32-bit float Image, with no view involved.
static func get_easel_image_float(easel: SaEasel) -> Image:
    if easel == null:
        push_error("SaExport.get_easel_image_float: easel is null")
        return null
    SaLocalView.flush_whole(easel)
    return get_texture_image_float(easel.output)


# ---------------------------------------------------------------------------
# Flat-image export
# ---------------------------------------------------------------------------


## Exports the composited canvas as a PNG file to *path*, in the document's gamut
## and named as it. See [SaExportGamut].
##
## *bits* is eight by default, which is Godot's own encoder and what a caller
## asks for unless it wants sixteen. Sixteen goes through [SaPng16Writer], which
## is the depth Godot's `save_png_to_buffer` takes no argument for.
##
## *tonemap* runs the view's own highlight rolloff over the pixels before they
## clip, rather than clipping them outright: the export dialog's line says
## which of the two a painter is choosing.
##
## *gamut_mapping* is a key of `SaGamutMapping.MODES`, the painter's preference
## as the caller read it. Under oklab a colour the file's cube cannot hold
## gives up chroma with its hue held rather than being cut a channel at a time.
## Every export that narrows takes it, and the two that keep their range, EXR
## and the 32-bit TIFF, never see it.
##
## *bake_relief* lights the picture with the relief the view shows before it is
## written, so a file of a thick painting looks like the painting, and does
## nothing to a document with no height. Every flat export takes it, and [SaExportRelief] is the pass.
##
## *dither* rounds each eight-bit texel by a fixed pattern of up to half a step
## either way, and does nothing at sixteen bits. Off by default, and the bytes
## are then the plain rounding's.
## *exposure_stops* lights the picture up or down by stops before the rolloff,
## as the view's display exposure does, so a file written at two stops under
## shows inside a light four times white what the view shows there at that
## exposure. It rides on the rolloff and does nothing without *tonemap*.
static func export_png(
    easel: SaEasel,
    path: String,
    bits: int = 8,
    tonemap: bool = false,
    gamut_mapping: String = SaGamutMapping.CLIP,
    bake_relief: bool = false,
    dither: bool = false,
    exposure_stops: float = 0.0
) -> Error:
    if easel == null:
        push_error("SaExport.export_png: easel is null")
        return ERR_INVALID_PARAMETER
    flush_for_export(easel)
    var relief := relief_of(easel, bake_relief)
    return export_png_texture(
        easel.output,
        _space_of(easel),
        path,
        bits,
        tonemap_of(easel, tonemap, exposure_stops),
        gamut_mapping,
        null,
        relief,
        dither
    )


## [method export_png] over frames, the picture read and the file written as
## that writes them, with *options* the format's and *then* called with the
## error once the file is whole. `SaExportInTurns` says how.
static func export_png_in_turns(easel: SaEasel, path: String, options: SaImageFormat.Write, then := Callable()) -> void:
    InTurns.png(easel, path, options, then)


## Writes *texture*, which holds *space*'s stored numbers, as a PNG at *path*.
##
## Both depths clip a value outside 0 to 1, because a PNG sample is a fixed point
## between two bounds, unless *tonemap* asks the highlight rolloff to give the
## file something to show above 1 instead. Sixteen is the finer grid, not a way
## past the clip: a document that has to keep a negative exports as EXR or TIFF,
## and the rolloff only ever brings a value below zero towards its own lightness
## and hue, never past zero.
##
## *metadata* is the author, the date and the program the file names, and null
## is an export made now by whoever Preferences names, which is every export a
## painter makes. A suite hands its own to hold the date still.
##
## *relief* is the lit relief to bake, or null for the colour alone, and
## *dither* is [method export_png]'s.
static func export_png_texture(
    texture: SaTexture,
    space: SaColorSpace,
    path: String,
    bits: int = 8,
    tonemap: PackedFloat32Array = PackedFloat32Array(),
    gamut_mapping: String = SaGamutMapping.CLIP,
    metadata: SaExportMetadata = null,
    relief: SaExportRelief = null,
    dither: bool = false,
) -> Error:
    if bits != 8 and bits != 16:
        push_error("SaExport.export_png_texture: a PNG holds 8 or 16 bits a channel, not %d" % bits)
        return ERR_INVALID_PARAMETER
    var bytes := png_bytes(texture, space, bits, tonemap, gamut_mapping, metadata, relief, dither)
    if bytes.is_empty():
        return ERR_CANT_ACQUIRE_RESOURCE
    return write_bytes(path, bytes, "export_png")


## The whole PNG [method export_png_texture] writes, as bytes, or empty when
## nothing could be read back. An OpenRaster file carries it as its
## `mergedimage.png`, so a viewer that reads only that shows the
## picture the PNG export would. *relief* is [method export_png_texture]'s,
## and *dither* [method export_png]'s, which sixteen bits never takes.
static func png_bytes(
    texture: SaTexture,
    space: SaColorSpace,
    bits: int = 8,
    tonemap: PackedFloat32Array = PackedFloat32Array(),
    gamut_mapping: String = SaGamutMapping.CLIP,
    metadata: SaExportMetadata = null,
    relief: SaExportRelief = null,
    dither: bool = false,
) -> PackedByteArray:
    var picture := png_picture(texture, space, bits, tonemap, gamut_mapping, relief, dither)
    var said := metadata if metadata != null else SaExportMetadata.now()
    return png_of_picture(picture, bits, SaExportGamut.gamut_named(space), said)


## The half of [method png_bytes] that needs the card: *texture* read back
## through the conversion, the rolloff, the mapping and, at eight bits, the
## rounding, as a float picture. Null when nothing could be read back. On the
## main thread, the one place a readback is allowed. The arguments are
## [method png_bytes]'s.
static func png_picture(
    texture: SaTexture,
    space: SaColorSpace,
    bits: int = 8,
    tonemap: PackedFloat32Array = PackedFloat32Array(),
    gamut_mapping: String = SaGamutMapping.CLIP,
    relief: SaExportRelief = null,
    dither: bool = false,
) -> Image:
    if bits == 16:
        # The float path, because the depth is the point and the rounding to
        # bytes would throw it away. It is also the readback the document's
        # gamut reaches the file through, the same one TIFF and EXR take.
        return SaExportGamut.encoded_image(texture, space, tonemap, gamut_mapping, relief)
    return SaExportGamut.rounded_image(texture, space, null, tonemap, gamut_mapping, relief, dither)


## The other half: *picture*, as [method png_picture] read it, encoded at
## *bits* and named for *gamut* and *metadata*, or empty bytes for a null
## picture. It touches no device, no node and no setting, so a worker thread
## runs it while the window draws on: the narrowing to eight bits, the
## encoder and both splices.
static func png_of_picture(picture: Image, bits: int, gamut: SaGamut, metadata: SaExportMetadata) -> PackedByteArray:
    if picture == null:
        return PackedByteArray()
    var png := SaPng16Writer.encode(picture) if bits == 16 else SaExportGamut.narrowed(picture).save_png_to_buffer()
    return SaExportGamut.png_with_text(SaExportGamut.png_with_gamut(png, gamut), metadata)


## *png* as an encoder wrote it, named for *space*'s gamut and carrying
## *metadata*, or an export made now when that is null. The same two splices
## whichever encoder wrote the bytes, and every PNG inside an OpenRaster file
## takes them too.
## *image*, a float picture, as a 16-bit PNG's bytes with no chunk beyond the
## picture, which [method named_png] then names.
static func png16(image: Image) -> PackedByteArray:
    return SaPng16Writer.encode(image)


static func named_png(png: PackedByteArray, space: SaColorSpace, metadata: SaExportMetadata) -> PackedByteArray:
    var named := SaExportGamut.png_with_gamut(png, SaExportGamut.gamut_named(space))
    return SaExportGamut.png_with_text(named, metadata if metadata != null else SaExportMetadata.now())


## Exports the composited canvas as a JPEG file to *path*, in the document's gamut
## and named as it. quality is clamped to [0.0, 1.0]. *tonemap* is
## [method export_png]'s, and so are *gamut_mapping*, *bake_relief* and
## *dither*. *flatten* is what a transparent area becomes, [method
## export_jpg_texture]'s.
static func export_jpg(
    easel: SaEasel,
    path: String,
    quality: float = 0.9,
    tonemap: bool = false,
    gamut_mapping: String = SaGamutMapping.CLIP,
    bake_relief: bool = false,
    flatten: Color = Color.WHITE,
    dither: bool = false
) -> Error:
    if easel == null:
        push_error("SaExport.export_jpg: easel is null")
        return ERR_INVALID_PARAMETER
    flush_for_export(easel)
    var relief := relief_of(easel, bake_relief)
    return export_jpg_texture(
        easel.output, _space_of(easel), path, quality, tonemap_of(easel, tonemap), gamut_mapping, relief, flatten, dither
    )


## Writes *texture*, which holds *space*'s stored numbers, as a JPEG at *path*,
## with *relief* baked when there is one.
##
## A JPEG holds no alpha, so the picture is laid over *flatten* first, a
## colour as the picker holds it. The picker's triple is already in the file's
## encoding, the document's gamut through the sRGB curve, so it goes in as it
## is. *dither* is [method export_png]'s.
static func export_jpg_texture(
    texture: SaTexture,
    space: SaColorSpace,
    path: String,
    quality: float = 0.9,
    tonemap: PackedFloat32Array = PackedFloat32Array(),
    gamut_mapping: String = SaGamutMapping.CLIP,
    relief: SaExportRelief = null,
    flatten: Color = Color.WHITE,
    dither: bool = false
) -> Error:
    var img := _byte_image(texture, space, tonemap, gamut_mapping, relief, dither)
    if img == null:
        return ERR_CANT_ACQUIRE_RESOURCE
    var bytes := _flattened(img, flatten).save_jpg_to_buffer(clampf(quality, 0.0, 1.0))
    return write_bytes(path, SaExportGamut.jpg_with_gamut(bytes, SaExportGamut.gamut_named(space)), "export_jpg")


## *picture*, eight bits with straight alpha, laid over an opaque *flatten*:
## an opaque pixel is left as it was, a transparent one is *flatten* exactly
## and a half-covered edge is the mix of the two.
##
## Without it the encoder dropped the alpha and kept the colour under it, and
## under alpha 0 that colour is not one value. The compositor writes black in
## the cells it composited and leaves white in the cells it never touched, so
## a stroke on a transparent document came out as a white page with a black
## block wherever chunks were allocated. A picture with no alpha below 255 is
## handed back as it is, which is every document with an opaque background.
## The image is the export's own readback, so this adds no dispatch.
static func _flattened(picture: Image, flatten: Color) -> Image:
    if picture.detect_alpha() == Image.ALPHA_NONE:
        return picture
    # `blend_rect` takes an image of its own format only, so the ground is
    # RGBA8 at full alpha rather than RGB8, and the encoder drops the alpha.
    var ground := Image.create(picture.get_width(), picture.get_height(), false, Image.FORMAT_RGBA8)
    ground.fill(Color(flatten, 1.0))
    ground.blend_rect(picture, Rect2i(Vector2i.ZERO, picture.get_size()), Vector2i.ZERO)
    return ground


## *texture* in *space*'s export encoding as rounded eight-bit bytes, the one
## narrowing PNG and JPEG share, converted cell by cell rather than over the whole
## output. *tonemap*, *gamut_mapping* and *dither* are [method export_png]'s,
## and *relief* is [method export_png_texture]'s.
static func _byte_image(
    texture: SaTexture,
    space: SaColorSpace,
    tonemap: PackedFloat32Array,
    gamut_mapping: String,
    relief: SaExportRelief,
    dither: bool
) -> Image:
    return SaExportGamut.encoded_byte_image(texture, space, null, tonemap, gamut_mapping, relief, dither)


## The colour space of the document *easel* shows, or null without one.
static func _space_of(easel: SaEasel) -> SaColorSpace:
    return easel.document.color_space if easel.document != null else null


## The relief pass for *easel* when *enabled*, under the document's own light,
## the one the view draws it under, or null when there is no height to bake.
static func relief_of(easel: SaEasel, enabled: bool) -> SaExportRelief:
    if easel == null or easel.document == null:
        return null
    var light := easel.document.relief_light
    return SaExportRelief.prepare(easel, enabled, light.toward(), light.strength)


## The rolloff's push constant for *easel* when *enabled*, empty otherwise. The
## document's own reference white with `SaSettings`' knee and desaturation, the
## same three the view reads, so a highlight the view would roll off is rolled
## off in the file rather than clipped.
##
## The view multiplies by the display exposure and then divides by the white,
## so *exposure_stops* is the white over the exposure's factor here, which is
## the same number reached by the kernel's one division.
static func tonemap_of(easel: SaEasel, enabled: bool, exposure_stops: float = 0.0) -> PackedFloat32Array:
    if not enabled:
        return PackedFloat32Array()
    var blend_white := easel.document.blend_reference_white if easel.document != null else 1.0
    var exposed_white := blend_white / pow(2.0, exposure_stops)
    return SaExportGamut.tonemap_params(true, SaSettings.tonemap_knee, SaSettings.tonemap_desaturation, exposed_white)


## The whole of an encoded file to *path*, reported the way the encoders' own
## saves report it. Safe on a worker thread, which is where an export target's
## file is written.
static func write_bytes(path: String, bytes: PackedByteArray, caller: String) -> Error:
    if bytes.is_empty():
        push_error("SaExport.%s: the encoder wrote nothing for '%s'" % [caller, path])
        return ERR_CANT_CREATE
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        var err := FileAccess.get_open_error()
        push_error("SaExport.%s: failed to write '%s' (err %d)" % [caller, path, err])
        return err
    file.store_buffer(bytes)
    file.close()
    return OK


## Writes *texture* to an OpenEXR file at *path*, at 32-bit float precision by
## default or 16-bit half when *half* is true (the export dialog's option).
##
## The only export that keeps out-of-range values. PNG and JPEG are 8-bit
## containers, so they clamp by definition, EXR is what a scene-referred document
## round-trips through. Verified bit-exact for negatives, values above 1.0 and
## the float extremes in `core/composite/tests/test_no_clamp.gd`, at the default full precision:
## half narrows the mantissa, so a document past half's range is the painter's
## own choice to make, not this method's.
##
## *space* is what *texture* stores, and given one the file holds it as linear
## sRGB, the space every reader opens an EXR in, Sara's own included. A null
## *space* writes the stored numbers unconverted, which is the bit-exact path the
## check above reads. Written that way, the default document would leave as
## Oklab's L, a and b and reopen flat red.
##
## *relief*, when there is one, is lit into the stored numbers on the same cell
## walk, before the conversion.
static func export_exr_texture(
    texture: SaTexture, path: String, half: bool = false, relief: SaExportRelief = null, space: SaColorSpace = null
) -> Error:
    var img := SaExportGamut.linear_image(texture, space, relief)
    if img == null:
        return ERR_CANT_ACQUIRE_RESOURCE
    # `Image.save_exr`'s own bool argument is grayscale, not depth: the file it
    # writes is whatever the Image's own format already is, so half comes from
    # converting first, the same way `get_canvas_image` narrows to RGBA8 for PNG.
    if half:
        img.convert(Image.FORMAT_RGBAH)
    var err := img.save_exr(path)
    if err != OK:
        push_error("SaExport.export_exr_texture: failed to write '%s' (err %d)" % [path, err])
    return err


## Exports the composited canvas as an OpenEXR file to *path*, in linear sRGB
## whatever the document's gamut, with the relief lit into it under
## *bake_relief*, as [method export_png] takes it.
static func export_exr(easel: SaEasel, path: String, half: bool = false, bake_relief: bool = false) -> Error:
    if easel == null:
        push_error("SaExport.export_exr: easel is null")
        return ERR_INVALID_PARAMETER
    flush_for_export(easel)
    return export_exr_texture(easel.output, path, half, relief_of(easel, bake_relief), _space_of(easel))


# ---------------------------------------------------------------------------
# .sad format
# ---------------------------------------------------------------------------


## Saves *document* to a .sad file at *path*, in the v4 container. [SaSadFile]
## holds the layout and the temporary-file dance. With *rounds*, a save the
## painter or the scripting door asked for, full precision colour is rounded to
## 12 significant bits, `SaSadSnapshot`, and otherwise every byte is kept.
static func save_sad(
    document: SaDocument, path: String, keep_versions: int = -1, preview: Image = null, rounds := false
) -> Error:
    SaSadFile.walk_out()
    SaSadSnapshot.begin(document, rounds, path)
    var saved := SaSadFile.save_file(document, path, keep_versions, preview)
    SaSadSnapshot.remember(SaSadSnapshot.end(), saved == OK)
    return saved


## Loads a .sad file from *path* into *document*, replacing its current layers.
##
## `document_compositor` is only needed when loading into a fresh SaDocument that
## does not have one yet, because loading rebuilds the layer caches, which
## composites. Loading into the live document leaves it null.
static func load_sad(document: SaDocument, path: String, document_compositor: SaCompositor = null) -> Error:
    return SaSadFile.load_file(document, path, document_compositor)


## Opens a .sad file from *path* into *document* as [method load_sad] does, and
## calls *then* with the error once it is in, a frame or many later for a file
## whose layers take longer than a frame to read, so the window keeps drawing.
## File > Open's way in. *landed*, when given, makes the window ready for the
## document once its stack is in, before its chunks, and answers the part of
## it the view shows, which is read first, [method SaSadFile.open_over_frames].
static func open_sad(document: SaDocument, path: String, then: Callable, landed: Callable = Callable()) -> void:
    SaSadFile.open_over_frames(document, path, then, landed)
