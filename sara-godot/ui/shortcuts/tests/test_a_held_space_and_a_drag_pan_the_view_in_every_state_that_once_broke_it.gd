## A held Space and a drag pan the view, in each of the states that have
## broken it before.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Space has stopped panning before, each time by a different cause. It
## selected the Pan tool when pressed, but the drag did not move the view. This suite reads
## that the view moves, not only that the tool is Pan while the key is held.
##
## **Driven as a painter does it.** The key goes through
## `Input.parse_input_event` to a node that hands the root's unhandled input to
## a shortcut router, `Main`'s one line, and the router watches the docker's
## window as it watches every window. The mouse goes the way `Window` hands an
## event the display server delivered, its input signal first and then into the
## viewport, with the dockers embedded. The
## press, every motion and the release are real events with a position and a
## relative, and nothing here calls the tool machine.
##
## **The five states** are: a button holding the
## keyboard, a dialog just closed, a brush stroke just finished, a floating
## docker clicked, and the tool options bar synced and clicked. Each starts from
## the brush in hand, holds Space, drags across the canvas, lets go of both, and
## reads that the view moved by the drag's travel and the brush is back.
extends "res://tests/test_framework.gd"

## Real windows go in the tree, and the brush needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")

## How far the drag goes, and the step between its motions.
const REACH := 120.0
const STEP := 10.0


## Hands the root's unhandled input to the router, which is `Main`'s one line.
class Forward:
    extends Node

    var router: ShortcutRouter = null

    func _unhandled_input(event: InputEvent) -> void:
        router.handle_viewport_input(event, get_viewport())


var _was_embedding: bool = false
var _host: Control = null
var _canvas: Node = null
var _router: ShortcutRouter = null
var _saved_events: Dictionary = {}


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    SaShortcutStore.capture_defaults()
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    SaCursorPolicy.forget_pointer_device()
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Control.new()
    _host.name = "U116Host"
    _host.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _host.size = Vector2(tree.root.size)
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    _canvas.bind_tools(Fixtures.make_tool_registry())
    _canvas.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _router = ShortcutRouter.new()
    var machine: ToolMachine = _canvas.tool_machine
    _router.tool_machine_provider = func() -> ToolMachine: return machine
    _host.add_child(_router)
    var forward := Forward.new()
    forward.router = _router
    _host.add_child(forward)
    machine.set_active_tool(&"brush")


func after_each() -> void:
    SaPointerDevice.suite_pointer = null
    if _host != null:
        _host.free()
    _host = null
    _canvas = null
    _router = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


## Nothing before it: the plain case every other state is measured against.
func test_space_and_a_drag_pan_the_view_on_a_fresh_canvas() -> void:
    _assert_space_pans("on a fresh canvas")


## A button that held the keyboard took Space as
## `ui_accept`, so the key reopened what the button opens and never reached the
## router. Sara's buttons keep the keyboard off themselves, and this one is
## given it anyway, the worst case. The engine's button answers `ui_accept` on
## the key's release, so the press reaches the router and the drag pans, and
## the release still presses the button, which is why Sara's buttons say
## `FOCUS_NONE`. This suite reads the pan, not the button.
func test_space_pans_with_a_button_holding_the_keyboard() -> void:
    var button := Button.new()
    button.text = "Edit Brush"
    button.focus_mode = Control.FOCUS_ALL
    button.position = Vector2(8, 8)
    _host.add_child(button)
    button.grab_focus()
    assert_eq(_host.get_viewport().gui_get_focus_owner(), button, "The button holds the keyboard")
    _assert_space_pans("with a button holding the keyboard")


## A dialog that went away left nothing focused, and Space pans after
## it.
func test_space_pans_after_a_dialog_was_closed() -> void:
    var dialog := Window.new()
    dialog.title = "A dialog"
    dialog.size = Vector2i(200, 120)
    dialog.position = Vector2i(40, 40)
    var ok := Button.new()
    ok.text = "OK"
    dialog.add_child(ok)
    _host.add_child(dialog)
    _router.watch_window(dialog)
    dialog.grab_focus()
    ok.grab_focus()
    dialog.hide()
    _assert_space_pans("after a dialog was closed")


## A stroke just finished leaves the brush holding nothing that the pan's
## press, drag and release could meet.
func test_space_pans_after_a_stroke() -> void:
    var at := _middle() - Vector2(REACH, 40)
    _hand(_left(true), at)
    for x: float in range(STEP, REACH + 1.0, STEP):
        _hand(_motion(MOUSE_BUTTON_MASK_LEFT, Vector2(STEP, 0)), at + Vector2(x, 0))
    _hand(_left(false), at + Vector2(REACH, 0))
    _assert_space_pans("after a stroke")


