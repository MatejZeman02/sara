## The keyboard follows the pointer into a docker and back out to the canvas.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Godot hands an embedded docker the motion under the pointer only while that
## docker holds the subwindow focus, and a tooltip's timer starts from that
## motion, so a docker nobody had clicked showed no tooltip. The rule is
## focus follows the pointer both ways, and `DockerFocus.follow` is
## the decision. What these read is that decision over detached windows, because
## a `Window` outside the tree cannot be given the focus and one inside it would
## map a real OS window and hang the run. What the running app does with it is
## `scenarios/a-docker-shows-no-tooltip-until-it-is-clicked.json`.
extends "res://tests/test_framework.gd"

var _made: Array[Window] = []


func after_each() -> void:
    for window in _made:
        window.free()
    _made.clear()


func _docker(at: Vector2i, size: Vector2i) -> Window:
    return _keep(DockerWindow.new(), at, size)


func _plain(at: Vector2i, size: Vector2i) -> Window:
    return _keep(Window.new(), at, size)


func _keep(window: Window, at: Vector2i, size: Vector2i) -> Window:
    window.position = at
    window.size = size
    _made.append(window)
    return window


## After a stroke nothing holds the focus, and a hover over
## the Colour Picker has to hand it to the docker.
func test_a_docker_under_the_pointer_takes_the_focus() -> void:
    var color := _docker(Vector2i(1200, 100), Vector2i(300, 400))
    var stack: Array[Window] = [color]

    assert_eq(DockerFocus.follow(stack, null, Vector2(1300, 200)), color, "A hover over a docker nobody clicked takes its focus")
    assert_eq(DockerFocus.follow(stack, color, Vector2(1300, 200)), color, "and a docker already holding it keeps it")


## The other half of the rule. Null is the main window, which is where a shortcut
## typed over the canvas has to go.
func test_the_canvas_takes_the_focus_back() -> void:
    var color := _docker(Vector2i(1200, 100), Vector2i(300, 400))
    var stack: Array[Window] = [color]

    assert_null(DockerFocus.follow(stack, color, Vector2(600, 600)), "Leaving the docker for the canvas hands the focus back")
    assert_null(DockerFocus.follow(stack, color, Vector2(1501, 200)), "and a texel past its edge is already the canvas")
    assert_null(DockerFocus.follow([], null, Vector2(600, 600)), "With no docker at all nothing moves")


func test_the_focus_moves_from_docker_to_docker() -> void:
    var layers := _docker(Vector2i(1200, 500), Vector2i(300, 300))
    var color := _docker(Vector2i(1200, 100), Vector2i(300, 400))
    var stack: Array[Window] = [layers, color]

    var crossed := DockerFocus.follow(stack, color, Vector2(1300, 700))
    assert_eq(crossed, layers, "The pointer crossing into the next docker takes it there")


## The stacking order is the engine's array, so the later of two overlapping
## dockers is the one on top and the one a press would land on.
func test_the_topmost_of_two_overlapping_dockers_takes_it() -> void:
    var under := _docker(Vector2i(700, 200), Vector2i(400, 400))
    var over := _docker(Vector2i(800, 300), Vector2i(400, 400))
    var stack: Array[Window] = [under, over]

    assert_eq(DockerFocus.window_under(stack, Vector2(900, 400)), over, "The later of the stack is on top")
    assert_eq(DockerFocus.follow(stack, null, Vector2(900, 400)), over, "and that is the docker the hover focuses")


## A popup closes on losing its focus, so a dropdown's list read over a docker
## would close under the pointer. A dialog holding the keyboard keeps it too.
func test_a_popup_or_a_dialog_holding_the_focus_keeps_it() -> void:
    var color := _docker(Vector2i(1200, 100), Vector2i(300, 400))
    var list := _plain(Vector2i(1250, 150), Vector2i(120, 300))
    var stack: Array[Window] = [color, list]

    assert_eq(DockerFocus.follow(stack, list, Vector2(1450, 450)), list, "A popup keeps the focus over its own docker")
    assert_eq(DockerFocus.follow(stack, list, Vector2(600, 600)), list, "and over the canvas")


## A window that is not a docker, under the pointer while a docker holds the
## focus, says nothing about where the keyboard should go, so the docker keeps it.
func test_a_window_that_is_not_a_docker_moves_nothing() -> void:
    var color := _docker(Vector2i(1200, 100), Vector2i(300, 400))
    var dialog := _plain(Vector2i(400, 300), Vector2i(300, 200))
    var stack: Array[Window] = [color, dialog]

    var kept := DockerFocus.follow(stack, color, Vector2(500, 400))
    assert_eq(kept, color, "An unfocused dialog under the pointer leaves the focus in the docker")
    assert_null(DockerFocus.follow(stack, null, Vector2(500, 400)), "and leaves it with the main window when that has it")


## The engine builds a tooltip's panel passthrough, and a docker's tooltip that
## hangs over the canvas would otherwise keep the focus in the docker.
func test_a_passthrough_window_is_not_under_the_pointer() -> void:
    var color := _docker(Vector2i(1200, 100), Vector2i(300, 400))
    var tip := _plain(Vector2i(1000, 450), Vector2i(400, 80))
    tip.mouse_passthrough = true
    var stack: Array[Window] = [color, tip]

    assert_null(DockerFocus.window_under(stack, Vector2(1100, 480)), "A tooltip's panel is not what the pointer is over")
    assert_null(DockerFocus.follow(stack, color, Vector2(1100, 480)), "so the canvas under it takes the focus back")
