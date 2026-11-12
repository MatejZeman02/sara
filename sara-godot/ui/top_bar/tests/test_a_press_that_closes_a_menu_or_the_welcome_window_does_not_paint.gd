## A press on the canvas that closes a top menu, the last title's
## list or the Welcome window closes it and paints nothing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## With a menu open or the Welcome window up, a press on the canvas must not
## paint a stroke as well as close it. Krita closes the menu and swallows the
## press.
##
## **The whole route, the way the engine hands a press over**: each event is
## emitted on the root window's `window_input` and then pushed into it, which is
## what `Window` does with an event the display server delivers. The bar, a real
## `MainCanvas` with the base modules' brush in hand, and the Welcome window
## stand in the real root with embedding forced, the way the top bar's menu suite
## stands its bar, so the lists and the window are real windows that open and close and the
## press reaches the canvas's control only if nothing kept it. Everything is
## asked in one frame, since a test that awaits drops every assertion after the
## await. The brush takes its point from the pointer rather than from
## the press, so each press puts [member SaPointerDevice.suite_pointer] where it
## lands first, as the canvas suites do. The running app's proof is
## `scenarios/a-press-that-closes-a-menu-or-the-welcome-window-does-not-paint.json`.
@tool
extends "res://tests/test_framework.gd"

## Real windows go in the tree, and the brush needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")


## A docker over the canvas, a bare `DockerWindow` because the Welcome window
## goes away on a press on a docker and stays up for any other window, with the
## presses that reach the panel filling it.
class Docker:
    extends DockerWindow

    var pressed: int = 0

    func _init() -> void:
        name = "D7Docker"
        borderless = true
        size = Vector2i(120, 80)
        var panel := Control.new()
        panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        panel.gui_input.connect(_count_press)
        add_child(panel)

    func _count_press(event: InputEvent) -> void:
        if SaPutAway.is_press(event):
            pressed += 1


