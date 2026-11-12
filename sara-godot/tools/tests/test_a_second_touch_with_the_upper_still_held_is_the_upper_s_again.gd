## A second touch with the upper barrel button still held is the upper's again.
##
## Under Wayland the upper is the tip's own left button, and the one left bit
## the driver keeps for both is cleared when the tip lifts, so a touch after a
## lift reached the machine as the tip's and painted under a held eraser. The
## upper let go in the air is no event at all (measured on a real pen), so `SaHeldButtons.UpperBarrel`
## presumes it still held after the
## tip's lift. The events below are that measurement's: the upper pressed in the
## air, a touch that is a pressed motion with no press, its lift as the left
## release, and a second touch that is a pressed motion, a left press and the
## lift again. The first half reads what the upper hands on, the second what
## the held buttons then make of it, and neither needs the display server.
extends "res://tests/test_framework.gd"

## The row the touches run along.
const ROW_Y := 64.0
## A pen's tilt in the air, which no mouse reports.
const TILT := Vector2(0.13, -0.08)
## The pressure the measured tip touched at.
const TOUCH := 0.6
## A motion's mask as the words a case compares.
const MASKS := {0: "motion none", MOUSE_BUTTON_MASK_LEFT: "motion left", MOUSE_BUTTON_MASK_MIDDLE: "motion middle"}

## The milliseconds the suite's clock reads, which a case moves.
var _now: int = 0
var _last_at: Vector2 = Vector2.ZERO


func before_each() -> void:
    _now = 1000
    _last_at = Vector2.ZERO


# --- What the upper hands on ----------------------------------------------------


## An Intuos pen: the upper pressed in the air, a touch, a lift, a second
## touch with the button still held and the lift again. Both touches go on as
## the middle button's, and nothing goes on as the tip's.
func test_two_touches_under_the_held_upper_are_both_the_middle_buttons() -> void:
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    var first := _touch(upper, 40, true)
    assert_eq(
        first,
        ["motion middle", "motion middle", "motion middle", "middle up"],
        "The first touch is middle motions and the lift its release"
    )
    var second := _touch(upper, 80, false)
    var plain := ["motion none", "motion none"]
    assert_eq(
        second,
        plain + ["middle down", "motion middle", "motion middle", "motion middle", "middle up"],
        "The second is a middle press, middle motions and the release, after the hover and the pressed motion that came first"
    )
    assert_false(upper.down, "and the upper is not counted as held once the tip is up")
    assert_false(_has_the_tips(first), "No left press or release of the first went on")
    assert_false(_has_the_tips(second), "nor of the second")


## Three touches the same, which is the clause's other half: the presumption is
## not used up by the second.
func test_three_touches_under_the_held_upper_are_all_the_middle_buttons() -> void:
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    var heard: Array[String] = _touch(upper, 40, true)
    for at: int in [80, 120]:
        heard.append_array(_touch(upper, at, false))
    assert_eq(heard.count("middle down"), 2, "The two touches after the first each press the middle button")
    assert_eq(heard.count("middle up"), 3, "and all three release it")
    assert_false(_has_the_tips(heard), "and none of it is the tip's")


