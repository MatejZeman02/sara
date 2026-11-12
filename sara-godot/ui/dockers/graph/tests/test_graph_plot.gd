## Where the Graph docker's scope puts the pixels it counts.
##
## The counts are read back off the GPU and checked against bins worked out on
## the CPU from the composited texel itself, rather than from the colour the
## fill was asked for: what the scope must agree with is what the picture
## holds, and the two are only the same while nothing in the composite moves.
extends "res://tests/test_framework.gd"

## Real dispatches into a real buffer.
const REQUIRES_GPU := true

const CANVAS := Vector2i(256, 128)

## What one pass over the whole canvas counts: a sample per texel.
const TOTAL := 256 * 128

## Half of it, written out rather than divided, because a constant is not a
## place to spend a warning annotation.
const HALF := 16384


func _easel(colour: Color) -> SaEasel:
    var easel := SaEasel.create_default(CANVAS)
    var layer := easel.document.get_node_or_null("Layer 1") as SaLayer
    layer.fill(colour)
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


## The composited texel, which is what the scope reads.
func _stored(easel: SaEasel) -> Color:
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(easel.output)
    return image.get_pixel(4, 4)


## The kernel's own `bin_of`, so the test says which bin it expects rather than
## searching for whichever one happens to be full.
func _bin(value: float) -> int:
    return int(clampf(value, 0.0, 1.0) * float(SaGraphPlot.BINS - 1) + 0.5)


func _luma(colour: Color) -> float:
    return colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722


func _run(easel: SaEasel, mode_id: String) -> PackedInt32Array:
    var plot := SaGraphPlot.new()
    assert_true(plot.run_over_document(easel.output, CANVAS, easel.document.color_space, mode_id), "The %s pass runs" % mode_id)
    return plot.read_counts()


## A flat colour is one bin per channel and nothing anywhere else, which is the
## simplest thing a histogram can be right about.
func test_a_flat_colour_is_one_bin_per_channel() -> void:
    var easel := _easel(Color(0.6, 0.3, 0.1, 1.0))
    var stored := _stored(easel)
    var counts := _run(easel, "histogram")

    for channel in range(3):
        var wanted := _bin([stored.r, stored.g, stored.b][channel])
        assert_eq(counts[channel * SaGraphPlot.BINS + wanted], TOTAL, "Channel %d holds every sample" % channel)
    assert_eq(counts[3 * SaGraphPlot.BINS + _bin(_luma(stored))], TOTAL, "and so does the luma row")
    assert_eq(counts[SaGraphPlot.MAX_SLOT], TOTAL, "The largest bin is the whole pass")

    var elsewhere := 0
    for bin in range(SaGraphPlot.BINS):
        if bin != _bin(stored.r):
            elsewhere += counts[bin]
    assert_eq(elsewhere, 0, "and the rest of the red row is empty")
    easel.free()


## The three channels of a colour that is not grey have to land apart, or the
## parade is drawing one graph three times.
func test_the_parade_keeps_the_channels_apart() -> void:
    var easel := _easel(Color(0.8, 0.4, 0.1, 1.0))
    var stored := _stored(easel)
    var counts := _run(easel, "parade")

    var bins := [_bin(stored.r), _bin(stored.g), _bin(stored.b)]
    assert_true(bins[0] != bins[1] and bins[1] != bins[2], "The three values are three bins: %s" % [bins])
    # One column of the fixed grid is one column of samples, so each holds the
    # 128 rows of the canvas and nothing else.
    for channel in range(3):
        var at := (channel * SaGraphPlot.COLUMNS + 100) * SaGraphPlot.BINS + int(bins[channel])
        assert_eq(counts[at], CANVAS.y, "Column 100 of channel %d is its own column of samples" % channel)
    assert_eq(counts[SaGraphPlot.MAX_SLOT], CANVAS.y, "so the largest bin is one column")
    easel.free()


