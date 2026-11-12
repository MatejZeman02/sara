## The transfer curve is drawn in a square, so it keeps its shape.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row under the CIE diagram expands to the page's width, and the curve was
## drawn across all of it: on a maximised window about 1,635 by 110, where Gamma
## 3.0 and sRGB were both one flat line along the bottom. Both axes run from
## nought to one, so the plot is a square centred in the row now, the answer
## `SaChromaticityDiagram.plot_rect` gives the horseshoe above it. What is graded
## here is that geometry and that two curves come out as two curves.
## `scenarios/the-transfer-plot-is-drawn-across-the-whole-page.json` is the
## maximised page on the running app.
extends "res://tests/test_framework.gd"


func _plot(width: float, height: float, transfer: SaTransferFunction) -> SaColorSpaceBrowser.TransferPlot:
    var plot := SaColorSpaceBrowser.TransferPlot.new()
    plot.size = Vector2(width, height)
    var space := SaColorSpace.oklab_p3()
    space.transfer = transfer
    plot.space = space
    return plot


## A row as wide as a maximised page draws a square as tall as the row, in the
## middle, rather than a strip as wide as the page.
func test_a_wide_row_draws_a_centred_square() -> void:
    var plot := _plot(1600.0, 240.0, SaTransferFunction.gamma30())
    var rect := plot.plot_rect()
    plot.free()
    assert_almost_eq(rect.size.x, rect.size.y, 0.001, "the plot is square")
    assert_almost_eq(rect.size.y, 240.0, 0.001, "as tall as the row")
    assert_almost_eq(rect.position.x, 680.0, 0.001, "and centred across it")


## A row taller than it is wide keeps the square by the width instead. Sized
## above the row's own square minimum, because a control is never smaller than
## the minimum it asks for, and a size under it would be clamped before it drew.
func test_a_tall_row_keeps_the_square_by_its_width() -> void:
    var plot := _plot(300.0, 400.0, SaTransferFunction.gamma30())
    var rect := plot.plot_rect()
    plot.free()
    assert_almost_eq(rect.size.x, 300.0, 0.001, "the square is as wide as the row")
    assert_almost_eq(rect.size.y, 300.0, 0.001, "and as tall")
    assert_almost_eq(rect.position.y, 50.0, 0.001, "centred down it")


## The row asks for a square's height, so a page of any width has room for one.
func test_the_row_asks_for_a_square_minimum() -> void:
    var plot := SaColorSpaceBrowser.TransferPlot.new()
    var wanted := plot.custom_minimum_size
    plot.free()
    assert_almost_eq(wanted.x, wanted.y, 0.001, "the minimum is square, %s" % wanted)


## At half the encoded range Gamma 3.0 is an eighth of
## the light and sRGB about a fifth, so the two drawn curves are not the same
## curve at the height a reader sees them.
func test_gamma_three_and_srgb_are_drawn_as_two_curves() -> void:
    var cube := _plot(1600.0, 240.0, SaTransferFunction.gamma30())
    var srgb := _plot(1600.0, 240.0, SaTransferFunction.srgb())
    var cube_mid: float = cube.report()["drawn_height_at"]["0.5"]
    var srgb_mid: float = srgb.report()["drawn_height_at"]["0.5"]
    cube.free()
    srgb.free()
    assert_almost_eq(cube_mid, 0.125, 0.002, "Gamma 3.0 is drawn an eighth of the way up at half")
    assert_true(srgb_mid > 0.2, "sRGB is drawn above a fifth there, %s" % srgb_mid)
    assert_true(srgb_mid - cube_mid > 0.05, "so the two drawn curves differ by more than a line's width")


## A point on the curve lands inside the square and not across the whole row.
func test_the_curve_is_drawn_inside_the_square() -> void:
    var plot := _plot(1600.0, 240.0, SaTransferFunction.gamma30())
    var rect := plot.plot_rect()
    var end := plot.to_plot(1.0)
    var start := plot.to_plot(0.0)
    plot.free()
    assert_almost_eq(start.x, rect.position.x, 0.001, "the curve starts at the square's left edge")
    assert_almost_eq(end.x, rect.end.x, 0.001, "and ends at its right edge, not the row's")
    assert_almost_eq(end.y, rect.position.y, 0.001, "at full light, the top of the square")
