## A docker dragged past an edge stands partly outside with its strip in.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Dockers may leave the window border and stay on the place even when out of
## canvas. A drag of an embedded docker may take it past the
## left, the right and the bottom edge until only
## [constant SaDockerLayoutFit.STRIP_IN_REACH] of its title strip is left on
## the window, and it stops there. Each edge is driven like a hand on the bar
## of a docker embedded in a 1280 by 1024 window under a bar, once to a place
## partly outside and once on past where the strip would leave. The running app
## is `scenarios/a-floating-docker-may-stand-partly-past-the-window-s-edge-and-stays-where-it-was-put.json`.
extends "res://tests/test_framework.gd"

const HOST := Vector2i(1280, 1024)
const SIZE := Vector2i(300, 500)

## The first row below the bar at 1280 by 1024, `MainDockers.below_bar`.
const BAR := 79

const STRIP := SaDockerLayoutFit.STRIP_IN_REACH

## Where the bar is pressed, from the docker's corner.
const PRESS := Vector2(150, 10)

var _kept_inset: Callable = Callable()
var _kept_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    _kept_inset = SaDialogWindow.top_inset
    SaDialogWindow.top_inset = func() -> int: return BAR
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A window added outside the screen below would map a real OS window and
    # block the run, so the root embeds as well.
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U42DragHostTest"
    EventBus.add_child(_host)


func after_each() -> void:
    SaDialogWindow.top_inset = _kept_inset
    DockerDragHandle.capture_pointer = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


func test_past_the_right_edge_it_stands_partly_outside_and_then_stops() -> void:
    var window := _embedded(Vector2i(900, 200))
    _drag(window, Vector2(200, 0))
    assert_eq(window.position, Vector2i(1100, 200), "Where the pointer took it")
    assert_true(window.position.x + window.size.x > HOST.x, "Its right part is past the window's edge")
    assert_true(_strip_in(window), "and its strip is inside")
    _drag(window, Vector2(400, 0))
    assert_eq(window.position, Vector2i(HOST.x - STRIP.x, 200), "Dragged on, it stops")
    assert_true(_strip_in(window), "with the strip's head still inside")


func test_past_the_left_edge_it_stands_partly_outside_and_then_stops() -> void:
    var window := _embedded(Vector2i(100, 200))
    _drag(window, Vector2(-250, 0))
    assert_eq(window.position, Vector2i(-150, 200), "Where the pointer took it")
    assert_true(window.position.x < 0, "Its left part is past the window's edge")
    assert_true(_strip_in(window), "and its strip is inside")
    _drag(window, Vector2(-400, 0))
    assert_eq(window.position, Vector2i(STRIP.x - SIZE.x, 200), "Dragged on, it stops")
    assert_true(_strip_in(window), "with the strip's right end, its buttons, still inside")


func test_past_the_bottom_edge_it_stands_partly_outside_and_then_stops() -> void:
    var window := _embedded(Vector2i(400, 500))
    _drag(window, Vector2(0, 450))
    assert_eq(window.position, Vector2i(400, 950), "Where the pointer took it")
    assert_true(window.position.y + window.size.y > HOST.y, "Its lower part is past the window's foot")
    assert_true(_strip_in(window), "and its strip is inside")
    _drag(window, Vector2(0, 400))
    assert_eq(window.position, Vector2i(400, HOST.y - STRIP.y), "Dragged on, it stops")
    assert_true(_strip_in(window), "with the strip's whole height still inside")


## The top edge goes over the bar, because dockers can go anywhere, and stops at the window's
## own top row, where the whole strip is still in.
func test_its_top_goes_over_the_bar_and_stops_at_the_window_s_top() -> void:
    var window := _embedded(Vector2i(400, 300))
    _drag(window, Vector2(0, -600))
    assert_eq(window.position, Vector2i(400, 0), "It stops at the window's top row, over the bar")


## A dialog is not part of a layout and keeps the whole rule it opens with.
func test_a_dialog_dragged_past_the_right_edge_stays_whole() -> void:
    var window := _embedded(Vector2i(900, 200))
    _drag(window, Vector2(400, 0), false)
    assert_eq(window.position, Vector2i(HOST.x - SIZE.x, 200), "Its right edge rests on the window's")


## Presses *window*'s bar, moves the pointer by *by* and lets go, through the
## bar's `gui_input` as a hand does it.
func _drag(window: Window, by: Vector2, part_of_layout: bool = true) -> void:
    var bar := Control.new()
    _host.add_child(bar)
    var handle := DockerDragHandle.new(part_of_layout)
    _host.add_child(handle)
    handle.bind(window, bar)
    var press := Vector2(window.position) + PRESS
    DockerDragHandle.capture_pointer = press
    bar.gui_input.emit(_button(true))
    DockerDragHandle.capture_pointer = press + by
    bar.gui_input.emit(InputEventMouseMotion.new())
    bar.gui_input.emit(_button(false))
    handle.free()
    bar.free()


## Whether at least [constant STRIP] of *window*'s title strip, or all of a
## narrower one, stands on the window below the bar.
func _strip_in(window: Window) -> bool:
    var strip := Rect2i(window.position, Vector2i(window.size.x, STRIP.y))
    var on := strip.intersection(Rect2i(0, BAR, HOST.x, HOST.y - BAR))
    return on.size.x >= mini(STRIP.x, window.size.x) and on.size.y == STRIP.y


## A window embedded in a 1280 by 1024 screen.
func _embedded(at: Vector2i) -> Window:
    var screen := SubViewport.new()
    screen.size = HOST
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    var window := Window.new()
    window.min_size = Vector2i(80, 60)
    window.position = at
    window.size = SIZE
    screen.add_child(window)
    return window


static func _button(down: bool) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = down
    return button
