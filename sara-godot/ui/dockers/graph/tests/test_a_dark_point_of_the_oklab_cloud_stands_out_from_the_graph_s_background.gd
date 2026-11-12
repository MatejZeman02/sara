## A dark point of the Oklab cloud stands out from the graph's background.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Oklab graph points near black have to stay visible and not fade out. A mark was its cell's colour added to
## the background grey, so a
## black cell drew the grey itself. Read here off the picture the draw kernel
## writes: a picture of one colour bins into one cell, and its mark is the
## texels that change when the picture's colour moves to either of two far
## colours, whose marks sit elsewhere. Each mark has to hold texels whose Oklab
## lightness is at least 0.15 from the background's, and the centre of a light
## one has to be the cell's own colour. The same run on the app is
## `scenarios/a-dark-point-of-the-oklab-cloud-stands-out-from-the-graph-s-background.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const SOURCE := Vector2i(64, 64)

## Two texels a cell at either, as at every size, so the rim and the
## mark are read at the cell the docker draws, with the larger picture's 192
## cells and the smaller one's 96.
const PLOTS: Array[Vector2i] = [Vector2i(384, 384), Vector2i(192, 192)]

## Black, the lightness named next to it, one at the
## background's own lightness, where only a rim can tell a mark from it, and a
## light one.
const LIGHTNESSES: Array[float] = [0.0, 0.05, 0.2, 0.9]

## Far from every grey, so their marks never touch the grey's.
const FAR_ONE := Color(0.9, 0.1, 0.1, 1.0)
const FAR_TWO := Color(0.1, 0.2, 0.9, 1.0)

## How far apart two texels' channels are before they count as different.
const CHANGED := 0.004

## What the frame's RGBA16F and the cloud's 255 steps of lightness allow a
## channel of the centre to differ from its cell's colour by.
const QUANTISED := 0.01


## The stored sRGB of the neutral grey of Oklab lightness *lightness*.
func _grey(lightness: float) -> Color:
    var encoded := OkhsvConversions.srgb_transfer_function(Vector3.ONE * pow(lightness, 3.0))
    return Color(encoded.x, encoded.y, encoded.z, 1.0)


## The Oklab lightness of a texel as the screen shows it.
func _lightness(texel: Vector3) -> float:
    return OkhsvConversions.linear_srgb_to_oklab(OkhsvConversions.srgb_transfer_function_inv(texel)).x


## The cloud a pass over a picture of *color* alone draws at *size*, as RGB
## triples in reading order. Everything it makes is let go before it returns.
func _draw(color: Color, size: Vector2i) -> Array[Vector3]:
    var image := Image.create(SOURCE.x, SOURCE.y, false, Image.FORMAT_RGBAF)
    image.fill(color)
    var source := SaGraphPlot.upload_image(image)
    var plot := SaGraphPlot.new()
    plot.set_plot_size(size)
    var texels: Array[Vector3] = []
    if source == null or not plot.run_over_document(source, SOURCE, SaColorSpace.srgb(), "cloud"):
        return texels
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(plot.shown.texture_rd_rid, 0)
    for at in range(0, bytes.size(), 8):
        texels.append(Vector3(bytes.decode_half(at), bytes.decode_half(at + 2), bytes.decode_half(at + 4)))
    return texels


func _differs(a: Vector3, b: Vector3) -> bool:
    var off := (a - b).abs()
    return maxf(off.x, maxf(off.y, off.z)) > CHANGED


## The indices of the texels of *color*'s mark: those that differ from both
## far colours' pictures, which only *color*'s own mark can.
func _mark(color: Color, size: Vector2i) -> Dictionary:
    var drawn := _draw(color, size)
    var one := _draw(FAR_ONE, size)
    var two := _draw(FAR_TWO, size)
    var at: Array[int] = []
    if drawn.size() != size.x * size.y or one.size() != drawn.size() or two.size() != drawn.size():
        return {"texels": drawn, "at": at}
    for i in drawn.size():
        if _differs(drawn[i], one[i]) and _differs(drawn[i], two[i]):
            at.append(i)
    return {"texels": drawn, "at": at}


func test_every_mark_stands_out_from_the_background_at_any_lightness() -> void:
    var ground := _lightness(Vector3.ONE * SaGraphPlot.BACKGROUND)
    for size in PLOTS:
        for lightness in LIGHTNESSES:
            var mark := _mark(_grey(lightness), size)
            var at: Array[int] = mark["at"]
            var texels: Array[Vector3] = mark["texels"]
            assert_true(at.size() > 0, "a mark of lightness %.2f is drawn at %d texels" % [lightness, size.x])
            var widest := 0.0
            for i in at:
                widest = maxf(widest, absf(_lightness(texels[i]) - ground))
            assert_true(
                widest >= 0.15,
                (
                    "the mark of lightness %.2f at %d texels reaches %.3f from the background's %.3f"
                    % [lightness, size.x, widest, ground]
                )
            )


func test_a_light_marks_centre_is_its_cells_colour() -> void:
    var want := _grey(0.9)
    var expect := Vector3(want.r, want.g, want.b)
    for size in PLOTS:
        var mark := _mark(want, size)
        var at: Array[int] = mark["at"]
        var texels: Array[Vector3] = mark["texels"]
        if at.is_empty():
            assert_true(false, "the light mark is drawn at %d texels" % size.x)
            continue
        var middle := Vector2.ZERO
        for i in at:
            middle += Vector2(i % size.x, floorf(float(i) / float(size.x)))
        middle /= float(at.size())
        var centre := int(roundf(middle.y)) * size.x + int(roundf(middle.x))
        var off := (texels[centre] - expect).abs()
        assert_true(
            maxf(off.x, maxf(off.y, off.z)) <= QUANTISED,
            "the centre at %d texels draws %s for its cell's %s" % [size.x, texels[centre], expect]
        )


## A bright mark already stands out, so it is drawn whole in its own colour
## and wears no rim: a bright cluster reads as it did before the rim existed.
func test_a_bright_mark_wears_no_rim() -> void:
    var want := _grey(0.9)
    var expect := Vector3(want.r, want.g, want.b)
    var mark := _mark(want, PLOTS[0])
    var texels: Array[Vector3] = mark["texels"]
    var lighter := 0
    for i: int in mark["at"]:
        if _lightness(texels[i]) > _lightness(expect) + 0.02:
            lighter += 1
    assert_eq(lighter, 0, "no texel of a light mark is lighter than its cell")
