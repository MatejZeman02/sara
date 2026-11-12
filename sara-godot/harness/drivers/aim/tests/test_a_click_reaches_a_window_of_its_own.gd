## A scenario's click reaches a docker that is a window of its own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## With embedded subwindows off every docker is
## a window of the operating system, and a `click` aimed at a control inside one
## was sent to the main window at the same point, where it painted a dab on the
## canvas. The driver now finds the window under the point, or the window a
## named control stands in, and hands the event to that window with the point
## made local to it.
##
## **The half that needs a window of its own is the capture**,
## `scenarios/a-scenarios-click-reaches-a-docker-that-is-a-window-of-its-own.json`,
## because a suite that adds a `Window` while the root does not embed maps a
## real OS window and stalls the run (`render/cursor/tests/test_a_window_of_its_own.gd`).
## What is here is everything an embedded window lets a suite reach: the hover
## a button needs before it takes a press, the hit test that finds the button,
## the arithmetic that carries a point into a docker and back, and the promise
## that a painter who embeds their dockers keeps every event in the main window.
extends "res://tests/test_framework.gd"

const PointerAim := preload("res://harness/drivers/aim/sa_pointer_aim.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")

const DOCKER_AT := Vector2i(400, 300)
const DOCKER_SIZE := Vector2i(240, 200)
const BUTTON_AT := Vector2(40, 30)
const BUTTON_SIZE := Vector2(60, 30)

var _host: Node = null
var _docker: Window = null
var _button: Button = null
var _previous_embedding: bool = true
var _run: CaptureRun = null
var _aim: SaPointerAim = null


## Adding a Window is only safe while the root embeds, so it is forced and put
## back. Parented to an autoload, because the runner calls this from its own
## `_ready` and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "D4TestHost"
    EventBus.add_child(_host)

    _docker = Window.new()
    _docker.name = "D4ProbeDocker"
    _docker.borderless = true
    _docker.position = DOCKER_AT
    _docker.size = DOCKER_SIZE
    _host.add_child(_docker)

    var panel := Control.new()
    panel.name = "D4ProbePanel"
    panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    _docker.add_child(panel)

    _button = Button.new()
    _button.name = "D4ProbeButton"
    _button.toggle_mode = true
    _button.position = BUTTON_AT
    _button.size = BUTTON_SIZE
    panel.add_child(_button)
    _docker.show()

    _run = CaptureRun.new()
    _aim = PointerAim.new(_run)


func after_each() -> void:
    _aim = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


func _root() -> Window:
    return (Engine.get_main_loop() as SceneTree).root


## The centre of the probe button, in root units.
func _button_in_root() -> Vector2:
    return Vector2(DOCKER_AT) + _button.get_global_rect().get_center()


func _press(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = _button.get_global_rect().get_center()
    event.global_position = event.position
    _docker.push_input(event, true)


## The fault's second half. The click reached the lock button's own window and
## the button in it, and the button did nothing, because a button takes a press
## only while it is hovered and nothing had hovered it. After the driver's hover
## the same press and release toggle it.
func test_a_hovered_button_takes_the_click() -> void:
    _aim.hover(_docker, _button_in_root())
    assert_true(_button.is_hovered(), "the driver told the button the pointer is over it")
    _press(true)
    _press(false)
    assert_true(_button.button_pressed, "and the click pressed it")


## The hover follows the pointer out again, as the display server's would, or a
## button the pointer left would go on taking presses meant for its neighbour.
func test_a_pointer_that_leaves_takes_the_hover_with_it() -> void:
    _aim.hover(_docker, _button_in_root())
    _aim.hover(_docker, Vector2(DOCKER_AT) + Vector2(200, 180))
    assert_false(_button.is_hovered(), "a point clear of the button ends its hover")
    _aim.hover(_docker, _button_in_root())
    _aim.hover(null, Vector2(1000, 800))
    assert_false(_button.is_hovered(), "and so does a point on the main window")


## The hit test finds the innermost control, passes over one that ignores the
## mouse, and gives a later sibling the point where two overlap, the order the
## engine draws them in.
func test_the_control_under_a_point_is_the_innermost_that_takes_the_mouse() -> void:
    var centre := _button.get_global_rect().get_center()
    assert_eq(PointerAim.control_under(_docker, centre), _button, "the button, not the panel under it")
    var veil := Label.new()
    veil.position = BUTTON_AT
    veil.size = BUTTON_SIZE
    veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _button.get_parent().add_child(veil)
    assert_eq(PointerAim.control_under(_docker, centre), _button, "a label over it that ignores the mouse is passed over")
    var cover := Button.new()
    cover.position = BUTTON_AT
    cover.size = BUTTON_SIZE
    _button.get_parent().add_child(cover)
    assert_eq(PointerAim.control_under(_docker, centre), cover, "a later sibling over it takes the point")
    assert_null(PointerAim.control_under(_docker, Vector2(-5, -5)), "a point outside the window is on nothing")


## A point carried into the docker and back lands where it started, which is
## what lets a step name a control inside a window of its own and aim at it.
func test_a_point_carried_into_a_docker_comes_back_to_itself() -> void:
    var root := _root()
    var local := PointerAim.local_in(root, _docker, _button_in_root())
    assert_eq(local, _button.get_global_rect().get_center(), "the root point is the button's centre in the docker")
    assert_eq(PointerAim.root_point_of(root, _docker, local), _button_in_root(), "and comes back to the root point")
    assert_eq(PointerAim.local_in(root, null, Vector2(12, 34)), Vector2(12, 34), "a point on the main window stays as it is")


## The promise to a painter who embeds their dockers: no window of their own is
## in the tree, so every point is the main window's and an event goes where it
## always went, with no window id and no hover kept by the driver.
func test_with_every_docker_embedded_every_point_is_the_main_windows() -> void:
    var root := _root()
    assert_null(PointerAim.window_under(root, _button_in_root()), "an embedded docker is reached through the main window")
    var key := InputEventKey.new()
    PointerAim.address_key(root, key)
    assert_eq(key.window_id, DisplayServer.MAIN_WINDOW_ID, "and keys go to the main window")
    var event := InputEventMouseButton.new()
    var target: Window = _aim.aim(event, _button_in_root())
    assert_null(target, "the click is aimed at the main window")
    assert_eq(event.window_id, DisplayServer.MAIN_WINDOW_ID, "and carries the main window's id")
    assert_eq(event.position, root.get_final_transform() * _button_in_root(), "at the physical point, as before")


## A name only picks a window of its own. An embedded docker is the main
## window's to reach, so a step that names a control in one still sends the
## event to the main window, which hands it on as it always did.
func test_a_named_embedded_window_is_reached_through_the_main_window() -> void:
    var event := InputEventMouseButton.new()
    var target: Window = _aim.aim(event, _button_in_root(), _docker)
    assert_null(target, "the event goes to the main window")
    assert_eq(event.window_id, DisplayServer.MAIN_WINDOW_ID, "and carries its id")
