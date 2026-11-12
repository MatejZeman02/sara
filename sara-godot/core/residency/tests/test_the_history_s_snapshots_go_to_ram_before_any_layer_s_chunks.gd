## The history's snapshots go to RAM before any layer's
## chunks, the oldest first.
##
## A ground fill, then three layers each painted with a run of dabs, makes a
## history whose snapshots are whole chunks (the fill) and parts of chunks (the
## dabs). Settling it under a budget a little below what the card holds moves
## the oldest snapshots out and no layer's chunk, and under a budget below what
## every snapshot holds moves them all and only then a layer's chunks.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

## A card of 1 GiB and 4 MiB, whose budget is three MiB, which every painting
## here is past, as in the sibling suite.
const SMALL_CARD := (1 << 30) + (4 << 20)
## A card of 64 GiB, whose budget is past anything a run here holds.
const LARGE_CARD := 1 << 36
const SIZE := Vector2i(1024, 768)
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


## The ground filled and three layers painted in bands of dabs, on a card of
## *card* bytes, so a small card settles at every release.
func _painted_easel(card: int) -> SaEasel:
    SaCardMemory.stand_in(card)
    var easel := SaEasel.create_default(SIZE)
    _easels.append(easel)
    var doc := easel.document
    var ground := doc.active_layer
    doc.fill_layer(GROUND, ground)
    # Filled again, so the step holds the ground's whole chunks as they were.
    doc.fill_layer(GROUND.darkened(0.2), ground)
    for index in COLOURS.size():
        SaLayerOps.new(doc).add()
        for step in 4:
            var pos := Vector2(100.0 + step * 220.0, 130.0 + index * 230.0 + step * 25.0)
            _stroke(doc, pos, 70.0, COLOURS[index])
    return easel


func _composite(easel: SaEasel) -> PackedByteArray:
    var doc := easel.document
    doc.fold.rebuild(doc, doc.compositor, Rect2(Vector2.ZERO, Vector2(doc.canvas_size)))
    doc.invalidate_all_allocated_chunks()
    easel.process_pending_composite()
    return SaExport.get_easel_image_float(easel).get_data()


## Every snapshot the history holds, the oldest step's first.
func _snapshots(doc: SaDocument) -> Array:
    var found: Array = []
    for state: Dictionary in doc.history.snapshot_states():
        for entry: Variant in state.values():
            if entry is SaChunk or entry is SaChunkDelta:
                found.append(entry)
    return found


func _is_stored(entry: Variant) -> bool:
    if entry is SaChunk:
        return (entry as SaChunk).is_stored()
    return (entry as SaChunkDelta).is_stored()


func _size(entry: Variant) -> int:
    if entry is SaChunk:
        return (entry as SaChunk).byte_size()
    return (entry as SaChunkDelta).byte_size()


func _stored_snapshots(doc: SaDocument) -> int:
    return _snapshots(doc).filter(_is_stored).size()


func _layers_of(node: Node, found: Array[SaLayer]) -> Array[SaLayer]:
    for child in node.get_children():
        if child is SaLayer:
            found.append(child)
        _layers_of(child, found)
    return found


func _stored_chunks(doc: SaDocument) -> int:
    var count := 0
    for layer: SaLayer in _layers_of(doc, []):
        for chunk: SaChunk in layer.chunks.values():
            if chunk.is_stored():
                count += 1
    return count


## Whether the stored snapshots are the oldest ones, each stored snapshot
## before every one still on the card.
func _oldest_first(doc: SaDocument) -> bool:
    var on_card_seen := false
    for entry: Variant in _snapshots(doc):
        if not _is_stored(entry):
            on_card_seen = true
        elif on_card_seen:
            return false
    return true


