## The `measure` step's Oklab statistics over a rectangle.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A script that sees through tools does not write its own. What it needs is the mean and the spread of L, a
## and b over a rectangle, a coverage figure, and the distance between two rectangles
## as a number. Every one of those is graded here against an answer worked out
## by hand with `SaOklab`, which is the processor's own copy of the matrices the
## kernel uses, so the two copies are compared rather than trusted.
##
## The chunks are written by hand with `texture_update`, the way
## `harness/drivers/sa_canvas_driver.gd`'s checker does, rather than painted. A flat colour
## in a known rectangle is what the arithmetic under test needs, and a stroke
## would bring a brush's own spacing and falloff into a measurement of the
## reduction.
extends "res://tests/test_framework.gd"

## The reduction is a real dispatch and the tally is a real buffer read.
const REQUIRES_GPU := true

## Two flat colours, one per chunk. Far apart in hue so the distance between
## them is a number a rounding error cannot reach.
const TEAL := Color(0.1, 0.6, 0.55, 1.0)
const RUST := Color(0.75, 0.3, 0.1, 1.0)

## What a mean is graded at. The kernel sums in a fixed point of one part in
## 32768 per axis, so a mean is good to about 3e-5 and a thousandth is slack.
const EPSILON := 0.001

## What a standard deviation over a flat colour has to be under. The two-pass
## reduction subtracts the mean before it squares, so a flat fill's deviation
## falls below one quantisation step and comes back as nothing at all. A
## one-pass variance would leave about 0.006 here, which is why this number is
## far under that and not merely small.
const FLAT_SD := 1e-5


func _document() -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(512, 256), SaCompositor.new(), SaColorSpace.srgb())
    return doc


## Writes *colour* into every texel of the chunk at *grid_pos* of the active
## layer, allocating it. *alpha_rows* leaves the rows past it transparent, which
## is how a half-covered chunk is made.
func _write_chunk(doc: SaDocument, grid_pos: Vector2i, colour: Color, alpha_rows: int = -1) -> int:
    var layer := doc.active_layer
    var chunk := layer.get_or_create_chunk(grid_pos)
    var texture: SaTexture = chunk.field(SaFieldSpec.ALBEDO)
    assert_not_null(texture, "The chunk at %s holds an albedo field" % grid_pos)
    var pixel := chunk.pixel_size()
    var wide := SaFieldSpec.BYTES_PER_TEXEL.get(texture.format, 16) as int
    var bytes := PackedByteArray()
    bytes.resize(pixel * pixel * wide)
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    for y in pixel:
        var alpha := 0.0 if alpha_rows >= 0 and y >= alpha_rows else colour.a
        for x in pixel:
            var at := (y * pixel + x) * wide
            for channel in 4:
                var stored := [colour.r, colour.g, colour.b, alpha][channel] as float
                if half:
                    bytes.encode_half(at + channel * 2, stored)
                else:
                    bytes.encode_float(at + channel * 4, stored)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    layer.mark_unresolved(grid_pos)
    return pixel


## The colour's own Oklab, by the processor's copy of the matrices.
func _lab(colour: Color) -> Vector3:
    return SaMeasure.to_oklab(SaColorSpace.srgb(), colour)


func _assert_mean(stats: Dictionary, want: Vector3, where: String) -> void:
    var mean: Variant = stats.get("mean", null)
    assert_true(mean is Dictionary, "%s answers a mean" % where)
    if not (mean is Dictionary):
        return
    assert_almost_eq(float(mean["l"]), want.x, EPSILON, "%s: L" % where)
    assert_almost_eq(float(mean["a"]), want.y, EPSILON, "%s: a" % where)
    assert_almost_eq(float(mean["b"]), want.z, EPSILON, "%s: b" % where)


# --- The main case ------------------------------------------------------------


