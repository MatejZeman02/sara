## A number a record holds reaches the control the row built, through the panel
## and through the edit window.
##
## The row and the widget are two answers to one number: `SaFilter.set_parameters`
## puts the record's number on the row and `SaPage.push_value` draws the widget
## from it. A `CUSTOM` row was the one the page could not move, so an attached
## filter's slider showed the number the row was declared with, and both editors
## of a record read the same stale number.
##
## The filter here declares 3 and the record holds 7, and the difference between
## the row's answer and the widget's is the defect. What the three base-module
## filters that hold their numbers in a dictionary rather than on their rows owe
## is asserted in their own suites, where their declarations live.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const KNOB := &"d27_suite.knob"
## What the filter's declaration says, which is the number the widget showed
## before the record reached it.
const DECLARED := 3.0
## What the record holds, which is the number the widget has to show.
const HELD := 7.0

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _layers: LayersDocker
var _options: ToolOptionsDocker
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
    _registry.register(Knob.new(), &"d27_suite")
    _record = SaFilterOps.new(_doc).attach(_doc.active_layer, KNOB, {"amount": HELD})
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _options = ToolOptionsDocker.new()
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    _layers.filter_registry = _registry
    _layers.tool_options = _options
    # Neither docker is in a tree, so `_ready` never ran and the pick is wired
    # by hand, the way `test_filter_panel.gd` wires it.
    _layers.item_list.filter_selected.connect(_layers._on_filter_selected)
    _layers.sync_layer_list()
    _window = SaFilterEditWindow.new()
    _window.watch(_registry)


func after_each() -> void:
    _window.free()
    _layers.free()
    _options.free()
    _canvas.free()
    _easel.free()
    _registry = null


## The widget a `ui.slider` row built, which is what a painter reads the number
## off. The control rather than the row is what this suite is about, and
## `SaPageRow.reads` answers null for a `FactorSlider` because it is not a
## `Range`, so the control is asked directly.
func _control(row: SaPageRow) -> FactorSlider:
    return row.custom_control as FactorSlider


func _panel() -> SaFilterPanel:
    return _options._filter_panel as SaFilterPanel


func test_the_panels_control_shows_the_records_number() -> void:
    _layers.item_list.picked.pick_filter(_record)
    var row := _panel().dialog.row(&"amount")
    assert_eq(row.read(), HELD, "The row holds the record's number")
    var control := _control(row)
    assert_not_null(control, "and the widget the row built is the slider the panel draws")
    assert_almost_eq(
        control.value, HELD, 0.001, "which shows the record's number and not the %d it was declared with" % int(DECLARED)
    )


func test_the_windows_control_shows_the_records_number() -> void:
    _window.open(_record, _doc)
    var row := _window.dialog.row(&"amount")
    assert_eq(row.read(), HELD, "The row holds the record's number")
    assert_almost_eq(
        _control(row).value, HELD, 0.001, "and the widget the window opened on shows it rather than the declared default"
    )


## One record after another, because the registry holds one filter instance and
## the second panel rebuilds its widgets: the number a widget shows has to be the
## record the panel is showing and never the one before it.
func test_a_second_record_draws_the_widget_the_second_time() -> void:
    _layers.item_list.picked.pick_filter(_record)
    assert_almost_eq(_control(_panel().dialog.row(&"amount")).value, HELD, 0.001, "The first record is on the widget")
    var second := SaFilterOps.new(_doc).attach(_doc.active_layer, KNOB, {"amount": 1.0})
    _layers.item_list.picked.pick_filter(second)
    var row := _panel().dialog.row(&"amount")
    assert_eq(row.read(), 1.0, "The second record's number is on the row")
    assert_almost_eq(_control(row).value, 1.0, 0.001, "and on the widget, which is not the first record's 7")


## The window's own second open, which is what a double click on another row
## does, and the pair the scenario's fifth step repeats.
func test_the_window_opened_twice_shows_the_record_it_was_opened_on() -> void:
    _window.open(_record, _doc)
    _window.open(_record, _doc)
    var row := _window.dialog.row(&"amount")
    assert_eq(row.read(), HELD, "Reopening on the same record holds its number")
    assert_almost_eq(_control(row).value, HELD, 0.001, "and the widget the second open built shows it")
