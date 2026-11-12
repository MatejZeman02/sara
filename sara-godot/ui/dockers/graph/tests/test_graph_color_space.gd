## What the Graph docker's scope is a picture of.
##
## Before this, `graph.gmacs` binned the composited texel as it stood for the
## histogram, the parade and the three waveforms, and decoded only for the
## vectorscope and the cloud. On an Oklab document a chunk holds (L, a, b), so
## one white stroke read bucket 15 on an sRGB document and bucket 3 on the Oklab
## one, and the parade drew the lightness in its red row.
##
## Every case here is the same picture in two colour spaces, which is the
## comparison no suite made: `test_graph_plot.gd` runs one document at a time and
## checks the counts against the stored texel, which stays true whatever the
## stored texel means.
extends "res://tests/test_framework.gd"

## Real dispatches into a real buffer.
const REQUIRES_GPU := true

const CANVAS := Vector2i(128, 64)

## What one pass over the whole canvas counts: a sample per texel.
const TOTAL := 128 * 64

## The luma row of the count buffer, after red, green and blue.
const LUMA_ROW := 3

## The buckets the Levels graph folds a row into for its dump. That graph is
## the base module's `SaAdjustGraph`, and a skeleton suite
## names no module class, so its sixteen are written out here.
const BUCKETS := 16


## An easel in *space* whose one layer holds *shown* as that space stores it.
## `from_display` is the same door the picker writes through, so the two
## documents hold the same colour rather than the same numbers.
func _easel(space: SaColorSpace, shown: Color) -> SaEasel:
    var easel := SaEasel.create_default(CANVAS, null, space)
    var layer := easel.document.get_node_or_null("Layer 1") as SaLayer
    layer.fill(space.from_display(shown))
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


func _counts(easel: SaEasel, mode_id: String) -> PackedInt32Array:
    var plot := SaGraphPlot.new()
    assert_true(plot.run_over_document(easel.output, CANVAS, easel.document.color_space, mode_id), "The %s pass runs" % mode_id)
    return plot.read_counts()


## Which bin of *row* holds the most, which is the whole pass for a flat fill.
func _peak(counts: PackedInt32Array, row: int) -> int:
    var best := 0
    var at := 0
    for bin in range(SaGraphPlot.BINS):
        var count: int = counts[row * SaGraphPlot.BINS + bin]
        if count > best:
            best = count
            at = bin
    return at


## The bin folded into the sixteen buckets the Levels graph reports, which is the
## number the filing measured and the number a capture reads.
func _bucket(bin: int) -> int:
    @warning_ignore("integer_division")
    var per := SaGraphPlot.BINS / BUCKETS
    @warning_ignore("integer_division")
    return bin / per


## The case the filing is: one white, two documents, one bucket. Red before the
## fix, where the Oklab document answered bucket 3 against the sRGB one's 15.
func test_white_reads_the_same_bucket_in_both_spaces() -> void:
    var srgb := _easel(SaColorSpace.srgb(), Color.WHITE)
    var oklab := _easel(SaColorSpace.oklab(), Color.WHITE)

    var srgb_bin := _peak(_counts(srgb, "histogram"), LUMA_ROW)
    var oklab_bin := _peak(_counts(oklab, "histogram"), LUMA_ROW)

    assert_eq(_bucket(srgb_bin), BUCKETS - 1, "White is the top bucket on an sRGB document")
    assert_eq(
        _bucket(oklab_bin), _bucket(srgb_bin), "and the same bucket on an Oklab one, got bins %d and %d" % [srgb_bin, oklab_bin]
    )
    srgb.free()
    oklab.free()


