## Duplicate, Lock Layer, Lock Alpha and the eye on a picked set are one undo
## step each.
##
## Each of them writes one step, not one a row, so one Ctrl+Z puts back the
## whole set. The running app's half, with real presses and a real Ctrl+Z, is
## `scenarios/an-action-on-a-picked-set-is-one-undo-step.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _layers: LayersDocker
var _a: SaLayer
var _b: SaLayer
var _c: SaLayer

## Whether the eye was an undo step when the test began.
var _eye_was: bool


func before_each() -> void:
    _eye_was = SaSettings.visibility_in_history
    SaSettings.visibility_in_history = false
    _easel = Bench.easel(Vector2i(128, 128))
    _doc = _easel.document
    _a = _doc.active_layer
    _a.name = "A"
    _b = SaLayerOps.new(_doc).add()
    _b.name = "B"
    _c = SaLayerOps.new(_doc).add()
    _c.name = "C"
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    _layers.list_keeper.listen()
    _layers.sync_layer_list()


func after_each() -> void:
    SaSettings.visibility_in_history = _eye_was
    _layers.free()
    _canvas.free()
    _easel.free()
    _a = null
    _b = null
    _c = null


func _list() -> SaLayerList:
    return _layers.item_list


func _row_of(layer: SaLayer) -> int:
    for i in _list().rows.size():
        if _list().layer_at(i) == layer:
            return i
    return -1


## A press on *layer*'s row, plain or with Ctrl, as the painter picks.
func _pick(layer: SaLayer, ctrl: bool = false) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.ctrl_pressed = ctrl
    _list()._on_row_gui_input(event, _row_of(layer))


func _names() -> PackedStringArray:
    var names := PackedStringArray()
    for layer in SaLayerOps.new(_doc).layers():
        names.append(str(layer.name))
    return names


## The note's case: C and A picked, Duplicate pressed, one Ctrl+Z, and both
## copies are gone.
func test_two_picked_rows_duplicate_as_one_step() -> void:
    _pick(_c)
    _pick(_a, true)
    var steps := _doc.history.step_count()

    _layers.actions.duplicate_layer()

    assert_eq(_names(), PackedStringArray(["Background", "A", "A Copy", "B", "C", "C Copy"]), "each picked row has its copy")
    assert_eq(_doc.history.step_count(), steps + 1, "and the press wrote one step")
    assert_true(_doc.undo(), "the step is undone")
    assert_eq(_names(), PackedStringArray(["Background", "A", "B", "C"]), "one Ctrl+Z takes both copies away")
    assert_true(_doc.redo(), "and redone")
    assert_eq(_names(), PackedStringArray(["Background", "A", "A Copy", "B", "C", "C Copy"]), "which brings both back")


## A set of one is the single-row duplicate it always was, its step named so.
func test_one_picked_row_duplicates_as_it_always_did() -> void:
    _pick(_b)
    _layers.actions.duplicate_layer()
    assert_eq(_names(), PackedStringArray(["Background", "A", "B", "B Copy", "C"]), "one copy above its source")
    assert_eq(_doc.active_layer, _doc.get_node_or_null("B Copy"), "and the copy is the active layer")
    assert_true(_doc.undo(), "the step is undone")
    assert_eq(_names(), PackedStringArray(["Background", "A", "B", "C"]), "and the copy is gone")


## The More menu's Lock Layer on C and B, one Ctrl+Z, and both are unlocked.
func test_two_picked_rows_lock_as_one_step() -> void:
    _pick(_c)
    _pick(_b, true)
    var steps := _doc.history.step_count()

    _layers.actions.set_paint_lock(true)

    assert_true(_c.is_locked and _b.is_locked, "both picked rows are locked")
    assert_false(_a.is_locked, "and the row nobody picked is not")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_true(_doc.undo(), "the step is undone")
    assert_false(_c.is_locked or _b.is_locked, "one Ctrl+Z unlocks both")


## The same for the menu's Lock Alpha.
func test_two_picked_rows_lock_alpha_as_one_step() -> void:
    _pick(_c)
    _pick(_b, true)
    var steps := _doc.history.step_count()

    _layers.actions.set_alpha_lock(true)

    assert_true(_c.alpha_locked and _b.alpha_locked, "both picked rows hold their alpha")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_true(_doc.undo(), "the step is undone")
    assert_false(_c.alpha_locked or _b.alpha_locked, "one Ctrl+Z takes both alpha locks")


## Three rows picked and B's eye clicked: all three hidden as one step, and one
## Ctrl+Z shows all three again.
func test_three_picked_rows_hide_as_one_step() -> void:
    SaSettings.visibility_in_history = true
    _pick(_c)
    _pick(_b, true)
    _pick(_a, true)
    var steps := _doc.history.step_count()

    _list()._on_eye_pressed(_row_of(_b))

    assert_false(_a.visible or _b.visible or _c.visible, "the eye hid all three")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_true(_doc.undo(), "the step is undone")
    assert_true(_a.visible and _b.visible and _c.visible, "one Ctrl+Z shows all three")
    assert_true(_doc.redo(), "and redone")
    assert_false(_a.visible or _b.visible or _c.visible, "which hides all three again")


## A row already in the state the eye asks for is left out of the step, so an
## undo never shows a row the press did not hide.
func test_a_row_already_hidden_stays_hidden_after_the_undo() -> void:
    SaSettings.visibility_in_history = true
    SaLayerOps.new(_doc).set_visible(_a, false)
    _layers.sync_layer_list()
    _pick(_c)
    _pick(_a, true)

    _list()._on_eye_pressed(_row_of(_c))
    assert_false(_c.visible or _a.visible, "both hidden")
    assert_true(_doc.undo(), "the step is undone")
    assert_true(_c.visible, "C is shown again")
    assert_false(_a.visible, "and A, hidden before the press, stays hidden")
