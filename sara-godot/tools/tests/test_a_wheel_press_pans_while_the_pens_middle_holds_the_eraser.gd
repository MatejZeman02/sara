## The mouse's wheel press has a binding of its own.
##
## A painter bound the pen's Middle row to Eraser while held and the wheel
## then erased too, because one row answered every middle press. Preferences >
## Tablet now has a Mouse middle button row beside it, Pan by default, and a
## middle press follows the pen's row when a pen made it and the mouse's
## otherwise. Two shapes say a pen made it. Wayland's is a left press after a
## hover in the air, which `SaHeldButtons.UpperBarrel` hands on as a middle
## press it marks as the pen's. Where the driver sends the upper button as a
## middle press itself, as Wacom's Middle click does on Windows, the pen's
## hovers before it are what tell the two apart, and `SaCursorPolicy` is where
## the cursor overlay keeps what they said, so each case below feeds it what
## the overlay does with every motion in a window.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

## The paint the eraser is given to take off.
const PAINT := Color(0.8, 0.2, 0.1, 1.0)
## What an erased texel's alpha is under, at the stroke's pressure.
const ERASED := 0.9
## The row the strokes run along.
const ROW_Y := 64.0
## A pen's tilt, which no mouse reports.
const TILT := Vector2(0.13, -0.08)
## The pressure the tip touches at.
const TOUCH := 0.6

var _stored: Dictionary = {}
var _stored_mouse_middle: String = ""
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _last_at: Vector2 = Vector2.ZERO


func before_each() -> void:
    _stored = SaSettings.pen_buttons.duplicate()
    _stored_mouse_middle = SaSettings.mouse_middle
    SaCursorPolicy.forget_pointer_device()


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    SaSettings.pen_buttons = _stored
    SaSettings.mouse_middle = _stored_mouse_middle
    if _machine != null or _surface != null:
        Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null


## The pen's middle on Eraser while held and the mouse's on Pan. A wheel press that follows hovers of a pen, then ten and more
## of a mouse, pans the view and erases nothing.
func test_a_wheel_press_after_mouse_motions_pans_and_erases_nothing() -> void:
    _set_up(false, SaSettingsPenButtons.ERASER, SaSettingsPenButtons.PAN)
    _paint_the_layer()
    var steps := _steps()
    for x: int in range(20, 40, 4):
        _overlay(_machine, _motion(Vector2(x, ROW_Y), 0.0, 0, TILT))
    for x: int in range(40, 100, 4):
        _overlay(_machine, _motion(Vector2(x, ROW_Y), 0.0, 0, Vector2.ZERO))
    var before := _surface.view.get_pan()
    _machine.handle_input(_middle(true, Vector2(100, ROW_Y)))
    assert_eq(_machine.active_tool_name, &"brush", "The wheel press swaps no eraser in")
    for x: int in range(104, 140, 4):
        _overlay(_machine, _motion(Vector2(x, ROW_Y), 0.0, MOUSE_BUTTON_MASK_MIDDLE, Vector2.ZERO))
    _machine.handle_input(_middle(false, Vector2(140, ROW_Y)))
    assert_true(_surface.view.get_pan() != before, "and its drag pans the view")
    assert_almost_eq(_alpha_at(Vector2(64, ROW_Y)), 1.0, 0.001, "while nothing along the row is erased")
    assert_eq(_steps(), steps, "and no undo step is added")
    assert_eq(_machine.active_tool_name, &"brush", "The release leaves the brush in hand")


## A mouse and no pen anywhere, which is where a wheel press is plainest.
func test_a_wheel_press_with_no_pen_seen_follows_the_mouse_row() -> void:
    _set_up(false, SaSettingsPenButtons.ERASER, SaSettingsPenButtons.EYEDROPPER)
    _overlay(_machine, _motion(Vector2(40, ROW_Y), 0.0, 0, Vector2.ZERO))
    _machine.handle_input(_middle(true, Vector2(40, ROW_Y)))
    assert_eq(_machine.active_tool_name, &"eyedropper", "The wheel press holds what the mouse's row says")
    _machine.handle_input(_middle(false, Vector2(40, ROW_Y)))
    assert_eq(_machine.active_tool_name, &"brush", "and the release hands the brush back")


## The upper button as Wayland sends it: a hover with the pen in the air, the
## left press, and a hover at no pressure with it held. It is the pen's whatever
## the overlay has heard, so the mouse's row never sees it, and with the eraser
## on it the eraser is held and the view stays where it was.
func test_the_upper_button_as_wayland_sends_it_holds_the_eraser_and_the_view_stays() -> void:
    _set_up(true, SaSettingsPenButtons.ERASER, SaSettingsPenButtons.PAN)
    _paint_the_layer()
    var before := _surface.view.get_pan()
    _machine.handle_input(_motion(Vector2(24, ROW_Y), 0.0, 0, TILT))
    _machine.handle_input(_left(true, Vector2(24, ROW_Y), MOUSE_BUTTON_MASK_LEFT))
    _machine.handle_input(_motion(Vector2(28, ROW_Y), 0.0, MOUSE_BUTTON_MASK_LEFT, TILT))
    assert_eq(_machine.active_tool_name, &"eraser", "The upper in the air holds the eraser")
    for x: int in range(32, 104, 4):
        _machine.handle_input(_motion(Vector2(x, ROW_Y), 0.0, MOUSE_BUTTON_MASK_LEFT, TILT))
    assert_eq(_surface.view.get_pan(), before, "and the view is still")
    assert_almost_eq(_alpha_at(Vector2(64, ROW_Y)), 1.0, 0.001, "with nothing erased by a hover")
    _machine.handle_input(_left(false, Vector2(104, ROW_Y), 0))
    assert_eq(_machine.active_tool_name, &"brush", "The release hands the brush back")