## Two flat colours in two rectangles, the known means, and the known distance.
func test_two_flat_rectangles_measure_their_own_colours_and_the_distance_between_them() -> void:
    var doc := _document()
    var pixel := _write_chunk(doc, Vector2i(0, 0), TEAL)
    _write_chunk(doc, Vector2i(1, 0), RUST)
    var measure := SaMeasure.new(doc)

    var left := measure.layer_stats(Rect2i(0, 0, pixel, pixel))
    var right := measure.layer_stats(Rect2i(SaChunk.SIZE, 0, pixel, pixel))

    _assert_mean(left, _lab(TEAL), "the teal rectangle")
    _assert_mean(right, _lab(RUST), "the rust rectangle")
    assert_almost_eq(
        SaMeasure.distance(left, right),
        _lab(TEAL).distance_to(_lab(RUST)),
        EPSILON,
        "the distance is the Oklab distance between the two means"
    )
    doc.free()


## A rectangle the layer holds no chunk for is coverage zero, and it answers no
## colour rather than black, which is a different claim.
func test_an_empty_rectangle_has_no_coverage_and_no_colour() -> void:
    var doc := _document()
    var measure := SaMeasure.new(doc)

    var nothing := measure.layer_stats(Rect2i(0, 0, 64, 64))

    assert_eq(nothing["coverage"], 0.0, "an unpainted rectangle covers nothing")
    assert_eq(int(nothing["covered"]), 0, "and no texel of it holds paint")
    assert_null(nothing["mean"], "so there is no mean to report")
    assert_eq(int(nothing["texels"]), 64 * 64, "the rectangle's own size is still answered")
    doc.free()


## The readback is the tally and never a texel. The claim is that the readback is the tally and
## nothing else.
func test_the_measure_class_reads_back_a_buffer_and_never_a_texture() -> void:
    var source := FileAccess.get_file_as_string("res://harness/report/sa_measure.gd")

    assert_false(source.is_empty(), "the measure class is where the suite thinks it is")
    assert_false(source.contains("texture_get_data"), "a measurement never reads a texture back")
    assert_true(source.contains("tally.read()"), "it reads the tally buffer instead")


# --- Coverage and spread ------------------------------------------------------


## Half the rows transparent is half the coverage, and the mean is over the
## painted half alone: an unpainted texel has no colour to average in.
func test_a_half_transparent_chunk_halves_the_coverage_and_keeps_the_colour() -> void:
    var doc := _document()
    var pixel := _write_chunk(doc, Vector2i(0, 0), TEAL, 0)
    _write_chunk(doc, Vector2i(0, 0), TEAL, int(float(pixel) / 2.0))

    var stats := SaMeasure.new(doc).layer_stats(Rect2i(0, 0, pixel, pixel))

    assert_almost_eq(float(stats["coverage"]), 0.5, 0.01, "half the rows hold paint")
    _assert_mean(stats, _lab(TEAL), "the painted half")
    doc.free()


## A flat colour has no spread, and says so exactly. This is what the second
## pass buys: the deviation from the mean is below one quantisation step, so it
## rounds to zero instead of to the step.
func test_a_flat_colour_reports_no_spread_at_all() -> void:
    var doc := _document()
    var pixel := _write_chunk(doc, Vector2i(0, 0), TEAL)

    var stats := SaMeasure.new(doc).layer_stats(Rect2i(0, 0, pixel, pixel))
    var spread: Dictionary = stats["sd"]

    assert_true(float(spread["l"]) < FLAT_SD, "L does not vary over a flat fill")
    assert_true(float(spread["a"]) < FLAT_SD, "nor does a")
    assert_true(float(spread["b"]) < FLAT_SD, "nor does b")
    doc.free()


## A rectangle over both chunks averages the two colours and reports the spread
## an even split has, which is half the distance between them on every axis.
## Two chunks also means two slots of the tally, so this is the reduction across
## slots as well as the arithmetic.
func test_a_rectangle_over_two_chunks_averages_both_and_reports_the_split() -> void:
    var doc := _document()
    _write_chunk(doc, Vector2i(0, 0), TEAL)
    _write_chunk(doc, Vector2i(1, 0), RUST)
    var teal := _lab(TEAL)
    var rust := _lab(RUST)

    var stats := SaMeasure.new(doc).layer_stats(Rect2i(0, 0, 2 * SaChunk.SIZE, SaChunk.SIZE))
    var spread: Dictionary = stats["sd"]

    _assert_mean(stats, (teal + rust) * 0.5, "both chunks together")
    assert_almost_eq(float(spread["l"]), absf(teal.x - rust.x) * 0.5, EPSILON, "the split in L")
    assert_almost_eq(float(spread["a"]), absf(teal.y - rust.y) * 0.5, EPSILON, "the split in a")
    assert_almost_eq(float(spread["b"]), absf(teal.z - rust.z) * 0.5, EPSILON, "the split in b")
    doc.free()


