## The upper barrel button is held exactly while the kernel says so, where a
## module reads the pen from it.
##
## The machine presumes the upper still held after the tip's lift, because
## Godot hands over no event for the upper let go in the air, so a touch after
## that release erased until the upper was pressed again. A pen source on the
## door's `SaPenRegistry` reads the kernel's word on the barrels, and
## `SaHeldButtons.UpperBarrel` asks it at a touch's press. The events below are
## the measured ones, the upper in the air, a touch, the lift and touches after
## it, with a stand-in source answering what the kernel would. With no source,
## or one that knows nothing, the presumption is what it was, and
## `test_a_second_touch_with_the_upper_still_held_is_the_upper_s_again.gd`
## still holds unchanged.
extends "res://tests/test_framework.gd"

## The row the touches run along.
const ROW_Y := 64.0
## A pen's tilt in the air, which no mouse reports.
const TILT := Vector2(0.13, -0.08)
## The pressure the measured tip touched at.
const TOUCH := 0.6


## A source that answers what a case sets, in place of a module reading the
## kernel.
class StandIn:
    extends SaPenSource

    var pen: SaPenSource.State = null

    func now() -> SaPenSource.State:
        return pen.copy() if pen != null else null

    func reads() -> bool:
        return pen != null


## The kernel's upper on a real pen. Not a constant, because a constant
## naming a global class breaks the class cache.
var _kernel_upper := SaPenSource.Barrel.SECOND
## The lower, which Godot reports as the right button.
var _kernel_lower := SaPenSource.Barrel.FIRST

## The milliseconds the suite's clock reads, which a case moves.
var _now: int = 0
var _last_at: Vector2 = Vector2.ZERO
var _source: StandIn = null
var _pens: SaPenRegistry = null


func before_each() -> void:
    _now = 1000
    _last_at = Vector2.ZERO
    _source = StandIn.new()
    _source.pen = SaPenSource.State.new()
    _source.pen.in_range = true
    _pens = SaPenRegistry.new()
    _pens.register(_source, &"stand_in")


# --- With the kernel's word ----------------------------------------------------


## The second touch under the held upper is the middle button's, because the
## kernel says the upper is held.
func test_the_second_touch_under_the_held_upper_is_the_middle_buttons() -> void:
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    var first := _touch(upper, 40, true)
    assert_eq(first.back(), "middle up", "The first touch's lift is the middle release")
    var second := _touch(upper, 80, false)
    assert_true(second.has("middle down"), "The second touch presses the middle button")
    assert_false(_has_the_tips(first + second), "and nothing of either is the tip's")


## The upper let go in the air is no event Godot hands over, and the kernel
## says it. The touch after it is the tip's, where the presumption would have erased.
func test_a_touch_after_the_upper_was_let_go_in_the_air_is_the_tips() -> void:
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    _touch(upper, 40, true)
    _touch(upper, 80, false)
    _let_go(_kernel_upper)
    var third := _touch(upper, 120, false)
    assert_true(third.has("left down"), "The third touch is the tip's press: %s" % [third])
    assert_true(third.has("left up"), "and its lift the tip's")
    assert_false(third.has("middle down"), "and nothing of it the middle button's")


## Across any number of touches, the upper held through each.
func test_the_upper_is_held_across_any_number_of_touches() -> void:
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    var heard: Array[String] = _touch(upper, 40, true)
    for at: int in [80, 120, 160, 200]:
        heard.append_array(_touch(upper, at, false))
    assert_eq(heard.count("middle down"), 4, "Every touch after the first presses the middle button")
    assert_false(_has_the_tips(heard), "and none of it is the tip's")


## A silence longer than the presumption's, with the pen hovering, ends no hold the kernel
## still reports, and the focus going to another window does not either.
func test_a_silence_or_the_focus_going_ends_nothing_the_kernel_still_holds() -> void:
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    _touch(upper, 40, true)
    _now += SaHeldButtons.UpperBarrel.LOST_AFTER_MSEC * 3
    assert_true(_touch(upper, 80, false).has("middle down"), "A touch after a long hover is the upper's")
    upper.forget()
    assert_true(_touch(upper, 120, false).has("middle down"), "and one after the focus came back")


