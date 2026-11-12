## A double click on an attached filter's row opens an editor of its own, on the
## values the record holds, where a change previews live, one Apply lands as one
## history step and Cancel puts back what the window opened with.
##
## Built and never added to the tree, the way `test_filter_dialog_starts_hidden.gd`
## explains: a Window in the tree maps an OS window and hangs the runner. So the
## double click itself is the scenario's to prove, because it goes through the
## input stack an embedded docker is fed by, and what is here is the window and
## the step it makes.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const KNOB := &"w5_suite.knob"

var _easel: SaEasel
var _doc: SaDocument
var _registry: SaFilterRegistry
var _record: SaAttachedFilter
var _window: SaFilterEditWindow


## A filter with one number, which is all the contract needs. The shape
## `test_filter_panel.gd` brings, for its reason: the tree's own filters are
## modules and a suite names none of them.
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
    _registry.register(Knob.new(), &"w5_suite")
    _record = SaFilterOps.new(_doc).attach(_doc.active_layer, KNOB, {"amount": 7.0})
    _window = SaFilterEditWindow.new()
    _window.watch(_registry)


func after_each() -> void:
    _window.free()
    _easel.free()
    _registry = null


## Opens the window on the attached record, which is what the row's double click
## does once it has taken the panel's pick back.
func _open() -> void:
    _window.open(_record, _doc)


## Moves the filter's one widget and lets the deferred rerun land, which is the
## frame boundary the running app gives it.
func _move(amount: float) -> void:
    _window.dialog.row(&"amount").drive(amount)
    _window.dialog.flush_rerun()


func test_opening_the_window_builds_the_filters_page() -> void:
    _open()
    assert_true(_window.visible, "The window is shown")
    assert_not_null(_window.dialog, "and the filter's page is built")
    assert_eq(_window.title, "Knob on %s" % _doc.active_layer.name, "titled by the filter and the layer it hangs on")
    assert_eq(_window.record, _record, "and pointed at the record the row draws")
    assert_eq(_window.dialog.row(&"amount").read(), 7.0, "The widget is drawn from what the record keeps")
    assert_eq(_record.revision, 0, "and opening announced no change")
    for declared: SaPageRow in _window.dialog.rows():
        if SaFilterEditWindow.LEFT_OUT.has(_window.dialog.widget_name(declared.key)):
            assert_false(declared.line.visible, "The %s row is left out" % _window.dialog.widget_name(declared.key))


func test_a_moved_widget_writes_the_record_and_makes_no_step() -> void:
    _open()
    var steps := _doc.undo_redo.get_history_count()
    var revision := _record.revision
    _move(2.0)
    assert_eq(_record.parameters, {"amount": 2.0}, "The record's parameters are the widget's")
    assert_true(_record.revision > revision, "and its revision moved, which is what redraws the canvas")
    assert_eq(_window.writes, 1, "One settled change is one write")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "and the history has no step for it")

    _window.dialog.request_rerun()
    _window.dialog.flush_rerun()
    assert_eq(_window.writes, 1, "A rerun that changed nothing writes nothing")


func test_apply_is_one_step_and_its_undo_is_what_the_window_opened_with() -> void:
    _open()
    var steps := _doc.undo_redo.get_history_count()
    _move(2.0)
    _window.accept()
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "Apply lands as one history step")
    assert_eq(_record.parameters, {"amount": 2.0}, "and the record keeps the edited number")
    assert_false(_window.visible, "The window closes")
    assert_null(_window.dialog, "and its page goes with it")

    _doc.undo()
    assert_eq(_record.parameters, {"amount": 7.0}, "One undo brings the values it opened with back")


func test_cancel_puts_the_values_it_opened_with_back() -> void:
    _open()
    var steps := _doc.undo_redo.get_history_count()
    _move(2.0)
    assert_eq(_record.parameters, {"amount": 2.0}, "The change is live while the window is open")
    _window.cancel()
    assert_eq(_record.parameters, {"amount": 7.0}, "Cancel leaves the filter as it was")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "and makes no step of its own")
    assert_false(_window.visible, "and the window closes")


func test_a_second_record_replaces_the_firsts_page() -> void:
    _open()
    var second := SaFilterOps.new(_doc).attach(_doc.active_layer, KNOB, {"amount": 1.0})
    _window.open(second, _doc)
    assert_eq(_window.record, second, "The window shows the record it was opened on")
    assert_eq(_window.dialog.row(&"amount").read(), 1.0, "with its own values")
    assert_eq(_window.writes, 0, "and one open is no write")


func test_a_record_nobody_provides_opens_a_window_that_says_so() -> void:
    var orphan := SaFilterOps.new(_doc).attach(_doc.active_layer, &"nobody.gone")
    _window.open(orphan, _doc)
    assert_true(_window.visible, "A record of a missing module still opens the window")
    assert_null(_window.dialog, "with no widgets")
    assert_false(_window.describe()["provided"], "and the dump says nobody provides it")
    _window.cancel()
    assert_false(_window.visible, "and Cancel closes it with nothing written")