# --- The reference, on the processor ------------------------------------------


## The same statistics over a picture, and the same answer as the canvas gives
## for the same colour. Two implementations of one definition, which is the only
## way either of them is checked.
func test_a_picture_measures_the_same_colour_the_canvas_does() -> void:
    var doc := _document()
    var pixel := _write_chunk(doc, Vector2i(0, 0), TEAL)
    var picture := Image.create(32, 32, false, Image.FORMAT_RGBAF)
    picture.fill(TEAL)

    var canvas := SaMeasure.new(doc).layer_stats(Rect2i(0, 0, pixel, pixel))
    var measured := SaMeasure.image_stats(picture, SaColorSpace.srgb(), Rect2i(0, 0, 32, 32))

    _assert_mean(measured, _lab(TEAL), "the picture")
    assert_almost_eq(SaMeasure.distance(canvas, measured), 0.0, EPSILON, "the canvas and the picture are the same colour")
    assert_eq(float(measured["coverage"]), 1.0, "an opaque picture covers its whole rectangle")
    doc.free()


## A rectangle reaching past the picture's edge measures the part that is there
## and counts the rest as uncovered, rather than reading off the end.
func test_a_rectangle_past_the_pictures_edge_measures_what_is_there() -> void:
    var picture := Image.create(16, 16, false, Image.FORMAT_RGBAF)
    picture.fill(RUST)

    var stats := SaMeasure.image_stats(picture, SaColorSpace.srgb(), Rect2i(0, 0, 32, 32))

    assert_eq(int(stats["texels"]), 32 * 32, "the rectangle asked about is the one answered for")
    assert_eq(int(stats["covered"]), 16 * 16, "and only the picture's own texels hold colour")
    assert_almost_eq(float(stats["coverage"]), 0.25, EPSILON, "a quarter of it")
    _assert_mean(stats, _lab(RUST), "the part that is there")


# --- The two copies of the constants ------------------------------------------


## The kernel and the class hold the same fixed point and the same cell order.
## They are two files and GDScript cannot include a `.gmacs`, so this is the
## same insistence `SaOklab` carries about its own three copies.
func test_the_kernel_and_the_class_agree_on_the_tally() -> void:
    var kernel := FileAccess.get_file_as_string("res://shaders/compute/measure.gmacs")

    assert_false(kernel.is_empty(), "the measure kernel is where the class looks for it")
    assert_true(kernel.contains("const float QUANT = %.1f" % SaMeasure.QUANT), "the fixed point is the same number")
    assert_true(kernel.contains("const float AB_RANGE = %.1f" % SaMeasure.AB_RANGE), "and so is the fold")
    assert_true(kernel.contains("const uint CELLS = %du" % SaMeasure.CELLS), "and the slot is the same width")
    for pair: Array in [
        ["CELL_TEXELS", SaMeasure.CELL_TEXELS],
        ["CELL_COVERED", SaMeasure.CELL_COVERED],
        ["CELL_SUM_L", SaMeasure.CELL_SUM_L],
        ["CELL_SUM_A", SaMeasure.CELL_SUM_A],
        ["CELL_SUM_B", SaMeasure.CELL_SUM_B],
        ["CELL_DEV_L", SaMeasure.CELL_DEV_L],
        ["CELL_DEV_A", SaMeasure.CELL_DEV_A],
        ["CELL_DEV_B", SaMeasure.CELL_DEV_B]
    ]:
        assert_true(
            kernel.contains("const uint %s = %du" % [pair[0], pair[1]]), "%s is cell %d in the kernel too" % [pair[0], pair[1]]
        )
