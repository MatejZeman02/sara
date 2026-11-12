## A docker resizes under a pen or a finger on a tablet.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Resizing needs a better way on a tablet. The grip at a
## docker's bottom right was twelve logical pixels square on every platform,
## which a pen tip misses and a finger cannot find. On Android it is now
## twenty-four. Here the touch is pushed into the docker's window as a
## `InputEventScreenTouch` at each start, so the window's own hit test decides
## whether the grip takes it, and the drag after it is a `InputEventScreenDrag`.
## With the platform taken as Linux the grip is twelve, as before.
extends "res://tests/test_framework.gd"

## The window the docker stands in and where it opens.
const SCREEN := Vector2i(1280, 1024)
const AT := Vector2i(100, 200)
const OPENED := Vector2i(300, 400)

## How far from the corner a touch may start and still take the grip.
const REACH := 16

## How far each drag pulls, right and down.
const PULL := Vector2(60, 80)

var _kept_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A window added outside the screen below would map a real OS window.
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U376GripHostTest"
    EventBus.add_child(_host)


func after_each() -> void:
    DockerDragHandle.capture_pointer = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


## A docker-shaped window, embedded in a screen, with the grip built for *platform*.
func _docker_on(platform: String) -> Window:
    var screen := SubViewport.new()
    screen.size = SCREEN
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    var window := Window.new()
    window.borderless = true
    window.min_size = Vector2i(80, 60)
    window.position = AT
    window.size = OPENED
    screen.add_child(window)
    var resizer := DockerResizer.new(window, platform)
    window.add_child(resizer)
    return window


## One touch at *start* in the window's own pixels, dragged by *by*, as a
## finger does it: a press, one drag, a lift. The pointer the grip reads is the
## same place in the screen's space, which a touch on a device moves with it.
func _touch_drag(window: Window, start: Vector2, by: Vector2) -> void:
    var in_screen := Vector2(window.position) + start
    DockerDragHandle.capture_pointer = in_screen
    var press := InputEventScreenTouch.new()
    press.index = 0
    press.position = start
    press.pressed = true
    window.push_input(press)
    DockerDragHandle.capture_pointer = in_screen + by
    var drag := InputEventScreenDrag.new()
    drag.index = 0
    drag.position = start + by
    drag.relative = by
    window.push_input(drag)
    var lift := InputEventScreenTouch.new()
    lift.index = 0
    lift.position = start + by
    lift.pressed = false
    window.push_input(lift)
    DockerDragHandle.capture_pointer = null


func test_the_grip_is_twenty_four_on_android_and_twelve_on_linux() -> void:
    assert_eq(DockerResizer.side_for("Android"), 24.0, "Android's grip is twice the desktop's")
    assert_eq(DockerResizer.side_for("Linux"), 12.0, "and Linux's is twelve, as it was")
    assert_eq(DockerResizer.side_for("Windows"), 12.0, "and so is Windows'")
    var linux := _docker_on("Linux")
    var grip := linux.get_node("DockerResizer") as Control
    assert_eq(grip.size, Vector2(12, 12 + DockerResizer.GAP), "The grip built on Linux stands twelve square under its clear band")


## Every start within sixteen of the corner, along both edges and the diagonal,
## takes the grip, and the docker grows by the pull.
func test_on_android_a_touch_within_sixteen_of_the_corner_resizes_the_docker() -> void:
    var corner := Vector2(OPENED)
    for off: Vector2 in [Vector2(1, 1), Vector2(REACH, 1), Vector2(1, REACH), Vector2(8, 12), Vector2(REACH, REACH)]:
        var window := _docker_on("Android")
        _touch_drag(window, corner - off, PULL)
        assert_eq(window.size, OPENED + Vector2i(PULL), "A touch %s from the corner pulled the docker to %s" % [off, window.size])
        assert_eq(window.position, AT, "and its top-left stayed")


## The same touches on Linux miss the grip once they are past its twelve, so
## the desktop keeps the grip it had.
func test_on_linux_the_grip_is_still_twelve() -> void:
    var corner := Vector2(OPENED)
    var near := _docker_on("Linux")
    _touch_drag(near, corner - Vector2(6, 6), PULL)
    assert_eq(near.size, OPENED + Vector2i(PULL), "A touch six from the corner still takes Linux's grip")
    var far := _docker_on("Linux")
    _touch_drag(far, corner - Vector2(REACH, REACH), PULL)
    assert_eq(far.size, OPENED, "and one sixteen away misses it and leaves the docker as it was")
