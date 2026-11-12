## The readback door, and the only one the filter door has.
##
## Everything else in the filter door keeps the pixels in VRAM:
## [SaFilterContext] copies chunks into a texture, a kernel dispatches over it,
## and [SaFilterApply] copies the result back, all GPU to GPU. This file is the
## one place a filter may ask for the texels themselves, as a Godot `Image` in
## `RGBAF` it can loop over with `get_pixel` and `set_pixel`.
##
## **It is an explicit command and never a stroke.** A filter asks for it by
## name, once, and pays for it visibly. That is the lesson as much as the door:
## a student who sets a CPU blur's radius to 200 watches the app wait, and sees
## why the kernel is the first door and not the second.
##
## **Nothing here writes to a layer.** `write_pixels` uploads the image into a
## texture and hands it to [SaFilterApply], which is what makes the undo step
## the same step the GPU door records, and what keeps that file's claim true:
## apply is the only writer in the whole filter door.
##
## **And in a dialog it hands the image to the preview instead**. A run inside
## a dialog is a preview the dialog will ask for again on the next widget
## change, so a `write_pixels` there shows and Apply writes, which is the
## shape the GPU door already had. A `write_pixels` outside a dialog, from a
## script or a suite, writes on the spot as it always did.
##
## Static, like [SaFilterApply], and for the same reason: there is no state
## between one read and the next.
class_name SaFilterPixels
extends RefCounted

## The export path's float readback, by script rather than through the autoload
## of the same name. The method is static and calling a static method on an
## instance is a warning the LSP check fails on, which `core/recorder/sa_recorder.gd`
## answers with a `@warning_ignore` and this file answers by not needing one.
const SaExportScript = preload("res://core/export/sa_export.gd")


## The layer's pixels over *ctx*'s rectangle, as an `RGBAF` `Image`.
##
## The same region [method SaFilterContext.layer_pixels] answers, through the
## same copy, read back by the export path's own float readback so nothing
## narrows: an F16 document widens to `RGBAF` exactly, and a value outside zero
## to one survives, because nothing in Sara clamps colour.
##
## Null when the rectangle is empty, which is what the context already reports
## on. The rectangle is left on the context, so [method write] writes back into
## the region that was read and a filter never has to name it twice.
static func read(ctx: SaFilterContext, margin: int = 0) -> Image:
    if ctx == null:
        SaProblems.report("SaFilterPixels", "there is no context to read pixels from.")
        return null
    var texture := ctx.layer_pixels(margin)
    if texture == null:
        return null
    return SaExportScript.get_texture_image_float(texture)


## Writes *image* back into the layer over the rectangle it was read from, as
## one undo step called *step_name*. Answers whether it wrote.
##
## The image is uploaded into a texture at the layer's own depth and handed to
## [SaFilterApply], so the CPU door and the GPU door write through one piece of
## code and record one shape of history. A filter that reads, changes a pixel
## and writes back therefore undoes exactly the way a kernel filter does.
##
## The size has to match the rectangle. An image of another size is refused
## rather than blitted into a corner, because a filter that resized its picture
## has made a mistake no placement rule can guess the intent of.
static func write(ctx: SaFilterContext, image: Image, step_name: String) -> bool:
    if ctx == null or image == null:
        SaProblems.report("SaFilterPixels", "a write needs both a context and an image.")
        return false
    var rect := ctx.rect
    if rect.size.x <= 0 or rect.size.y <= 0:
        SaProblems.report("SaFilterPixels", "nothing was read yet, so there is no rectangle to write back into.")
        return false
    if image.get_size() != rect.size:
        SaProblems.report(
            "SaFilterPixels", "the image is %s and the region read was %s, so it was not written." % [image.get_size(), rect.size]
        )
        return false
    var texture := _uploaded(ctx, image)
    if texture == null:
        return false
    ctx.show(texture)
    # A preview shows and does not write, which is exactly what the GPU door
    # does: `ctx.show` is the whole of a kernel filter's `run` and Apply is the
    # only writer. Written whatever the state of the dialog, a CPU filter would
    # record one undo step per rerun and Cancel would undo none of them.
    # Answering `true` for a preview is not a lie about writing, it is the
    # answer to "was the image accepted", which is the only thing a filter can
    # act on: the size was right, the upload worked, and the result is what
    # Apply will land.
    if ctx._previewing:
        return true
    return SaFilterApply.apply(ctx, step_name)


## One pixel of *image* with the coordinates clamped to its edge.
##
## `Image.get_pixel` outside the picture is an
## error, and a neighbourhood loop over a rectangle reads outside it by
## definition. Clamping to the edge is the same rule the margin already
## follows, so a filter written with a margin and one written without it differ
## in quality rather than in whether they run.
static func at(image: Image, x: int, y: int) -> Color:
    if image == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    var size := image.get_size()
    if size.x <= 0 or size.y <= 0:
        return Color(0.0, 0.0, 0.0, 0.0)
    return image.get_pixel(clampi(x, 0, size.x - 1), clampi(y, 0, size.y - 1))


## *image* in a texture of the layer's own depth, ready for the apply.
##
## The conversion is the import path's: an F16 document takes `RGBAH` and an F32
## one `RGBAF`, and a copy is converted rather than the caller's image, because
## a filter that reads its own image back after writing should find what it
## wrote rather than a narrowed version of it.
static func _uploaded(ctx: SaFilterContext, image: Image) -> SaTexture:
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        SaProblems.report("SaFilterPixels", "there is no rendering device to upload the pixels to.")
        return null
    # The context's own, read the way `SaFilterApply` reads its document and
    # its layer: the depth every texture in a run shares is a fact about the
    # layer, and asking it twice is how two answers start to differ.
    var format: int = ctx.field_format()
    var texture := SaTexture.new(ctx.rect.size, format)
    var payload := image.duplicate() as Image
    if payload.is_compressed():
        payload.decompress()
    payload.convert(Image.FORMAT_RGBAH if format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF)
    rd.texture_update(texture.rid, 0, payload.get_data())
    return texture
