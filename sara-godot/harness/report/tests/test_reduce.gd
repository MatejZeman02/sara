## The `reduce` step's sum, mean, minimum and maximum of a layer,
## reduced on the graphics card.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The chunks are written by hand with `texture_update`, the way
## `test_measure.gd` writes them, with a value that differs from texel to
## texel and reaches below zero and above one. The answer the reduction is
## graded against is worked out here from the very bytes uploaded, decoded the
## way the card decodes them, so a half-float chunk is graded at the value it
## holds and not at the one it was asked to hold.
extends "res://tests/test_framework.gd"

## The reduction is a real dispatch and the record is a real buffer read.
const REQUIRES_GPU := true

## A float32 sum of a hundred thousand texels, folded pairwise, is good to a
## few parts in ten million of the sum of the magnitudes. Ten in a million is
## slack for it and would still catch one texel counted twice.
const RELATIVE := 1e-5


func _document(size: Vector2i) -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(size, SaCompositor.new(), SaColorSpace.srgb())
    return doc


## The value the suite writes at document pixel *at*: red swings from -1.5 to
## 1.5, green sits above one, blue climbs across the canvas and alpha is whole.
static func _value(at: Vector2i) -> Color:
    return Color((at.x % 7 - 3) * 0.5, 1.0 + (at.y % 5) * 0.25, at.x * 0.001, 1.0)


## Writes the pattern into the chunk at *grid_pos* and adds what it wrote into
## *truth*, keyed by document pixel, as the card will read it back.
func _write_chunk(doc: SaDocument, grid_pos: Vector2i, truth: Dictionary) -> void:
    var chunk := doc.active_layer.get_or_create_chunk(grid_pos)
    var texture: SaTexture = chunk.field(SaFieldSpec.ALBEDO)
    var pixel := chunk.pixel_size()
    var wide := SaFieldSpec.BYTES_PER_TEXEL.get(texture.format, 16) as int
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var bytes := PackedByteArray()
    bytes.resize(pixel * pixel * wide)
    for y in pixel:
        for x in pixel:
            var at := grid_pos * SaChunk.SIZE + Vector2i(x, y)
            var colour := _value(at)
            var stored := Vector4()
            for channel in 4:
                var offset := (y * pixel + x) * wide
                if half:
                    bytes.encode_half(offset + channel * 2, colour[channel])
                    stored[channel] = bytes.decode_half(offset + channel * 2)
                else:
                    bytes.encode_float(offset + channel * 4, colour[channel])
                    stored[channel] = bytes.decode_float(offset + channel * 4)
            truth[at] = stored
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)


## The four answers over *rect*, worked out on the processor from *truth*, a
## texel no chunk holds counting as zero. The sums are kept in GDScript floats,
## which are doubles, because a Vector4 is single precision and a running total
## of a quarter of a million texels in one drifts further than the card's tree.
static func _expected(truth: Dictionary, rect: Rect2i) -> Dictionary:
    var sum: Array[float] = [0.0, 0.0, 0.0, 0.0]
    var magnitude: Array[float] = [0.0, 0.0, 0.0, 0.0]
    var least := Vector4(INF, INF, INF, INF)
    var most := Vector4(-INF, -INF, -INF, -INF)
    for y in range(rect.position.y, rect.end.y):
        for x in range(rect.position.x, rect.end.x):
            var value: Vector4 = truth.get(Vector2i(x, y), Vector4.ZERO)
            for channel in 4:
                sum[channel] += value[channel]
                magnitude[channel] += absf(value[channel])
            least = least.min(value)
            most = most.max(value)
    var area := float(rect.get_area())
    var total := Vector4(sum[0], sum[1], sum[2], sum[3])
    var mean := Vector4(sum[0] / area, sum[1] / area, sum[2] / area, sum[3] / area)
    var spread := Vector4(magnitude[0], magnitude[1], magnitude[2], magnitude[3])
    return {"sum": total, "mean": mean, "min": least, "max": most, "magnitude": spread, "area": area}


