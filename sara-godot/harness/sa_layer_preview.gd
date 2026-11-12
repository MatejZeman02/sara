## The small form of a layer read: what a notebook shows rather
## than computes with, made smaller and eight bits a channel on the graphics
## card, so a slider move reads back a few hundred KB where a 1920 by 1080
## layer in float32 is 33 MB.
##
## Handed the layer's texels already copied into one texture, which is how the
## `read_pixels` step gathers a rectangle. One dispatch of
## `shaders/compute/read_preview.gmacs` covers the preview and never the
## canvas, each preview texel the average of the box of texels it covers, and
## writes a storage buffer of packed bytes, which is all that is read back. A
## buffer and not an `rgba8` image, because the dialect takes float image
## formats only and keeps integer ones out on purpose.
##
## Each value is clipped and a NaN zeroed before the average, which is what
## `sara.tone_map` does to a full read, so the preview's mean is the full
## picture's to within one step of eight bits. The clip is on a picture for a
## screen and never on the layer, which the kernel only reads (hard rule 5).
##
## Its own class beside the step rather than inside it, because it owns a
## kernel, a size rule and a readback the float read has none of, and the
## step's folder is one a reader takes in whole.
extends RefCounted

## The kernel that makes the preview.
const SHADER := "read_preview"

## Where the kernel reads the gathered texels and writes the preview.
const BINDING_SOURCE: int = 0
const BINDING_PREVIEW: int = 1


## The size the preview of *source* is at *longest* texels on the long side at
## most: the long side *longest*, the short one in proportion and at least one
## texel, and *source* itself when it is no larger, so a small rectangle is
## narrowed and never enlarged.
static func size_for(source: Vector2i, longest: int) -> Vector2i:
    var long_side := maxi(source.x, source.y)
    if long_side <= longest or long_side <= 0:
        return source
    var scale := float(longest) / float(long_side)
    return Vector2i(maxi(1, roundi(source.x * scale)), maxi(1, roundi(source.y * scale)))


## *texture* made *size* and eight bits a channel, as the bytes of an `RGBA8`
## image, row by row. Empty when there is no device.
static func bytes_of(texture: SaTexture, size: Vector2i) -> PackedByteArray:
    if GlobalShaderCompiler.get_rd() == null:
        return PackedByteArray()
    var zeros := PackedByteArray()
    zeros.resize(size.x * size.y * 4)
    var preview := SaCompute.Buffer.new(zeros)
    var compute := SaCompute.new(SHADER)
    compute.use_storage_format(texture.format)
    compute.set_texture(BINDING_SOURCE, texture.rid)
    compute.set_buffer(BINDING_PREVIEW, preview.rid)
    var steps := Vector2(texture.size) / Vector2(size)
    compute.set_params({"out_w": float(size.x), "out_h": float(size.y), "step_x": steps.x, "step_y": steps.y})
    compute.dispatch_kernel(SHADER, SaCompute.groups_for(size.x), SaCompute.groups_for(size.y), 1)
    return preview.read()
