## The ALT-right drag grows a docker about its own centre, not towards its
## bottom-right corner.
##
## The rule: ALT + right click to resize changes the size from the middle of the
## docker, not to the bottom right only. Sideways movement stretches the sides,
## upward vertical.
##
## The corner grip does not follow that rule. It is anchored at the corner
## opposite it, because a grip pulled down lifted the docker's top over
## the menu bar. `DockerDragHandle.grip_rect` is the grip's arithmetic and
## `test_docker_resizer.gd` drives it. This suite is the ALT-right drag's, which
## still holds the centre. What it cannot show is that the gesture is wired to
## it, which is what scenarios/docker-resize-centre.json measures on the
## running app: the docker's centre is (570.0, 400.0) in every ALT-right dump.
extends "res://tests/test_framework.gd"

const MINIMUM := Vector2i(80, 60)

## A 300 by 400 docker whose centre is at (570, 400), the scenario's own.
const START_POSITION := Vector2i(420, 200)
const START_SIZE := Vector2i(300, 400)


func _centre(rect: Rect2i) -> Vector2:
    return Vector2(rect.position) + Vector2(rect.size) * 0.5


## Every test below presses at the bottom-right corner, which is the quadrant
## a positive drag has always grown from, and every number these tests pin
## predates the fix, so they still hold once a press has to name where the
## drag began.
func _br(position: Vector2i, size: Vector2i) -> Vector2:
    return Vector2(position + size)


func test_the_centre_does_not_move() -> void:
    var rect := DockerDragHandle.resize_rect(
        START_POSITION, START_SIZE, Vector2(60, 40), _br(START_POSITION, START_SIZE), MINIMUM
    )

    assert_eq(_centre(rect), Vector2(570.0, 400.0), "The middle of the docker is where it was")
    assert_eq(rect.size, Vector2i(420, 480), "and both sides moved out by the drag")
    assert_eq(rect.position, Vector2i(360, 160), "so the top-left came back by it")


## The half of the rule that says which axis is which: a drag along one axis
## leaves the other alone.
func test_sideways_movement_stretches_the_sides_and_vertical_the_ends() -> void:
    var press := _br(START_POSITION, START_SIZE)
    var wide := DockerDragHandle.resize_rect(START_POSITION, START_SIZE, Vector2(60, 0), press, MINIMUM)
    assert_eq(wide.size, Vector2i(420, 400), "Sideways changes the width only")
    assert_eq(wide.position.y, START_POSITION.y, "and leaves the top where it was")

    var tall := DockerDragHandle.resize_rect(START_POSITION, START_SIZE, Vector2(0, 40), press, MINIMUM)
    assert_eq(tall.size, Vector2i(300, 480), "Vertical changes the height only")
    assert_eq(tall.position.x, START_POSITION.x, "and leaves the left edge where it was")


## Why the size takes twice the drag rather than once. It is not a doubling for
## its own sake: it is what puts the corner nearest the press back under the
## pointer while the centre holds still.
func test_the_dragged_corner_keeps_up_with_the_pointer() -> void:
    var drag := Vector2(60, 40)
    var rect := DockerDragHandle.resize_rect(START_POSITION, START_SIZE, drag, _br(START_POSITION, START_SIZE), MINIMUM)

    var corner_before := Vector2(START_POSITION + START_SIZE)
    var corner_after := Vector2(rect.position + rect.size)

    assert_eq(corner_after - corner_before, drag, "The bottom-right corner moved exactly as far as the pointer")


## A docker smaller than its contents draws over itself, so the floor wins. The
## centre has to survive the clamp, or a docker held at its minimum walks across
## the screen while the pointer keeps pulling.
func test_a_clamped_docker_keeps_its_centre() -> void:
    var rect := DockerDragHandle.resize_rect(
        START_POSITION, START_SIZE, Vector2(-400, -400), _br(START_POSITION, START_SIZE), MINIMUM
    )

    assert_eq(rect.size, MINIMUM, "The minimum wins over the pointer")
    assert_eq(_centre(rect), Vector2(570.0, 400.0), "and the middle is still the middle")


