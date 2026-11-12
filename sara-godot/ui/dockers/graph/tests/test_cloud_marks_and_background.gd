## The Oklab cloud's points and the background under every graph.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Oklab cloud points are a bit smaller but change size when clustered, and
## the background is a bit lighter. Both are read off the
## picture the draw kernel writes rather than off its constants, because a size
## is only what the texels come out at: a picture of one colour with a single
## pixel of another bins into one crowded cell and one cell holding a lone
## sample, and the texels wearing each colour are counted. The same run on the
## app is `scenarios/the-oklab-clouds-points-and-its-background.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KERNEL := "res://shaders/compute/graph.gmacs"

## The picture binned: 256 across so the pass's 256 by 256 samples land one
## per pixel and the stray pixel is exactly one sample.
const SOURCE := Vector2i(256, 256)

## Two texels a cell, as at every size: 192 cells across.
const PLOT := Vector2i(384, 384)

## A warm colour most of the picture holds and a cool one a single pixel holds.
## Neither sits on an edge of the RGB cube, so no wireframe texel shares either
## direction: every edge holds two channels at 0 or 1.
const CLUSTER := Color(0.55, 0.35, 0.25, 1.0)
const STRAY := Color(0.3, 0.55, 0.75, 1.0)


## The value of a `const float` in the dialect, or NAN when there is none.
func _kernel_const(name: String) -> float:
    var text := FileAccess.get_file_as_string(KERNEL)
    for line in text.split("\n"):
        var trimmed := line.strip_edges()
        if not trimmed.begins_with("const "):
            continue
        var halves := trimmed.split("=", true, 1)
        var words := halves[0].strip_edges().split(" ", false)
        if halves.size() == 2 and words.size() >= 3 and words[2] == name:
            return float(halves[1].strip_edges())
    return NAN


## The plot a pass over the two-colour picture draws in *mode_id*, as RGB
## triples in reading order. The texture, the plot and the upload are let go
## before this returns, so the leak check sees none of them.
func _draw(mode_id: String) -> Array[Vector3]:
    var image := Image.create(SOURCE.x, SOURCE.y, false, Image.FORMAT_RGBAF)
    image.fill(CLUSTER)
    image.set_pixel(40, 200, STRAY)
    var source := SaGraphPlot.upload_image(image)
    var plot := SaGraphPlot.new()
    plot.set_plot_size(PLOT)
    var texels: Array[Vector3] = []
    if source == null or not plot.run_over_document(source, SOURCE, SaColorSpace.srgb(), mode_id):
        return texels
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(plot.shown.texture_rd_rid, 0)
    # RGBA16F, eight bytes a texel.
    for at in range(0, bytes.size(), 8):
        texels.append(Vector3(bytes.decode_half(at), bytes.decode_half(at + 2), bytes.decode_half(at + 4)))
    return texels


## How many texels carry *color*'s direction. A mark is laid over
## the background by its coverage rather than lifted onto it, so a mark's body
## is its cell's colour as it stands and only its one-texel edge mixes in the
## grey, which the direction's tolerance leaves out.
func _texels_wearing(texels: Array[Vector3], color: Color) -> int:
    var want := Vector3(color.r, color.g, color.b) / maxf(color.r, maxf(color.g, color.b))
    var count := 0
    for drawn in texels:
        var peak := maxf(drawn.x, maxf(drawn.y, drawn.z))
        if peak < 0.05:
            continue
        var off := (drawn / peak - want).abs()
        if maxf(off.x, maxf(off.y, off.z)) < 0.06:
            count += 1
    return count


func test_a_cluster_is_drawn_larger_than_a_stray_sample() -> void:
    var texels := _draw("cloud")
    assert_eq(texels.size(), PLOT.x * PLOT.y, "the pass drew a picture to read")

    var crowded := _texels_wearing(texels, CLUSTER)
    var lone := _texels_wearing(texels, STRAY)

    assert_true(lone > 0, "a stray sample still shows, which is the point of the stray-sample floor (%d texels)" % lone)
    assert_true(crowded > lone, "the crowded cell's mark is the larger (%d texels against %d)" % [crowded, lone])
    assert_true(crowded > 4 * lone, "and larger enough to read as a mass against a dot (%d against %d)" % [crowded, lone])


## A lone point is a bit smaller than it once was: its disc covers fewer texels
## than a 1.25-cell disc would at the plot's own cells.
func test_a_stray_sample_is_smaller_than_v4_drew_it() -> void:
    var lone := _texels_wearing(_draw("cloud"), STRAY)
    var v4_disc := PI * pow(1.25 * float(PLOT.x) / float(SaGraphPlot.cloud_cells_for(PLOT)), 2.0)
    assert_true(lone < int(v4_disc), "a stray sample covers %d texels, under the earlier %d" % [lone, int(v4_disc)])


func test_the_mirror_matches_the_kernel() -> void:
    assert_almost_eq(_kernel_const("BACKGROUND"), SaGraphPlot.BACKGROUND, 1e-6, "the clear and the draw agree")
    assert_true(SaGraphPlot.BACKGROUND > 0.0, "and it is lighter than the black it was")


## Every graph leaves some of its picture empty of trace, and a trace only ever
## adds to what is under it, so the darkest texel of each is its background.
## One grey for all of them is what keeps the docker from flickering.
func test_every_mode_draws_over_the_same_lighter_background() -> void:
    for mode: Array in SaGraphPlot.MODES:
        var texels := _draw(mode[0])
        if texels.is_empty():
            assert_true(false, "%s drew nothing to read" % mode[0])
            continue
        var darkest := Vector3(INF, INF, INF)
        for texel in texels:
            darkest = darkest.min(texel)
        var lift := SaGraphPlot.BACKGROUND
        assert_almost_eq(darkest.x, lift, 0.005, "%s is drawn over the background grey" % mode[0])
        assert_almost_eq(darkest.y, lift, 0.005, "%s's background is a grey" % mode[0])
        assert_almost_eq(darkest.z, lift, 0.005, "on all three channels")