## The upper button as a driver that sends it as a middle press itself does,
## Windows' Middle click: the pen hovers first, so the press is the pen's and
## follows the pen's row, and the view stays where it was.
func test_a_middle_press_after_a_pen_s_hovers_follows_the_pen_s_row() -> void:
    _set_up(false, SaSettingsPenButtons.ERASER, SaSettingsPenButtons.PAN)
    _paint_the_layer()
    var before := _surface.view.get_pan()
    for x: int in range(20, 60, 4):
        _overlay(_machine, _motion(Vector2(x, ROW_Y), 0.0, 0, TILT))
    _machine.handle_input(_middle(true, Vector2(60, ROW_Y)))
    assert_eq(_machine.active_tool_name, &"eraser", "The pen's middle press holds the eraser")
    for x: int in range(64, 104, 4):
        _overlay(_machine, _motion(Vector2(x, ROW_Y), TOUCH, MOUSE_BUTTON_MASK_MIDDLE, TILT))
    assert_eq(_surface.view.get_pan(), before, "and the view is still")
    _machine.handle_input(_middle(false, Vector2(104, ROW_Y)))
    # Wash gathers the eraser's coverage in the stroke buffer and lands it at
    # the commit, which the release is, so the layer reads painted until then.
    assert_true(_alpha_at(Vector2(80, ROW_Y)) < ERASED, "while the tip's touch under it erases")
    assert_eq(_machine.active_tool_name, &"brush", "The release hands the brush back")


## Each row is the other's way round as well: the pen's on Pan and the mouse's
## on Eraser, and the release follows the row its press did even when the
## overlay has changed its mind between them.
func test_the_release_follows_the_row_its_press_did() -> void:
    _set_up(false, SaSettingsPenButtons.PAN, SaSettingsPenButtons.ERASER)
    _overlay(_machine, _motion(Vector2(20, ROW_Y), 0.0, 0, TILT))
    var before := _surface.view.get_pan()
    _machine.handle_input(_middle(true, Vector2(24, ROW_Y)))
    assert_eq(_machine.active_tool_name, &"brush", "A pen's middle press on Pan holds no tool")
    _overlay(_machine, _motion(Vector2(40, ROW_Y), 0.0, MOUSE_BUTTON_MASK_MIDDLE, TILT))
    assert_true(_surface.view.get_pan() != before, "and pans the view")
    SaCursorPolicy.forget_pointer_device()
    _machine.handle_input(_middle(false, Vector2(40, ROW_Y)))
    var settled := _surface.view.get_pan()
    _machine.handle_input(_motion(Vector2(60, ROW_Y), 0.0, 0, Vector2.ZERO))
    assert_eq(_surface.view.get_pan(), settled, "The release ends the pan though the pointer is a mouse's by then")
    _machine.handle_input(_middle(true, Vector2(60, ROW_Y)))
    assert_eq(_machine.active_tool_name, &"eraser", "and a wheel press then holds the mouse row's eraser")
    _machine.handle_input(_middle(false, Vector2(60, ROW_Y)))
    assert_eq(_machine.active_tool_name, &"brush", "which the release hands back")


# --- Helpers --------------------------------------------------------------------


## A surface and a machine on the brush, with the pen's Middle row on
## *pen_action* and the mouse's on *mouse_action*, and the upper button told
## from the tip as Wayland does when *wayland* holds.
func _set_up(wayland: bool, pen_action: String, mouse_action: String) -> void:
    _surface = Fixtures.make_surface(Vector2i(128, 128))
    # The built-in blend modes, as `main.gd` wires them. Wash is the brush's
    # default, so an eraser gathers in the stroke buffer and lands
    # under Erase at the commit, and a compositor without the registry would
    # resolve that mode to Normal and leave the paint standing.
    _surface.easel.compositor.set_registry(Fixtures.make_registries(_surface).blend_modes)
    _machine = Fixtures.make_bound_machine(_surface, wayland)
    _machine.set_active_tool(&"brush")
    var table := SaSettings.pen_buttons.duplicate()
    table["middle"] = pen_action
    SaSettings.pen_buttons = table
    SaSettings.mouse_middle = mouse_action


## What the cursor overlay does with every motion in a window, and then the
## machine hearing it.
func _overlay(machine: ToolMachine, motion: InputEventMouseMotion) -> void:
    SaCursorPolicy.note_pointer_device(motion)
    machine.handle_input(motion)


## The active layer filled with opaque paint, and the eraser wide enough that
## the row's middle is well inside its stroke.
func _paint_the_layer() -> void:
    _surface.get_document().fill_layer(PAINT)
    assert_almost_eq(_alpha_at(Vector2(64, ROW_Y)), 1.0, 0.001, "The layer starts painted")
    var settings: Resource = _machine.get_tool(&"eraser").get("settings")
    settings.set("radius", 0.08)


func _steps() -> int:
    var history := _surface.get_document().history
    return history.step_count() if history != null else -1


func _alpha_at(at: Vector2) -> float:
    var reader := StateEyedropperScript.new()
    reader.surface = _surface
    reader.sample_from = StateEyedropperScript.SampleFrom.LAYER
    return reader.pick_color_at_pos(at).a


## A motion at *at*, where the fake view puts the pointer too, since a tool
## reads its position from the view, and with the `relative` a pan follows.
func _motion(at: Vector2, pressure: float, mask: int, tilt: Vector2) -> InputEventMouseMotion:
    (_surface.view as Fixtures.FakeView).mouse_position = at
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.relative = at - _last_at
    _last_at = at
    event.pressure = pressure
    event.tilt = tilt
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
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.global_position = at
    event.button_mask = mask
    return event