## The waveform is the three channels at every column, laid on top of one
## another rather than side by side, which is what darktable draws and what
## distinguishes it from the histogram.
func test_the_waveform_holds_three_channels_per_column() -> void:
    var easel := _easel(Color(0.25, 0.75, 0.5, 1.0))
    var stored := _stored(easel)
    var counts := _run(easel, "waveform")

    for channel in range(3):
        var wanted := _bin([stored.r, stored.g, stored.b][channel])
        for column: int in [0, 37, 128, 255]:
            var at := (channel * SaGraphPlot.COLUMNS + int(column)) * SaGraphPlot.BINS + wanted
            assert_eq(counts[at], CANVAS.y, "Channel %d of column %s carries its samples" % [channel, column])
    easel.free()


## The waveform and the parade are one binning pass read two ways, so the
## counts they leave are the same counts. A difference here means one of them
## grew a layout of its own, which is what the shared pass exists to prevent.
func test_the_waveform_and_the_parade_are_one_pass() -> void:
    var easel := _easel(Color(0.25, 0.75, 0.5, 1.0))
    assert_eq(_run(easel, "waveform"), _run(easel, "parade"), "One picture, one set of counts")
    easel.free()


## A saturated red sits up and to the right of the middle in Oklab a and b,
## which is the thing a vectorscope exists to show and the thing a histogram
## cannot.
func test_the_vectorscope_puts_red_off_centre() -> void:
    var easel := _easel(Color(1.0, 0.0, 0.0, 1.0))
    var counts := _run(easel, "vectorscope")

    var filled := 0
    var found := -1
    for index in range(SaGraphPlot.BINS * SaGraphPlot.BINS):
        if counts[index] > 0:
            filled += 1
            found = index
    assert_eq(filled, 1, "One colour is one bin")
    assert_eq(counts[found], TOTAL, "holding the whole pass")
    @warning_ignore("integer_division")
    var b_bin := found / SaGraphPlot.BINS
    var a_bin := found % SaGraphPlot.BINS
    assert_true(a_bin > 140, "Red is well to the red side of neutral, got a=%d" % a_bin)
    assert_true(b_bin > 140, "and above it, got b=%d" % b_bin)
    easel.free()


## The pass counts the parallelogram it is handed and not the document, which
## is what makes a scope of the view rather than of the whole painting.
func test_only_the_area_asked_for_is_counted() -> void:
    var easel := _easel(Color(0.9, 0.9, 0.9, 1.0))
    # The left half painted dark, so the two halves are two bins. Placed as a
    # picture at the origin, which is the one door that puts pixels on part of
    # a canvas without a brush.
    @warning_ignore("integer_division")
    var dark := Image.create_empty(CANVAS.x / 2, CANVAS.y, false, Image.FORMAT_RGBAF)
    dark.fill(Color(0.1, 0.1, 0.1, 1.0))
    SaImageImport.place(easel.document, dark, "Left", easel.document.color_space)
    easel.request_full_composite()
    easel.process_pending_composite()

    var plot := SaGraphPlot.new()
    var half := Vector2(float(CANVAS.x) * 0.5, 0.0)
    assert_true(
        plot.run(
            easel.output, CANVAS, Vector2.ZERO, half, Vector2(0.0, float(CANVAS.y)), easel.document.color_space, "histogram"
        ),
        "A pass over the left half runs"
    )
    var counts := plot.read_counts()
    assert_eq(counts[SaGraphPlot.MAX_SLOT], HALF, "Every sample landed in one bin, so only the dark half was read")
    assert_true(counts[_bin(0.9)] == 0, "and nothing counted the light half")
    easel.free()


