## The waveform bins every pixel it shows.
##
## Compared with darktable's, Sara's waveform looked too low-res: a fixed 256 by 256 grid of samples put about
## one sample in each bin of a column, which is speckle, and a fixed 256 by 256
## grid of bins stretched over the panel, which is blocks. A pass now takes a
## sample per shown pixel and the waveform and the parade bin into a live grid of
## the picture's own size, while what a capture reports stays on the fixed grid
## so no stored choice changes with the panel.
extends "res://tests/test_framework.gd"

## Real dispatches into a real buffer.
const REQUIRES_GPU := true

## A gradient taller and wider than any live grid below, so every level a
## column spans has rows of the picture that fall in it.
const GRADIENT := Vector2i(1024, 768)

## The picture the docker opens at, about, and the same at twice its width,
## which is the pair the scenario shoots.
const DEFAULT_PLOT := Vector2i(304, 232)
const WIDE_PLOT := Vector2i(608, 232)


## A picture whose value climbs across and down at once, so each column of a
## waveform holds a band of values rather than one, and the three channels at
## three heights, so each is its own trace.
func _gradient() -> SaTexture:
    var image := Image.create_empty(GRADIENT.x, GRADIENT.y, false, Image.FORMAT_RGBAF)
    for y in GRADIENT.y:
        for x in GRADIENT.x:
            var value := 0.5 * float(x) / float(GRADIENT.x - 1) + 0.5 * float(y) / float(GRADIENT.y - 1)
            image.set_pixel(x, y, Color(value, value * 0.8, value * 0.6, 1.0))
    return SaGraphPlot.upload_image(image, maxi(GRADIENT.x, GRADIENT.y))


func _plot_over(texture: SaTexture, size: Vector2i, mode_id: String) -> SaGraphPlot:
    var plot := SaGraphPlot.new()
    plot.set_plot_size(size)
    assert_true(plot.run_over_document(texture, texture.size, null, mode_id), "The %s pass runs at %s" % [mode_id, size])
    return plot


## Every column of the live grid holds a trace for each channel, and the trace
## has no empty bin between its lowest and its highest: the speckle was bins of
## one sample beside bins of none, inside the band a column covers.
func test_a_gradient_fills_every_column_with_no_gap() -> void:
    var texture := _gradient()
    assert_not_null(texture, "The gradient uploads")
    for size: Vector2i in [DEFAULT_PLOT, WIDE_PLOT]:
        var plot := _plot_over(texture, size, "waveform")
        var grid := plot.live
        assert_eq(grid.x, size.x, "A column per texel of the picture at %s" % size)
        assert_eq(grid.y, int(size.y * SaGraphPlot.VALUE_TOP), "and a level per row below 1.0")
        var live := plot.read_live_counts()
        assert_eq(live.size(), SaGraphPlot.live_size(grid), "The live grid is three planes of it")
        var empty_columns := 0
        var gaps := 0
        for channel in 3:
            for column in grid.x:
                var base := (channel * grid.x + column) * grid.y
                var low := -1
                var high := -1
                for level in grid.y:
                    if live[base + level] > 0:
                        high = level
                        if low < 0:
                            low = level
                if low < 0:
                    empty_columns += 1
                    continue
                for level in range(low, high + 1):
                    if live[base + level] == 0:
                        gaps += 1
        assert_eq(empty_columns, 0, "Every column of every channel holds a trace at %s" % size)
        assert_eq(gaps, 0, "and no trace has an empty bin inside its range at %s" % size)


## The capture reads the fixed grid, and the fixed grid is the same counts at
## both panel sizes while the live grid is twice as wide at the wider one.
func test_the_capture_bins_the_same_at_both_panel_sizes() -> void:
    var texture := _gradient()
    for mode_id: String in ["waveform", "parade"]:
        var narrow := _plot_over(texture, DEFAULT_PLOT, mode_id)
        var wide := _plot_over(texture, WIDE_PLOT, mode_id)
        assert_eq(wide.live.x, narrow.live.x * 2, "The %s's live grid follows the width" % mode_id)
        assert_eq(narrow.samples, wide.samples, "while the samples follow what is shown, not the panel")
        var fixed_narrow := narrow.read_counts()
        var fixed_wide := wide.read_counts()
        assert_eq(fixed_narrow.size(), SaGraphPlot.LIVE_SLOT, "The capture reads the fixed grid")
        assert_true(fixed_narrow == fixed_wide, "and the %s's fixed grid is the same counts at both sizes" % mode_id)
        var report := narrow.bins_report()
        assert_eq(report, wide.bins_report().merged({"live": report["live"]}, true), "so is what the dump reports")
        assert_eq(int(report["fixed_total"]), 3 * GRADIENT.x * GRADIENT.y, "three channels of every sample")


