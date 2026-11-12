## Under Wayland the upper barrel button is told from the tip with the pen in
## the air and bound as the middle button.
##
## Godot 4.7's Wayland driver turns the code GNOME sends for the upper button
## into the left one, the tip's (godotengine/godot#124067). A virtual pen under
## GNOME's mutter measured the two shapes these cases feed. The upper pressed in
## the air is a left press after a hover at no pressure, more hovers at none
## and a left release. The tip is a motion carrying its pressure and then the
## left press, more pressed motions and the release. The first half reads what
## `SaHeldButtons.UpperBarrel` hands on, the second what the tool machine then
## does with it, which needs the display server to be Wayland because the
## machine asks it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

## What the merged composite is cleared to for the eyedropper to find.
const UNDER_THE_PEN := Color(0.1, 0.6, 0.3, 1.0)
## The paint the eraser is given to take off.
const PAINT := Color(0.8, 0.2, 0.1, 1.0)
## What an erased texel's alpha is under, at the stroke's pressure.
const ERASED := 0.9
## The row the strokes run along, and a point well off it.
const ROW_Y := 64.0
const OFF_THE_ROW := Vector2(64, 16)
## A pen's tilt in the air, which no mouse reports.
const TILT := Vector2(0.13, -0.08)
## The pressure the measured tip touched at.
const TOUCH := 0.6
## A motion's mask as the words a case compares.
const MASKS := {0: "motion none", MOUSE_BUTTON_MASK_LEFT: "motion left", MOUSE_BUTTON_MASK_MIDDLE: "motion middle"}

var _stored: Dictionary = {}
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _picked: Array[Color] = []
## Where the last motion was, which the next one's `relative` is taken from,
## because a pan follows that rather than the position.
var _last_at: Vector2 = Vector2.ZERO


func before_each() -> void:
    _stored = SaSettings.pen_buttons.duplicate()
    _picked.clear()
    EventBus.color_picked.connect(_on_picked)


func after_each() -> void:
    EventBus.color_picked.disconnect(_on_picked)
    SaSettings.pen_buttons = _stored
    if _machine != null or _surface != null:
        Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null


func _on_picked(color: Color) -> void:
    _picked.append(color)


# --- What the upper barrel hands on ---------------------------------------------