## The lower held does not make a touch the upper's: the upper is the barrel
## the kernel pressed last when it was told from the tip in the air.
func test_the_lower_held_is_not_taken_for_the_upper() -> void:
    _press(_kernel_lower)
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    _touch(upper, 40, true)
    _let_go(_kernel_upper)
    var touch := _touch(upper, 80, false)
    assert_true(touch.has("left down"), "With the lower still held, the touch after the upper let go is the tip's")


## The held buttons as the machine drives them, the upper bound to the eraser:
## two touches under the upper are two strokes of the eraser, and the touch
## after it was let go in the air reaches the tool as the tip's own press,
## with no eraser held.
func test_the_eraser_takes_the_two_touches_and_the_brush_the_third() -> void:
    var held := SaHeldButtons.new(true, func() -> int: return _now)
    held.upper.pens = _pens
    var heard: Array[String] = []
    _drive(held, held.upper.told(_motion(Vector2(24, ROW_Y), 0.0, 0)), heard)
    _press(_kernel_upper)
    _drive(held, held.upper.told(_button(true, Vector2(24, ROW_Y), MOUSE_BUTTON_MASK_LEFT)), heard)
    _drive(held, held.upper.told(_motion(Vector2(28, ROW_Y), 0.0, MOUSE_BUTTON_MASK_LEFT)), heard)
    for at: int in [40, 80]:
        _stroke(held, at, at == 40, heard)
    assert_eq(heard.count("eraser down"), 2, "The eraser heard two presses")
    assert_eq(heard.count("eraser up"), 2, "and two releases")
    _let_go(_kernel_upper)
    _stroke(held, 120, false, heard)
    assert_eq(heard.count("brush down"), 1, "The third touch is a press with no held tool")
    assert_eq(heard.count("brush up"), 1, "and so is its lift")
    assert_eq(held.wanted({&"eraser": true}), &"", "and the eraser is not held")


# --- With no word from the kernel ----------------------------------------------


## No source on the door: the touch after the upper let go in the air is
## presumed the upper's, as the presumption has it.
func test_with_no_source_the_presumption_stands() -> void:
    var upper := SaHeldButtons.new(true, func() -> int: return _now).upper
    upper.pens = SaPenRegistry.new()
    _press_the_upper_in_the_air(upper)
    _touch(upper, 40, true)
    _let_go(_kernel_upper)
    assert_true(_touch(upper, 80, false).has("middle down"), "A touch after the lift is presumed the upper's")


## A source that knows nothing, a node not readable or a pen not seen into
## range since it opened, leaves the presumption as well, and so does a
## source that learned no upper because it knew nothing when the upper was
## told.
func test_a_source_that_knows_nothing_leaves_the_presumption() -> void:
    _source.pen = null
    var upper := _upper()
    _press_the_upper_in_the_air(upper)
    _touch(upper, 40, true)
    _source.pen = SaPenSource.State.new()
    _source.pen.in_range = true
    assert_true(_touch(upper, 80, false).has("middle down"), "With no upper learned, the touch is presumed the upper's")
    _now += SaHeldButtons.UpperBarrel.LOST_AFTER_MSEC + 1
    assert_true(_touch(upper, 120, false).has("left down"), "and the presumption's silence still ends the presumption")


## The measurement, every case of it, through a registry whose source
## knows nothing, reads the same words as with no registry at all.
func test_the_d13_measurement_reads_the_same_with_a_source_that_knows_nothing() -> void:
    _source.pen = null
    var without := SaHeldButtons.new(true, func() -> int: return _now).upper
    var with_nothing := _upper()
    var heard_without: Array[String] = []
    var heard_with: Array[String] = []
    for upper: SaHeldButtons.UpperBarrel in [without, with_nothing]:
        _last_at = Vector2.ZERO
        var heard := heard_without if upper == without else heard_with
        _press_the_upper_in_the_air(upper)
        heard.append_array(_touch(upper, 40, true))
        for at: int in [80, 120]:
            heard.append_array(_touch(upper, at, false))
    assert_eq(heard_with, heard_without, "Every event goes on as it did")


# --- Helpers --------------------------------------------------------------------


