## The layers a history step keeps go to RAM with its
## snapshots, and the history's share counts only what is on the card.
##
## A ground and three painted layers, then a painted layer deleted, the canvas
## cropped and resampled, make a history whose last three steps keep whole
## layers and whole grids beside the strokes' snapshots. A settle under a
## budget moves what those steps keep to RAM before any chunk of the tree, the
## oldest step's first, and every step undone from RAM reads as with no budget.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const SIZE := Vector2i(512, 512)
const GROUND := Color(0.85, 0.8, 0.7, 1.0)
const COLOURS: Array[Color] = [Color(0.8, 0.1, 0.1, 1.0), Color(0.1, 0.6, 0.2, 0.7), Color(0.1, 0.2, 0.9, 0.5)]

var _easels: Array[SaEasel] = []


func after_each() -> void:
    SaCardMemory.stand_in(-1)
    for easel in _easels:
        easel.free()
    _easels.clear()


func _stroke(doc: SaDocument, pos: Vector2, radius: float, colour: Color) -> void:
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
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, colour, radius, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    doc.commit_stroke()


## The ground and three layers painted, the middle one deleted, the canvas
## cropped and then resampled, with no budget, so nothing has moved yet.
func _built() -> SaEasel:
    SaCardMemory.stand_in(0)
    var easel := SaEasel.create_default(SIZE)
    _easels.append(easel)
    var doc := easel.document
    doc.history.layer_budget_bytes = 1 << 30
    doc.fill_layer(GROUND, doc.active_layer)
    var painted: Array[SaLayer] = []
    for index in COLOURS.size():
        painted.append(SaLayerOps.new(doc).add())
        for step in 3:
            var pos := Vector2(90.0 + step * 160.0, 100.0 + index * 150.0 + step * 20.0)
            _stroke(doc, pos, 60.0, COLOURS[index])
    assert_true(SaLayerOps.new(doc).remove(painted[1]), "the green layer is deleted")
    assert_true(SaCrop.new(doc).crop_to(Rect2i(32, 40, 448, 416)), "the canvas is cropped")
    assert_true(SaResample.new(doc).resample_to(Vector2i(600, 560)), "and resampled")
    return easel


func _composite(easel: SaEasel) -> PackedByteArray:
    var doc := easel.document
    doc.fold.rebuild(doc, doc.compositor, Rect2(Vector2.ZERO, Vector2(doc.canvas_size)))
    doc.invalidate_all_allocated_chunks()
    easel.process_pending_composite()
    return SaExport.get_easel_image_float(easel).get_data()


func _is_stored(entry: Variant) -> bool:
    if entry is SaChunk:
        return (entry as SaChunk).is_stored()
    return (entry as SaChunkDelta).is_stored()


func _size(entry: Variant) -> int:
    if entry is SaChunk:
        return (entry as SaChunk).byte_size()
    return (entry as SaChunkDelta).byte_size()


func _layers_of(node: Node, found: Array[SaLayer]) -> Array[SaLayer]:
    for child in node.get_children():
        if child is SaLayer:
            found.append(child)
        _layers_of(child, found)
    return found


func _stored_tree_chunks(doc: SaDocument) -> int:
    var count := 0
    for layer: SaLayer in _layers_of(doc, []):
        for chunk: SaChunk in layer.chunks.values():
            if chunk.is_stored():
                count += 1
    return count


## The whole chunks the history keeps for its structural steps, the ones the
## pixel steps' snapshot states never name.
func _kept_chunks(doc: SaDocument) -> Array:
    var named: Dictionary[int, bool] = {}
    for state: Dictionary in doc.history.snapshot_states():
        for entry: Variant in state.values():
            if entry is Object:
                named[(entry as Object).get_instance_id()] = true
    return SaResidency.history_entries(doc).filter(
        func(e: Variant) -> bool: return e is SaChunk and not named.has((e as Object).get_instance_id())
    )


func _deleted_layer(doc: SaDocument) -> SaLayer:
    for held: Array in doc.history.holdings():
        for entry: Variant in held:
            if entry is SaLayer and not doc.is_ancestor_of(entry):
                return entry
    return null