## A pass takes one sample per pixel it is told the view shows, one per texel
## when it is told nothing, and never more than the ceiling the cloud's sums
## hold.
func test_a_pass_takes_a_sample_per_shown_pixel() -> void:
    var span_x := Vector2(3000.0, 0.0)
    var span_y := Vector2(0.0, 2000.0)
    assert_eq(SaGraphPlot.samples_for(Vector2i(1500, 1000), span_x, span_y), Vector2i(1500, 1000), "One a shown pixel")
    assert_eq(SaGraphPlot.samples_for(Vector2i.ZERO, span_x, span_y), Vector2i(3000, 2000), "one a texel when not told")
    var huge := SaGraphPlot.samples_for(Vector2i(9000, 9000), span_x, span_y)
    assert_eq(huge, SaGraphPlot.MAX_SAMPLES, "and held under the ceiling")
    assert_true(
        255.0 * float(SaGraphPlot.MAX_SAMPLES.x) * float(SaGraphPlot.MAX_SAMPLES.y) < 4294967296.0,
        "which is where the cloud's fixed point sums, at 255 steps, still fit a uint"
    )


## Zoomed out, a sample stands for its pixel and not for a texel beside it. A
## one texel checkerboard seen at a quarter is a mid grey on screen, and the
## histogram of it has to be one mid grey bin rather than black and white.
func test_a_zoomed_out_sample_reads_its_whole_pixel() -> void:
    var side := 256
    var image := Image.create_empty(side, side, false, Image.FORMAT_RGBAF)
    for y in side:
        for x in side:
            var on := (x + y) % 2 == 0
            image.set_pixel(x, y, Color.WHITE if on else Color.BLACK)
    var texture := SaGraphPlot.upload_image(image, side)
    var plot := SaGraphPlot.new()
    var full := Vector2(side, side)
    @warning_ignore("integer_division")
    var shown := Vector2i(side / 4, side / 4)
    assert_eq(
        SaGraphPlot.filter_for(Vector2(full.x, 0.0), Vector2(0.0, full.y), shown),
        RenderingDevice.SAMPLER_FILTER_LINEAR,
        "A pixel of four texels is read through the linear sampler"
    )
    var ok := plot.run(texture, texture.size, Vector2.ZERO, Vector2(full.x, 0.0), Vector2(0.0, full.y), null, "histogram", shown)
    assert_true(ok, "The pass over a quarter of the pixels runs")
    var counts := plot.read_counts()
    var middle := int(0.5 * float(SaGraphPlot.BINS - 1) + 0.5)
    var near_middle := 0
    for bin in range(middle - 2, middle + 3):
        near_middle += counts[bin]
    assert_eq(near_middle, shown.x * shown.y, "Every sample of the red row reads the pixel's grey")
    assert_eq(counts[0] + counts[SaGraphPlot.BINS - 1], 0, "and none reads a black or a white texel")

    assert_eq(
        SaGraphPlot.filter_for(Vector2(full.x, 0.0), Vector2(0.0, full.y), Vector2i(side, side)),
        RenderingDevice.SAMPLER_FILTER_NEAREST,
        "At a pixel a texel the sampler is nearest, which is the texel shown"
    )


## The wide panel is drawn at its own size and every texel column of it draws
## a trace, which is the live grid read a column a texel with none skipped.
func test_every_column_of_the_wide_picture_draws_a_trace() -> void:
    var texture := _gradient()
    var plot := _plot_over(texture, WIDE_PLOT, "waveform")
    assert_eq(Vector2i(plot.shown.get_size()), WIDE_PLOT, "The picture is the panel's size")
    var image := SaExport.get_texture_image_float(plot._plot)
    assert_not_null(image, "and reads back")
    var dark_columns := 0
    for x in image.get_width():
        var brightest := 0.0
        for y in image.get_height():
            brightest = maxf(brightest, image.get_pixel(x, y).r)
        if brightest < 0.3:
            dark_columns += 1
    assert_eq(dark_columns, 0, "Every column of the picture carries the red trace")


## Paint alone is scoped at most every `PAINT_INTERVAL_MSEC`, which the
## reduction service decides for the graph, because a pass
## at a sample per shown pixel costs more than the fixed grid did, and anything
## else, a moved view or a resized panel, is scoped at once.
func test_paint_is_scoped_at_an_interval_and_the_rest_at_once() -> void:
    var interval := SaReductionService.PAINT_INTERVAL_MSEC
    assert_false(SaReductionService.pass_due(true, 1000, 1000 - interval + 1), "Paint inside the interval waits")
    assert_true(SaReductionService.pass_due(true, 1000, 1000 - interval), "and runs once it has gone by")
    assert_true(SaReductionService.pass_due(false, 1000, 999), "A moved view runs at once")
