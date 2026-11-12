## A slider step taken after an undo is a new step, not one folded into the
## step before it, and the history keeps every step its budget has room for.
##
## UndoRedo's count is the same after such a step as before it, one redo step
## discarded and one added, and so it is when the oldest step is pushed out as
## a new one comes in. Read as a fold, either left the history's own lists one
## step short of UndoRedo's, and the next step then dropped the oldest real one
## with no drop counted.
extends "res://tests/test_framework.gd"

## Painted steps hold real chunk textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

var _value: int = 0


func _set_value(value: int) -> void:
    _value = value


func _fresh() -> SaEasel:
    return SaEasel.create_default(Vector2i(256, 256))


## One committed stroke over the chunk at *grid_pos*, the way the other
## history suites make one.
func _paint(doc: SaDocument, grid_pos: Vector2i) -> void:
    doc.begin_stroke(1.0, &"normal")
    doc.stroke_layer.get_or_create_chunk(grid_pos)
    doc.commit_stroke()


## Paint two steps, undo one, move the opacity and paint once more.
func _the_sequence(doc: SaDocument, saved_after_opacity: bool = false) -> void:
    _paint(doc, Vector2i(0, 0))
    _paint(doc, Vector2i(1, 0))
    assert_true(doc.undo(), "The second stroke undoes")
    SaLayerOps.new(doc).set_opacity(doc.active_layer, 0.5)
    if saved_after_opacity:
        doc.mark_saved(SaDataRoot.path("h101_probe.sad"))
    _paint(doc, Vector2i(0, 1))


func test_an_opacity_step_after_an_undo_is_a_step_of_its_own() -> void:
    var easel := _fresh()
    var doc := easel.document
    doc.history.announce_drops = false
    _paint(doc, Vector2i(0, 0))
    _paint(doc, Vector2i(1, 0))
    assert_true(doc.undo(), "The second stroke undoes")
    SaLayerOps.new(doc).set_opacity(doc.active_layer, 0.5)
    assert_eq(doc.history.step_count(), doc.undo_redo.get_history_count(), "The history counts what UndoRedo holds")
    assert_eq(doc.history.step_count(), 2, "which is the first stroke and the opacity")
    easel.free()


func test_the_step_after_it_drops_nothing() -> void:
    var easel := _fresh()
    var doc := easel.document
    doc.history.announce_drops = false
    var opacity_before := doc.active_layer.opacity
    _the_sequence(doc)
    assert_eq(doc.undo_redo.get_history_count(), 3, "UndoRedo holds the first stroke, the opacity and the last stroke")
    assert_eq(doc.history.step_count(), 3, "and so does the history")
    assert_eq(doc.history.dropped_steps, 0, "with no step dropped, because the budget had room")
    var undone := 0
    while doc.undo():
        undone += 1
    assert_eq(undone, 3, "Three steps undo, the first stroke among them")
    assert_false(doc.active_layer.chunks.has(Vector2i(0, 0)), "Undone to the start, the first stroke is gone")
    assert_eq(doc.active_layer.opacity, opacity_before, "and the opacity is what it was")
    easel.free()


func test_the_saved_mark_follows_an_opacity_step_after_an_undo() -> void:
    var easel := _fresh()
    var doc := easel.document
    doc.history.announce_drops = false
    _the_sequence(doc, true)
    assert_true(doc.modified, "The stroke after the save is a change")
    assert_true(doc.undo(), "Undoing it")
    assert_false(doc.modified, "stands on the opacity step the save was made at")
    assert_true(doc.undo(), "Undoing the opacity")
    assert_true(doc.modified, "goes before the save")
    assert_true(doc.redo(), "and redoing it")
    assert_false(doc.modified, "comes back to the saved step")
    easel.free()


func test_an_opacity_drag_with_no_undo_before_it_is_one_step() -> void:
    var easel := _fresh()
    var doc := easel.document
    var opacity_before := doc.active_layer.opacity
    _paint(doc, Vector2i(0, 0))
    var ops := SaLayerOps.new(doc)
    for value: float in [0.9, 0.8, 0.7, 0.6, 0.5]:
        ops.set_opacity(doc.active_layer, value)
    assert_eq(doc.undo_redo.get_history_count(), 2, "Five positions of one drag fold into one action")
    assert_eq(doc.history.step_count(), 2, "and the history counts it once")
    assert_true(doc.undo(), "One undo")
    assert_eq(doc.active_layer.opacity, opacity_before, "takes the whole drag back")
    easel.free()


## A step that pushes the oldest one out as it comes in leaves the count where
## it was too, and is the other case a count read as a fold.
func test_a_merging_step_that_pushes_the_oldest_out_is_counted_as_a_drop() -> void:
    var easel := _fresh()
    var doc := easel.document
    var history := doc.history
    history.announce_drops = false
    history.pin_budget = true
    history.budget_bytes = 3
    for value: int in [1, 2, 3]:
        history.commit_pair("step", _set_value.bind(value), _set_value.bind(value - 1), 1)
        _value = value
    history.commit_pair("slider", _set_value.bind(4), _set_value.bind(3), 1, 0, UndoRedo.MERGE_ENDS)
    _value = 4
    assert_eq(history.step_count(), doc.undo_redo.get_history_count(), "The history counts what UndoRedo holds")
    assert_eq(history.step_count(), 3, "which is the three that fit")
    assert_eq(history.dropped_steps, 1, "and the one pushed out is counted")
    while doc.undo():
        pass
    assert_eq(_value, 1, "Undone as far as it goes, the value is the oldest kept step's")
    easel.free()