## A floating docker holds the subwindow focus once clicked, and the keys go
## to its window and from there to the router.
func test_space_pans_after_a_floating_docker_was_clicked() -> void:
    var docker := Window.new()
    docker.name = "U116Docker"
    docker.borderless = true
    docker.size = Vector2i(120, 80)
    docker.position = Vector2i(16, 16)
    var panel := Panel.new()
    panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    docker.add_child(panel)
    _host.add_child(docker)
    _router.watch_window(docker)
    var inside := Vector2(docker.position) + Vector2(40, 30)
    _hand(_left(true), inside)
    _hand(_left(false), inside)
    assert_true(docker.has_focus(), "The click leaves the docker holding the focus")
    _assert_space_pans("with a floating docker clicked")


## A sync of the tool options bar gave a row the keyboard, and
## the next Space pressed it. The bar here is the real one, synced by the tool
## changes and clicked on its first button.
func test_space_pans_after_the_tool_options_bar_synced_and_was_clicked() -> void:
    var machine: ToolMachine = _canvas.tool_machine
    var bar := ToolOptionsBar.new()
    bar.target_tool_machine = machine
    _host.add_child(bar)
    bar.position = Vector2.ZERO
    bar.size = Vector2(_host.size.x, 40)
    bar.bind_registries(Fixtures.make_registries().blend_modes)
    machine.set_active_tool(&"eyedropper")
    machine.set_active_tool(&"brush")
    bar.sync_row_enabled()
    var row := _first_button(bar)
    assert_not_null(row, "The bar has a button to click")
    if row != null:
        _hand(_left(true), row.get_global_rect().get_center())
        _hand(_left(false), row.get_global_rect().get_center())
    var owner := _host.get_viewport().gui_get_focus_owner()
    assert_false(owner is BaseButton, "No button of the bar holds the keyboard after the click")
    _assert_space_pans("after the tool options bar synced")


## The case that reproduces it: Space pressed after the button went
## down, with a stroke under way. The pan came into the hand with no press of
## its own and the drag moved nothing until the button went up and down again.
## The machine hands it a press where the pointer is now.
func test_space_pressed_after_the_button_went_down_pans_the_drag() -> void:
    var machine: ToolMachine = _canvas.tool_machine
    var view: SaView = machine.surface.view
    var start := _middle() - Vector2(REACH / 2.0, 0)
    _hand(_left(true), start)
    _hand(_motion(MOUSE_BUTTON_MASK_LEFT, Vector2(STEP, 0)), start + Vector2(STEP, 0))
    _key(KEY_SPACE, true)
    assert_eq(machine.active_tool_name, &"pan", "Space held during a stroke puts the pan in the hand")
    var before := view.get_pan()
    var travelled := 0.0
    for x: float in range(2.0 * STEP, REACH + 1.0, STEP):
        _hand(_motion(MOUSE_BUTTON_MASK_LEFT, Vector2(STEP, 0)), start + Vector2(x, 0))
        travelled += STEP
    _hand(_left(false), start + Vector2(REACH, 0))
    assert_almost_eq(view.get_pan().x - before.x, travelled, 0.01, "and the drag that goes on moves the view by its travel")
    _key(KEY_SPACE, false)
    assert_eq(machine.active_tool_name, &"brush", "and letting go of Space hands the brush back")
    assert_eq(machine._drag.last_line, "", "A drag that panned prints no line")


## The way that reproduced in the running app: Space pressed over the canvas, a
## click into a dialog, and Space let go there. The dialog keeps a plain key, so
## the machine never heard the release and the pan stayed in the hand with no
## key down. The next event that is no key puts the brush back.
func test_space_let_go_over_a_dialog_hands_the_brush_back() -> void:
    var machine: ToolMachine = _canvas.tool_machine
    # A small dialog of Sara's own kind, which keeps a plain key for its controls.
    var dialog := SaRadiusDialog.new("U116Dialog")
    dialog.position = Vector2i(16, 16)
    _host.add_child(dialog)
    _router.watch_window(dialog)
    var inside := Vector2(dialog.position) + Vector2(120, 100)
    # A window shown takes the focus. The engine's rule for an unfocusable one,
    # which gives up the focus it held, hands it back to the main window.
    dialog.unfocusable = true
    dialog.grab_focus()
    dialog.unfocusable = false
    assert_false(dialog.has_focus(), "The main window has the keyboard")
    _key(KEY_SPACE, true)
    assert_eq(machine.active_tool_name, &"pan", "Space held over the canvas puts the pan in the hand")
    _hand(_left(true), inside)
    _hand(_left(false), inside)
    assert_true(dialog.has_focus(), "The click hands the dialog the keyboard")
    _key(KEY_SPACE, false)
    _hand(_motion(0, Vector2(STEP, 0)), _middle())
    assert_eq(machine.active_tool_name, &"brush", "and once Space is up the next motion hands the brush back")
    dialog.hide()
    _assert_space_pans("after Space was let go over a dialog")