var _host: Control = null
var _was_embedding: bool = false
var _bar: TopMenuBar = null
var _canvas: Node = null
var _welcome: SaWelcomeWindow = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    SaCursorPolicy.forget_pointer_device()
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`. The canvas goes in
    # first, so the bar stands over it and takes a press on a title.
    _host = Control.new()
    _host.name = "D7Host"
    _host.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _host.size = Vector2(tree.root.size)
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    _canvas.bind_tools(Fixtures.make_tool_registry())
    _canvas.notification(Container.NOTIFICATION_SORT_CHILDREN)
    var registries := SaTestFixtures.make_menu_registries()
    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(registries.commands)
    _lay_out()


func after_each() -> void:
    SaPointerDevice.suite_pointer = null
    if _host != null:
        _host.free()
    _host = null
    _bar = null
    _canvas = null
    _welcome = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


func test_the_hand_holds_a_brush_and_a_press_on_the_canvas_paints() -> void:
    var descriptor: Variant = _canvas.tool_machine.get_descriptor(_canvas.tool_machine.active_tool_name)
    assert_true(descriptor != null and descriptor.is_painting, "The tool in hand paints")
    var steps := _steps()
    _click(_on_the_canvas())
    assert_eq(_steps(), steps + 1, "and a press and release with nothing open is a stroke and an undo step")


func test_a_press_on_the_canvas_closes_the_open_menu_and_paints_nothing() -> void:
    _bar._on_menu_button_pressed("Filter")
    assert_eq(_open_names(), ["Filter"], "Filter is open")
    var steps := _steps()
    var version := _version()

    _press(_on_the_canvas())
    assert_eq(_open_names(), [], "The press closes Filter")
    assert_false(_canvas._capturing_stroke, "and takes no pointer for a stroke")
    assert_false(_drawing(), "and the brush began none")
    _release(_on_the_canvas())

    assert_eq(_steps(), steps, "The release closes no stroke, so no undo step was added")
    assert_eq(_version(), version, "and the history did not move")
    assert_eq(_canvas._held_buttons, 0, "The release let go of the press it followed")
    _click(_on_the_canvas())
    assert_eq(_steps(), steps + 1, "The next press paints, since nothing is open")


## A drag of the press that closed the menu reaches the tool as a hover, so a
## tool that acts on a drag with the button down acts on nothing.
func test_a_drag_after_the_press_paints_nothing_and_its_release_is_kept_too() -> void:
    _bar._on_menu_button_pressed("Edit")
    var steps := _steps()
    var at := _on_the_canvas()
    _press(at)
    for step: int in 4:
        _drag(at - Vector2(30.0 * (step + 1), 20.0 * (step + 1)))
    _release(at - Vector2(120.0, 80.0))
    assert_false(_drawing(), "No stroke began under the drag")
    assert_eq(_steps(), steps, "and none was closed")


func test_a_press_on_the_canvas_closes_the_last_titles_list_and_a_menu_from_it_and_paints_nothing() -> void:
    _bar.menu_overflow.fit(120.0)
    _lay_out()
    var fold := _bar.menu_overflow
    assert_true(fold.visible and fold.folded.size() > 0, "The row folds titles behind the last one: %s" % [fold.folded])
    var steps := _steps()

    fold.open_list()
    assert_true(fold.list.visible, "The last title's list is open")
    _click(_on_the_canvas())
    assert_false(fold.list.visible, "The press closes the list")
    assert_eq(_steps(), steps, "and paints nothing")

    var folded: String = fold.folded[-1]
    _bar._on_menu_button_pressed(folded)
    assert_eq(_open_names(), [folded], "A folded menu opens under the last title")
    _click(_on_the_canvas())
    assert_eq(_open_names(), [], "and the press closes it")
    assert_eq(_steps(), steps, "and paints nothing")


func test_a_press_on_the_canvas_puts_the_welcome_window_away_and_paints_nothing() -> void:
    _show_welcome()
    var steps := _steps()
    var version := _version()
    var at := _on_the_canvas()
    assert_false(_welcome_rect().has_point(at), "The press lands outside the window, on the canvas")

    _press(at)
    assert_false(_welcome.visible, "The press puts the Welcome window away")
    assert_false(_canvas._capturing_stroke, "and takes no pointer for a stroke")
    _release(at)

    assert_eq(_steps(), steps, "No stroke and no undo step")
    assert_eq(_version(), version, "and the history did not move")
    _click(at)
    assert_eq(_steps(), steps + 1, "The next press paints")


## One press still closes the window and opens a menu, as its header says.
func test_a_press_on_a_title_with_the_welcome_window_up_closes_it_and_opens_that_menu() -> void:
    _show_welcome()
    var title: Button = _bar.menu_buttons["File"]
    _click(title.get_global_rect().get_center())
    assert_false(_welcome.visible, "The press on File puts the Welcome window away")
    assert_eq(_open_names(), ["File"], "and opens File")


## A press on a docker goes on to the docker as well, and the canvas under the
## docker never holds it, since the point is the docker's and not the canvas's.
func test_a_press_on_a_docker_with_the_welcome_window_up_closes_it_and_reaches_the_docker() -> void:
    var at := _on_the_canvas()
    var docker := Docker.new()
    docker.position = Vector2i(at) - Vector2i(60, 40)
    _host.add_child(docker)
    _show_welcome()
    assert_false(_welcome_rect().has_point(at), "The docker's middle is outside the Welcome window")
    var steps := _steps()

    _press(at)
    assert_false(_welcome.visible, "The press on the docker puts the Welcome window away")
    assert_eq(docker.pressed, 1, "and goes on to the docker")
    assert_eq(_canvas._held_buttons, 0, "which the canvas under it does not hold")
    _release(at)
    assert_eq(_steps(), steps, "and nothing is painted")


## The canvas, the bar and the Welcome window all hear a press at the root, in
## the order they connected. Here the canvas hears it last, after the window has
## gone, so what it reads is the press the window named on the way out.
func test_the_press_is_kept_when_the_canvas_hears_it_after_the_window_went() -> void:
    _show_welcome()
    var root := (Engine.get_main_loop() as SceneTree).root
    root.window_input.disconnect(_canvas._on_window_input)
    root.window_input.connect(_canvas._on_window_input)
    var steps := _steps()
    _click(_on_the_canvas())
    assert_false(_welcome.visible, "The window went first")
    assert_eq(_steps(), steps, "and the canvas still painted nothing")

    _bar._on_menu_button_pressed("Layer")
    _click(_on_the_canvas())
    assert_eq(_open_names(), [], "A menu closed before the canvas heard the press")
    assert_eq(_steps(), steps, "paints nothing either")


## A desktop menu bar closes on any button, and the engine closes a list on the
## left one alone. A right press on the canvas left the list up and opened the
## Brush Presets docker beside it, and now it closes the list and goes no further.
func test_a_right_press_on_the_canvas_closes_the_open_menu_and_reaches_no_tool() -> void:
    _bar._on_menu_button_pressed("Image")
    var at := _on_the_canvas()
    _send(at, MOUSE_BUTTON_RIGHT, true)
    assert_eq(_open_names(), [], "The right press closes Image")
    assert_eq(_canvas._held_buttons, int(MOUSE_BUTTON_MASK_RIGHT), "and the canvas keeps it from the tool")
    _send(at, MOUSE_BUTTON_RIGHT, false)
    assert_eq(_canvas._held_buttons, 0, "with its release")


## A press in an open list is the list's, and one on a docker or a title goes on
## to what it landed on, so the bar puts nothing away for either.
func test_a_press_in_the_open_list_or_on_its_title_is_not_put_away_by_the_bar() -> void:
    _bar._on_menu_button_pressed("Filter")
    var list: SaChoicePopup = _bar.menus["Filter"]
    var inside := Rect2(Vector2(list.position), Vector2(list.size)).get_center()
    assert_true(_bar._list_at(inside), "The middle of the open list is in it")
    var tools: Button = _bar.menu_buttons["Tools"]
    assert_eq(_bar._title_under(tools.get_global_rect().get_center()), tools, "Tools is a title")
    assert_false(_bar._list_at(_on_the_canvas()), "and the canvas is neither in a list")
    assert_null(_bar._title_under(_on_the_canvas()), "nor a title")


# --- Helpers --------------------------------------------------------------------


## The bar sorted inside the window, as the engine would a frame on.
func _lay_out() -> void:
    _bar.offset_bottom = _bar.get_combined_minimum_size().y
    for box: Container in [_bar, _bar.rows, _bar.rows.main_row, _bar.menu_bar.get_parent() as Container, _bar.menu_bar]:
        box.notification(Container.NOTIFICATION_SORT_CHILDREN)


## The Welcome window up in the middle of the main window, embedded, as Help
## opens it.
func _show_welcome() -> void:
    _welcome = SaWelcomeWindow.new()
    _host.add_child(_welcome)
    _welcome.popup_centered()
    assert_true(_welcome.visible, "The Welcome window is up")


func _welcome_rect() -> Rect2:
    return Rect2(Vector2(_welcome.position), Vector2(_welcome.size))


## A point of the document, near its lower right corner and inside the canvas's
## control, where no list, no title and no Welcome window stands.
func _on_the_canvas() -> Vector2:
    var shown: Rect2 = _canvas.canvas.get_global_rect().intersection(_canvas.control_node.get_global_rect())
    return shown.end - Vector2(40.0, 40.0)


func _open_names() -> Array:
    var open: Array = []
    for menu_name: String in _bar.menus:
        if (_bar.menus[menu_name] as SaChoicePopup).visible:
            open.append(menu_name)
    return open


func _drawing() -> bool:
    var tool_machine: ToolMachine = _canvas.tool_machine
    return tool_machine.active_tool != null and bool(tool_machine.active_tool.get("is_drawing"))


func _steps() -> int:
    var history: Object = _canvas.canvas.document.history
    return history.step_count() if history != null else -1


func _version() -> int:
    return int(_canvas.canvas.document.undo_redo.get_version())


func _click(at: Vector2) -> void:
    _press(at)
    _release(at)


func _press(at: Vector2) -> void:
    _send(at, MOUSE_BUTTON_LEFT, true)


func _release(at: Vector2) -> void:
    _send(at, MOUSE_BUTTON_LEFT, false)


## A motion with the left button held, to *at*.
func _drag(at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    motion.pressure = 1.0
    _hand(motion, at)


func _send(at: Vector2, which: MouseButton, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = which
    event.pressed = pressed
    var mask := MOUSE_BUTTON_MASK_LEFT if which == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
    event.button_mask = mask if pressed else 0
    _hand(event, at)


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
