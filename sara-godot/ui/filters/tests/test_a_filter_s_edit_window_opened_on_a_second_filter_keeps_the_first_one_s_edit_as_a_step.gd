## The filter edit window is not modal, so a double click on a second attached
## filter's row opens it on that record while it still holds the first. The
## first record's live edit is settled as Apply settles it, one Edit Filter step
## whose undo puts the opening value back, rather than left on the record with
## no step for Ctrl+Z to find. Then the window holds the second record alone,
## and its Apply and Cancel touch nothing of the first.
##
## Built and never added to the tree, for the reason `test_the_filter_editor.gd`
## gives.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const KNOB := &"second_record_suite.knob"

var _easel: SaEasel
var _doc: SaDocument
var _registry: SaFilterRegistry
var _window: SaFilterEditWindow
var _first: SaAttachedFilter
var _second: SaAttachedFilter


## A filter with one number, the shape `test_the_filter_editor.gd` brings.
class Knob:
    extends SaFilter

    var amount: SaSlider

    func title() -> String:
        return "Knob"

    func build(ui: SaDialog) -> void:
        ui.title("Knob")
        ui.preview()
        amount = ui.slider("Amount", 0, 10, 3)
        ui.apply_cancel()

    func parameters() -> Dictionary:
        return {"amount": float(amount.value)}

    func set_parameters(values: Dictionary) -> void:
        if values.has("amount"):
            amount.value = values["amount"]

    func run(_ctx: SaFilterContext) -> void:
        pass


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _registry = SaFilterRegistry.new()
    _registry.register(Knob.new(), &"second_record_suite")
    _window = SaFilterEditWindow.new()
    _window.watch(_registry)
    _first = SaFilterOps.new(_doc).attach(_doc.active_layer, KNOB, {"amount": 7.0})
    _second = SaFilterOps.new(_doc).attach(_doc.active_layer, KNOB, {"amount": 1.0})


func after_each() -> void:
    _window.free()
    _easel.free()
    _registry = null


## Moves the window's one slider as a hand would and lets the deferred write
## land, unless *flushed* is false, which leaves it pending as a move in the
## same frame as the second open would.
func _move(value: float, flushed: bool = true) -> void:
    _window.dialog.row(&"amount").drive(value)
    if flushed:
        _window.dialog.flush_rerun()


func test_the_first_records_edit_stays_as_one_step_that_undo_takes_back() -> void:
    var steps := _doc.undo_redo.get_history_count()
    _window.open(_first, _doc)
    _move(2.0)
    _window.open(_second, _doc)
    assert_eq(_first.parameters, {"amount": 2.0}, "The first record keeps the value the painter moved it to")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one step more in the history")
    _doc.undo()
    assert_eq(_first.parameters, {"amount": 7.0}, "whose undo puts the opening value back")
    assert_eq(_second.parameters, {"amount": 1.0}, "and leaves the second record alone")
    _doc.redo()
    assert_eq(_first.parameters, {"amount": 2.0}, "and whose redo brings the edit again")


func test_a_move_still_pending_when_the_second_opens_is_settled_too() -> void:
    var steps := _doc.undo_redo.get_history_count()
    _window.open(_first, _doc)
    _move(4.0, false)
    _window.open(_second, _doc)
    assert_eq(_first.parameters, {"amount": 4.0}, "A move whose write was deferred lands on the first record")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "in the one step the settle makes")
    _doc.undo()
    assert_eq(_first.parameters, {"amount": 7.0}, "and undo takes it back")


func test_an_untouched_first_record_makes_no_step() -> void:
    var steps := _doc.undo_redo.get_history_count()
    _window.open(_first, _doc)
    _window.open(_second, _doc)
    assert_eq(_doc.undo_redo.get_history_count(), steps, "Opening on a second record with nothing moved makes no step")
    assert_eq(_first.parameters, {"amount": 7.0}, "and the first record is as it was")


func test_the_window_then_shows_the_second_record() -> void:
    _window.open(_first, _doc)
    _move(2.0)
    _window.open(_second, _doc)
    assert_eq(_window.record, _second, "The window holds the second record")
    assert_eq(_window.dialog.row(&"amount").read(), 1.0, "drawn from its own values")
    assert_eq(_window.describe()["opened_with"], {"amount": 1.0}, "and Cancel would restore the second's values")


func test_cancel_on_the_second_record_acts_on_it_alone() -> void:
    _window.open(_first, _doc)
    _move(2.0)
    _window.open(_second, _doc)
    var steps := _doc.undo_redo.get_history_count()
    _move(5.0)
    assert_eq(_second.parameters, {"amount": 5.0}, "The second record previews its move")
    _window.cancel()
    assert_eq(_second.parameters, {"amount": 1.0}, "Cancel puts the second record back")
    assert_eq(_first.parameters, {"amount": 2.0}, "and leaves the first at its settled edit")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "with no step")
    _doc.undo()
    assert_eq(_first.parameters, {"amount": 7.0}, "so the latest step is still the first record's edit")


func test_apply_on_the_second_record_acts_on_it_alone() -> void:
    _window.open(_first, _doc)
    _move(2.0)
    _window.open(_second, _doc)
    var steps := _doc.undo_redo.get_history_count()
    _move(5.0)
    _window.accept()
    assert_eq(_second.parameters, {"amount": 5.0}, "Apply keeps the second record's value")
    assert_eq(_first.parameters, {"amount": 2.0}, "and leaves the first as it was settled")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one step of its own")
    _doc.undo()
    assert_eq(_second.parameters, {"amount": 1.0}, "whose undo takes back the second record's edit")
    assert_eq(_first.parameters, {"amount": 2.0}, "and only that")
