## Sara knows what the open documents' chunks and history hold
## against a budget set from the card.
##
## Two documents are painted and stepped, and each one's resident and history
## bytes are read against sums made here from the chunks' own edges and the
## field formats' widths, so the accounting is checked against the formula the
## spec names rather than against itself. The budget is read off a stood-in
## card. The Performance page's row that lowers it is read by its own suite
## beside the page, `test_the_memory_budget_row_lowers_the_budget.gd`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

## The stood-in card, eight GiB.
const CARD := 8 << 30
const RED := Color(1.0, 0.0, 0.0, 1.0)

var _easels: Array[SaEasel] = []
var _share_before := 0.0


func before_each() -> void:
    _share_before = SaSettings.card_memory_share
    SaSettings.card_memory_share = SaSettings.MAX_CARD_MEMORY_SHARE
    _easels.clear()


func after_each() -> void:
    SaCardMemory.stand_in(-1)
    SaSettings.card_memory_share = _share_before
    for easel in _easels:
        easel.free()
    _easels.clear()


func _document(size: Vector2i) -> SaDocument:
    var easel := SaEasel.create_default(size)
    _easels.append(easel)
    return easel.document


## One hard dab on *doc*'s active layer, opened and committed as the brush does.
func _stroke(doc: SaDocument, pos: Vector2, radius: float) -> void:
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var compute := PaintKernel.compute()
    var region := Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0)
    var paint := SaPaintContext.for_region(doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, RED, radius, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    doc.commit_stroke()


## Every field of *chunk*, its edge squared times its format's width.
func _chunk_formula(chunk: SaChunk) -> int:
    var total := 0
    for field_id: StringName in chunk.field_ids():
        var texture := chunk.field(field_id)
        if texture != null:
            total += chunk.pixel_size() * chunk.pixel_size() * int(SaFieldSpec.BYTES_PER_TEXEL[texture.format])
    return total


func _chunks_formula(chunks: Dictionary[Vector2i, SaChunk]) -> int:
    var total := 0
    for chunk: SaChunk in chunks.values():
        if chunk != null:
            total += _chunk_formula(chunk)
    return total


## Every layer of *node*'s tree, with its mask's chunks.
func _tree_formula(node: Node) -> int:
    var total := 0
    for child in node.get_children():
        var layer := child as SaLayer
        if layer != null:
            total += _chunks_formula(layer.chunks)
            if layer.mask != null:
                total += _chunks_formula(layer.mask.chunks)
        total += _tree_formula(child)
    return total


func _resident_formula(doc: SaDocument) -> int:
    return _tree_formula(doc) + _chunks_formula(doc.stroke_layer.chunks)


func test_each_document_reads_the_sums_of_its_chunks_fields_and_of_its_history() -> void:
    # A stroke over paint keeps the chunks it changes as a step, and a delete
    # keeps the layer, so both of the history's totals hold something.
    var first := _document(Vector2i(512, 512))
    first.fill_layer(Color(0.2, 0.6, 0.9, 1.0), first.active_layer)
    _stroke(first, Vector2(100, 100), 20.0)
    SaLayerOps.new(first).add()
    _stroke(first, Vector2(400, 400), 20.0)
    var second := _document(Vector2i(768, 256))
    _stroke(second, Vector2(300, 100), 30.0)
    _stroke(second, Vector2(300, 100), 30.0)
    var doomed := SaLayerOps.new(second).add()
    _stroke(second, Vector2(600, 200), 10.0)
    SaLayerOps.new(second).remove(doomed)
    assert_true(second.history.total_layer_bytes() > 0, "the deleted layer is kept by the history")

    for doc: SaDocument in [first, second]:
        assert_true(doc.undo_redo.get_history_count() >= 3, "%s has history steps" % doc.canvas_size)
        assert_true(_resident_formula(doc) > 0, "and painted chunks")
        assert_eq(SaMemoryBudget.resident_bytes(doc), _resident_formula(doc), "resident bytes of %s" % doc.canvas_size)
        var history := doc.history.total_bytes() + doc.history.total_layer_bytes()
        assert_true(history > 0, "the history holds snapshots")
        assert_eq(SaMemoryBudget.history_bytes(doc), history, "history bytes of %s" % doc.canvas_size)
        assert_eq(SaMemoryBudget.document_bytes(doc), _resident_formula(doc) + history, "and the two together")
    assert_true(SaMemoryBudget.resident_bytes(first) != SaMemoryBudget.resident_bytes(second), "each its own")


func test_a_stroke_across_a_new_chunk_raises_the_resident_bytes_by_that_chunk() -> void:
    var doc := _document(Vector2i(768, 256))
    _stroke(doc, Vector2(100, 100), 20.0)
    var layer := doc.active_layer
    var before := SaMemoryBudget.resident_bytes(doc)
    var grid := Vector2i(2, 0)
    assert_false(layer.chunks.has(grid), "the third chunk is not painted yet")
    _stroke(doc, Vector2(640, 128), 20.0)
    assert_true(layer.chunks.has(grid), "the stroke made it")
    assert_eq(SaMemoryBudget.resident_bytes(doc) - before, _chunk_formula(layer.chunks[grid]), "by exactly its fields")


func test_the_budget_is_the_share_of_the_card_and_follows_the_setting() -> void:
    SaCardMemory.stand_in(CARD)
    assert_eq(SaMemoryBudget.budget(), roundi(CARD * SaSettings.MAX_CARD_MEMORY_SHARE), "six tenths of 8 GiB")
    assert_true(SaMemoryBudget.budget() < CARD - SaCardMemory.margin(CARD), "below the card's limit")
    SaSettings.card_memory_share = 0.3
    assert_eq(SaMemoryBudget.budget(), roundi(CARD * 0.3), "a lowered share lowers it")
    SaSettings.card_memory_share = 0.9
    assert_almost_eq(SaSettings.card_memory_share, SaSettings.MAX_CARD_MEMORY_SHARE, 1e-6, "never past the default")
    SaCardMemory.stand_in(0)
    assert_eq(SaMemoryBudget.budget(), 0, "a card of 0 has no budget")
    SaCardMemory.stand_in(2 << 30)
    var limit := (2 << 30) - SaCardMemory.margin(2 << 30)
    assert_eq(SaMemoryBudget.budget(), roundi(limit * SaMemoryBudget.LIMIT_SHARE), "a small card's is cut below the limit")


func test_the_setting_is_stored_under_performance() -> void:
    assert_eq(SaSettingsKeys.place_of(&"card_memory_share"), ["performance", "card_memory_share"], "its key")