## A grid that runs off the canvas drops what it finds there rather than
## counting it as black, which would put a spike at zero whenever the painter
## zooms out.
func test_nothing_off_the_canvas_is_counted() -> void:
    var easel := _easel(Color(0.5, 0.5, 0.5, 1.0))
    var plot := SaGraphPlot.new()
    # Twice the canvas both ways, so a quarter of the grid is over paint, which
    # at a sample per texel is the canvas's worth.
    assert_true(
        plot.run(
            easel.output,
            CANVAS,
            Vector2.ZERO,
            Vector2(float(CANVAS.x) * 2.0, 0.0),
            Vector2(0.0, float(CANVAS.y) * 2.0),
            easel.document.color_space,
            "histogram"
        ),
        "The oversized pass runs"
    )
    var counts := plot.read_counts()
    var largest: int = counts[SaGraphPlot.MAX_SLOT]
    assert_true(absi(largest - TOTAL) <= 512, "About a quarter of the samples were over paint, got %d" % largest)
    easel.free()


## One pass is three dispatches whatever the canvas is, and a graph nobody
## changed costs none. That fixed cost is what the Info docker's counter shows.
func test_a_pass_is_three_dispatches_whatever_the_canvas() -> void:
    var easel := _easel(Color(0.4, 0.4, 0.4, 1.0))
    var plot := SaGraphPlot.new()
    plot.run_over_document(easel.output, CANVAS, easel.document.color_space, "histogram")

    var before := SaCompute.counters()["dispatches"] as int
    plot.run_over_document(easel.output, CANVAS, easel.document.color_space, "histogram")
    assert_eq(SaCompute.counters()["dispatches"] as int - before, 3, "Clear, bin, draw")
    easel.free()


## The dropdown opens on the waveform, and the number the kernel knows a mode
## by is not its place in that list.
func test_the_modes_are_named_and_ordered() -> void:
    assert_eq(SaGraphPlot.MODES.size(), 6, "Six graphs since the waveform gained its W")
    assert_eq(SaGraphPlot.mode_at(0), "waveform", "The waveform is first")
    assert_eq(SaGraphPlot.DEFAULT_MODE, "waveform", "and is what a docker with no stored choice opens on")
    assert_eq(SaGraphPlot.mode_at(1), "waveform_white", "with its W beside it, where a comparison is one row away")
    assert_eq(SaGraphPlot.index_of("cloud"), 5, "The Oklab cloud is last")
    assert_eq(SaGraphPlot.mode_at(SaGraphPlot.index_of("sonogram")), "waveform", "A word nothing knows is the default")
    assert_eq(SaGraphPlot.mode_at(9), "waveform", "as is an index nothing offers")

    assert_eq(SaGraphPlot.kernel_mode("histogram"), 0, "The kernel still calls the histogram nought")
    assert_eq(SaGraphPlot.kernel_mode("waveform"), 3, "and the waveform three, wherever the dropdown puts it")
    assert_eq(SaGraphPlot.kernel_mode("cloud"), 4, "The cloud is the number the shader learned last")
    assert_eq(SaGraphPlot.kernel_mode("waveform_white"), 5, "and the white waveform the one after it")


## The RGBW toggle is two modes to the shader and one switch to the painter, so
## the docker has to be able to ask which ids the switch covers.
func test_the_two_waveforms_are_what_the_toggle_covers() -> void:
    assert_true(SaGraphPlot.is_waveform("waveform"), "RGB is a waveform")
    assert_true(SaGraphPlot.is_waveform("waveform_white"), "and so is W")
    for other: String in ["histogram", "parade", "vectorscope", "cloud", "nonsense"]:
        assert_false(SaGraphPlot.is_waveform(other), "%s is not, so it gets no W toggle" % other)


## The traced modes are drawn against the largest bin in the whole pass, which on
## a document with a flat background is that background's, so a stroke came out
## nearly black. They ask for more gain and the round modes do not.
func test_the_traced_modes_ask_for_more_gain() -> void:
    for mode_id: String in ["parade", "waveform", "waveform_white"]:
        var gain := SaGraphPlot.gain_for(SaGraphPlot.kernel_mode(mode_id))
        assert_eq(gain, SaGraphPlot.TRACE_GAIN, "%s is a trace and is lifted" % mode_id)
        assert_true(gain > SaGraphPlot.GAIN, "which is more than the plain scale")
    for mode_id: String in ["histogram", "vectorscope", "cloud"]:
        assert_eq(SaGraphPlot.gain_for(SaGraphPlot.kernel_mode(mode_id)), SaGraphPlot.GAIN, "%s is not" % mode_id)


