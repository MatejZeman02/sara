## The modified mark follows the history: an undo or redo that lands on the
## step the document was saved or created at clears it, and one that leaves
## that step raises it.
##
## Before this an undo raised the mark whatever it undid, so painting and
## undoing back to an empty canvas left `Untitled*` in the title and Ctrl+N
## asked about unsaved changes on a document with nothing in it.
extends "res://tests/test_framework.gd"


func _fresh() -> SaEasel:
    return SaEasel.create_default(Vector2i(256, 256))


## One committed stroke, the way `test_document_identity` makes one: a chunk in
## the stroke buffer is a stroke that touched it.
func _paint(doc: SaDocument) -> void:
    doc.begin_stroke(1.0, &"normal")
    doc.stroke_layer.get_or_create_chunk(Vector2i.ZERO)
    doc.commit_stroke()


func test_undoing_every_stroke_of_a_fresh_document_leaves_it_clean() -> void:
    var easel := _fresh()
    var doc := easel.document
    _paint(doc)
    assert_true(doc.modified, "A stroke raises the mark")
    assert_true(doc.undo(), "which undoes")
    assert_false(doc.modified, "and the undo back to the fresh document clears it")

    _paint(doc)
    _paint(doc)
    assert_true(doc.undo(), "The first of two undoes")
    assert_true(doc.modified, "leaves one stroke on the canvas, which is a change")
    assert_true(doc.undo(), "and the second")
    assert_false(doc.modified, "comes back to the fresh document, clean, the sweep's second time round")
    assert_true(doc.redo(), "A redo")
    assert_true(doc.modified, "leaves the fresh document again")
    easel.free()


func test_the_saved_step_is_clean_and_either_side_of_it_is_not() -> void:
    var easel := _fresh()
    var doc := easel.document
    _paint(doc)
    doc.mark_saved(SaDataRoot.path("d12_probe.sad"))
    _paint(doc)
    assert_true(doc.modified, "A stroke after the save is a change")
    assert_true(doc.undo(), "which undoes")
    assert_false(doc.modified, "back to the saved step, clean")
    assert_true(doc.undo(), "One more undo")
    assert_true(doc.modified, "goes past the save, and the file on disk has that stroke")
    assert_true(doc.redo(), "A redo")
    assert_false(doc.modified, "comes back to the saved step")
    easel.free()


func test_a_new_step_where_an_undone_one_stood_is_a_change() -> void:
    var easel := _fresh()
    var doc := easel.document
    _paint(doc)
    doc.mark_saved(SaDataRoot.path("d12_probe.sad"))
    assert_true(doc.undo(), "Undo past the save")
    _paint(doc)
    assert_true(doc.modified, "A stroke in the undone one's place is not the saved stroke")
    assert_true(doc.undo(), "and undoing it")
    assert_true(doc.modified, "stands before the saved step, not on it")
    easel.free()


func test_a_step_folded_into_the_saved_one_is_a_change() -> void:
    var easel := _fresh()
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    ops.set_opacity(doc.active_layer, 0.5)
    doc.mark_saved(SaDataRoot.path("d12_probe.sad"))
    # The same named step within UndoRedo's merge window folds into the saved
    # one rather than adding a row, so the history index does not move.
    ops.set_opacity(doc.active_layer, 0.6)
    assert_true(doc.modified, "Dragging on past the save is a change")
    assert_true(doc.undo(), "Undoing the folded step")
    assert_true(doc.modified, "goes before both values")
    assert_true(doc.redo(), "and redoing it")
    assert_true(doc.modified, "lands on 0.6, which the file never held")
    easel.free()


func test_a_change_outside_the_history_keeps_the_mark_through_an_undo() -> void:
    var easel := _fresh()
    var doc := easel.document
    _paint(doc)
    doc.mark_saved(SaDataRoot.path("d12_probe.sad"))
    _paint(doc)
    assert_true(doc.undo(), "Back on the saved step")
    assert_false(doc.modified, "clean")
    # What a recovery copy or any other change with no step of its own does.
    doc.modified = true
    assert_true(doc.redo(), "A redo")
    assert_true(doc.undo(), "and an undo back to the saved step")
    assert_true(doc.modified, "leave it modified, because the change has no step an undo could take back")
    doc.mark_saved(SaDataRoot.path("d12_probe.sad"))
    _paint(doc)
    assert_true(doc.undo(), "After a save a stroke and its undo")
    assert_false(doc.modified, "come back clean, because the save is what forgets the change")
    easel.free()


func test_an_evicted_saved_step_is_never_reached_again() -> void:
    var easel := _fresh()
    var doc := easel.document
    doc.history.pin_budget = true
    doc.history.announce_drops = false
    doc.history.budget_bytes = 1
    # Fills over paint, because a step that snapshots nothing weighs nothing and
    # is never evicted.
    doc.fill_layer(Color.RED)
    doc.fill_layer(Color.GREEN)
    doc.mark_saved(SaDataRoot.path("d12_probe.sad"))
    doc.fill_layer(Color.BLUE)
    doc.fill_layer(Color.WHITE)
    assert_true(doc.history.dropped_steps > 0, "The budget evicted the saved step")
    var undos := 0
    while doc.undo() and undos < 100:
        undos += 1
    assert_true(undos < 100, "The history runs out of steps to undo")
    assert_true(doc.modified, "The oldest place the history reaches is blue, after the save")
    easel.free()


func test_a_file_opened_on_a_cleared_history_is_clean_where_it_was_opened() -> void:
    var easel := _fresh()
    var doc := easel.document
    _paint(doc)
    doc.undo_redo.clear_history()
    doc.history.reset()
    assert_true(doc.modified, "A reset history is not a save")
    doc.mark_saved(SaDataRoot.path("d12_probe.sad"))
    _paint(doc)
    assert_true(doc.undo(), "Undoing the first stroke after the open")
    assert_false(doc.modified, "comes back to the file as opened")
    easel.free()
