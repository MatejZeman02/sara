## A stroke made with the right button, an extra button or a
## barrel button follows the pointer across a docker.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A button bound to Eraser while held makes its stroke from the motions of its
## drag, and a docker holding the subwindow focus is handed every mouse event
## before the GUI, so the canvas's `gui_input` heard none of a drag that began
## while a docker held it, and the middle button's capture at the window was the
## only one there was. The window now follows the drag of every button it took
## the press of, wherever it lands.
##
## **The route the engine hands an event over**, as the tool machine's suite
## does it: each event is emitted on the root window's `window_input` and then
## pushed into it, with the dockers embedded, so a docker holding the focus is
## handed it before anything else. A new embedded window has the focus from the
## moment it is shown, as a docker does from startup, so each drag is made twice,
## with the focus held and given up. The tool machine counts the motions it is
## handed, so each drag below asks for exactly the number it sent, once each.
## The running app's proof is
## `scenarios/a-stroke-made-with-the-right-button-an-extra-button-or-a-barrel.json`.
extends "res://tests/test_framework.gd"

## Real windows go in the tree, and the eraser needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")

## The buttons a stroke can be made with, with the id their row is stored under
## and the bit the motions of their drag carry.
const BUTTONS: Array[Dictionary] = [
    {"id": "right", "index": MOUSE_BUTTON_RIGHT, "mask": MOUSE_BUTTON_MASK_RIGHT},
    {"id": "extra1", "index": MOUSE_BUTTON_XBUTTON1, "mask": MOUSE_BUTTON_MASK_MB_XBUTTON1},
    {"id": "extra2", "index": MOUSE_BUTTON_XBUTTON2, "mask": MOUSE_BUTTON_MASK_MB_XBUTTON2},
]
## How far either side of the docker the drag runs, and the step between motions.
const REACH := 200.0
const STEP := 10.0


## A docker over the middle of the canvas that counts what reaches its panel,
## a bare window since `render` names no docker of `ui`.
class Docker:
    extends Window

    var motions: int = 0
    var presses: int = 0

    func _init() -> void:
        name = "B2Docker"
        borderless = true
        size = Vector2i(120, 80)
        var panel := Control.new()
        panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        panel.gui_input.connect(_count)
        add_child(panel)

    func _count(event: InputEvent) -> void:
        if event is InputEventMouseMotion:
            motions += 1
        elif event is InputEventMouseButton and event.pressed:
            presses += 1


var _stored: Dictionary = {}
var _was_embedding: bool = false
var _host: Control = null
var _canvas: Node = null
var _docker: Docker = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _stored = SaSettings.pen_buttons.duplicate()
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    SaCursorPolicy.forget_pointer_device()
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Control.new()
    _host.name = "B2Host"
    _host.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _host.size = Vector2(tree.root.size)
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    _canvas.bind_tools(Fixtures.make_tool_registry())
    _canvas.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _docker = Docker.new()
    _docker.position = Vector2i(_middle() - Vector2(60, 40))
    _host.add_child(_docker)


func after_each() -> void:
    SaPointerDevice.suite_pointer = null
    SaSettings.pen_buttons = _stored
    if _host != null:
        _host.free()
    _host = null
    _canvas = null
    _docker = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


## The ask: every motion of the drag, the stretch over the docker included, is
## the tool's, whether the docker is the window holding the focus or not.
func test_a_drag_across_a_docker_reaches_the_tool_in_every_motion() -> void:
    for button: Dictionary in BUTTONS:
        for focused: bool in [false, true]:
            _bind(button["id"], SaSettingsPenButtons.ERASER)
            var where := "the %s button, the docker %s" % [button["id"], "focused" if focused else "not focused"]
            var machine := _machine()
            var before := machine.active_tool_name
            _focus(focused)
            machine.reset_motion_samples()
            _press(button, _middle() - Vector2(REACH, 0))
            assert_eq(machine.active_tool_name, &"eraser", "%s swaps the eraser in" % where)
            var sent := 0
            for x: float in range(-REACH, REACH + 1.0, STEP):
                _move(button, _middle() + Vector2(x, 0))
                sent += 1
            assert_eq(machine.motion_samples_seen, sent, "%s: the tool hears all %d motions, once each" % [where, sent])
            _release(button, _middle() + Vector2(REACH, 0))
            assert_eq(machine.active_tool_name, before, "%s: the release hands the tool back" % where)
            assert_eq(_canvas._dragging, 0, "%s: and the window follows nothing after it" % where)


## A button bound to Pan moves the view by the drag's
## own travel, across the docker as well as either side of it.
func test_a_drag_bound_to_pan_moves_the_view_across_a_docker() -> void:
    for button: Dictionary in BUTTONS:
        _bind(button["id"], SaSettingsPenButtons.PAN)
        _focus(true)
        var view: SaView = _machine().surface.view
        var start := view.get_pan()
        var travelled := 0.0
        _press(button, _middle() - Vector2(REACH, 0))
        for x: float in range(-REACH, REACH + 1.0, STEP):
            _move(button, _middle() + Vector2(x, 0), Vector2(STEP, 0))
            travelled += STEP
        _release(button, _middle() + Vector2(REACH, 0))
        var panned := view.get_pan().x - start.x
        assert_almost_eq(panned, travelled, 0.01, "The %s button's drag pans the view all the way" % button["id"])