## An upper that reads the suite's clock and the stand-in, on Wayland.
func _upper() -> SaHeldButtons.UpperBarrel:
    var upper := SaHeldButtons.new(true, func() -> int: return _now).upper
    upper.pens = _pens
    return upper


func _press(barrel: SaPenSource.Barrel) -> void:
    if _source.pen == null:
        return
    _source.pen.barrels |= 1 << barrel
    _source.pen.last_pressed = barrel


func _let_go(barrel: SaPenSource.Barrel) -> void:
    if _source.pen != null:
        _source.pen.barrels &= ~(1 << barrel)


## The measured upper in the air, the kernel pressing it before Godot's left
## press arrives, as it does.
func _press_the_upper_in_the_air(upper: SaHeldButtons.UpperBarrel) -> void:
    upper.told(_motion(Vector2(20, ROW_Y), 0.0, 0))
    _press(_kernel_upper)
    upper.told(_button(true, Vector2(20, ROW_Y), MOUSE_BUTTON_MASK_LEFT))
    upper.told(_motion(Vector2(24, ROW_Y), 0.0, MOUSE_BUTTON_MASK_LEFT))
    assert_true(upper.down, "The upper is down after its press and a hover at no pressure")


## One touch at *at* as the pen sends it under Wayland and the words it goes
## on as, the measured shape: the first is a pressed motion with the left bit the
## upper already holds, a later one a hover, a pressed motion and a left press.
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
    _now += 30
    return out


## The same touch through the held buttons, as the machine drives them.
func _stroke(held: SaHeldButtons, at: int, first: bool, heard: Array[String]) -> void:
    var x := float(at)
    if not first:
        _drive(held, held.upper.told(_motion(Vector2(x - 8.0, ROW_Y), 0.0, 0)), heard)
    _drive(held, held.upper.told(_motion(Vector2(x, ROW_Y), TOUCH, MOUSE_BUTTON_MASK_LEFT if first else 0)), heard)
    if not first:
        _drive(held, held.upper.told(_button(true, Vector2(x, ROW_Y), MOUSE_BUTTON_MASK_LEFT)), heard)
    for step: int in 2:
        _drive(held, held.upper.told(_motion(Vector2(x + 4.0 * (step + 1), ROW_Y), TOUCH, MOUSE_BUTTON_MASK_LEFT)), heard)
    _drive(held, held.upper.told(_button(false, Vector2(x + 12.0, ROW_Y), 0)), heard)
    _now += 30


## What the machine does with *told*: a middle press binds the eraser and a
## middle release lets it go, and everything else is routed to the tool. A
## left press or release the tool hears is the eraser's while the eraser is
## held and the brush's otherwise.
func _drive(held: SaHeldButtons, told: Array[InputEvent], heard: Array[String]) -> void:
    for event: InputEvent in told:
        var button := event as InputEventMouseButton
        if button != null and button.button_index == MOUSE_BUTTON_MIDDLE:
            if button.pressed:
                held.press(MOUSE_BUTTON_MIDDLE, &"eraser")
            else:
                _hear(held.release(button), heard, "eraser")
            continue
        var tool := "eraser" if not held.is_empty() else "brush"
        if held.is_empty():
            _hear(event, heard, tool)
            continue
        for routed: InputEvent in held.route(event, &"eraser"):
            _hear(routed, heard, tool)


func _hear(event: InputEvent, heard: Array[String], tool: String) -> void:
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        heard.append("%s %s" % [tool, "down" if button.pressed else "up"])


func _has_the_tips(words: Array) -> bool:
    for word: String in words:
        if word.begins_with("left"):
            return true
    return false


func _kinds(events: Array[InputEvent]) -> Array[String]:
    var out: Array[String] = []
    for event: InputEvent in events:
        var button := event as InputEventMouseButton
        if button != null:
            var which: String = {MOUSE_BUTTON_LEFT: "left", MOUSE_BUTTON_MIDDLE: "middle"}.get(button.button_index, "other")
            out.append("%s %s" % [which, "down" if button.pressed else "up"])
        elif event is InputEventMouseMotion:
            var mask := (event as InputEventMouseMotion).button_mask
            out.append("motion %d" % mask)
    return out


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
