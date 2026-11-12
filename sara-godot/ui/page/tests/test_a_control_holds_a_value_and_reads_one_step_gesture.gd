## A control holds a value and reads one step gesture.
##
## Two halves. [SaStep] turns a wheel notch, a pan past its threshold and an
## arrow key into the same signed step, and keeps the fraction a pan or a smooth
## wheel leaves for the next event. [SaValueControl] is the base class of a
## module's own control, and one on it changes its value, says so once, is
## printed by the dump and is moved by a scenario with no method of its own:
## the knob below is the bare base class.
##
## Offscreen and windowless, for the reason `test_filter_dialog.gd` gives: a
## `Window` added to the tree maps a real OS window and hangs the runner. The
## dialog's rows and the step that drives them are reachable without one.
extends "res://tests/test_framework.gd"


## A filter whose one control is the bare base class, on a row named after the
## parameter it holds, which is the whole of what a module writes to bind one.
class KnobFilter:
    extends SaFilter

    func title() -> String:
        return "Knob"

    func build(ui: SaDialog) -> void:
        ui.parameter(&"turn", 0.0, -10.0, 10.0)
        ui.custom("Knob", _make_knob).named(&"turn")

    func _make_knob(_rerun: Callable) -> Control:
        return SaValueControl.new(float(parameter(&"turn")), -10.0, 10.0, 2.0)

    func run(_ctx: SaFilterContext) -> void:
        pass


func _wheel(index: MouseButton, factor: float = 1.0) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = index
    event.pressed = true
    event.factor = factor
    return event


## A pan of *notches*, sent the way a compositor sends it, as
## [constant SaStep.PAN_PER_NOTCH] of delta for every notch.
func _pan(notches: Vector2) -> InputEventPanGesture:
    var event := InputEventPanGesture.new()
    event.delta = notches * SaStep.PAN_PER_NOTCH
    return event


func _key(code: Key, pressed: bool = true) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = pressed
    return event


func test_a_wheel_notch_a_pan_past_its_threshold_and_an_arrow_key_give_the_same_step() -> void:
    assert_eq(SaStep.new().read(_wheel(MOUSE_BUTTON_WHEEL_UP)), 1, "A wheel notch up is one step")
    assert_eq(SaStep.new().read(_pan(Vector2(0.0, -1.0))), 1, "a pan of one notch up is the same step")
    assert_eq(SaStep.new().read(_key(KEY_UP)), 1, "and so is the Up arrow")
    assert_eq(SaStep.new().read(_key(KEY_RIGHT)), 1, "and the Right arrow")
    assert_eq(SaStep.new().read(_wheel(MOUSE_BUTTON_WHEEL_RIGHT)), 1, "and a notch to the right")
    assert_eq(SaStep.new().read(_wheel(MOUSE_BUTTON_WHEEL_DOWN)), -1, "Down on the wheel is a step back")
    assert_eq(SaStep.new().read(_pan(Vector2(0.0, 1.0))), -1, "and down on a pan")
    assert_eq(SaStep.new().read(_key(KEY_DOWN)), -1, "and the Down arrow")
    assert_eq(SaStep.new().read(_key(KEY_LEFT)), -1, "and the Left arrow")


func test_a_pan_short_of_its_threshold_waits_for_the_rest() -> void:
    var steps := SaStep.new()
    assert_eq(steps.read(_pan(Vector2(0.0, -0.6))), 0, "Six tenths of a notch is no step yet")
    assert_eq(steps.read(_pan(Vector2(0.0, -0.6))), 1, "and the next six tenths make one")
    assert_eq(steps.read(_wheel(MOUSE_BUTTON_WHEEL_UP, 0.5)), 0, "A smooth wheel's half notch is carried too")
    assert_eq(steps.read(_wheel(MOUSE_BUTTON_WHEEL_UP, 0.5)), 1, "and two of them are a step")
    assert_true(SaStep.reads(_wheel(MOUSE_BUTTON_WHEEL_UP, 0.1)), "A fraction is still a gesture the control takes")


func test_what_is_not_a_step_reads_as_none() -> void:
    var release := _wheel(MOUSE_BUTTON_WHEEL_UP)
    release.pressed = false
    assert_eq(SaStep.new().read(release), 0, "A wheel's release is no second step")
    assert_false(SaStep.reads(release), "and no gesture at all")
    assert_eq(SaStep.new().read(_key(KEY_UP, false)), 0, "Nor is an arrow's release")
    var chord := _key(KEY_UP)
    chord.ctrl_pressed = true
    assert_eq(SaStep.new().read(chord), 0, "and an arrow under Ctrl is a shortcut's")
    assert_false(SaStep.reads(_key(KEY_A)), "A letter is not a step")
    assert_eq(SaStep.notches(_wheel(MOUSE_BUTTON_LEFT)), Vector2.ZERO, "and a click moves nothing")


