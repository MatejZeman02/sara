## The ground a liquify preset's picture is drawn on: a grid of dark lines, the
## level ones wavy, laid on the active layer of the throwaway document the
## presets chooser paints a preset's picture in.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Private to the liquify folder, laid by `state_liquify.gd` when its tool is
## readied for a picture, in `begin_picture`.
##
## Each liquify preset has a thumbnail of what it does. A picture
## is the preset's stroke over the bare document, which for a brush shows the
## paint it lays, and liquify lays none: a push over nothing moves nothing. So
## its picture is drawn over lines, the upright ones straight and the level
## ones wavy, so a push drags them, a twirl curls them, a shrink pinches them,
## a grow swells them and a smooth takes the waves out where it passes.
##
## **Laid from the processor, once, on a document nobody paints on.** Hard rule
## 1 is the canvas during a stroke, and this is the picture's own throwaway
## document before its stroke, as the suites lay their stripes. The coverage
## is worked out only near each line, a few texels a column, so a picture of
## 512 by 256 costs about thirty thousand steps rather than one per texel.
extends RefCounted

const SaLiquifySessionScript = preload("res://modules/sara-base-modules/base/liquify/sa_liquify_session.gd")

## The lines' spacing, half width, swing and the period of the level lines'
## waves, as shares of the picture's height, so a tip's square picture and a
## stroke's strip of 512 by 256 show the same grid. At 256 that is a line every
## 64 texels, 6.4 wide, swinging 8 either side over 64: a wave a preset of a
## hundred or so straightens best, and in the chooser's cell of 128 by 64 a line
## every 16 texels about 1.5 wide.
const SPACING: float = 0.25
const HALF_WIDTH: float = 0.0125
const SWING: float = 0.03125
const PERIOD: float = 0.25
## The lines' colour, black, which every colour space stores as nothing in its
## three numbers, over the document's mid grey ground.
const INK := Color(0.0, 0.0, 0.0, 1.0)
## The twirls a Reconstruct's picture is drawn over, their size as a share of
## the picture's height and their turn in radians.
const UNSETTLE_SIZE: float = 0.7
const UNSETTLE_TURN: float = 1.2


## Lays the grid on *document*'s active layer, over every chunk the document
## covers. False with no layer or no device to lay it on.
static func lay(document: SaDocument) -> bool:
    var layer := document.active_layer if document != null else null
    var rd := GlobalShaderCompiler.get_rd()
    if layer == null or rd == null:
        return false
    var size := document.canvas_size
    var cover := coverage(size)
    var first := layer.get_or_create_chunk(Vector2i.ZERO)
    var edge := first.pixel_size()
    var grid := Vector2i(ceili(float(size.x) / edge), ceili(float(size.y) / edge))
    var laid: Array[Vector2i] = []
    for gy in grid.y:
        for gx in grid.x:
            var at := Vector2i(gx, gy)
            var chunk := layer.get_or_create_chunk(at)
            var texture := chunk.albedo()
            var image := _tile(cover, size, at * edge, edge)
            if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
                image.convert(Image.FORMAT_RGBAH)
            rd.texture_update(texture.rid, 0, image.get_data())
            layer.mark_unresolved(at)
            laid.append(at)
    document.invalidate_chunks(laid)
    return true


## Twirls the grid in three places across the middle of a picture of *size*,
## in *session*, which a Reconstruct's picture is drawn over, so the stroke
## shows the lines it put back beside those it did not reach.
static func unsettle(session: SaLiquifySessionScript, size: Vector2i) -> void:
    var height := float(size.y)
    for share: float in [0.25, 0.5, 0.75]:
        session.twirl(Vector2(float(size.x) * share, height * 0.5), height * UNSETTLE_SIZE, 1.0, UNSETTLE_TURN)


## How much of each texel of a picture of *size* the lines cover, row by row.
static func coverage(size: Vector2i) -> PackedFloat32Array:
    var cover := PackedFloat32Array()
    cover.resize(size.x * size.y)
    var height := float(size.y)
    var spacing := SPACING * height
    var half := HALF_WIDTH * height
    var swing := SWING * height
    var period := PERIOD * height
    var reach := ceili(half + 1.0)
    # The upright lines, straight, the same in every row.
    var line_x := spacing * 0.5
    while line_x < float(size.x):
        for x in range(maxi(0, floori(line_x) - reach), mini(size.x, ceili(line_x) + reach + 1)):
            var across := _edge(absf(float(x) + 0.5 - line_x), half)
            for y in size.y:
                _cover(cover, y * size.x + x, across)
        line_x += spacing
    # The level lines, wavy, measured across their own slope, so a line is
    # as wide where it climbs as where it is flat.
    var line_y := spacing * 0.5
    while line_y < height:
        for x in size.x:
            var phase := TAU * (float(x) + 0.5) / period
            var middle := line_y + swing * sin(phase)
            var slope := swing * TAU / period * cos(phase)
            var stretch := sqrt(1.0 + slope * slope)
            var band := ceili(reach * stretch)
            for y in range(maxi(0, floori(middle) - band), mini(size.y, ceili(middle) + band + 1)):
                _cover(cover, y * size.x + x, _edge(absf(float(y) + 0.5 - middle) / stretch, half))
        line_y += spacing
    return cover


## The share of a texel whose middle is *distance* from a line's middle that a
## line *half* wide covers, with a texel of edge.
static func _edge(distance: float, half: float) -> float:
    return clampf(half + 0.5 - distance, 0.0, 1.0)


static func _cover(cover: PackedFloat32Array, index: int, share: float) -> void:
    if share > cover[index]:
        cover[index] = share


## The chunk at *origin*, *edge* texels square, of the lines *cover* over a
## picture of *size*, as black whose alpha is that coverage, straight alpha as
## the chunks hold it. Texels past the picture are left clear.
static func _tile(cover: PackedFloat32Array, size: Vector2i, origin: Vector2i, edge: int) -> Image:
    var texels := PackedFloat32Array()
    texels.resize(edge * edge * 4)
    for y in mini(edge, size.y - origin.y):
        var row := (origin.y + y) * size.x + origin.x
        for x in mini(edge, size.x - origin.x):
            var share := cover[row + x]
            if share > 0.0:
                var at := (y * edge + x) * 4
                texels[at] = INK.r
                texels[at + 1] = INK.g
                texels[at + 2] = INK.b
                texels[at + 3] = INK.a * share
    return Image.create_from_data(edge, edge, false, Image.FORMAT_RGBAF, texels.to_byte_array())