## A release that lands over the docker still ends the drag, and the motions
## after it are no longer the tool's.
func test_a_drag_ends_on_its_release_wherever_it_lands() -> void:
    for button: Dictionary in BUTTONS:
        _bind(button["id"], SaSettingsPenButtons.ERASER)
        var machine := _machine()
        _press(button, _middle() - Vector2(REACH, 0))
        _move(button, _middle())
        _release(button, _middle())
        assert_eq(_canvas._dragging, 0, "The %s button's release over the docker ends the drag" % button["id"])
        machine.reset_motion_samples()
        _hand(_motion(MOUSE_BUTTON_MASK_LEFT), _middle() + Vector2(STEP, 0))
        assert_eq(machine.motion_samples_seen, 0, "and the window hands the tool no motion after it")


## A press on a docker is the docker's, and so is the drag it begins, out over
## the canvas and back. The canvas takes no press the docker covers, so it
## follows nothing.
func test_a_drag_begun_on_a_docker_is_still_the_dockers() -> void:
    for button: Dictionary in BUTTONS:
        _bind(button["id"], SaSettingsPenButtons.ERASER)
        var machine := _machine()
        var before := machine.active_tool_name
        _focus(true)
        _docker.motions = 0
        _docker.presses = 0
        machine.reset_motion_samples()
        _press(button, _middle())
        assert_eq(_canvas._dragging, 0, "The %s press on the docker is not the canvas's to follow" % button["id"])
        for x: float in range(0.0, REACH + 1.0, STEP):
            _move(button, _middle() + Vector2(x, 0))
        assert_eq(machine.motion_samples_seen, 0, "so the tool hears none of its drag")
        assert_true(_docker.motions > 0, "which the docker hears")
        assert_eq(_docker.presses, 1, "after the press it took")
        _release(button, _middle() + Vector2(REACH, 0))
        assert_eq(machine.active_tool_name, before, "and the tool in hand is the one it was")


## The signal fires before the cursor overlay has seen a motion, so a tool asked
## where the pointer is was a motion behind and the stroke ended a point short.
## The pointer is where the motion landed by the time the tool is handed it.
func test_a_tool_asked_where_the_pointer_is_is_told_where_the_motion_landed() -> void:
    for button: Dictionary in BUTTONS:
        _bind(button["id"], SaSettingsPenButtons.ERASER)
        _focus(true)
        SaCursorPolicy.forget_pointer_device()
        _press(button, _middle() - Vector2(REACH, 0))
        var canvas: Control = _canvas.canvas
        for x: float in [-REACH + STEP, -STEP, 0.0, STEP, REACH]:
            var at := _middle() + Vector2(x, 0)
            _hand(_motion(button["mask"]), at, false)
            # The place `_hand` gave the display server's pointer is not the pen's.
            SaPointerDevice.suite_pointer = null
            var want := canvas.get_global_transform_with_canvas().affine_inverse() * at
            var got := SaCursorPolicy.pointer_in(canvas)
            assert_almost_eq(got.x, want.x, 0.01, "The %s button's motion at %d is the pointer a tool reads" % [button["id"], x])
        _release(button, _middle() + Vector2(REACH, 0))


# --- Helpers --------------------------------------------------------------------


## The docker holding the subwindow focus or not. A new embedded window has it
## from the moment it is shown, as a docker does from startup.
func _focus(held: bool) -> void:
    if held:
        _docker.grab_focus()
    else:
        # The engine's own rule for an unfocusable window, which gives up whatever
        # focus it held and takes none, is the one call that hands it back.
        _docker.unfocusable = true
        _docker.grab_focus()
        _docker.unfocusable = false
    assert_eq(_docker.has_focus(), held, "The docker %s the focus" % ("holds" if held else "does not hold"))


func _machine() -> ToolMachine:
    return _canvas.tool_machine


## The middle of the canvas's control, in the main window's space.
func _middle() -> Vector2:
    return (_canvas.control_node as Control).get_global_rect().get_center()


func _bind(button_id: String, action: String) -> void:
    var table := SaSettings.pen_buttons.duplicate()
    table[button_id] = action
    SaSettings.pen_buttons = table


func _press(button: Dictionary, at: Vector2) -> void:
    _hand(_button(button, true), at)


func _release(button: Dictionary, at: Vector2) -> void:
    _hand(_button(button, false), at)


func _move(button: Dictionary, at: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
    var event := _motion(button["mask"])
    event.relative = relative
    _hand(event, at)


func _button(button: Dictionary, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = button["index"]
    event.pressed = pressed
    event.button_mask = int(button["mask"]) if pressed else 0
    return event


func _motion(mask: int) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.button_mask = mask
    event.pressure = 0.6 if mask != 0 else 0.0
    event.tilt = Vector2(0.2, 0.1)
    return event


## *event* at *at*, in the main window's logical space, handed to the root the
## way `Window` hands an event the display server delivered: its input signal
## first, in the window's own space, then into the viewport unless *through* is
## false, which stops after the signal.
func _hand(event: InputEventMouse, at: Vector2, through: bool = true) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var to_desktop: Transform2D = SaPointerDevice.desktop_transform(root)
    SaPointerDevice.suite_pointer = to_desktop * at
    event.position = root.get_final_transform() * at
    event.global_position = event.position
    root.window_input.emit(event)
    if through:
        root.push_input(event)