## The picture follows the panel to the texel, held inside two limits,
## and the bin grid does not move with it.
func test_the_picture_takes_the_size_it_is_given() -> void:
    var plot := SaGraphPlot.new()
    assert_eq(plot.plot_size, SaGraphPlot.PLOT, "A fresh plot is the default square")

    assert_true(plot.set_plot_size(Vector2i(301, 205)), "A new size is a change")
    assert_eq(plot.plot_size, Vector2i(301, 205), "taken as it is,, so a texel meets a pixel")
    assert_false(plot.set_plot_size(Vector2i(301, 205)), "and the same size again is not")

    plot.set_plot_size(Vector2i(4, 9999))
    assert_eq(plot.plot_size, Vector2i(SaGraphPlot.MIN_PLOT, SaGraphPlot.MAX_PLOT), "Both limits hold")
    assert_eq(SaGraphPlot.COLUMNS, 256, "and the bin grid is the kernel's, not the panel's")


## A picture the size of a wide panel is drawn at that size, so the graph fills
## the docker rather than being a square scaled into it.
func test_a_resized_plot_draws_at_the_new_size() -> void:
    var easel := _easel(Color(0.5, 0.5, 0.5, 1.0))
    var plot := SaGraphPlot.new()
    plot.set_plot_size(Vector2i(512, 128))
    assert_true(plot.run_over_document(easel.output, CANVAS, easel.document.color_space, "waveform"), "The wide pass runs")
    assert_eq(Vector2i(plot.shown.get_size()), Vector2i(512, 128), "and the picture is the size that was asked for")
    easel.free()


## The Oklab cloud puts one colour in one cell and remembers which colour it
## was, which is what lets the draw answer with the paint rather than with a
## colour worked out from where the cell sits.
func test_the_cloud_holds_the_colour_of_its_cell() -> void:
    var easel := _easel(Color(0.5, 0.5, 0.5, 1.0))
    var stored := _stored(easel)
    var counts := _run(easel, "cloud")

    var cell := _only_filled_cell(counts)
    assert_true(cell >= 0, "A flat colour is one cell")
    assert_eq(counts[cell], TOTAL, "holding the whole pass")

    var lab := _oklab(stored)
    var lightness := float(counts[SaGraphPlot.PLANE + cell]) / float(TOTAL) / 255.0
    assert_almost_eq(lightness, lab.x, 0.002, "The lightness sum averages back to the colour's own")
    # A grey has no a and no b, so both sums sit at the middle of the range.
    assert_almost_eq(float(counts[2 * SaGraphPlot.PLANE + cell]) / float(TOTAL), 128.0, 1.0, "a is neutral")
    assert_almost_eq(float(counts[3 * SaGraphPlot.PLANE + cell]) / float(TOTAL), 128.0, 1.0, "and so is b")
    easel.free()


## Lightness runs up the picture and the greys run up one column, which is the
## whole reason the cloud has a third axis the vectorscope has not.
func test_the_cloud_puts_lightness_up_the_neutral_axis() -> void:
    var dark := _easel(Color(0.2, 0.2, 0.2, 1.0))
    var light := _easel(Color(0.8, 0.8, 0.8, 1.0))
    var red := _easel(Color(0.9, 0.05, 0.05, 1.0))

    var dark_cell := _only_filled_cell(_run(dark, "cloud"))
    var light_cell := _only_filled_cell(_run(light, "cloud"))
    var red_cell := _only_filled_cell(_run(red, "cloud"))
    assert_true(dark_cell >= 0 and light_cell >= 0 and red_cell >= 0, "Each flat colour is one cell")

    @warning_ignore("integer_division")
    var dark_row := dark_cell / SaGraphPlot.CLOUD_FIXED_CELLS
    @warning_ignore("integer_division")
    var light_row := light_cell / SaGraphPlot.CLOUD_FIXED_CELLS
    var cells := SaGraphPlot.CLOUD_FIXED_CELLS
    assert_eq(dark_cell % cells, light_cell % cells, "Two greys share the neutral column")
    assert_true(light_row < dark_row, "and the lighter one is higher, got %d against %d" % [light_row, dark_row])
    assert_true(red_cell % cells != dark_cell % cells, "A red is off that column")

    dark.free()
    light.free()
    red.free()


