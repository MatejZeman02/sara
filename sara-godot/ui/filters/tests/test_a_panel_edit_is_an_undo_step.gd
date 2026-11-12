## An attached filter's slider edit in the tool options panel is an undo step.
## Brightness dragged from 21 to -53
## in the panel left nothing on the History list, and Ctrl+Z took the whole
## filter off, while the edit window's Apply logged Edit Filter.
##
## Both doors now write through `SaFilterOps.set_parameters`. The panel's first
## write opens an Edit Filter step and the rest of the drag folds into it, one
## undo puts the values back and the panel's widgets with them, a second takes
## the filter off, and a redo brings the drag's last value back. The running
## app's half is
## `scenarios/an-attached-filter-s-slider-edit-in-tool-options-is-an-undo-step.json`.
##
## The suite brings a filter of its own, for the reason `test_filter_panel.gd`
## gives.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const KNOB := &"s17_suite.knob"
const DIAL := &"s17_suite.dial"

## Longer than the 800 ms Godot's `UndoRedo` folds a step into its namesake
## within.
const PAST_THE_FOLD_MS := 850

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _layers: LayersDocker
var _options: ToolOptionsDocker
var _registry: SaFilterRegistry
var _record: SaAttachedFilter


## A filter with one number, the shape `test_filter_panel.gd` brings.
class Knob:
    extends SaFilter

    var amount: SaSlider

    func title() -> String:
        return "Knob"

    func build(ui: SaDialog) -> void:
        ui.title("Knob")
        ui.preview()
        amount = ui.slider("Amount", -100, 100, 0)
        ui.apply_cancel()

    func parameters() -> Dictionary:
        return {"amount": float(amount.value)}

    func set_parameters(values: Dictionary) -> void:
        if values.has("amount"):
            amount.value = values["amount"]

    func run(_ctx: SaFilterContext) -> void:
        pass


## A filter shaped the way the adjust filters are: its number lives in the
## filter's store and a control of its own draws it, in a box, so the page has
## no value to push into it. `SaPage.refresh` leaves such a row where it was,
## which is why the panel draws its rows again on an undo.
class Dial:
    extends SaFilter

    func id() -> StringName:
        return &"dial"

    func title() -> String:
        return "Dial"

    func build(ui: SaDialog) -> void:
        ui.title("Dial")
        ui.parameter(&"amount", 0.0, -100.0, 100.0)
        ui.custom("Amount", _make_slider).named(&"amount")

    func _make_slider(rerun: Callable) -> Control:
        var box := HBoxContainer.new()
        var slider := FactorSlider.new()
        slider.name = "DialSlider"
        slider.min_value = -100.0
        slider.max_value = 100.0
        slider.value = float(parameter(&"amount"))
        slider.value_changed.connect(
            func(moved: float) -> void:
                write_parameter(&"amount", moved)
                rerun.call()
        )
        box.add_child(slider)
        return box

    func run(_ctx: SaFilterContext) -> void:
        pass


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _registry = SaFilterRegistry.new()
    _registry.register(Knob.new(), &"s17_suite")
    _registry.register(Dial.new(), &"s17_suite")
    _record = SaFilterOps.new(_doc).attach(_doc.active_layer, KNOB, {"amount": 21.0})
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _options = ToolOptionsDocker.new()
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    _layers.filter_registry = _registry
    _layers.tool_options = _options
    # Neither docker is in a tree, so the pick is wired by hand, the way
    # `test_filter_panel.gd` wires it.
    _layers.item_list.filter_selected.connect(_layers._on_filter_selected)
    _layers.sync_layer_list()
    # The compositor's stand-in. In the running app the redraw a step makes
    # evaluates the record through the registry's one instance before
    # `document_changed` reaches the panel, so the instance already holds the
    # record's values when the panel asks. Connected before the pick, so it
    # runs first, which is the order the app has. The first run of the
    # scenario showed a panel that compared with the instance and kept -53.
    _doc.document_changed.connect(_evaluate)
    _layers.item_list.picked.pick_filter(_record)


func after_each() -> void:
    _layers.free()
    _options.free()
    _canvas.free()
    _easel.free()
    _registry = null


## What the chain does to the shared instance when it evaluates a record.
func _evaluate() -> void:
    for record: SaAttachedFilter in _doc.active_layer.filters:
        _registry.get_filter(record.key).set_parameters(record.parameters)


func _panel() -> SaFilterPanel:
    return _options._filter_panel as SaFilterPanel


## Moves the panel's slider to *amount* and lets the deferred rerun land, which
## is one frame of a drag in the running app. The control is moved and its
## signal raised, the way `SaFilterEditWindow._drive` moves one, because the
## row's `drive` writes a `CUSTOM` row's value and leaves its control where it
## was, and the control is what a slider that follows an undo has to move.
func _move(amount: float) -> void:
    var slider := _panel().dialog.row(&"amount").control as FactorSlider
    slider.value = amount
    slider.value_changed.emit(slider.value)
    _panel().dialog.flush_rerun()


## What the panel's slider shows, which is the control and not the row. A
## `FactorSlider` is no `Range`, so the row's `reads` has no answer for it.
func _shown() -> float:
    return (_panel().dialog.row(&"amount").control as FactorSlider).value


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