func test_each_axis_clamps_on_its_own() -> void:
    var rect := DockerDragHandle.resize_rect(
        START_POSITION, START_SIZE, Vector2(60, -400), _br(START_POSITION, START_SIZE), MINIMUM
    )

    assert_eq(rect.size, Vector2i(420, 60), "Width grows while height stops at the floor")
    assert_eq(_centre(rect), Vector2(570.0, 400.0), "and neither axis drags the centre with it")


## A drag of nothing is a resize of nothing. Worth pinning, because the ALT-drag
## begins with a press that applies the arithmetic at zero, and a gesture that
## jumped on press would be the first thing a person noticed.
func test_a_drag_of_nothing_changes_nothing() -> void:
    var rect := DockerDragHandle.resize_rect(START_POSITION, START_SIZE, Vector2.ZERO, _br(START_POSITION, START_SIZE), MINIMUM)

    assert_eq(rect.position, START_POSITION, "The docker has not moved")
    assert_eq(rect.size, START_SIZE, "nor changed size")


## An odd size cannot be halved exactly, so the centre lands on a half pixel and
## the position is rounded once rather than the drag being rounded twice.
func test_an_odd_size_rounds_once() -> void:
    var rect := DockerDragHandle.resize_rect(
        Vector2i(100, 100), Vector2i(101, 101), Vector2(10, 10), _br(Vector2i(100, 100), Vector2i(101, 101)), MINIMUM
    )

    assert_eq(rect.size, Vector2i(121, 121), "The size is the start plus twice the drag")
    assert_eq(rect.position, Vector2i(90, 90), "and the top-left is the centre less half of it")


## The reported case: the rule names the top right corner, and this is the one the
## bug got wrong. A press there grows on a leftward and an upward pull, exactly
## the opposite of the bottom-right corner's own sign on each axis.
func test_a_press_in_the_top_right_corner_grows_towards_it() -> void:
    var press := Vector2(START_POSITION.x + START_SIZE.x, START_POSITION.y)
    var rect := DockerDragHandle.resize_rect(START_POSITION, START_SIZE, Vector2(40, -30), press, MINIMUM)

    assert_eq(_centre(rect), Vector2(570.0, 400.0), "The middle stays where it was")
    assert_eq(rect.size, Vector2i(380, 460), "Pulling right and up both grow, because both pull away from the centre")


## The other diagonal: a press in the top left corner, pulled right and down,
## towards the centre, shrinks on both axes.
func test_a_press_in_the_top_left_corner_shrinks_towards_the_centre() -> void:
    var press := Vector2(START_POSITION)
    var rect := DockerDragHandle.resize_rect(START_POSITION, START_SIZE, Vector2(40, 30), press, MINIMUM)

    assert_eq(_centre(rect), Vector2(570.0, 400.0), "The middle stays where it was")
    assert_eq(rect.size, Vector2i(220, 340), "Pulling right and down both shrink from here, towards the centre")


## The fourth quadrant, bottom left, completes the four corners the suite
## covers.
func test_a_press_in_the_bottom_left_corner_mirrors_the_top_right() -> void:
    var press := Vector2(START_POSITION.x, START_POSITION.y + START_SIZE.y)
    var rect := DockerDragHandle.resize_rect(START_POSITION, START_SIZE, Vector2(-40, 30), press, MINIMUM)

    assert_eq(_centre(rect), Vector2(570.0, 400.0), "The middle stays where it was")
    assert_eq(rect.size, Vector2i(380, 460), "Pulling left and down both grow, away from the centre on this corner")


## A press exactly on the centre falls to the positive side of both axes, the
## bottom-right quadrant, so nothing is ambiguous and nothing divides by zero.
func test_a_press_on_the_centre_defaults_to_growing() -> void:
    var press := _centre(Rect2i(START_POSITION, START_SIZE))
    var rect := DockerDragHandle.resize_rect(START_POSITION, START_SIZE, Vector2(40, 30), press, MINIMUM)

    assert_eq(rect.size, Vector2i(380, 460), "Right and down still grow, the bottom-right default")