func test_what_the_delete_the_crop_and_the_resample_keep_goes_to_ram_before_the_tree() -> void:
    var easel := _built()
    var doc := easel.document
    var gone := _deleted_layer(doc)
    assert_not_null(gone, "the history holds the deleted layer out of the tree")
    var kept := _kept_chunks(doc)
    var gone_chunks: Array = gone.chunks.values()
    assert_true(gone_chunks.size() > 0, "the deleted layer kept its paint, %d chunks" % gone_chunks.size())
    assert_true(gone_chunks.all(func(c: SaChunk) -> bool: return kept.has(c)), "and its chunks are the history's to move")
    assert_true(kept.size() > gone_chunks.size(), "the crop and the resample keep whole grids too, %d" % kept.size())
    var entries := SaResidency.history_entries(doc)
    var on_card := SaMemoryBudget.history_bytes(doc)
    var steps := doc.history.step_count()
    assert_true(on_card > 0, "the history holds bytes on the card, %d" % on_card)

    var held := SaCardMemory.held()
    var moved := SaResidency.settle(doc, held - (on_card >> 1))
    assert_true(moved > 0, "half the history's share asked moves something, %d" % moved)
    var stored := entries.map(_is_stored)
    var first_on_card := stored.find(false)
    assert_true(first_on_card > 0, "the oldest entries went first")
    assert_false(stored.slice(first_on_card).has(true), "every entry in RAM is older than every one on the card")
    assert_eq(_stored_tree_chunks(doc), 0, "and no chunk of the tree moved")

    var moved_bytes := 0
    for entry: Variant in entries:
        if not _is_stored(entry):
            moved_bytes += _size(entry)
    SaResidency.settle(doc, SaCardMemory.held() - moved_bytes)
    assert_true(entries.all(_is_stored), "a budget below the whole share takes every entry")
    assert_true(gone_chunks.all(func(c: SaChunk) -> bool: return c.is_stored()), "the deleted layer's chunks among them")
    assert_true(kept.all(func(c: SaChunk) -> bool: return c.is_stored()), "and the crop's and the resample's")
    assert_eq(_stored_tree_chunks(doc), 0, "still before any chunk of the tree")
    assert_eq(SaMemoryBudget.history_bytes(doc), 0, "the history's share reads nothing on the card")
    assert_eq(doc.history.step_count(), steps, "the history keeps its steps")


func test_after_a_settle_the_history_s_share_falls_by_what_moved_and_its_charge_stands() -> void:
    var doc := _built().document
    var before := SaMemoryBudget.history_bytes(doc)
    var charged := doc.history.total_bytes() + doc.history.total_layer_bytes()
    var steps := doc.history.step_count()
    var entries := SaResidency.history_entries(doc)
    var sizes: Array[int] = []
    for entry: Variant in entries:
        sizes.append(_size(entry))
    SaResidency.settle(doc, SaCardMemory.held() - (before >> 2))
    var moved := 0
    for i in entries.size():
        if _is_stored(entries[i]):
            moved += sizes[i]
    assert_true(moved > 0, "something moved, %d bytes" % moved)
    assert_eq(SaMemoryBudget.history_bytes(doc), before - moved, "the share fell by the bytes the moved snapshots held")
    assert_eq(doc.history.total_bytes() + doc.history.total_layer_bytes(), charged, "the limits read what was charged")
    assert_eq(doc.history.step_count(), steps, "and the step count is as before")


func test_every_step_undone_from_ram_reads_as_with_no_budget() -> void:
    var plain := _built()
    var tight := _built()
    var gone := _deleted_layer(tight.document)
    assert_eq(_composite(tight), _composite(plain), "the two start alike")
    var undone := 0
    var came_back := false
    while undone <= plain.document.history.step_count():
        SaResidency.settle(tight.document, SaCardMemory.held() - SaMemoryBudget.history_bytes(tight.document))
        assert_eq(SaMemoryBudget.history_bytes(tight.document), 0, "before undo %d the history is in RAM" % (undone + 1))
        var went_back := tight.document.undo_redo.undo()
        assert_eq(plain.document.undo_redo.undo(), went_back, "both undo together")
        if not went_back:
            break
        undone += 1
        assert_eq(tight.document.canvas_size, plain.document.canvas_size, "undone %d steps, the same size" % undone)
        assert_eq(_composite(tight), _composite(plain), "undone %d steps, the same pixels" % undone)
        if tight.document.is_ancestor_of(gone):
            came_back = true
            var listed := SaResidency.history_entries(tight.document)
            assert_false(
                gone.chunks.values().any(func(c: SaChunk) -> bool: return listed.has(c)),
                "the layer back in the tree is no longer the history's to move"
            )
    assert_eq(undone, plain.document.history.step_count(), "undone back to the start")
    assert_true(came_back, "the deleted layer came back on the way, until its add was undone")