## The one cell of the first plane holding anything, or -1 when that is not
## what the pass left.
func _only_filled_cell(counts: PackedInt32Array) -> int:
    var found := -1
    for index in range(SaGraphPlot.PLANE):
        if counts[index] > 0:
            if found >= 0:
                return -1
            found = index
    return found


## The stored texel in Oklab, by the same road the kernel takes: the document's
## transfer curve back to light, then Ottosson's matrices.
func _oklab(colour: Color) -> Vector3:
    var linear := OkhsvConversions.srgb_transfer_function_inv(Vector3(colour.r, colour.g, colour.b))
    return OkhsvConversions.linear_srgb_to_oklab(linear)


## The neutral axis is a column's centre and not the seam between two.
##
## A grey projects to a horizontal unit coordinate of exactly 0.5, and with an
## even number of columns no uniform grid can put that anywhere but on a
## boundary. One GPU came back with "expected 127 got 128"
## on a suite that was green on another part, because float noise in
## the Oklab conversion decided which side and the two parts decided
## differently. The grid is offset by half a cell now, so 0.5 is the centre of
## column COLUMNS / 2 and has to move by a whole two-hundred-and-fifty-sixth
## before the answer changes.
##
## Five greys rather than two, because each carries its own noise and the claim
## is that none of it reaches the answer.
func test_every_grey_lands_in_the_middle_of_the_neutral_column() -> void:
    @warning_ignore("integer_division")
    var neutral: int = SaGraphPlot.CLOUD_FIXED_CELLS / 2
    for level: float in [0.05, 0.2, 0.5, 0.8, 0.95]:
        var easel := _easel(Color(level, level, level, 1.0))
        var cell := _only_filled_cell(_run(easel, "cloud"))
        assert_true(cell >= 0, "A grey at %.2f is one cell" % level)
        assert_eq(cell % SaGraphPlot.CLOUD_FIXED_CELLS, neutral, "in column %d, at %.2f" % [neutral, level])
        easel.free()


## The column survives a real excursion off the neutral axis, in both
## directions, which is what a grey's float noise
## amounts to.
##
## This is the assertion the old arithmetic could not pass anywhere. Its
## boundary sat exactly on 0.5, so any negative Oklab a fell in column 127 and
## any positive one in 128, whatever their size: the two colours below differ
## by a thousandth and would have been split. Half a cell of offset gives the
## neutral column a width of one two-hundred-and-fifty-sixth around 0.5, and
## the excursion here is inside it with room to spare.
func test_a_hair_off_neutral_is_still_the_neutral_column() -> void:
    @warning_ignore("integer_division")
    var neutral: int = SaGraphPlot.CLOUD_FIXED_CELLS / 2
    var warm := Color(0.502, 0.5, 0.5, 1.0)
    var cool := Color(0.5, 0.502, 0.5, 1.0)
    var warm_a := _oklab(warm).y
    var cool_a := _oklab(cool).y
    assert_true(warm_a > 0.0 and cool_a < 0.0, "The two sit either side of the axis, %f and %f" % [warm_a, cool_a])

    for entry: Array in [[warm, warm_a], [cool, cool_a]]:
        var easel := _easel(entry[0] as Color)
        var cell := _only_filled_cell(_run(easel, "cloud"))
        assert_true(cell >= 0, "A near-neutral at a = %f is one cell" % (entry[1] as float))
        assert_eq(cell % SaGraphPlot.CLOUD_FIXED_CELLS, neutral, "and lands in column %d" % neutral)
        easel.free()