## The row's line: a drag under the pan that moved nothing says so in the log,
## with what the machine heard. Here the press never reached the machine, as a
## press a control or a window took would not, and the motions come anyway.
func test_a_drag_under_the_pan_that_moves_nothing_prints_a_line() -> void:
    var machine: ToolMachine = _canvas.tool_machine
    var view: SaView = machine.surface.view
    _key(KEY_SPACE, true)
    var before := view.get_pan()
    var start := _middle()
    for x: float in range(STEP, REACH + 1.0, STEP):
        _hand(_motion(MOUSE_BUTTON_MASK_LEFT, Vector2(STEP, 0)), start + Vector2(x, 0))
    _hand(_motion(0, Vector2(STEP, 0)), start + Vector2(REACH + STEP, 0))
    _key(KEY_SPACE, false)
    assert_eq(view.get_pan(), before, "A drag whose press the pan never heard moves nothing")
    var line: String = machine._drag.last_line
    assert_true(line.begins_with(SaNavigationDrag.LINE), "and prints the line: %s" % line)
    assert_true(line.contains("press heard false"), "which says the machine heard no press")
    assert_true(line.contains("the pan tool"), "and names the tool")


# --- The gesture ----------------------------------------------------------------


## Holds Space, drags across the canvas's middle, lets go of the button and the
## key, and reads the view moved by the travel and the brush back in the hand.
func _assert_space_pans(where: String) -> void:
    var machine: ToolMachine = _canvas.tool_machine
    var view: SaView = machine.surface.view
    _key(KEY_SPACE, true)
    assert_eq(machine.active_tool_name, &"pan", "Space held %s puts the pan in the hand" % where)
    var before := view.get_pan()
    var start := _middle() - Vector2(REACH / 2.0, 0)
    _hand(_left(true), start)
    var travelled := 0.0
    for x: float in range(STEP, REACH + 1.0, STEP):
        _hand(_motion(MOUSE_BUTTON_MASK_LEFT, Vector2(STEP, STEP / 2.0)), start + Vector2(x, x / 2.0))
        travelled += STEP
    _hand(_left(false), start + Vector2(REACH, REACH / 2.0))
    var moved := view.get_pan() - before
    assert_almost_eq(moved.x, travelled, 0.01, "and a drag %s moves the view across by its travel" % where)
    assert_almost_eq(moved.y, travelled / 2.0, 0.01, "and down by its travel")
    _key(KEY_SPACE, false)
    assert_eq(machine.active_tool_name, &"brush", "and letting go of Space %s hands the brush back" % where)


# --- Helpers --------------------------------------------------------------------


## The middle of the canvas's control, in the main window's space.
func _middle() -> Vector2:
    return (_canvas.control_node as Control).get_global_rect().get_center()


func _first_button(node: Node) -> BaseButton:
    for child: Node in node.find_children("*", "BaseButton", true, false):
        var button := child as BaseButton
        if button.is_visible_in_tree() and button.get_global_rect().size.x > 0.0:
            return button
    return null


## A press or release of *code* through the engine, which hands it to the GUI
## and then to whatever `_unhandled_input` or window signal comes next.
func _key(code: Key, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.physical_keycode = code
    event.pressed = pressed
    Input.parse_input_event(event)
    Input.flush_buffered_events()


func _left(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    return event


func _motion(mask: int, relative: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.button_mask = mask
    event.relative = relative
    event.pressure = 0.6 if mask != 0 else 0.0
    return event


## *event* at *at*, in the main window's logical space, handed to the root the
## way `Window` hands an event the display server delivered: its input signal
## first, in the window's own space, then into the viewport.
func _hand(event: InputEventMouse, at: Vector2) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var to_desktop: Transform2D = SaPointerDevice.desktop_transform(root)
    SaPointerDevice.suite_pointer = to_desktop * at
    event.position = root.get_final_transform() * at
    event.global_position = event.position
    root.window_input.emit(event)
    root.push_input(event)