func _assert_close(got: Variant, want: Vector4, tolerance: Vector4, what: String) -> void:
    assert_true(got is Array and (got as Array).size() == 4, "%s answers four channels" % what)
    if not (got is Array) or (got as Array).size() != 4:
        return
    for channel in 4:
        var value := float((got as Array)[channel])
        assert_true(
            absf(value - want[channel]) <= tolerance[channel],
            "%s channel %d is %f, wanted %f within %f" % [what, channel, value, want[channel], tolerance[channel]]
        )


func _assert_reduction(result: Dictionary, want: Dictionary, where: String) -> void:
    var area: float = want["area"]
    var sum_tolerance: Vector4 = (want["magnitude"] as Vector4) * RELATIVE + Vector4.ONE * 1e-3
    _assert_close(result["sum"], want["sum"], sum_tolerance, "%s, the sum" % where)
    _assert_close(result["mean"], want["mean"], sum_tolerance / area, "%s, the mean" % where)
    # A least and a most are one texel's value, not a sum, so they are exact.
    _assert_close(result["min"], want["min"], Vector4.ONE * 1e-6, "%s, the minimum" % where)
    _assert_close(result["max"], want["max"], Vector4.ONE * 1e-6, "%s, the maximum" % where)
    assert_eq(int(result["texels"]), int(area), "%s counts every texel of the rectangle" % where)


## The whole layer and a rectangle whose edges fall inside chunks, every chunk
## allocated, against the answer worked out texel by texel.
func test_whole_layer_and_a_rectangle_that_cuts_a_chunk() -> void:
    var doc := _document(Vector2i(512, 512))
    var truth := {}
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
        _write_chunk(doc, grid_pos, truth)

    var whole := Rect2i(0, 0, 512, 512)
    var result := SaReduce.new(doc.active_layer).reduce(whole)
    assert_eq(int(result["allocated"]), 512 * 512, "Every texel of the whole layer is in a chunk")
    _assert_reduction(result, _expected(truth, whole), "The whole layer")
    assert_true(float(result["min"][0]) < 0.0, "The red minimum is the negative one written")
    assert_true(float(result["max"][1]) > 1.0, "The green maximum is above one, and nothing clamped it")

    var cut := Rect2i(101, 37, 300, 250)
    _assert_reduction(SaReduce.new(doc.active_layer).reduce(cut), _expected(truth, cut), "A rectangle cutting four chunks")
    doc.free()


## A rectangle over a chunk that is not there reads zeros there, which pulls
## the minimum and the maximum to zero and the mean down, and adds nothing.
func test_an_unallocated_chunk_counts_as_zero() -> void:
    var doc := _document(Vector2i(512, 256))
    var truth := {}
    _write_chunk(doc, Vector2i(0, 0), truth)
    var whole := Rect2i(0, 0, 512, 256)
    var result := SaReduce.new(doc.active_layer).reduce(whole)
    assert_eq(int(result["allocated"]), 256 * 256, "Only the one chunk's texels were reduced on the card")
    _assert_reduction(result, _expected(truth, whole), "Half a layer")
    assert_eq(float(result["min"][1]), 0.0, "Green, above one where painted, has the unpainted zero as its minimum")
    doc.free()


## An empty rectangle answers a zero sum and no mean, minimum or maximum, and
## the step's line says which were undefined.
func test_an_empty_rectangle_answers_zeros_and_undefined() -> void:
    var doc := _document(Vector2i(512, 256))
    _write_chunk(doc, Vector2i(0, 0), {})
    var result := SaReduce.new(doc.active_layer).reduce(Rect2i(10, 10, 0, 20))
    assert_eq(result["sum"], [0.0, 0.0, 0.0, 0.0], "An empty rectangle sums to zero")
    assert_null(result["min"], "An empty rectangle has no minimum")
    assert_null(result["max"], "An empty rectangle has no maximum")
    assert_null(result["mean"], "An empty rectangle has no mean")

    var line := SaReduce.capture(doc, {"rect": [600, 0, 50, 50]})
    var parsed: Dictionary = JSON.parse_string(line.trim_prefix("SaCapture: reduce "))
    assert_eq(parsed["undefined"], ["mean", "min", "max"], "A rectangle off the canvas says what it cannot answer")
    assert_eq(parsed["sum"], [0.0, 0.0, 0.0, 0.0], "and sums to zero")
    doc.free()


