## The tablet flag comes back to the mouse under Windows Ink, and stays with a
## pen that hovers.
##
## On a Windows tablet the Info docker's Device row
## read `Tablet` while the pen hovered, which is right, and still read `Tablet`
## after a mouse click and a mouse move, which is not. Godot's Windows driver
## writes a pressure of exactly 1.0 on every mouse motion while the left button
## is down and no tilt, so a mouse drag passed the old test for a pen on every
## motion and the streak that hands the pointer back never counted.
##
## The motions below are the ones the driver builds: `WM_MOUSEMOVE` for the
## mouse, 1.0 or 0.0 and nothing else, and `WM_POINTERUPDATE` for the pen, its
## pressure over 1024 and its tilt in degrees over 90.
extends "res://tests/test_framework.gd"


func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()


static func _mouse(left_down: bool) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.pressure = SaCursorPolicy.MADE_UP_PRESSURE if left_down else 0.0
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT if left_down else 0
    return motion


static func _pen(pressure_of_1024: int, tilt_degrees: Vector2) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.pressure = float(pressure_of_1024) / 1024.0
    motion.tilt = tilt_degrees / 90.0
    return motion


func _hover_the_pen(count: int) -> void:
    for i in count:
        SaCursorPolicy.note_pointer_device(_pen(0, Vector2(12.0, -7.0 + i)))


func test_a_mouse_drag_as_windows_ink_sends_it_hands_the_pointer_back() -> void:
    _hover_the_pen(5)
    assert_true(SaCursorPolicy.pointer_is_tablet, "A hovering pen is a tablet")

    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    SaCursorPolicy.note_pointer_device(press)
    for i in SaCursorPolicy.MOUSE_MOTION_STREAK:
        SaCursorPolicy.note_pointer_device(_mouse(true))
        assert_true(SaCursorPolicy.pointer_is_tablet, "Still the pen after %d dragged motions" % (i + 1))
    SaCursorPolicy.note_pointer_device(_mouse(true))
    assert_false(SaCursorPolicy.pointer_is_tablet, "and the mouse one dragged motion past the streak")


func test_a_mouse_moved_after_a_click_is_a_mouse() -> void:
    _hover_the_pen(5)
    var click := InputEventMouseButton.new()
    click.button_index = MOUSE_BUTTON_LEFT
    click.pressed = true
    SaCursorPolicy.note_pointer_device(click)
    SaCursorPolicy.note_pointer_device(_mouse(true))
    click = click.duplicate()
    click.pressed = false
    SaCursorPolicy.note_pointer_device(click)
    for i in SaCursorPolicy.MOUSE_MOTION_STREAK:
        SaCursorPolicy.note_pointer_device(_mouse(false))
    assert_false(SaCursorPolicy.pointer_is_tablet, "A click and a move is the mouse's")


func test_a_pen_hovering_with_no_pressure_and_a_tilt_stays_a_pen() -> void:
    _hover_the_pen(SaCursorPolicy.MOUSE_MOTION_STREAK * 5)
    assert_true(SaCursorPolicy.pointer_is_tablet, "Hover is the pen however long it lasts")


## The case the made-up pressure must not swallow: a pen with no tilt pressed as
## hard as it goes. Its press begins at a fraction, so a full reading later in
## the same press is still the pen's.
func test_a_pen_pressed_to_its_full_range_stays_a_pen() -> void:
    for reading: int in [40, 300, 700, 1000]:
        SaCursorPolicy.note_pointer_device(_pen(reading, Vector2.ZERO))
    for i in SaCursorPolicy.MOUSE_MOTION_STREAK * 3:
        SaCursorPolicy.note_pointer_device(_pen(1024, Vector2.ZERO))
    assert_true(SaCursorPolicy.pointer_is_tablet, "A full press that began light is the pen's")


## The pen after the mouse, so a flag the mouse took back is the pen's again on
## its first motion, and a new press of the pen is judged on its own.
func test_the_pen_takes_the_pointer_back_from_the_mouse() -> void:
    _hover_the_pen(2)
    for i in SaCursorPolicy.MOUSE_MOTION_STREAK + 1:
        SaCursorPolicy.note_pointer_device(_mouse(true))
    assert_false(SaCursorPolicy.pointer_is_tablet, "The mouse has it")
    SaCursorPolicy.note_pointer_device(_mouse(false))
    SaCursorPolicy.note_pointer_device(_pen(0, Vector2(3.0, 4.0)))
    assert_true(SaCursorPolicy.pointer_is_tablet, "One tilted hover is the pen again")
    SaCursorPolicy.note_pointer_device(_pen(0, Vector2.ZERO))
    SaCursorPolicy.note_pointer_device(_pen(220, Vector2.ZERO))
    for i in SaCursorPolicy.MOUSE_MOTION_STREAK * 2:
        SaCursorPolicy.note_pointer_device(_pen(1024, Vector2.ZERO))
    assert_true(SaCursorPolicy.pointer_is_tablet, "and its own press is not the mouse's")
