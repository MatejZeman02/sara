## The Levels dialog's Lightness channel counts Oklab L.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Levels histogram matches Photoshop's and Krita's, so Lightness must not
## draw the composite's Rec. 709 luma, which is Master a second time. So the layer here is three chunks
## of three known
## lightnesses, a dark grey, a pure red and a light grey, chosen so that luma
## and Oklab L put their peaks in different bins, and the graph is run the way
## the dialog runs it, over the layer.
extends "res://tests/test_framework.gd"

## Real dispatches into a real buffer.
const REQUIRES_GPU := true

## The fourth row of the count buffer, the one Master and Lightness share.
const GREY_ROW := 3

## How many bins either side of the expected one a peak may land in. The
## kernel rounds a float into a bin and the expectation here is computed on
## the CPU, so one bin of slack is the rounding and nothing more.
const SLACK := 1


## The three bands, as the display colours an sRGB document stores. The greys
## are built from the L they should read, so the test states its answer.
func _bands() -> Array[Color]:
    return [_grey_of_lightness(0.25), Color(1.0, 0.0, 0.0, 1.0), _grey_of_lightness(0.75)]


## A neutral grey has Oklab L equal to the cube root of its linear value, so
## the grey of a lightness is that lightness cubed, encoded for the screen.
func _grey_of_lightness(lightness: float) -> Color:
    var linear := pow(lightness, 3.0)
    return Color(linear, linear, linear, 1.0).linear_to_srgb()


func _oklab_l(display: Color) -> float:
    var linear := display.srgb_to_linear()
    return SaOklab.from_linear_srgb(Vector3(linear.r, linear.g, linear.b)).x


func _luma(display: Color) -> float:
    return display.r * 0.2126 + display.g * 0.7152 + display.b * 0.0722


func _bin(value: float) -> int:
    return int(clampf(value, 0.0, 1.0) * float(SaGraphPlot.BINS - 1) + 0.5)


## An sRGB document, so what a chunk stores is what the screen shows and the
## band colours above are the stored values. One chunk per band, side by side.
func _layer_of_bands(easel: SaEasel) -> SaLayer:
    var layer := easel.document.get_node_or_null("Layer 1") as SaLayer
    var bands := _bands()
    for index in bands.size():
        layer.get_or_create_chunk(Vector2i(index, 0)).clear(bands[index])
    return layer


func _easel() -> SaEasel:
    return SaEasel.create_default(Vector2i(SaChunk.SIZE * 3, SaChunk.SIZE), null, SaColorSpace.srgb())


func _counts(layer: SaLayer, channel: String) -> PackedInt32Array:
    var plot := SaGraphPlot.new()
    plot.scale = "linear"
    plot.histogram_channel = channel
    assert_true(plot.run_over_layer(layer, SaColorSpace.srgb(), "histogram"), "The %s pass runs" % channel)
    return plot.read_counts()


## How many samples of the grey row fall within `SLACK` of *bin*.
func _near(counts: PackedInt32Array, bin: int) -> int:
    var sum := 0
    for at in range(maxi(0, bin - SLACK), mini(SaGraphPlot.BINS - 1, bin + SLACK) + 1):
        sum += counts[GREY_ROW * SaGraphPlot.BINS + at]
    return sum


func test_the_lightness_peaks_sit_where_oklab_l_puts_them() -> void:
    var easel := _easel()
    var layer := _layer_of_bands(easel)
    var side: int = layer.chunks[Vector2i.ZERO].pixel_size()
    var per_band := side * side
    var counts := _counts(layer, "lightness")

    for band: Color in _bands():
        var lightness := _oklab_l(band)
        var luma := _luma(band)
        assert_true(absi(_bin(lightness) - _bin(luma)) > 2 * SLACK, "the band %s tells L from luma" % band)
        assert_eq(_near(counts, _bin(lightness)), per_band, "Lightness puts the band %s at L %.3f" % [band, lightness])
        assert_eq(_near(counts, _bin(luma)), 0, "and nothing at its luma %.3f" % luma)
    easel.free()


## Master keeps the luma it had, so the two entries of the dropdown are two
## graphs rather than one drawn twice.
func test_master_still_counts_luma() -> void:
    var easel := _easel()
    var layer := _layer_of_bands(easel)
    var side: int = layer.chunks[Vector2i.ZERO].pixel_size()
    var counts := _counts(layer, "master")

    for band: Color in _bands():
        assert_eq(_near(counts, _bin(_luma(band))), side * side, "Master puts the band %s at its luma" % band)
    easel.free()


## The colour rows and their own largest
## bins are the same counts to the last sample whichever channel is chosen.
func test_the_rgb_rows_are_unchanged_at_tolerance_zero() -> void:
    var easel := _easel()
    var layer := _layer_of_bands(easel)
    var master := _counts(layer, "master")
    var lightness := _counts(layer, "lightness")
    var rgb_rows := 3 * SaGraphPlot.BINS

    assert_eq(lightness.slice(0, rgb_rows), master.slice(0, rgb_rows), "red, green and blue count the same")
    for row in 3:
        var slot := SaGraphPlot.MAX_SLOT + 1 + row
        assert_eq(lightness[slot], master[slot], "and row %d keeps its own largest bin" % row)
    easel.free()
