## A press just after Tab, where a docker stood, paints nothing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Tab hides the dockers, and a click where the Size slider stood must not add a
## history step and paint a white dab under the pointer. Painting where the
## dockers were is what hiding them is for, so the canvas keeps that place. What goes is the moment the painter has not caught
## up with the Tab: each hidden docker's place is outlined for half a second, a
## press inside an outline is swallowed and the outline flashes, and once the
## outline has faded the canvas paints there as it does now.
##
## The whole route, `SaFocusMode` above a real `MainCanvas` in the root window
## and the press pushed in at the root, so what is held is that the press
## never reaches the tool machine rather than that a method answers no. The
## fade is the mode's own `_process`, stepped by hand because a suite has no
## frames. The route on the running app is
## `scenarios/a-press-just-after-tab-where-a-docker-stood-paints-nothing.json`.
##
## The brush takes its point from the pointer and not from the press, so each
## press puts [member SaPointerDevice.suite_pointer] where it lands first. On
## a desktop the live pointer can be nowhere near the canvas, and a press that
## should paint then lays no dab and closes no step.
extends "res://tests/test_framework.gd"

## The brush needs a RenderingDevice, and the window a display.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")

## Where the Size docker stood, inside the canvas's control, and a point of the
## canvas that no docker stood on.
const STOOD := Rect2(Vector2(400.0, 120.0), Vector2(200.0, 100.0))
const INSIDE := Vector2(450.0, 160.0)
const OUTSIDE := Vector2(150.0, 300.0)

var _host: Node = null
var _canvas: Node = null
var _focus: SaFocusMode = null
var _table: Array = []


func before_each() -> void:
    SaFocusMode.active = false
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "PressAfterTabTestHost"
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    _canvas.bind_tools(Fixtures.make_tool_registry())
    _canvas.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _focus = SaFocusMode.new()
    _host.add_child(_focus)
    var docker := Window.new()
    docker.name = "SizeDocker"
    _table = [{"id": "SizeDocker", "node": docker}]


func after_each() -> void:
    SaFocusMode.active = false
    SaPointerDevice.suite_pointer = null
    for config: Dictionary in _table:
        (config["node"] as Window).free()
    _table = []
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _canvas = null
    _focus = null


func test_a_press_at_once_where_a_docker_stood_starts_no_stroke() -> void:
    _tab()
    var steps := _steps()
    _press(INSIDE)
    assert_false(_canvas._capturing_stroke, "A press inside the outline does not take the pointer for a stroke")
    assert_false(_drawing(), "and the brush never began one")
    _release(INSIDE)
    assert_eq(_steps(), steps, "so the release closes nothing and no history step was added")


func test_a_press_outside_every_place_paints_at_once() -> void:
    _tab()
    var steps := _steps()
    _press(OUTSIDE)
    assert_true(_canvas._capturing_stroke, "A press outside every rectangle starts the stroke at once")
    _release(OUTSIDE)
    assert_eq(_steps(), steps + 1, "and closes it as a history step")


func test_after_the_fade_the_place_paints() -> void:
    _tab()
    _focus._process(SaFocusMode.OUTLINE_SECONDS + 0.1)
    var steps := _steps()
    _press(INSIDE)
    assert_true(_canvas._capturing_stroke, "Once the outline has faded a press there starts the stroke")
    _release(INSIDE)
    assert_eq(_steps(), steps + 1, "and closes it as a history step")


## The first press was swallowed, and the same place answers a second one the
## same way until the fade is over: the painter's hurry is not a click on the
## canvas however many times it is made.
func test_a_second_press_inside_the_fade_is_swallowed_too() -> void:
    _tab()
    var steps := _steps()
    for i: int in 3:
        _press(INSIDE)
        _release(INSIDE)
    assert_eq(_steps(), steps, "Three clicks inside the second add no step")


# --- Helpers --------------------------------------------------------------------


## Tab: the docker is open, so it is hidden, and its place is handed over.
func _tab() -> void:
    var window: Window = _table[0]["node"]
    window.visible = true
    _focus.toggle(_table, {"SizeDocker": STOOD})
    assert_true(_focus.outlines_showing(), "Tab outlines the place the docker stood")


func _drawing() -> bool:
    var tool_machine: ToolMachine = _canvas.tool_machine
    return tool_machine.active_tool != null and bool(tool_machine.active_tool.get("is_drawing"))


func _steps() -> int:
    var history: Object = _canvas.canvas.document.history
    return history.step_count() if history != null else -1


## In through the root window, the way the engine hands a click over, so the
## focus mode's `_input` sees it before the canvas's control does.
func _press(at: Vector2) -> void:
    _send(at, true)


func _release(at: Vector2) -> void:
    _send(at, false)


func _send(at: Vector2, pressed: bool) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var to_desktop: Transform2D = SaPointerDevice.desktop_transform(root)
    SaPointerDevice.suite_pointer = to_desktop * at
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    event.position = at
    event.global_position = at
    root.push_input(event)