## A colour that is not neutral, so the answer cannot be right by having all
## three channels equal. Two bins of 256 is under one part in a hundred, which is
## the Oklab round trip's own rounding rather than a difference in what is asked.
func test_a_mid_colour_reads_the_same_bin_in_both_spaces() -> void:
    var shown := Color(0.72, 0.35, 0.18, 1.0)
    var srgb := _easel(SaColorSpace.srgb(), shown)
    var oklab := _easel(SaColorSpace.oklab(), shown)

    var srgb_counts := _counts(srgb, "parade")
    var oklab_counts := _counts(oklab, "parade")
    for channel in range(3):
        var here := _peak(srgb_counts, channel * SaGraphPlot.COLUMNS + 64)
        var there := _peak(oklab_counts, channel * SaGraphPlot.COLUMNS + 64)
        assert_true(
            absi(here - there) <= 2, "Channel %d is the same level in both spaces, got %d and %d" % [channel, here, there]
        )
    srgb.free()
    oklab.free()


## The parade's three rows are the screen's red, green and blue whatever the
## document stores. On an Oklab document the stored triple's second and third
## channels are a and b, which are near zero for a neutral, so before the fix a
## white fill drew the green and blue rows at the bottom and the red row at the
## top: the pure red the filing counted out of the panel.
func test_the_parade_of_a_neutral_is_three_equal_rows() -> void:
    var oklab := _easel(SaColorSpace.oklab(), Color(0.75, 0.75, 0.75, 1.0))
    var counts := _counts(oklab, "parade")

    var levels: Array[int] = []
    for channel in range(3):
        # Column 65 of the fixed grid, because 128 columns of samples land on
        # every other one of its 256: sample 32 at 32.5 / 128 * 255 + 0.5.
        levels.append(_peak(counts, channel * SaGraphPlot.COLUMNS + 65))
    assert_true(levels[0] > 128, "A light neutral sits high, got %s" % [levels])
    assert_true(
        maxi(levels[0], maxi(levels[1], levels[2])) - mini(levels[0], mini(levels[1], levels[2])) <= 2,
        "and the three rows are one level, got %s" % [levels]
    )
    oklab.free()


## The round modes were already decoding, and they were decoding the wrong thing
## on an Oklab document: a stored (L, a, b) went through the transfer curve and
## then through linear sRGB into Oklab again. A saturated red has to land in the
## same cell of the vectorscope whichever space holds it.
func test_the_vectorscope_puts_red_in_the_same_place_in_both_spaces() -> void:
    var srgb := _easel(SaColorSpace.srgb(), Color(1.0, 0.0, 0.0, 1.0))
    var oklab := _easel(SaColorSpace.oklab(), Color(1.0, 0.0, 0.0, 1.0))

    var here := _peak_cell(_counts(srgb, "vectorscope"))
    var there := _peak_cell(_counts(oklab, "vectorscope"))
    assert_true(here.x > 140, "Red is well to the red side of neutral, got %s" % here)
    assert_true(
        absi(here.x - there.x) <= 2 and absi(here.y - there.y) <= 2,
        "and lands in the same cell in both spaces, got %s and %s" % [here, there]
    )
    srgb.free()
    oklab.free()


## The a and b bins of the fullest vectorscope cell.
func _peak_cell(counts: PackedInt32Array) -> Vector2i:
    var best := 0
    var at := 0
    for index in range(SaGraphPlot.BINS * SaGraphPlot.BINS):
        if counts[index] > best:
            best = counts[index]
            at = index
    @warning_ignore("integer_division")
    var b_bin := at / SaGraphPlot.BINS
    return Vector2i(at % SaGraphPlot.BINS, b_bin)


## An sRGB document bins exactly the numbers it always did, because the kernel
## takes the passthrough branch rather than a decode and an encode that only
## round to the identity. A histogram of a flat fill is one bin, and a round trip
## that moved a value by a hair would make it two.
func test_an_srgb_document_still_bins_its_stored_values() -> void:
    var easel := _easel(SaColorSpace.srgb(), Color(0.6, 0.3, 0.1, 1.0))
    var counts := _counts(easel, "histogram")

    var filled := 0
    for bin in range(SaGraphPlot.BINS):
        if counts[bin] > 0:
            filled += 1
    assert_eq(filled, 1, "The red row is one bin, so nothing was rounded across a boundary")
    assert_eq(counts[SaGraphPlot.MAX_SLOT], TOTAL, "holding the whole pass")
    easel.free()
