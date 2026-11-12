## The undo history is bounded by bytes, not by steps.
extends "res://tests/test_framework.gd"

## Snapshots are real chunk textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true


## What one chunk snapshot of *doc* weighs in the history: a whole tile at the
## document's own texel depth, asked of the document rather than assumed to be
## sixteen bytes (hard rule 3, sparse chunks).
func _chunk_bytes(doc: SaDocument) -> int:
    return SaChunk.SIZE * SaChunk.SIZE * int(SaFieldSpec.BYTES_PER_TEXEL[doc.color_space.texel_format()])


func _document(size: Vector2i = Vector2i(256, 256)) -> Array:
    var easel := SaEasel.create_default(size)
    return [easel, easel.document]


## A step cap says nothing about memory, which is the whole reason this exists:
## thirty-two steps of a dab is a few megabytes and thirty-two of a full-canvas
## stroke is about 2.5 GiB.
func test_the_budget_bounds_the_bytes_rather_than_the_steps() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    assert_not_null(doc.history, "A document has a history")

    # Room for three chunk snapshots and no more. Pinned, because the budget
    # follows the document and this test is about the arithmetic under
    # that, not the depth on top of it.
    doc.history.pin_budget = true
    doc.history.budget_bytes = _chunk_bytes(doc) * 3
    for i in 8:
        doc.fill_layer(Color(float(i) / 8.0, 0.2, 0.2, 1.0))

    assert_true(doc.history.total_bytes() <= _chunk_bytes(doc) * 3, "The history never exceeds what it was given")
    assert_true(doc.history.step_count() <= 3, "so eight fills are kept as at most three steps")
    assert_true(doc.history.step_count() >= 2, "and it keeps as many as do fit, rather than one")
    assert_true(doc.undo_redo.has_undo(), "with the most recent still undoable")

    easel.free()


## The most recent step is never evicted, even when it alone is over budget.
##
## Being unable to undo the thing you just did is worse than being over a number
## nobody set deliberately.
func test_a_step_larger_than_the_whole_budget_still_exists() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]

    doc.history.pin_budget = true
    doc.history.budget_bytes = 1
    # The first fill of the fresh paint layer snapshots no chunks and weighs
    # nothing, and a step that weighs nothing is never evicted by the
    # pool it does not draw on. The second weighs a whole chunk, so it is the
    # one a third step over the budget has to push out.
    doc.fill_layer(Color(0.1, 0.1, 0.1, 1.0))
    doc.fill_layer(Color(0.3, 0.3, 0.3, 1.0))
    var first := _texel(doc)
    doc.fill_layer(Color(0.7, 0.7, 0.7, 1.0))

    assert_eq(doc.history.step_count(), 1, "Only the newest step is kept")
    assert_true(doc.undo_redo.has_undo(), "and it is undoable")
    doc.undo_redo.undo()
    assert_almost_eq(_texel(doc).r, first.r, 0.01, "so the last thing done can still be undone")

    easel.free()


## A generous budget keeps everything, so the eviction above is the budget
## working rather than the history losing steps on its own.
func test_a_budget_nothing_reaches_evicts_nothing() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]

    doc.history.pin_budget = true
    doc.history.budget_bytes = _chunk_bytes(doc) * 64
    for i in 6:
        doc.fill_layer(Color(float(i) / 6.0, 0.1, 0.1, 1.0))

    assert_eq(doc.history.step_count(), 6, "Six fills are six steps")
    # The first fill snapshots a layer with no chunks, which weighs nothing.
    assert_eq(doc.history.total_bytes(), _chunk_bytes(doc) * 5, "and the accounting is the sum of what they hold")

    easel.free()


## Undoing and then doing something else drops the redo stack, and the accounting
## has to drop with it or the budget starts counting memory nobody holds.
func test_replacing_the_redo_stack_stops_being_counted() -> void:
    var pair := _document()
    var easel: SaEasel = pair[0]
    var doc: SaDocument = pair[1]
    doc.history.pin_budget = true
    doc.history.budget_bytes = _chunk_bytes(doc) * 64

    for i in 4:
        doc.fill_layer(Color(float(i) / 4.0, 0.1, 0.1, 1.0))
    assert_eq(doc.history.step_count(), 4, "Four steps to start with")

    doc.undo_redo.undo()
    doc.undo_redo.undo()
    doc.fill_layer(Color(0.9, 0.9, 0.9, 1.0))

    assert_false(doc.undo_redo.has_redo(), "The redo stack is gone")
    assert_eq(doc.history.step_count(), doc.undo_redo.get_history_count(), "and the accounting agrees with the history")

    easel.free()


func _texel(doc: SaDocument) -> Color:
    var texture := doc.active_layer.get_field(Vector2i(0, 0))
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(0, 0)
