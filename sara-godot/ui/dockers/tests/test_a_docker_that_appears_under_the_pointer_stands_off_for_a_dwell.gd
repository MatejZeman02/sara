## A docker that appears under a resting pointer takes the keyboard only after the
## pointer has stayed in it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It takes longer for the mouse to focus a new docker that appeared under it,
## so it does not happen by accident. `DockerFocus.Arrival` tells a docker that came under the pointer
## from one the pointer crossed into, and `DockerFocus.follow` is handed its
## answer. These read both over detached windows with a clock of their own,
## because a `Window` outside the tree cannot be given the focus and one inside
## it would map a real OS window. What the running app does with it is
## `scenarios/a-docker-that-appears-under-the-pointer-takes-the-keyboard-only-after-the-pointer-has-stayed-in-it.json`.
extends "res://tests/test_framework.gd"

const DWELL := DockerFocus.DWELL_MSEC

var _made: Array[Window] = []


func after_each() -> void:
    for window in _made:
        window.free()
    _made.clear()


func _docker(at: Vector2i, size: Vector2i) -> Window:
    var window := DockerWindow.new()
    window.position = at
    window.size = size
    _made.append(window)
    return window


## What the focus does after a motion at *at* and *now* ticks, with *arrival*
## told of it first, as `DockerFocus._on_host_input` does.
func _motion(arrival: DockerFocus.Arrival, stack: Array[Window], focused: Window, at: Vector2, now: int) -> Window:
    arrival.note(DockerFocus.window_under(stack, at), at, now)
    return DockerFocus.follow(stack, focused, at, Callable(), arrival.stands_off)


## Tab brings the Colour docker back under a resting pointer. The hand twitches
## by a few pixels, and the keyboard stays with the canvas until the dwell.
func test_a_docker_shown_under_a_resting_pointer_stands_off_until_the_dwell() -> void:
    var color := _docker(Vector2i(1200, 100), Vector2i(300, 400))
    color.visible = false
    var stack: Array[Window] = [color]
    var arrival := DockerFocus.Arrival.new()

    assert_null(_motion(arrival, stack, null, Vector2(1300, 200), 1000), "With the docker hidden the canvas has the keyboard")
    color.visible = true
    assert_null(
        _motion(arrival, stack, null, Vector2(1303, 202), 1100),
        "A twitch inside a docker that appeared under the pointer leaves the keyboard with the canvas",
    )
    assert_null(
        _motion(arrival, stack, null, Vector2(1306, 204), 1100 + DWELL - 1),
        "and so does one a moment short of the dwell",
    )
    arrival.look(color, true, 1100 + DWELL)
    var after := DockerFocus.follow(stack, null, Vector2(1306, 204), Callable(), arrival.stands_off)
    assert_eq(after, color, "After the dwell with the pointer inside, the docker takes the keyboard")


## The ordinary way in is unchanged: tooltips and shortcuts over a docker the
## painter moved to are as they were.
func test_a_pointer_that_crosses_the_edge_takes_the_focus_at_once() -> void:
    var color := _docker(Vector2i(1200, 100), Vector2i(300, 400))
    var stack: Array[Window] = [color]
    var arrival := DockerFocus.Arrival.new()

    assert_null(_motion(arrival, stack, null, Vector2(1190, 200), 1000), "Outside the docker the canvas has it")
    assert_eq(_motion(arrival, stack, null, Vector2(1205, 200), 1010), color, "The first motion across the edge takes the focus")


## Leaving the docker that appeared and coming back is a crossing like any other.
func test_leaving_and_coming_back_takes_the_focus() -> void:
    var color := _docker(Vector2i(1200, 100), Vector2i(300, 400))
    color.visible = false
    var stack: Array[Window] = [color]
    var arrival := DockerFocus.Arrival.new()

    _motion(arrival, stack, null, Vector2(1210, 200), 1000)
    color.visible = true
    assert_null(_motion(arrival, stack, null, Vector2(1205, 200), 1010), "The docker that appeared stands off")
    assert_null(_motion(arrival, stack, null, Vector2(1190, 200), 1020), "the pointer leaves it for the canvas")
    assert_eq(_motion(arrival, stack, null, Vector2(1205, 200), 1030), color, "and coming back across its edge takes the focus")


