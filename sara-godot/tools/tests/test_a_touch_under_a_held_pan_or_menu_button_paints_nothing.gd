## A touch while a pen button bound to Pan or Context menu is held paints
## nothing.
##
## With Wacom's upper button on Middle click under WinTab and the Middle row on
## Pan, a painter reported that "it pans in both cases, but when touching it
## also paints a dot", and on Context menu a touch painted a dot as if no button
## were held. The driver sends the button as a middle press and the tip as a
## left press under it, and the left press reached the brush as a stroke of one
## dab. Here the pen hovers first, as it does before a Middle click, so the
## press follows the pen's row.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

## The row the touches land on.
const ROW_Y := 64.0
## A pen's tilt, which no mouse reports.
const TILT := Vector2(0.13, -0.08)
## The pressure the tip touches at.
const TOUCH := 0.6
## The touches made under one hold, as the feature requires.
const TOUCHES := 5

var _stored: Dictionary = {}
var _stored_mouse_middle: String = ""
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _menus: Array[Vector2] = []
var _last_at: Vector2 = Vector2.ZERO


func before_each() -> void:
    _stored = SaSettings.pen_buttons.duplicate()
    _stored_mouse_middle = SaSettings.mouse_middle
    SaCursorPolicy.forget_pointer_device()
    _menus = []


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    SaSettings.pen_buttons = _stored
    SaSettings.mouse_middle = _stored_mouse_middle
    if _machine != null or _surface != null:
        Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null


func test_touches_under_a_held_pan_button_paint_nothing() -> void:
    _set_up(SaSettingsPenButtons.PAN, &"brush")
    var steps := _steps()
    _hover_then_hold_the_middle()
    _touch_five_times(MOUSE_BUTTON_MASK_MIDDLE)
    _machine.handle_input(_middle(false, Vector2(120, ROW_Y)))
    assert_almost_eq(_alpha_along_the_row(), 0.0, 0.001, "No touch under the held Pan button painted")
    assert_eq(_steps(), steps, "and no undo step is added")


func test_touches_under_a_held_menu_button_paint_nothing() -> void:
    _set_up(SaSettingsPenButtons.CONTEXT_MENU, &"brush")
    var steps := _steps()
    _hover_then_hold_the_middle()
    _touch_five_times(MOUSE_BUTTON_MASK_MIDDLE)
    _machine.handle_input(_middle(false, Vector2(120, ROW_Y)))
    assert_almost_eq(_alpha_along_the_row(), 0.0, 0.001, "No touch under the held Context menu button painted")
    assert_eq(_steps(), steps, "and no undo step is added")


## Under the Marquee, a tool that keeps its menu, the press asks for one.
func test_the_menu_button_under_the_marquee_asks_for_the_menu() -> void:
    _set_up(SaSettingsPenButtons.CONTEXT_MENU, &"marquee")
    _hover_then_hold_the_middle()
    assert_eq(_menus.size(), 1, "The press asked for the menu")
    _machine.handle_input(_middle(false, Vector2(60, ROW_Y)))


## A menu that took the button's release leaves the next touch its own: the
## press's mask says no button is held, so the brush paints.
func test_a_touch_after_a_release_the_machine_never_saw_paints() -> void:
    _set_up(SaSettingsPenButtons.CONTEXT_MENU, &"brush")
    _hover_then_hold_the_middle()
    _touch_five_times(0)
    assert_true(_alpha_along_the_row() > 0.0, "The touches with no button held painted")


## The control: no button held, and a touch paints as it always did.
func test_a_touch_with_no_button_held_still_paints() -> void:
    _set_up(SaSettingsPenButtons.PAN, &"brush")
    for x: int in range(20, 60, 4):
        _overlay(_motion(Vector2(x, ROW_Y), 0.0, 0))
    _touch_five_times(0)
    assert_true(_alpha_along_the_row() > 0.0, "A plain touch painted")


# --- Helpers --------------------------------------------------------------------


## A surface and a machine on *tool*, with the pen's Middle row and the mouse's
## on *action*, so the row holds whichever the press is taken for.
func _set_up(action: String, tool: StringName) -> void:
    _surface = Fixtures.make_surface(Vector2i(128, 128))
    _machine = Fixtures.make_bound_machine(_surface, false)
    _machine.set_active_tool(tool)
    _machine.context_menu_requested.connect(func(at: Vector2) -> void: _menus.append(at))
    var table := SaSettings.pen_buttons.duplicate()
    table["middle"] = action
    SaSettings.pen_buttons = table
    SaSettings.mouse_middle = action


## The pen's hovers, then the upper button pressed in the air.
func _hover_then_hold_the_middle() -> void:
    for x: int in range(20, 60, 4):
        _overlay(_motion(Vector2(x, ROW_Y), 0.0, 0))
    _machine.handle_input(_middle(true, Vector2(60, ROW_Y)))


## Five touches along the row, each a press, three motions at the touch's
## pressure and a release, with *held* the other buttons down.
func _touch_five_times(held: int) -> void:
    for i in TOUCHES:
        var x := 64.0 + 10.0 * i
        _machine.handle_input(_left(true, Vector2(x, ROW_Y), MOUSE_BUTTON_MASK_LEFT | held))
        for step in range(1, 4):
            _overlay(_motion(Vector2(x + step, ROW_Y), TOUCH, MOUSE_BUTTON_MASK_LEFT | held))
        _machine.handle_input(_left(false, Vector2(x + 3, ROW_Y), held))


## The most paint along the row the touches landed on.
func _alpha_along_the_row() -> float:
    var reader := StateEyedropperScript.new()
    reader.surface = _surface
    reader.sample_from = StateEyedropperScript.SampleFrom.LAYER
    var most := 0.0
    for i in TOUCHES:
        most = maxf(most, reader.pick_color_at_pos(Vector2(65.0 + 10.0 * i, ROW_Y)).a)
    return most


func _steps() -> int:
    var history := _surface.get_document().history
    return history.step_count() if history != null else -1


## What the cursor overlay does with every motion in a window, and then the
## machine hearing it.
func _overlay(motion: InputEventMouseMotion) -> void:
    SaCursorPolicy.note_pointer_device(motion)
    _machine.handle_input(motion)


func _motion(at: Vector2, pressure: float, mask: int) -> InputEventMouseMotion:
    (_surface.view as Fixtures.FakeView).mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.relative = at - _last_at
    _last_at = at
    event.pressure = pressure
    event.tilt = TILT
    event.button_mask = mask
    return event


func _middle(pressed: bool, at: Vector2) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_MIDDLE
    event.pressed = pressed
    event.position = at
    event.global_position = at
    event.button_mask = MOUSE_BUTTON_MASK_MIDDLE if pressed else 0
    return event


func _left(pressed: bool, at: Vector2, mask: int) -> InputEventMouseButton:
    (_surface.view as Fixtures.FakeView).mouse_position = at
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.global_position = at
    event.button_mask = mask
    return event
