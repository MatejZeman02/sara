## Enter in a filter dialog's number field takes the number and applies nothing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Editing a value inside a slider in a filter dialog and pressing Enter only
## saves the edited value and sets the slider to it. A number taken with Enter
## presses the dialog's default in every other dialog, and both filter windows
## say their fields do not answer, as the Brush Editor does, so Gaussian Blur's
## radius typed and entered neither applies the blur nor closes the window.
## Every other dialog keeps its answer, which
## `ui/dialogs/tests/test_enter_presses_the_button_the_outline_is_on.gd` holds.
##
## Enter goes in through `push_input` on the window, press and release, the way
## `test_enter_presses_the_button_the_outline_is_on.gd` sends it, with the window embedded so no OS window maps. The
## dialog's answer and the rerun are both deferred calls and a suite has no
## frame, so each is asked for by hand in the order the frame would run them,
## the answer first because the field's focus queued it first. The running app
## is `scenarios/enter-in-a-filter-dialog-s-number-field-takes-the-number-and-applies-nothing.json`.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
## Opens real windows, and only a run with a RenderingDevice has one.
const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const OWNER := &"sara-base-modules"

## The radius typed, away from Gaussian Blur's default of 10.
const TYPED := 23.0

## The layer's paint, so an Apply would have something to write and so a step
## to make. On an empty layer the base's Apply wrote nothing, and the history
## read the same either way.
const PAINT := Color(0.8, 0.3, 0.2, 1.0)

var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _registry: SaFilterRegistry = null
var _host: Node = null
var _was_embedding: bool = true
var _key: StringName = &""


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U16TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(Vector2i(256, 256))
    _easel.document.fill_layer(PAINT, _easel.document.active_layer)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _registry = SaFilterRegistry.new()
    var blur := SaGaussianBlurFilter.new()
    _registry.register(blur, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, blur)
    _easel.compositor.filter_chain.registry = _registry


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    Teardown.free_nodes([_canvas, _easel])
    _canvas = null
    _easel = null
    _registry = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


## One edge of Enter, spelled with both keycode fields as a keyboard sends it.
static func _enter(pressed: bool) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_ENTER
    key.physical_keycode = KEY_ENTER
    key.pressed = pressed
    return key


## Opens *slider*'s text box, types *typed* into it and taps Enter on *window*,
## which is what a painter's double click, digits and Return come to.
func _type_and_enter(window: SaDialogWindow, slider: FactorSlider, typed: float) -> void:
    slider.start_editing()
    assert_true(slider._line_edit.has_focus(), "the radius field holds the keyboard")
    slider._line_edit.text = str(int(typed))
    window.push_input(_enter(true))
    window.push_input(_enter(false))


## The two deferred calls Enter left, in the order the frame runs them. The
## rerun is asked for only while a page is up, because an answer that applied
## closed the window and let its page go, which is the failure this suite is for.
func _let_the_frame_land(window: SaDialogWindow) -> void:
    window.answer_for_a_number_field()
    var dialog := window.get("dialog") as SaDialog
    if dialog != null:
        dialog.flush_rerun()


func _radius_slider(dialog: SaDialog) -> FactorSlider:
    var radius := dialog.row(&"radius")
    return radius.control as FactorSlider if radius != null else null


func test_enter_in_the_filter_dialogs_radius_takes_it_and_runs_the_preview_on_it() -> void:
    var window := SaFilterDialogWindow.new()
    window.target_canvas = _canvas
    window.watch(_registry)
    _host.add_child(window)
    window.open_filter(_key)
    var history := _easel.document.undo_redo
    var steps := history.get_history_count()
    var runs := window.runs
    var blur := window.filter
    var slider := _radius_slider(window.dialog)
    assert_not_null(slider, "Gaussian Blur's first row is its radius slider")
    if slider == null:
        return
    assert_false(window.number_field_answers, "the Filter dialog says its fields take a number and nothing more")

    _type_and_enter(window, slider, TYPED)
    _let_the_frame_land(window)

    assert_true(window.visible, "the dialog is still open")
    assert_not_null(window.dialog, "on the filter it opened on")
    assert_false(slider._line_edit.visible, "the slider has left its text box")
    assert_almost_eq(slider.value, TYPED, 1e-6, "and stands at the typed radius")
    assert_eq(window.runs, runs + 1, "the preview ran once more")
    assert_almost_eq(float(blur.parameter(&"radius")), TYPED, 1e-6, "on the typed radius")
    assert_eq(history.get_history_count(), steps, "and no history step was made, so nothing was applied")
    window.cancel_filter()


func test_enter_in_the_edit_windows_radius_takes_it_and_writes_it_onto_the_record() -> void:
    var document := _easel.document
    var record := SaFilterOps.new(document).attach(document.active_layer, _key, {})
    var history := document.undo_redo
    var steps := history.get_history_count()
    var window := SaFilterEditWindow.new()
    window.watch(_registry)
    _host.add_child(window)
    window.open(record, document)
    var slider := _radius_slider(window.dialog)
    assert_not_null(slider, "the attached blur's window draws its radius slider")
    if slider == null:
        return
    assert_false(window.number_field_answers, "the filter edit window says its fields take a number and nothing more")

    _type_and_enter(window, slider, TYPED)
    _let_the_frame_land(window)

    assert_true(window.visible, "the window is still open")
    assert_eq(window.record, record, "on the record it opened on")
    assert_false(slider._line_edit.visible, "the slider has left its text box")
    assert_almost_eq(slider.value, TYPED, 1e-6, "and stands at the typed radius")
    assert_eq(window.writes, 1, "the preview, which is the record's own write, ran once")
    assert_almost_eq(float(record.parameters.get("radius", 0.0)), TYPED, 1e-6, "on the typed radius")
    assert_eq(history.get_history_count(), steps, "and no history step was made, so nothing was applied")
    window.cancel()