## The measured upper in the air: a press after a hover at no pressure, which
## the next hover at none says is the upper's, and it goes on as the middle
## button for its whole length.
func test_a_left_press_followed_by_hovers_at_no_pressure_is_the_middle_button() -> void:
    var upper := SaHeldButtons.new(true).upper
    assert_eq(_kinds(upper.told(_motion(Vector2(40, ROW_Y), 0.0, 0))), ["motion none"], "A hover goes on as it came")
    var press := upper.told(_button(true, Vector2(40, ROW_Y), MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_kinds(press), [], "The left press after it is held back")
    var moved := upper.told(_motion(Vector2(44, ROW_Y), 0.0, MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_kinds(moved), ["middle down", "motion middle"], "and the next hover at none hands it on as the middle press")
    assert_true(upper.down, "with the left button counted as the upper's")
    var again := upper.told(_motion(Vector2(48, ROW_Y), 0.0, MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_kinds(again), ["motion middle"], "Its hovers carry the middle button and not the left")
    var released := upper.told(_button(false, Vector2(48, ROW_Y), 0))
    assert_eq(_kinds(released), ["middle up"], "and its release is the middle one's")
    assert_false(upper.down, "which lets it go")


## The measured tip: its pressure comes on a motion before its press, so the
## press goes on at once and the stroke opens where it always did.
func test_a_left_press_after_a_motion_with_pressure_is_the_tip_at_once() -> void:
    var upper := SaHeldButtons.new(true).upper
    upper.told(_motion(Vector2(40, ROW_Y), 0.0, 0))
    assert_eq(_kinds(upper.told(_motion(Vector2(40, ROW_Y), TOUCH, 0))), ["motion none"], "The touch's motion goes on")
    var press := upper.told(_button(true, Vector2(40, ROW_Y), MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_kinds(press), ["left down"], "and so does the tip's press after it, at once")
    var moved := upper.told(_motion(Vector2(44, ROW_Y), TOUCH, MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_kinds(moved), ["motion left"], "Its motions keep the left button")
    assert_eq(_kinds(upper.told(_button(false, Vector2(44, ROW_Y), 0))), ["left up"], "and so does its release")


## A desktop that sends the tip's pressure after its press: the press is held
## back after the hover, and the first motion with pressure says it was the
## tip's after all, so the stroke opens one motion late rather than not at all.
func test_a_held_press_that_meets_pressure_goes_on_as_the_tip_one_motion_late() -> void:
    var upper := SaHeldButtons.new(true).upper
    upper.told(_motion(Vector2(40, ROW_Y), 0.0, 0))
    assert_eq(_kinds(upper.told(_button(true, Vector2(40, ROW_Y), MOUSE_BUTTON_MASK_LEFT))), [], "The press is held")
    var moved := upper.told(_motion(Vector2(44, ROW_Y), TOUCH, MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_kinds(moved), ["left down", "motion left"], "and the motion with pressure lets it go on before itself")
    assert_false(upper.down, "as the tip's")


## The upper clicked with the pen held still sends no motion between its press
## and its release, and the pair goes on as a middle click.
func test_the_upper_clicked_with_the_pen_still_is_a_middle_click() -> void:
    var upper := SaHeldButtons.new(true).upper
    upper.told(_motion(Vector2(40, ROW_Y), 0.0, 0))
    upper.told(_button(true, Vector2(40, ROW_Y), MOUSE_BUTTON_MASK_LEFT))
    var released := upper.told(_button(false, Vector2(40, ROW_Y), 0))
    assert_eq(_kinds(released), ["middle down", "middle up"], "The press and the release go on as the middle button's")


## The tip touching while the upper is held is a motion with pressure and no
## press, as measured, and lifting it lets the one left button go, which is
## the upper's release as far as Sara can hear.
func test_the_tip_under_a_held_upper_is_its_motions_and_its_lift_the_release() -> void:
    var upper := SaHeldButtons.new(true).upper
    upper.told(_motion(Vector2(40, ROW_Y), 0.0, 0))
    upper.told(_button(true, Vector2(40, ROW_Y), MOUSE_BUTTON_MASK_LEFT))
    upper.told(_motion(Vector2(44, ROW_Y), 0.0, MOUSE_BUTTON_MASK_LEFT))
    var touched := upper.told(_motion(Vector2(48, ROW_Y), TOUCH, MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_kinds(touched), ["motion middle"], "The touch is a middle motion with the pen's pressure")
    var touch := touched[0] as InputEventMouseMotion
    assert_almost_eq(touch.pressure if touch != null else 0.0, TOUCH, 0.0001, "keeping the pressure")
    assert_eq(_kinds(upper.told(_button(false, Vector2(48, ROW_Y), 0))), ["middle up"], "and the lift lets it go")


## The pen leaving the window with the upper held: Godot lets the button go
## without a release, so the first motion with no left button says it.
func test_a_motion_with_no_left_button_lets_a_held_upper_go() -> void:
    var upper := SaHeldButtons.new(true).upper
    upper.told(_motion(Vector2(40, ROW_Y), 0.0, 0))
    upper.told(_button(true, Vector2(40, ROW_Y), MOUSE_BUTTON_MASK_LEFT))
    upper.told(_motion(Vector2(44, ROW_Y), 0.0, MOUSE_BUTTON_MASK_LEFT))
    var back := upper.told(_motion(Vector2(48, ROW_Y), 0.0, 0))
    assert_eq(_kinds(back), ["middle up", "motion none"], "The middle button is let go before the motion")
    assert_false(upper.down, "and the upper is no longer held")


## A mouse reports no tilt, so its press goes on as the left one whatever the
## pressure, and away from Wayland nothing is told at all.
func test_a_mouse_and_another_driver_go_on_as_they_came() -> void:
    var upper := SaHeldButtons.new(true).upper
    var mouse := _motion(Vector2(40, ROW_Y), 0.0, 0)
    mouse.tilt = Vector2.ZERO
    upper.told(mouse)
    assert_eq(_kinds(upper.told(_button(true, Vector2(40, ROW_Y), MOUSE_BUTTON_MASK_LEFT))), ["left down"], "A mouse")
    var elsewhere := SaHeldButtons.new(false).upper
    elsewhere.told(_motion(Vector2(40, ROW_Y), 0.0, 0))
    var press := elsewhere.told(_button(true, Vector2(40, ROW_Y), MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_kinds(press), ["left down"], "and a pen's press away from Wayland goes on as the left one")


## The Middle row says under Wayland that it is the upper button and says
## where it cannot be told, in a painter's words with no engine issue in them.
## Elsewhere it keeps its own hint.
func test_the_middle_row_says_what_wayland_does_with_the_upper() -> void:
    var middle: Dictionary = SaSettingsPenButtons.BUTTONS[1]
    assert_eq(middle["index"], MOUSE_BUTTON_MIDDLE, "The second row is the middle button's")
    var here := SaSettingsPenButtons.hint(middle, true)
    assert_true(here.contains("upper button"), "Under Wayland it is the upper button, '%s'" % here)
    assert_false(here.contains("godot") or here.contains("Godot") or here.contains("#"), "names no engine issue")
    assert_true(here.contains("hovers") and here.contains("touches"), "and says where it can be told and where not")
    assert_eq(SaSettingsPenButtons.hint(middle, false), String(middle["hint"]), "Elsewhere the row keeps its hint")


# --- What the machine does with it ----------------------------------------------


## The upper bound to the eyedropper holds it while pressed in the air, and to
## pan moves the view, and the release hands the brush back.
func test_a_left_press_followed_by_hovers_holds_the_bound_action() -> void:
    if not _on_wayland():
        return
    _bind(SaSettingsPenButtons.EYEDROPPER)
    _upper_down(Vector2(40, ROW_Y))
    assert_eq(_machine.active_tool_name, &"eyedropper", "The upper in the air holds the eyedropper")
    _machine.handle_input(_button(false, Vector2(48, ROW_Y), 0))
    assert_eq(_machine.active_tool_name, &"brush", "and its release hands the brush back")

    _bind(SaSettingsPenButtons.PAN)
    var before: Vector2 = _surface.view.get_pan()
    _upper_down(Vector2(40, ROW_Y))
    for at: Vector2 in _row(48, 80):
        _machine.handle_input(_motion(at, 0.0, MOUSE_BUTTON_MASK_LEFT))
    _machine.handle_input(_button(false, Vector2(80, ROW_Y), 0))
    assert_true(_surface.view.get_pan().x > before.x, "Bound to pan, its hover moves the view")
    assert_false(_machine.active_tool.get("is_drawing"), "and the brush opened no stroke under it")


## The tip's own shape still opens the brush's stroke, and closes it as one
## undo step.
func test_a_left_press_followed_by_pressed_motions_holds_a_stroke() -> void:
    if not _on_wayland():
        return
    _bind(SaSettingsPenButtons.EYEDROPPER)
    var steps := _steps()
    _machine.handle_input(_motion(Vector2(24, ROW_Y), 0.0, 0))
    _machine.handle_input(_motion(Vector2(24, ROW_Y), TOUCH, 0))
    _machine.handle_input(_button(true, Vector2(24, ROW_Y), MOUSE_BUTTON_MASK_LEFT))
    assert_true(_machine.active_tool.get("is_drawing"), "The tip's press opens the brush's stroke at once")
    for at: Vector2 in _row(28, 104):
        _machine.handle_input(_motion(at, TOUCH, MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_machine.active_tool_name, &"brush", "with the brush in hand")
    _machine.handle_input(_button(false, Vector2(104, ROW_Y), 0))
    assert_eq(_steps(), steps + 1, "and its release closes it as one undo step")


## The upper held in the air with the eraser bound, and the tip touching under
## it: the eraser's stroke takes paint off, and the tip's lift closes it and
## hands the brush back, as the measured events allow.
func test_the_tip_under_the_upper_erases_once() -> void:
    if not _on_wayland():
        return
    _bind(SaSettingsPenButtons.ERASER)
    _paint_the_layer()
    var steps := _steps()
    _upper_down(Vector2(24, ROW_Y))
    assert_eq(_machine.active_tool_name, &"eraser", "The upper in the air holds the eraser")
    for at: Vector2 in _row(24, 104):
        _machine.handle_input(_motion(at, TOUCH, MOUSE_BUTTON_MASK_LEFT))
    _machine.handle_input(_button(false, Vector2(104, ROW_Y), 0))
    # Wash gathers the eraser's coverage in the stroke buffer and lands it at
    # the commit, which the lift is, so the layer reads painted until then.
    assert_true(_alpha_at(Vector2(64, ROW_Y)) < ERASED, "The tip touching under it erases along the row")
    assert_almost_eq(_alpha_at(OFF_THE_ROW), 1.0, 0.001, "and leaves the paint off it alone")
    assert_eq(_steps(), steps + 1, "The tip's lift closes the eraser's stroke as one undo step")
    assert_eq(_machine.active_tool_name, &"brush", "and hands the brush back")


# --- Helpers --------------------------------------------------------------------


## Whether the machine tells the upper here, building it when it does. The
## machine asks the display server, so away from Wayland the half is skipped.
func _on_wayland() -> bool:
    if DisplayServer.get_name() != "Wayland":
        skip("the tool machine tells the upper barrel under Wayland only, and this is %s" % DisplayServer.get_name())
        return false
    _surface = Fixtures.make_surface(Vector2i(128, 128))
    # The built-in blend modes, as `main.gd` wires them. Wash is the brush's
    # default, so an eraser gathers in the stroke buffer and lands
    # under Erase at the commit, and a compositor without the registry would
    # resolve that mode to Normal and leave the paint standing.
    _surface.easel.compositor.set_registry(Fixtures.make_registries(_surface).blend_modes)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    return true


## The measured upper in the air at *at*: a hover, the left press and a hover
## at no pressure, which is where the machine learns it is the upper.
func _upper_down(at: Vector2) -> void:
    _machine.handle_input(_motion(at, 0.0, 0))
    _machine.handle_input(_button(true, at, MOUSE_BUTTON_MASK_LEFT))
    _machine.handle_input(_motion(at + Vector2(4, 0), 0.0, MOUSE_BUTTON_MASK_LEFT))


func _bind(action: String) -> void:
    var table := SaSettings.pen_buttons.duplicate()
    table["middle"] = action
    SaSettings.pen_buttons = table


## Each event as words a case can compare: the button and whether it went
## down, or a motion and the button its mask holds, none when it holds no button.
func _kinds(events: Array[InputEvent]) -> Array[String]:
    var out: Array[String] = []
    for event: InputEvent in events:
        var button := event as InputEventMouseButton
        if button != null:
            var which: String = {MOUSE_BUTTON_LEFT: "left", MOUSE_BUTTON_MIDDLE: "middle"}.get(button.button_index, "other")
            out.append("%s %s" % [which, "down" if button.pressed else "up"])
        elif event is InputEventMouseMotion:
            var mask := (event as InputEventMouseMotion).button_mask
            out.append(String(MASKS.get(mask, "motion %d" % mask)))
    return out


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


func _row(from_x: int, to_x: int) -> Array[Vector2]:
    var out: Array[Vector2] = []
    for x: int in range(from_x, to_x + 1, 4):
        out.append(Vector2(x, ROW_Y))
    return out


## A pen's motion at *at*, where the fake view puts the pointer too when there
## is one, since a tool reads its position from the view.
func _motion(at: Vector2, pressure: float, mask: int) -> InputEventMouseMotion:
    if _surface != null:
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


func _button(pressed: bool, at: Vector2, mask: int) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.global_position = at
    event.button_mask = mask
    return event
