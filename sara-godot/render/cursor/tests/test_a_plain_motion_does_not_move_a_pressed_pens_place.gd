## A motion with no pressure and no tilt while the pen's tip is down is not the
## pen, and a hover with neither still is.
##
## On a Windows tablet a let-out Layers
## dragged with the pen under Windows Ink went back and forth between the pen
## and one fixed place near where the drag began, 372 times in 897 changes of
## place. Godot 4.7 answers the pen's own messages as handled, so the system
## pointer stays put while the docker moves under it, and the motion Windows
## sends the moved window carries that pointer's place with neither pressure
## nor tilt. The place the drag reads kept every such motion as the pen's.
##
## The motions below are the ones the driver builds: `WM_POINTERUPDATE` for the
## pen, its pressure over 1024 and its tilt in degrees over 90, and the moved
## window's `WM_MOUSEMOVE`, 0.0 and no tilt. They arrive in the root window,
## which stands in for the let-out docker because a suite cannot map a window
## of its own, and the place a let-out docker's drag reads is the pen's on the
## desktop, the same whatever window carried it there. The drag itself is
## `ui/dockers/tests/test_a_let_out_docker_dragged_with_the_pen_follows_it.gd`.
extends "res://tests/test_framework.gd"

## Where the system pointer stays while the pen drags, and where the drag
## begins.
const STILL := Vector2(240.0, 160.0)
const PRESSED := Vector2(250.0, 165.0)
## How far each pen motion moves on from the last, and how many there are.
const STEP := Vector2(18.0, 7.0)
const STEPS := 12


func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()


static func _root() -> Window:
    return (Engine.get_main_loop() as SceneTree).root


static func _pen(at: Vector2, pressure_of_1024: int) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.global_position = at
    motion.pressure = float(pressure_of_1024) / 1024.0
    motion.tilt = Vector2(14.0, -9.0) / 90.0
    return motion


static func _plain(at: Vector2) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.global_position = at
    return motion


static func _tip(at: Vector2, down: bool) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = down
    button.position = at
    button.global_position = at
    return button


## The pen hovering to *at*, then its tip coming down there, as Windows Ink
## sends a press: a button at the pen's place, then the pen's pressed motions.
func _press_at(window: Window, at: Vector2) -> void:
    SaCursorPolicy.note_pointer_device(_pen(at, 0), window)
    SaCursorPolicy.note_pointer_device(_tip(at, true), window)


static func _on_the_desktop(window: Window, at: Vector2) -> Vector2:
    var to_desktop: Transform2D = SaPointerDevice.desktop_transform(window)
    return to_desktop * at


func test_a_plain_motion_while_the_pen_is_down_leaves_the_pens_place() -> void:
    var window := _root()
    _press_at(window, PRESSED)
    var pen := PRESSED
    for i in STEPS:
        pen += STEP
        SaCursorPolicy.note_pointer_device(_pen(pen, 300 + 20 * i), window)
        SaCursorPolicy.note_pointer_device(_plain(STILL), window)
        assert_true(SaCursorPolicy.pointer_is_tablet, "Still the pen after the plain motion of step %d" % i)
        assert_eq(SaCursorPolicy.pointer_in(window), pen, "The pen's place in its window after step %d is the pen's" % i)
        assert_true(
            SaCursorPolicy.pointer_in(null).is_equal_approx(_on_the_desktop(window, pen)),
            "and on the desktop, where a let-out docker's drag reads it, after step %d" % i
        )


func test_a_pen_that_lifted_keeps_its_place_from_the_next_plain_motion() -> void:
    var window := _root()
    _press_at(window, PRESSED)
    SaCursorPolicy.note_pointer_device(_pen(PRESSED + STEP, 400), window)
    SaCursorPolicy.note_pointer_device(_tip(PRESSED + STEP, false), window)
    SaCursorPolicy.note_pointer_device(_plain(STILL), window)
    assert_eq(SaCursorPolicy.pointer_in(window), STILL, "Once the tip is up a plain motion is the pen's hover again")


func test_a_hover_is_still_kept_from_a_plain_motion() -> void:
    var window := _root()
    SaCursorPolicy.note_pointer_device(_pen(PRESSED, 0), window)
    SaCursorPolicy.note_pointer_device(_plain(STILL), window)
    assert_true(SaCursorPolicy.pointer_is_tablet, "A plain motion after a tilted hover is still the pen")
    assert_eq(SaCursorPolicy.pointer_in(window), STILL, "and its place is kept, the hover with no tilt")


## A press whose release never reached Sara must not hold a mouse's place on
## the pen's: the plain motions count towards the streak as before, and once it
## hands the pointer to the mouse the press is forgotten with it.
func test_a_release_that_never_came_lets_go_with_the_streak() -> void:
    var window := _root()
    _press_at(window, PRESSED)
    SaCursorPolicy.note_pointer_device(_pen(PRESSED + STEP, 500), window)
    for i in SaCursorPolicy.MOUSE_MOTION_STREAK:
        SaCursorPolicy.note_pointer_device(_plain(STILL), window)
    assert_true(SaCursorPolicy.pointer_is_tablet, "The streak has not run out")
    SaCursorPolicy.note_pointer_device(_plain(STILL), window)
    assert_false(SaCursorPolicy.pointer_is_tablet, "One plain motion past it hands the pointer to the mouse")

    SaCursorPolicy.note_pointer_device(_pen(PRESSED, 0), window)
    SaCursorPolicy.note_pointer_device(_plain(STILL + STEP), window)
    assert_eq(SaCursorPolicy.pointer_in(window), STILL + STEP, "and the pen back in hover keeps a plain motion's place")


## A motion the mouse made while a mouse button was down, under Windows Ink, is
## no pen press, so the plain motion after its release is kept as it always was.
func test_a_mouse_press_is_not_the_pens() -> void:
    var window := _root()
    SaCursorPolicy.note_pointer_device(_pen(PRESSED, 0), window)
    SaCursorPolicy.note_pointer_device(_tip(PRESSED, true), window)
    var dragged := _plain(PRESSED + STEP)
    dragged.pressure = SaCursorPolicy.MADE_UP_PRESSURE
    SaCursorPolicy.note_pointer_device(dragged, window)
    SaCursorPolicy.note_pointer_device(_plain(STILL), window)
    assert_eq(SaCursorPolicy.pointer_in(window), STILL, "A press that began at the made-up pressure holds no pen place")
