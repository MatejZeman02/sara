## The compositor evaluates a layer's attached filters in order: over the layer's chunk, before its mask, its
## clip and its blend, at
## composite time and never into the chunk. The fixture is the invert, so a
## texel of the output says whether a record ran, and running it twice says
## whether the second read what the first wrote.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const INVERTED := Color(0.75, 0.5, 0.25, 1.0)
## One texel in the first chunk and one in the last.
const NEAR := Vector2i(10, 10)
const FAR := Vector2i(300, 300)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _background: SaLayer = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(512, 512))
    _doc = _easel.document
    _background = _doc.get_node("Background") as SaLayer
    _doc.fill_layer(PAINT, _background)
    Bench.composite(_easel)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _background = null


func _shows(at: Vector2i, expected: Color, what: String) -> void:
    var found := Bench.texel(_easel.output, at)
    assert_almost_eq(found.r, expected.r, 0.01, "%s, red at %s: %s" % [what, at, found])
    assert_almost_eq(found.b, expected.b, 0.01, "%s, blue at %s: %s" % [what, at, found])


func test_a_filter_on_a_layer_that_is_not_active_changes_the_composite_and_not_the_layer() -> void:
    assert_true(_doc.active_layer != _background, "The background is not the active layer")
    var ops := SaFilterOps.new(_doc)
    var record := ops.attach(_background, Bench.INVERT)
    Bench.composite(_easel)
    _shows(NEAR, INVERTED, "The attached invert shows on the canvas")
    _shows(FAR, INVERTED, "in every chunk")
    var stored := Bench.texel(_background.get_field(Vector2i(0, 0)), NEAR)
    assert_almost_eq(stored.r, PAINT.r, 1e-5, "while the layer's own texel is what it was")
    assert_not_null(record.cached_pass, "and the record keeps the pass it was evaluated to")

    ops.set_enabled(record, false)
    Bench.composite(_easel)
    _shows(NEAR, PAINT, "A record switched off composites as if it were not there")

    ops.set_enabled(record, true)
    Bench.composite(_easel)
    _shows(NEAR, INVERTED, "and comes back on")

    ops.detach(_background, record)
    Bench.composite(_easel)
    _shows(NEAR, PAINT, "A detach shows the layer again")
    _shows(FAR, PAINT, "in every chunk")


func test_a_document_with_no_filter_hands_the_chunk_back_untouched() -> void:
    var chunk := _background.get_field(Vector2i(0, 0))
    var chain := _easel.compositor.filter_chain
    assert_true(
        chain.filtered(_background, chunk, Vector2i(0, 0), SaDocument.WHOLE_CHUNK) == chunk,
        "No record, no scratch and no dispatch"
    )
    var record := SaFilterOps.new(_doc).attach(_background, Bench.INVERT)
    SaFilterOps.new(_doc).set_enabled(record, false)
    assert_true(
        chain.filtered(_background, chunk, Vector2i(0, 0), SaDocument.WHOLE_CHUNK) == chunk, "nor for a record that is off"
    )


func test_the_second_record_reads_what_the_first_wrote() -> void:
    var ops := SaFilterOps.new(_doc)
    ops.attach(_background, Bench.INVERT)
    ops.attach(_background, Bench.INVERT)
    Bench.composite(_easel)
    _shows(NEAR, PAINT, "Two inverts in order are the layer again")
    _shows(FAR, PAINT, "in every chunk")


func test_a_filtered_layer_folds_into_the_cache_below_the_active_one() -> void:
    var ops := SaLayerOps.new(_doc)
    var upper := ops.add()
    assert_true(_doc.active_layer == upper, "A new layer is active, so two layers sit below it")
    _doc.fill_layer(Color(0, 0, 0, 0), _doc.get_node("Layer 1") as SaLayer)
    SaFilterOps.new(_doc).attach(_background, Bench.INVERT)
    Bench.composite(_easel)
    assert_eq(_doc.fold.bottom_stack.size(), 1, "The two layers below folded into one step")
    assert_true(_doc.fold.bottom_stack[0][SaLayerStack.LAYER] == _doc.fold.bottom_cache, "which is the bottom cache")
    _shows(NEAR, INVERTED, "and the fold ran the background's filter on the way in")


func test_a_filter_on_the_active_layer_runs_over_it() -> void:
    _doc.set_active_layer(_background)
    SaFilterOps.new(_doc).attach(_background, Bench.INVERT)
    Bench.composite(_easel)
    _shows(NEAR, INVERTED, "The active layer leaves the batch and goes through the chain")
    _shows(FAR, INVERTED, "in every chunk")


func test_a_records_mask_keeps_the_filter_off_where_it_is_zero() -> void:
    var record := SaFilterOps.new(_doc).attach(_background, Bench.INVERT)
    record.mask = SaMask.own()
    var coverage := record.mask.get_or_create(Vector2i(0, 0))
    var values := PackedFloat32Array()
    values.resize(coverage.size.x * coverage.size.y)
    for y in coverage.size.y:
        for x in coverage.size.x:
            values[y * coverage.size.x + x] = 1.0 if x < 128 else 0.0
    GlobalShaderCompiler.get_rd().texture_update(coverage.rid, 0, values.to_byte_array())
    record.touch()
    Bench.composite(_easel)
    _shows(Vector2i(40, 10), INVERTED, "Where the record's mask is one the filter runs")
    _shows(Vector2i(200, 10), PAINT, "where it is zero the layer shows as it is")
    _shows(FAR, INVERTED, "and a chunk the mask never held reads as one")


func test_a_key_no_module_registers_is_skipped_and_said_once() -> void:
    var announce := SaProblems.announce
    SaProblems.announce = false
    var before := SaProblems.pending.size()
    SaFilterOps.new(_doc).attach(_background, &"nobody.nothing")
    Bench.composite(_easel)
    Bench.composite(_easel)
    SaProblems.announce = announce
    _shows(NEAR, PAINT, "A record nothing answers leaves the layer as it is")
    assert_eq(SaProblems.pending.size(), before + 1, "and is reported once, not once per chunk per frame")
    SaProblems.pending.resize(before)
