## The picture loader for a pattern: a PNG or an EXR becomes a grey mask and
## then an `r32f` texture.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Read through `core/image/sa_image_import.gd`, which is the one reader in Sara that
## sniffs a file's bytes rather than trusting its name, so a pattern called
## `.png` that is a WebP opens the way it opens in File > Open. What this file
## adds is the mask rule, and it is the opposite of the tip loader's on purpose:
## a tip is drawn dark where the brush marks, a pattern is a paper, and on
## paper white is where the paint lands. So **luminance times alpha, white is
## one**, with Rec. 709's weights, which are the ones the pixel door's own
## `luminance` uses. A transparent texel is nought however light it is.
##
## An 8-bit picture's grey is kept as encoded rather than linearised. A mask
## is coverage rather than colour: a painter who scans a paper and reads a
## half grey in it means half, and the import's colour conversion is for a
## picture that lands on a layer, which this never does.
##
## Loading is CPU work done once, outside any stroke, and the upload is the
## texture's first and only trip, as the tip loader's is, and the canvas is
## never read back.
class_name SaPatternImage
extends RefCounted

## Rec. 709, as the pixel door's `luminance` helper weighs a colour.
const LUMINANCE := Vector3(0.2126, 0.7152, 0.0722)


## *path* decoded and reduced to one float per texel, `Image.FORMAT_RF`, or
## null with the reason already reported by the import.
static func read_mask(path: String) -> Image:
    var picture := SaImageImport.read(path)
    if picture == null:
        return null
    return mask_of(picture)


## The grey mask of *picture*, one float per texel in `FORMAT_RF`.
##
## Through `FORMAT_RGBAF` so an EXR keeps its floats and an 8-bit file is
## widened once rather than read texel by texel through `get_pixel`, which
## builds a `Color` for each and is ten times the work over a scan.
static func mask_of(picture: Image) -> Image:
    var wide := picture.duplicate() as Image
    wide.convert(Image.FORMAT_RGBAF)
    var texels := wide.get_data().to_float32_array()
    var count := wide.get_width() * wide.get_height()
    var mask := PackedFloat32Array()
    mask.resize(count)
    for i in count:
        var at := i * 4
        var grey := texels[at] * LUMINANCE.x + texels[at + 1] * LUMINANCE.y + texels[at + 2] * LUMINANCE.z
        mask[i] = clampf(grey * texels[at + 3], 0.0, 1.0)
    return Image.create_from_data(wide.get_width(), wide.get_height(), false, Image.FORMAT_RF, mask.to_byte_array())


## *mask* uploaded to an `r32f` texture of its own size, or null when there is
## no mask or no device.
static func upload(mask: Image) -> SaTexture:
    if mask == null or mask.get_width() <= 0 or mask.get_height() <= 0:
        return null
    var texture := SaTexture.new(mask.get_size(), RenderingDevice.DATA_FORMAT_R32_SFLOAT)
    if texture.rd == null or not texture.rid.is_valid():
        return null
    texture.rd.texture_update(texture.rid, 0, mask.get_data())
    return texture