## The second touch's stroke opens on a motion that carries its pressure, as the
## first's does, and the one the tip sent before its press is handed on again as
## the middle button's, so a tap with the pen held still opens it as well.
func test_the_second_touch_hands_its_pressed_motion_on_again_as_the_middle_buttons() -> void:
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    _touch(upper, 40, true)
    upper.told(_motion(Vector2(70, ROW_Y), 0.0, 0))
    var pressed := _motion(Vector2(80, ROW_Y), TOUCH, 0)
    upper.told(pressed)
    var press := upper.told(_button(true, Vector2(80, ROW_Y), MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_kinds(press), ["middle down", "motion middle"], "The press goes on as the middle button's with the motion again")
    var again := press[1] as InputEventMouseMotion
    assert_almost_eq(again.pressure, TOUCH, 0.0001, "carrying the pen's pressure")
    assert_eq(again.position, Vector2(80, ROW_Y), "where the touch began")
    assert_eq(again.relative, Vector2.ZERO, "and no travel of its own")


## The first touch is the plain tip's when no upper went down: the presumption
## belongs to the upper alone.
func test_a_touch_with_no_upper_before_it_is_the_tips() -> void:
    var upper := _upper()
    upper.told(_motion(Vector2(40, ROW_Y), 0.0, 0))
    upper.told(_motion(Vector2(40, ROW_Y), TOUCH, 0))
    assert_eq(
        _kinds(upper.told(_button(true, Vector2(40, ROW_Y), MOUSE_BUTTON_MASK_LEFT))),
        ["left down"],
        "A tip's press goes on as the left button"
    )
    assert_eq(_kinds(upper.told(_button(false, Vector2(44, ROW_Y), 0))), ["left up"], "and so does its lift")
    upper.told(_motion(Vector2(60, ROW_Y), 0.0, 0))
    upper.told(_motion(Vector2(80, ROW_Y), TOUCH, 0))
    assert_eq(
        _kinds(upper.told(_button(true, Vector2(80, ROW_Y), MOUSE_BUTTON_MASK_LEFT))),
        ["left down"],
        "and the next touch is the tip's as well"
    )


# --- Where the presumption ends -------------------------------------------------


## The upper pressed again in the air is a press Godot does hand over, which
## says the old hold is over, so the touch after it is the upper's by the
## ordinary route and a plain touch after a release in the air is the tip's.
func test_the_upper_pressed_again_in_the_air_ends_the_old_hold() -> void:
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    _touch(upper, 40, true)
    upper.told(_motion(Vector2(60, ROW_Y), 0.0, 0))
    var press := upper.told(_button(true, Vector2(60, ROW_Y), MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_kinds(press), [], "A press after a hover is held back again")
    var hovered := upper.told(_motion(Vector2(64, ROW_Y), 0.0, MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_kinds(hovered), ["middle down", "motion middle"], "and the next hover says it is the upper's")
    assert_eq(
        _kinds(upper.told(_button(false, Vector2(64, ROW_Y), 0))),
        ["middle up"],
        "A release in the air, which Godot does hand over here, lets it go"
    )
    upper.told(_motion(Vector2(80, ROW_Y), 0.0, 0))
    upper.told(_motion(Vector2(80, ROW_Y), TOUCH, 0))
    assert_eq(
        _kinds(upper.told(_button(true, Vector2(80, ROW_Y), MOUSE_BUTTON_MASK_LEFT))),
        ["left down"],
        "so the touch after it is the tip's"
    )


## The pen away from the tablet's range for longer than the silence loses the
## upper's state in libinput, and a button still held comes back as a press, so
## the touch after the silence is the tip's until one does.
func test_a_silence_between_two_touches_ends_the_presumption() -> void:
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    _touch(upper, 40, true)
    upper.told(_motion(Vector2(60, ROW_Y), 0.0, 0))
    _now += SaHeldButtons.UpperBarrel.LOST_AFTER_MSEC + 1
    upper.told(_motion(Vector2(300, ROW_Y), 0.0, 0))
    upper.told(_motion(Vector2(300, ROW_Y), TOUCH, 0))
    assert_eq(
        _kinds(upper.told(_button(true, Vector2(300, ROW_Y), MOUSE_BUTTON_MASK_LEFT))),
        ["left down"],
        "A touch after the pen's silence is the tip's"
    )


## A pause that is shorter than the silence, with the hand's tremor still
## reporting, keeps the presumption, and a hover another window's focus
## hands the canvas's route alone keeps it as well.
func test_a_gap_under_the_silence_keeps_the_presumption() -> void:
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    _touch(upper, 40, true)
    _now += SaHeldButtons.UpperBarrel.LOST_AFTER_MSEC
    upper.told(_motion(Vector2(60, ROW_Y), 0.0, 0))
    upper.heard(_motion(Vector2(64, ROW_Y), 0.0, 0))
    upper.told(_motion(Vector2(80, ROW_Y), TOUCH, 0))
    var press := upper.told(_button(true, Vector2(80, ROW_Y), MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_kinds(press).front(), "middle down", "A touch within the silence is the upper's")


## The upper let go with the tip still down: the pressure goes on after the left
## release, which is not the tip's lift, so nothing is presumed and the next
## touch is the tip's.
func test_the_upper_let_go_on_the_surface_presumes_nothing() -> void:
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    upper.told(_motion(Vector2(48, ROW_Y), TOUCH, MOUSE_BUTTON_MASK_LEFT))
    assert_eq(_kinds(upper.told(_button(false, Vector2(52, ROW_Y), 0))), ["middle up"], "The release hands the hold back")
    upper.told(_motion(Vector2(56, ROW_Y), TOUCH, 0))
    upper.told(_motion(Vector2(60, ROW_Y), 0.0, 0))
    upper.told(_motion(Vector2(80, ROW_Y), TOUCH, 0))
    assert_eq(
        _kinds(upper.told(_button(true, Vector2(80, ROW_Y), MOUSE_BUTTON_MASK_LEFT))),
        ["left down"],
        "and the touch after the lift is the tip's"
    )


## The upper pressed and let go in the air with no touch between is a release
## Godot hands over, so nothing is presumed after it.
func test_the_upper_let_go_in_the_air_presumes_nothing() -> void:
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    assert_eq(_kinds(upper.told(_button(false, Vector2(48, ROW_Y), 0))), ["middle up"], "The release hands the hold back")
    upper.told(_motion(Vector2(60, ROW_Y), 0.0, 0))
    upper.told(_motion(Vector2(60, ROW_Y), TOUCH, 0))
    assert_eq(
        _kinds(upper.told(_button(true, Vector2(60, ROW_Y), MOUSE_BUTTON_MASK_LEFT))),
        ["left down"],
        "and the next touch is the tip's"
    )


## The focus going to another window lets the upper's state go, since a button
## may change there unheard.
func test_forgetting_the_upper_ends_the_presumption() -> void:
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    _touch(upper, 40, true)
    upper.forget()
    upper.told(_motion(Vector2(60, ROW_Y), 0.0, 0))
    upper.told(_motion(Vector2(80, ROW_Y), TOUCH, 0))
    assert_eq(
        _kinds(upper.told(_button(true, Vector2(80, ROW_Y), MOUSE_BUTTON_MASK_LEFT))),
        ["left down"],
        "A touch after the focus went is the tip's"
    )


## Away from Wayland nothing is told at all, however many touches.
func test_another_driver_goes_on_as_it_came() -> void:
    var elsewhere := SaHeldButtons.new(false, func() -> int: return _now).upper
    var heard: Array[String] = []
    for at: int in [40, 80]:
        elsewhere.told(_motion(Vector2(at, ROW_Y), 0.0, 0))
        elsewhere.told(_motion(Vector2(at, ROW_Y), TOUCH, 0))
        heard.append_array(_kinds(elsewhere.told(_button(true, Vector2(at, ROW_Y), MOUSE_BUTTON_MASK_LEFT))))
        heard.append_array(_kinds(elsewhere.told(_button(false, Vector2(at + 8, ROW_Y), 0))))
    assert_eq(heard, ["left down", "left up", "left down", "left up"], "Every press and release goes on as the left button")


# --- What the held buttons make of it -------------------------------------------


## The held buttons as the machine drives them: the middle button's press is
## bound to the eraser, and what the upper hands on is routed to the tool. Each
## touch is one left press and one left release the eraser hears, in that
## order, three times over, and no touch is longer than its own.
func test_each_touch_under_the_held_upper_is_a_stroke_of_the_held_tool_of_its_own() -> void:
    var held := SaHeldButtons.new(true, func() -> int: return _now)
    var heard: Array[String] = []
    _drive(held, held.upper.told(_motion(Vector2(24, ROW_Y), 0.0, 0)), heard)
    _drive(held, held.upper.told(_button(true, Vector2(24, ROW_Y), MOUSE_BUTTON_MASK_LEFT)), heard)
    _drive(held, held.upper.told(_motion(Vector2(28, ROW_Y), 0.0, MOUSE_BUTTON_MASK_LEFT)), heard)
    assert_eq(held.wanted({&"eraser": true}), &"eraser", "The upper in the air holds the eraser")
    for at: int in [40, 80, 120]:
        var first := at == 40
        if not first:
            for hover: float in [at - 20.0, at - 4.0]:
                _drive(held, held.upper.told(_motion(Vector2(hover, ROW_Y), 0.0, 0)), heard)
        var x := float(at)
        _drive(held, held.upper.told(_motion(Vector2(x, ROW_Y), TOUCH, MOUSE_BUTTON_MASK_LEFT if first else 0)), heard)
        if not first:
            _drive(held, held.upper.told(_button(true, Vector2(x, ROW_Y), MOUSE_BUTTON_MASK_LEFT)), heard)
        for step: int in 3:
            _drive(held, held.upper.told(_motion(Vector2(x + 4.0 * (step + 1), ROW_Y), TOUCH, MOUSE_BUTTON_MASK_LEFT)), heard)
        _drive(held, held.upper.told(_button(false, Vector2(x + 12.0, ROW_Y), 0)), heard)
        _now += 30
    assert_eq(heard.count("left down"), 3, "The eraser heard three presses")
    assert_eq(heard.count("left up"), 3, "and three releases")
    var open := 0
    for word: String in heard:
        if word == "left down":
            open += 1
            assert_eq(open, 1, "No press came with another stroke open")
        elif word == "left up":
            open -= 1
    assert_eq(open, 0, "and every stroke was closed")
    assert_eq(held.wanted({&"eraser": true}), &"", "The last lift hands the brush back")


# --- Helpers --------------------------------------------------------------------


## An upper that reads the suite's clock, on Wayland.
func _upper() -> SaHeldButtons.UpperBarrel:
    return SaHeldButtons.new(true, func() -> int: return _now).upper


## The measured upper in the air: a hover, the left press and a hover at no
## pressure, which is where the upper learns it is the upper's.
func _press_the_upper_in_the_air(upper: SaHeldButtons.UpperBarrel) -> void:
    upper.told(_motion(Vector2(20, ROW_Y), 0.0, 0))
    upper.told(_button(true, Vector2(20, ROW_Y), MOUSE_BUTTON_MASK_LEFT))
    upper.told(_motion(Vector2(24, ROW_Y), 0.0, MOUSE_BUTTON_MASK_LEFT))
    assert_true(upper.down, "The upper is down after its press and a hover at no pressure")


## One touch at *at* as the pen sends it and the words it goes on as. The first
## is a pressed motion with the left bit the upper already holds and no press,
## a later one hovers and presses after a pressed motion with none. Then two
## more motions and the lift, which is the left release, and the pen's hover
## after it is the next touch's own first motion.
func _touch(upper: SaHeldButtons.UpperBarrel, at: int, first: bool) -> Array[String]:
    var out: Array[String] = []
    var x := float(at)
    if not first:
        out.append_array(_kinds(upper.told(_motion(Vector2(x - 8.0, ROW_Y), 0.0, 0))))
        out.append_array(_kinds(upper.told(_motion(Vector2(x, ROW_Y), TOUCH, 0))))
        out.append_array(_kinds(upper.told(_button(true, Vector2(x, ROW_Y), MOUSE_BUTTON_MASK_LEFT))))
    else:
        out.append_array(_kinds(upper.told(_motion(Vector2(x, ROW_Y), TOUCH, MOUSE_BUTTON_MASK_LEFT))))
    for step: int in 2:
        out.append_array(_kinds(upper.told(_motion(Vector2(x + 4.0 * (step + 1), ROW_Y), TOUCH, MOUSE_BUTTON_MASK_LEFT))))
    out.append_array(_kinds(upper.told(_button(false, Vector2(x + 12.0, ROW_Y), 0))))
    return out


## What the machine does with *told*: a middle press binds the eraser and a
## middle release lets it go, which the held buttons hand back as the left
## release that closes the stroke, and everything else is routed to the tool.
## What the tool hears is appended as words.
func _drive(held: SaHeldButtons, told: Array[InputEvent], heard: Array[String]) -> void:
    for event: InputEvent in told:
        var button := event as InputEventMouseButton
        if button != null and button.button_index == MOUSE_BUTTON_MIDDLE:
            if button.pressed:
                held.press(MOUSE_BUTTON_MIDDLE, &"eraser")
            else:
                _hear(held.release(button), heard)
            continue
        for routed: InputEvent in held.route(event, &"eraser"):
            _hear(routed, heard)


func _hear(event: InputEvent, heard: Array[String]) -> void:
    var button := event as InputEventMouseButton
    if button != null:
        heard.append("left down" if button.pressed else "left up")


## Whether any of *words* is the left button's.
func _has_the_tips(words: Array) -> bool:
    for word: String in words:
        if word.begins_with("left"):
            return true
    return false


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


## A pen's motion at *at*, with the travel from the last one.
func _motion(at: Vector2, pressure: float, mask: int) -> InputEventMouseMotion:
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
