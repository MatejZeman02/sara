## White Point's pick: the colour a click reads, averaged over the square the
## Eyedropper tool's Sample size names, as light-linear sRGB.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **One setting for both.** The side is the Eyedropper's own `sample_size`, kept
## in the base module's preferences under `eyedropper_sample_size`, so a painter
## who set 9 for the tool picks a white point over nine by nine texels too, and
## at the default of 1 the pick is the one texel Levels' `read_texel` reads.
##
## **What it reads.** What this White Point filters, the layer's own paint or
## the record's input through `SaNodeInput`, never the composite with the
## preview drawn over it. The square is clipped to the canvas, and each chunk it
## crosses is copied into its place in one readback texture the square's size,
## with the tool's `texels_of` turning document pixels into a layer's texels.
## That is one copy and one read back a click, the read back hard rule 1 allows
## a pick.
##
## **Painted texels alone, in light.** A texel no chunk holds adds nothing, and
## each one read is weighted by its alpha, as the tool's own mean weighs it, so
## a square that runs off the paint is the mean of the paint. The mean is taken
## of light-linear sRGB and not of the stored values, because the filter scales
## light: a click on the average of two tints should give the correction a click
## on their mean colour gives, and on an sRGB or Oklab document the mean of the
## stored values is a different, darker colour than the mean of their light.
class_name SaWhitePointSquare
extends RefCounted

const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

## None picked, in every channel.
const NOTHING := Vector3(NAN, NAN, NAN)

var _readback: SaTexture = null


## The side the Eyedropper tool's Sample size names, in texels.
static func side() -> int:
    return StateEyedropperScript.new().sample_size


## The light-linear sRGB mean of the painted texels of *input* in the square of
## *size* texels around *at*, in document coordinates, on a document of
## *canvas_size* in *space*. [constant NOTHING] where nothing is painted.
func read(input: SaNodeInput, at: Vector2, canvas_size: Vector2i, space: SaColorSpace, size: int) -> Vector3:
    var centre := Vector2i(floori(at.x), floori(at.y))
    if not Rect2i(Vector2i.ZERO, canvas_size).has_point(centre):
        return NOTHING
    @warning_ignore("integer_division")
    var half := maxi(size, 1) / 2
    var canvas := Rect2i(Vector2i.ZERO, canvas_size)
    var square := Rect2i(centre - Vector2i(half, half), Vector2i.ONE * (half * 2 + 1)).intersection(canvas)
    var pieces := _pieces(input, square)
    if pieces.is_empty():
        return NOTHING
    var first: SaTexture = pieces[0][0]
    var density := float(first.size.x) / float(SaChunk.SIZE)
    var whole := StateEyedropperScript.texels_of(square, density)
    if _readback == null or _readback.format != first.format or _readback.size != whole.size:
        _readback = SaTexture.new(whole.size, first.format)
    var rd := GlobalShaderCompiler.get_rd()
    var covered: Array = []
    for piece: Array in pieces:
        var source: SaTexture = piece[0]
        var texels := StateEyedropperScript.texels_of(piece[2], density)
        var from := texels.position - StateEyedropperScript.texels_of(Rect2i(piece[1], Vector2i.ONE), density).position
        var target := texels.position - whole.position
        rd.texture_copy(
            source.rid,
            _readback.rid,
            Vector3(from.x, from.y, 0),
            Vector3(target.x, target.y, 0),
            Vector3(texels.size.x, texels.size.y, 1),
            0,
            0,
            0,
            0
        )
        for y in range(target.y, target.y + texels.size.y):
            for x in range(target.x, target.x + texels.size.x):
                covered.append(y * whole.size.x + x)
    return mean_light(rd.texture_get_data(_readback.rid, 0), first.format, covered, space)


## The light-linear sRGB mean of the texels *indices* of *data*, each weighted
## by its alpha, for a document in *space*. [constant NOTHING] when no texel
## holds paint.
static func mean_light(data: PackedByteArray, format: int, indices: Array, space: SaColorSpace) -> Vector3:
    var light := Vector3.ZERO
    var alpha := 0.0
    for index: int in indices:
        var texel := SaFieldSpec.decode_texel(data, format, index)
        if texel.a <= 0.0:
            continue
        light += SaWhitePointFilter.linear_of(texel, space) * texel.a
        alpha += texel.a
    if alpha <= 0.0:
        return NOTHING
    return light / alpha


## Each chunk of *input* the *square* crosses that holds a texture, as
## `[texture, its origin in document pixels, the part of the square on it]`.
static func _pieces(input: SaNodeInput, square: Rect2i) -> Array:
    var pieces: Array = []
    if square.size.x <= 0 or square.size.y <= 0:
        return pieces
    @warning_ignore("integer_division")
    var first := square.position / SaChunk.SIZE
    @warning_ignore("integer_division")
    var last := (square.end - Vector2i.ONE) / SaChunk.SIZE
    for gy in range(first.y, last.y + 1):
        for gx in range(first.x, last.x + 1):
            var grid := Vector2i(gx, gy)
            var source := input.at(grid)
            if source == null or not source.rid.is_valid():
                continue
            var origin := grid * SaChunk.SIZE
            pieces.append([source, origin, Rect2i(origin, Vector2i.ONE * SaChunk.SIZE).intersection(square)])
    return pieces