func test_notches_are_along_the_screen_the_way_a_page_scrolls() -> void:
    assert_eq(SaStep.notches(_wheel(MOUSE_BUTTON_WHEEL_DOWN)), Vector2(0.0, 1.0), "A notch down scrolls onwards")
    assert_eq(
        SaStep.notches(_wheel(MOUSE_BUTTON_WHEEL_LEFT, 0.25)), Vector2(-0.25, 0.0), "A fraction sideways keeps its fraction"
    )
    assert_eq(SaStep.notches(_pan(Vector2(0.5, -2.0))), Vector2(0.5, -2.0), "and a pan is its delta in notches")


func test_a_control_on_the_base_class_changes_its_value_and_emits_once() -> void:
    var knob := SaValueControl.new(0.0, -10.0, 10.0, 2.0)
    var heard: Array[float] = []
    knob.value_changed.connect(func(moved: float) -> void: heard.append(moved))
    knob._gui_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
    assert_almost_eq(knob.value, 2.0, 0.001, "A notch moves the value one step")
    assert_eq(heard.size(), 1, "and says so once")
    knob._gui_input(_pan(Vector2(0.0, -1.0)))
    knob._gui_input(_key(KEY_RIGHT))
    assert_almost_eq(knob.value, 6.0, 0.001, "A pan and an arrow move it as far as a notch")
    assert_eq(heard.size(), 3, "each once")
    knob.move_to(6.0)
    assert_eq(heard.size(), 3, "A move to where it stands says nothing")
    knob.move_to(99.0)
    assert_almost_eq(knob.value, 10.0, 0.001, "A move past the range is held to it")
    knob._gui_input(_key(KEY_UP))
    assert_eq(heard.size(), 4, "and a step past the end is no change to say")
    knob.show_value(-4.0)
    assert_almost_eq(knob.value, -4.0, 0.001, "A value shown from outside is held")
    assert_eq(heard.size(), 4, "without a word")
    knob.free()


func test_the_control_is_bound_printed_and_moved_by_a_scenario_with_no_hook_of_its_own() -> void:
    var host := VBoxContainer.new()
    var filter := KnobFilter.new()
    var dialog := SaDialog.for_filter(filter)
    dialog.realize(host)
    var row := dialog.row(&"turn")
    assert_true(row.control is SaValueControl, "The knob is the row's control")
    var knob := row.control as SaValueControl
    assert_eq(knob.get_script(), SaValueControl, "and the knob is the bare base class")

    var said := SaFilterDialogWindow._drive(row, {"widget": "turn", "value": 4})
    assert_true(said.contains("holds 4"), "A scenario's value is answered by the base class")
    assert_almost_eq(float(filter.parameter(&"turn")), 4.0, 0.001, "and the filter keeps it with no copy")
    assert_true(dialog.rerun_pending, "The move asks for a rerun")
    dialog.flush_rerun()
    assert_eq(dialog.runs, 1, "and one run follows")

    SaFilterDialogWindow._drive(row, {"widget": "turn", "key": "right", "times": 2})
    assert_almost_eq(float(filter.parameter(&"turn")), 8.0, 0.001, "Two arrow presses from a scenario are two steps")
    SaFilterDialogWindow._drive(row, {"widget": "turn", "pan": -SaStep.PAN_PER_NOTCH})
    assert_almost_eq(float(filter.parameter(&"turn")), 10.0, 0.001, "and a pan up one more")
    SaFilterDialogWindow._drive(row, {"widget": "turn", "wheel": -3})
    assert_almost_eq(float(filter.parameter(&"turn")), 4.0, 0.001, "and three notches down three back")

    var printed := {}
    for block: Dictionary in dialog.describe()["sections"] as Array:
        for described: Dictionary in block["rows"] as Array:
            if described["key"] == "turn":
                printed = described
    assert_almost_eq(float(printed.get("value", 0.0)), 4.0, 0.001, "The dump prints the value the row holds")
    assert_eq(String(printed.get("bound_to", "")).get_slice(".", 1), "turn", "bound to the filter's parameter")
    assert_eq(printed.get("control", {}), {"value": 4.0, "low": -10.0, "high": 10.0, "step": 2.0}, "and the control's own line")

    filter.store.take({"turn": -6.0})
    assert_almost_eq(knob.value, -6.0, 0.001, "A record written behind the dialog's back moves the knob")
    host.free()
