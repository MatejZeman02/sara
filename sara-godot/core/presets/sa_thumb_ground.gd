## The ground a thumbnail is drawn on when the brush lays no paint of its own: bands
## of colour across the picture, laid on the active layer of the throwaway document.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A brush that only changes what is under it (an airbrush that mixes, a blender,
## a filter brush) draws nothing over the bare document, so its picture was an
## empty grey square. Over bands of two colours the same stroke shows what it
## does: a blur softens the edges between them, a smudge drags one into the next,
## a mixing brush lays a veil that takes the colour beneath.
##
## **Laid once, on a document nobody paints on.** Hard rule 1 is the canvas
## during a stroke, and this is the picture's own throwaway document before its
## stroke, as `liquify_picture.gd` lays its grid. The bands are worked out per
## column, so a picture of 512 by 256 costs one pass over its texels.
class_name SaThumbGround
extends RefCounted

## The two colours of the bands, as they are shown. A warm and a cool one of about
## the same lightness, so the dark ink of the plain brushes still reads over both.
const WARM := Color(0.93, 0.66, 0.38, 1.0)
const COOL := Color(0.38, 0.62, 0.9, 1.0)

## How many bands cross the picture's width. Even, so it ends on the other colour
## than it began, and the edge a stroke crosses is seen a few times.
const BANDS: int = 6


## Lays the bands on *document*'s active layer, over every chunk the document
## covers. False with no layer or no device to lay them on.
static func lay(document: SaDocument) -> bool:
    var layer := document.active_layer if document != null else null
    var rd := GlobalShaderCompiler.get_rd()
    if layer == null or rd == null:
        return false
    var size := document.canvas_size
    var warm := document.color_space.from_display(WARM)
    var cool := document.color_space.from_display(COOL)
    var first := layer.get_or_create_chunk(Vector2i.ZERO)
    var edge := first.pixel_size()
    var grid := Vector2i(ceili(float(size.x) / edge), ceili(float(size.y) / edge))
    var laid: Array[Vector2i] = []
    for gy in grid.y:
        for gx in grid.x:
            var at := Vector2i(gx, gy)
            var chunk := layer.get_or_create_chunk(at)
            var texture := chunk.albedo()
            var image := _tile(size, at * edge, edge, warm, cool)
            if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
                image.convert(Image.FORMAT_RGBAH)
            rd.texture_update(texture.rid, 0, image.get_data())
            layer.mark_unresolved(at)
            laid.append(at)
    document.invalidate_chunks(laid)
    return true


## The chunk at *origin*, *edge* texels square, of the bands over a picture of
## *size*, opaque. Texels past the picture are left clear.
static func _tile(size: Vector2i, origin: Vector2i, edge: int, warm: Color, cool: Color) -> Image:
    var texels := PackedFloat32Array()
    texels.resize(edge * edge * 4)
    for y in mini(edge, size.y - origin.y):
        for x in mini(edge, size.x - origin.x):
            var band := int(float(origin.x + x) * BANDS / size.x)
            var colour := warm if band % 2 == 0 else cool
            var at := (y * edge + x) * 4
            texels[at] = colour.r
            texels[at + 1] = colour.g
            texels[at + 2] = colour.b
            texels[at + 3] = 1.0
    return Image.create_from_data(edge, edge, false, Image.FORMAT_RGBAF, texels.to_byte_array())