func test_the_oldest_snapshots_go_first_and_a_layer_s_chunks_only_once_every_snapshot_has() -> void:
    var easel := _painted_easel(0)
    var doc := easel.document
    var snapshots := _snapshots(doc)
    assert_true(snapshots.size() > 12, "the history holds whole chunks and parts of chunks, %d" % snapshots.size())
    assert_true(snapshots.any(func(e: Variant) -> bool: return e is SaChunk), "the fill left whole chunks")
    assert_true(snapshots.any(func(e: Variant) -> bool: return e is SaChunkDelta), "the dabs left parts of chunks")
    var snapshot_bytes := 0
    for entry: Variant in snapshots:
        snapshot_bytes += _size(entry)
    assert_eq(_stored_snapshots(doc), 0, "with no budget nothing is in RAM")

    var held := SaCardMemory.held()
    var half := snapshot_bytes >> 1
    var moved := SaResidency.settle(doc, held - half)
    assert_true(moved > 0, "a budget below the card moves something, %d" % moved)
    assert_true(_is_stored(snapshots[0]), "the oldest step's snapshot is in RAM")
    assert_false(_is_stored(snapshots[-1]), "the newest is still on the card")
    assert_true(_oldest_first(doc), "every snapshot in RAM is older than every one on the card")
    assert_eq(_stored_chunks(doc), 0, "and no layer's chunk has moved")
    assert_true(held - SaCardMemory.held() >= half, "the card gave back what the budget asked")

    var left := 0
    for entry: Variant in snapshots:
        left += _size(entry)
    SaResidency.settle(doc, SaCardMemory.held() - left - 1)
    assert_eq(_stored_snapshots(doc), snapshots.size(), "a budget below every snapshot takes them all")
    assert_true(_stored_chunks(doc) > 0, "and then a layer's chunk, %d" % _stored_chunks(doc))
    assert_true(SaChunkDelta.stored_bytes < snapshot_bytes, "the parts in RAM hold less than on the card")


func test_every_step_undone_and_redone_from_ram_reads_as_with_no_budget() -> void:
    var plain := _painted_easel(0)
    var tight := _painted_easel(SMALL_CARD)
    assert_true(_stored_snapshots(tight.document) > 0, "past the budget the snapshots are in RAM")
    assert_eq(_stored_snapshots(plain.document), 0, "with none they are not")
    assert_eq(tight.document.history.step_count(), plain.document.history.step_count(), "both keep the same steps")

    var undone := 0
    while undone <= plain.document.history.step_count():
        SaCardMemory.stand_in(SMALL_CARD)
        SaResidency.settle(tight.document)
        SaCardMemory.stand_in(0)
        var went_back := tight.document.undo_redo.undo()
        assert_eq(plain.document.undo_redo.undo(), went_back, "both undo together")
        if not went_back:
            break
        undone += 1
        assert_eq(_composite(tight), _composite(plain), "undone %d steps, the same pixels" % undone)
    assert_eq(undone, plain.document.history.step_count(), "undone back to the start")

    var redone := 0
    while redone <= undone:
        SaCardMemory.stand_in(SMALL_CARD)
        SaResidency.settle(tight.document)
        assert_true(_stored_snapshots(tight.document) > 0, "the snapshots went back to RAM before redo %d" % (redone + 1))
        SaCardMemory.stand_in(0)
        var went_on := tight.document.undo_redo.redo()
        assert_eq(plain.document.undo_redo.redo(), went_on, "both redo together")
        if not went_on:
            break
        redone += 1
        assert_eq(_composite(tight), _composite(plain), "redone %d steps, the same pixels" % redone)
    assert_eq(redone, undone, "every step redone")


func test_a_budget_past_everything_moves_nothing_and_keeps_the_steps() -> void:
    var plain := _painted_easel(0)
    var steps := plain.document.history.step_count()
    var dropped := plain.document.history.dropped_steps
    var raised := _painted_easel(LARGE_CARD)
    var doc := raised.document
    assert_true(SaMemoryBudget.budget() > SaCardMemory.held(), "the budget is past everything the run holds")
    assert_eq(_stored_snapshots(doc), 0, "every release left the snapshots on the card")
    assert_eq(_stored_chunks(doc), 0, "and the chunks")
    assert_eq(_composite(raised), _composite(plain), "and the painting is the same")
    assert_eq(doc.history.step_count(), steps, "the history keeps its steps")
    assert_eq(doc.history.dropped_steps, dropped, "and dropped none more")
    var position := doc.history.position()
    var readbacks := SaResidency.readbacks
    assert_eq(SaResidency.settle(doc), 0, "a settle asked again moves nothing")
    assert_eq(SaResidency.readbacks, readbacks, "and reads nothing back")
    assert_eq(doc.history.step_count(), steps, "the steps are as they were")
    assert_eq(doc.history.position(), position, "and it stands where it stood")
    var tight := _painted_easel(SMALL_CARD)
    assert_eq(tight.document.history.step_count(), steps, "a history past the budget keeps as many steps")
    assert_eq(tight.document.history.dropped_steps, dropped, "and drops as many")