## The dispatches follow the chunks the rectangle covers: one chunk's worth on
## a canvas of four chunks and on one of sixty-four is the same count, and a
## rectangle over two chunks costs more than one over one.
func test_dispatches_follow_the_rectangle_not_the_canvas() -> void:
    var small := _document(Vector2i(512, 512))
    var large := _document(Vector2i(2048, 2048))
    for doc: SaDocument in [small, large]:
        for y in ceili(float(doc.canvas_size.y) / SaChunk.SIZE):
            for x in ceili(float(doc.canvas_size.x) / SaChunk.SIZE):
                doc.active_layer.get_or_create_chunk(Vector2i(x, y)).clear(Color(0.25, -0.5, 2.0, 1.0))

    var one_chunk := Rect2i(10, 10, 200, 200)
    var two_chunks := Rect2i(10, 10, 400, 200)
    var on_small := _dispatches(small, one_chunk)
    var on_large := _dispatches(large, one_chunk)
    var wider := _dispatches(large, two_chunks)
    assert_true(on_small > 0, "A reduction dispatches")
    assert_eq(on_large, on_small, "One chunk's rectangle costs the same on a canvas sixteen times the size")
    assert_true(wider > on_large, "A rectangle over two chunks costs more than one over one, %d against %d" % [wider, on_large])

    var whole := SaReduce.new(large.active_layer).reduce(Rect2i(Vector2i.ZERO, large.canvas_size))
    _assert_close(whole["mean"], Vector4(0.25, -0.5, 2.0, 1.0), Vector4.ONE * 1e-4, "A cleared canvas of sixty-four chunks")
    small.free()
    large.free()


func _dispatches(doc: SaDocument, rect: Rect2i) -> int:
    var before := SaCompute.dispatches
    SaReduce.new(doc.active_layer).reduce(rect)
    return SaCompute.dispatches - before


## The step names a layer by name or by index from the bottom, asks for only
## the operations it wants, and refuses what it cannot find.
func test_the_step_names_a_layer_and_its_operations() -> void:
    var doc := _document(Vector2i(512, 256))
    var painted := doc.active_layer
    painted.get_or_create_chunk(Vector2i.ZERO).clear(Color(1.5, 0.0, -0.25, 1.0))
    var index := SaLayerOps.new(doc).layers().find(painted)

    for named: Variant in [String(painted.name), index]:
        var line := SaReduce.capture(doc, {"layer": named, "ops": ["mean", "max"]})
        assert_true(line.begins_with("SaCapture: reduce {"), "The step answers one verdict line")
        var parsed: Dictionary = JSON.parse_string(line.trim_prefix("SaCapture: reduce "))
        assert_eq(String(parsed["layer"]), String(painted.name), "The layer %s is the one reduced" % named)
        assert_eq(int(parsed["index"]), index, "and its index is its place from the bottom")
        assert_false(parsed.has("sum"), "An operation not asked for is not answered")
        assert_false(parsed.has("min"), "Nor the minimum")
        assert_almost_eq(float(parsed["mean"][0]), 0.75, 1e-4, "The red mean is the value above one over half the canvas")
        assert_almost_eq(float(parsed["max"][2]), 0.0, 1e-6, "Blue is negative, and the blank texels' zero is its maximum")

    assert_true(SaReduce.capture(doc, {"layer": "No such"}).contains("refused"), "An unknown layer is refused by name")
    assert_true(SaReduce.capture(doc, {"layer": 99}).contains("refused"), "An index past the top is refused")
    assert_true(SaReduce.capture(doc, {"ops": ["median"]}).contains("refused"), "An unknown operation is refused")
    doc.free()