## A docker moved or resized under the pointer is one the pointer never crossed
## into, and a press in it lifts the stand-off as the engine's press gives it
## the focus.
func test_a_docker_moved_under_the_pointer_stands_off_until_a_press() -> void:
    var layers := _docker(Vector2i(100, 100), Vector2i(300, 300))
    var stack: Array[Window] = [layers]
    var arrival := DockerFocus.Arrival.new()

    _motion(arrival, stack, null, Vector2(800, 500), 1000)
    layers.position = Vector2i(700, 400)
    assert_null(_motion(arrival, stack, null, Vector2(802, 501), 1010), "A docker moved under the pointer stands off")
    arrival.pressed()
    assert_eq(
        DockerFocus.follow(stack, null, Vector2(802, 501), Callable(), arrival.stands_off),
        layers,
        "and a press in it lifts that",
    )


## A docker opened on top of the one the pointer rests in has appeared too, and
## the one beneath, hidden under it, gives the keyboard to the canvas. Tab
## showing the dockers hands one of them the focus by itself, which is this case.
func test_a_docker_opened_over_the_focused_one_stands_off() -> void:
    var under := _docker(Vector2i(1200, 100), Vector2i(300, 400))
    var over := _docker(Vector2i(1150, 150), Vector2i(300, 300))
    over.visible = false
    var stack: Array[Window] = [under, over]
    var arrival := DockerFocus.Arrival.new()

    assert_eq(_motion(arrival, stack, null, Vector2(1300, 200), 1000), under, "The pointer is in the first docker")
    over.visible = true
    assert_null(
        _motion(arrival, stack, under, Vector2(1302, 201), 1010),
        "A docker opened over it takes nothing on the first twitch, and the canvas has the keyboard",
    )


## The case: the pointer rests in the Colour Picker, Tab hides the
## dockers and Tab shows them again, with no motion in between. Only the look
## once a frame sees the docker come and go under the resting pointer.
func test_tab_hiding_and_showing_the_docker_under_a_resting_pointer() -> void:
    var color := _docker(Vector2i(1600, 80), Vector2i(310, 390))
    var stack: Array[Window] = [color]
    var arrival := DockerFocus.Arrival.new()
    var at := Vector2(1750, 300)

    _motion(arrival, stack, null, Vector2(900, 500), 1000)
    assert_eq(_motion(arrival, stack, null, at, 1010), color, "Crossing into the docker takes the keyboard")
    color.visible = false
    arrival.look(DockerFocus.window_under(stack, at), true, 1100)
    color.visible = true
    arrival.look(DockerFocus.window_under(stack, at), true, 1200)
    assert_null(
        _motion(arrival, stack, null, at + Vector2(3, 2), 1250),
        "A twitch after the second Tab leaves the keyboard with the canvas",
    )
    arrival.look(DockerFocus.window_under(stack, at + Vector2(3, 2)), true, 1200 + DWELL)
    var after := DockerFocus.follow(stack, null, at + Vector2(3, 2), Callable(), arrival.stands_off)
    assert_eq(after, color, "and the look at the end of the dwell hands it over")


## A docker dragged by its bar moves with the pointer under a held button, which
## is no arrival.
func test_a_look_with_a_button_held_finds_no_arrival() -> void:
    var layers := _docker(Vector2i(100, 100), Vector2i(300, 300))
    var stack: Array[Window] = [layers]
    var arrival := DockerFocus.Arrival.new()

    _motion(arrival, stack, null, Vector2(800, 500), 1000)
    layers.position = Vector2i(700, 400)
    arrival.look(DockerFocus.window_under(stack, Vector2(800, 500)), false, 1010)
    assert_false(arrival.stands_off(layers), "A look under a held button marks nothing")