func test_a_drag_in_several_moves_is_one_edit_filter_step() -> void:
    var steps := _steps()
    for amount: float in [10.0, -20.0, -40.0, -53.0]:
        _move(amount)
    assert_eq(_record.parameters, {"amount": -53.0}, "The record holds where the drag ended")
    assert_eq(_panel().writes, 4, "Every settled move is a write")
    assert_eq(_steps(), steps + 1, "and the four writes are one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Edit Filter", "named Edit Filter, as the edit window's Apply is")


func test_one_undo_puts_the_slider_and_the_record_back_and_keeps_the_filter() -> void:
    for amount: float in [10.0, -20.0, -53.0]:
        _move(amount)
    assert_true(_doc.undo(), "The drag undoes")
    assert_eq(_record.parameters, {"amount": 21.0}, "One undo puts the value the drag started from back")
    assert_eq(_shown(), 21.0, "and the panel's slider follows it")
    assert_true(_doc.active_layer.filters.has(_record), "The filter is still attached")
    assert_eq(_panel().record, _record, "and its panel is still up")

    assert_true(_doc.undo(), "A second undo")
    assert_false(_doc.active_layer.filters.has(_record), "takes the filter off")


func test_redo_brings_the_drags_last_value_back() -> void:
    for amount: float in [10.0, -53.0]:
        _move(amount)
    _doc.undo()
    assert_true(_doc.redo(), "The drag redoes")
    assert_eq(_record.parameters, {"amount": -53.0}, "Redo puts the drag's last value back")
    assert_eq(_shown(), -53.0, "and the slider with it")
    assert_eq(_panel().writes, 2, "Following the record is not a write of the panel's")


func test_an_edit_after_other_work_is_a_step_of_its_own() -> void:
    var steps := _steps()
    _move(-53.0)
    SaFilterOps.new(_doc).set_enabled(_record, false)
    _move(0.0)
    assert_eq(_steps(), steps + 3, "A step between two edits keeps them apart")
    _doc.undo()
    assert_eq(_record.parameters, {"amount": -53.0}, "and the later edit undoes alone")
    assert_eq(_shown(), -53.0, "with the slider")


func test_an_edit_after_an_undo_starts_a_new_step() -> void:
    _move(-53.0)
    _doc.undo()
    var steps := _steps()
    _move(5.0)
    assert_false(_doc.undo_redo.has_redo(), "The new edit takes the undone step's place")
    assert_eq(_steps(), steps, "as one step of its own, since the step it would fold into is gone")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Edit Filter", "named Edit Filter")
    _doc.undo()
    assert_eq(_record.parameters, {"amount": 21.0}, "whose undo is the value the slider was put back to")


## Godot folds a step into its namesake only within 800 ms of it, which is
## what `SaFilterOps.set_parameters` says, so a drag held still longer than
## that is two steps. Pinned here so the sentence and the engine cannot part.
func test_a_drag_held_still_past_the_fold_window_is_two_steps() -> void:
    var steps := _steps()
    _move(-20.0)
    OS.delay_msec(PAST_THE_FOLD_MS)
    _move(-53.0)
    assert_eq(_steps(), steps + 2, "Two steps, the engine's window being 800 ms")


func test_a_new_panel_does_not_fold_into_the_last_ones_step() -> void:
    var second := SaFilterOps.new(_doc).attach(_doc.active_layer, KNOB, {"amount": 1.0})
    _move(-53.0)
    _layers.item_list.picked.pick_filter(second)
    var steps := _steps()
    _move(2.0)
    assert_eq(_steps(), steps + 1, "Another record's first write is a step of its own")
    _doc.undo()
    assert_eq(second.parameters, {"amount": 1.0}, "whose undo touches that record")
    assert_eq(_record.parameters, {"amount": -53.0}, "and leaves the first as it was")


func test_a_rerun_that_changed_nothing_makes_no_step() -> void:
    var steps := _steps()
    _panel().dialog.request_rerun()
    _panel().dialog.flush_rerun()
    assert_eq(_steps(), steps, "No change, no step")
    assert_eq(_panel().writes, 0, "and no write")


func test_a_slider_the_page_cannot_push_follows_the_undo_too() -> void:
    var dial := SaFilterOps.new(_doc).attach(_doc.active_layer, DIAL, {"amount": 21.0})
    _layers.item_list.picked.pick_filter(dial)
    var slider := _panel().find_child("DialSlider", true, false) as FactorSlider
    assert_eq(slider.value, 21.0, "The module's own slider is drawn at the record's value")
    for amount: float in [-20.0, -53.0]:
        slider.value = amount
        slider.value_changed.emit(slider.value)
        _panel().dialog.flush_rerun()
    assert_eq(dial.parameters["amount"], -53.0, "The drag wrote the record")
    assert_true(_panel().find_child("DialSlider", true, false) == slider, "and the panel's own writes drew nothing again")
    _doc.undo()
    assert_eq(dial.parameters["amount"], 21.0, "One undo puts 21 back")
    slider = _panel().find_child("DialSlider", true, false) as FactorSlider
    assert_eq(slider.value, 21.0, "and the slider drawn again reads it")
