## After a pen picks a colour, its pointer is drawn in the window the pen is
## over and in no other, and under Windows Ink the focus follows the pen out of
## the docker the pick was made in.
##
## After a pick with a tablet pen,
## Tool Options showed no pointer and Sara's own pointer stayed over the colour
## swatch. A virtual pen found the pointer in Tool Options and none
## in the Colour Picker, embedded and let out, and found one fault of its own:
## embedded, the main window's overlay drew a second arrow beneath Tool Options,
## because the policy's yes over a docker with an overlay of its own was taken
## by both. Windows is where Godot hears the pen in the focused
## window alone, and the pick had given the colour docker the focus.
##
## The policy asks its register which windows have an overlay, so a plain
## Control registered there stands for one here. A pen is fed the way the
## overlay's `_input` feeds it, known for a pen by its tilt.
extends "res://tests/test_framework.gd"

const COLOUR_AT := Vector2i(700, 100)
const COLOUR_SIZE := Vector2i(260, 360)
const TOOLS_AT := Vector2i(200, 460)
const TOOLS_SIZE := Vector2i(400, 200)
## On a swatch of the colour docker, and inside Tool Options, in each one's own
## space.
const ON_A_SWATCH := Vector2(150.0, 300.0)
const IN_TOOLS := Vector2(170.0, 120.0)

var _host: Node = null
var _loose: Array[Window] = []
var _overlays: Array[Control] = []
var _previous_mode: String = "auto"


func before_each() -> void:
    _previous_mode = SaSettings.software_cursor
    SaSettings.software_cursor = "always"
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "PickThenToolOptionsTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    for overlay in _overlays:
        SaCursorPolicy.unregister_overlay(overlay)
    _overlays.clear()
    SaSettings.software_cursor = _previous_mode
    if _host != null:
        _host.free()
        _host = null
    for window in _loose:
        window.free()
    _loose.clear()


## A docker embedded in the main window, with an overlay of its own.
func _docker(at: Vector2i, size: Vector2i) -> Window:
    var docker := Window.new()
    docker.borderless = true
    docker.position = at
    docker.size = size
    var overlay := Control.new()
    docker.add_child(overlay)
    SaCursorPolicy.register_overlay(overlay)
    _overlays.append(overlay)
    _host.add_child(docker)
    docker.show()
    return docker


## A window in no tree, which is all the focus rule reads of a let-out docker.
func _let_out() -> Window:
    var window := Window.new()
    _loose.append(window)
    return window


func _pen_at(window: Window, at: Vector2, pressure: float = 0.0) -> void:
    var motion := InputEventMouseMotion.new()
    motion.tilt = Vector2(0.2, -0.1)
    motion.pressure = pressure
    motion.position = at
    SaCursorPolicy.note_pointer_device(motion, window)


func _button(window: Window, at: Vector2, pressed: bool) -> void:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    button.position = at
    SaCursorPolicy.note_pointer_device(button, window)


## A tap on the swatch: over it, down, a pressed motion, up, and a hover.
func _pick_in(window: Window, at: Vector2) -> void:
    _pen_at(window, at)
    _button(window, at, true)
    _pen_at(window, at + Vector2(1.0, 0.0), 0.4)
    _button(window, at + Vector2(1.0, 0.0), false)
    _pen_at(window, at + Vector2(2.0, 0.0))


func test_after_a_pick_one_overlay_draws_the_pen_in_tool_options() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var root := (Engine.get_main_loop() as SceneTree).root
    var colour := _docker(COLOUR_AT, COLOUR_SIZE)
    var tools := _docker(TOOLS_AT, TOOLS_SIZE)

    _pick_in(colour, ON_A_SWATCH)
    var over_the_swatch := SaCursorPolicy.pointer_in_window(root)
    var on_swatch := SaCursorPolicy.pointer_in_window(colour)
    assert_true(SaCursorPolicy.arrow_drawn_in(colour, on_swatch), "Over the swatch the colour docker draws it")
    assert_true(SaCursorPolicy.wants_software_pointer(root, over_the_swatch), "the main window still hides the OS cursor there")
    assert_false(SaCursorPolicy.arrow_drawn_in(root, over_the_swatch), "and draws no arrow of its own under the docker")

    _pen_at(tools, IN_TOOLS)
    var in_tools := SaCursorPolicy.pointer_in_window(tools)
    assert_eq(in_tools, IN_TOOLS, "Tool Options reads the pen at its own place")
    assert_true(SaCursorPolicy.arrow_drawn_in(tools, in_tools), "so its overlay draws the pointer there")
    var in_colour := SaCursorPolicy.pointer_in_window(colour)
    assert_false(
        Rect2(Vector2.ZERO, Vector2(COLOUR_SIZE)).has_point(in_colour),
        "The colour docker reads the pen outside itself, %s" % in_colour
    )
    assert_false(SaCursorPolicy.arrow_drawn_in(colour, in_colour), "and draws nothing")
    var in_root := SaCursorPolicy.pointer_in_window(root)
    assert_true(in_root.is_equal_approx(Vector2(TOOLS_AT) + IN_TOOLS), "The main window carries the same place, %s" % in_root)
    assert_true(SaCursorPolicy.wants_software_pointer(root, in_root), "keeps the OS cursor hidden over Tool Options")
    assert_false(SaCursorPolicy.arrow_drawn_in(root, in_root), "and leaves the arrow to Tool Options, so one overlay draws it")


func test_the_eyedropper_on_the_canvas_reads_the_same() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var root := (Engine.get_main_loop() as SceneTree).root
    var tools := _docker(TOOLS_AT, TOOLS_SIZE)
    var on_the_canvas := Vector2(TOOLS_AT) + Vector2(60.0, -120.0)

    _pick_in(root, on_the_canvas)
    var clear := SaCursorPolicy.pointer_in_window(root)
    assert_true(SaCursorPolicy.arrow_drawn_in(root, clear), "Clear of every docker the main window draws it")
    _pen_at(tools, IN_TOOLS)
    var in_tools := SaCursorPolicy.pointer_in_window(tools)
    assert_true(SaCursorPolicy.arrow_drawn_in(tools, in_tools), "Tool Options draws it after the pick")
    assert_false(SaCursorPolicy.arrow_drawn_in(root, SaCursorPolicy.pointer_in_window(root)), "and the main window does not")


func test_a_mouse_is_drawn_nowhere() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var tools := _docker(TOOLS_AT, TOOLS_SIZE)
    var motion := InputEventMouseMotion.new()
    motion.position = IN_TOOLS
    for _step in SaPointerDevice.MOUSE_MOTION_STREAK + 1:
        SaCursorPolicy.note_pointer_device(motion, tools)
    assert_false(SaCursorPolicy.arrow_drawn_in(tools, IN_TOOLS), "A mouse keeps the OS cursor, which the driver moves")


func test_after_a_pick_in_a_docker_the_focus_follows_the_pen() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var colour := _let_out()
    var tools := _let_out()
    # The main window as the pen comes over it, asked through a stand-in so the
    # answer does not hang on whether the suite's own window has the focus.
    var main_window := _let_out()

    _pick_in(colour, ON_A_SWATCH)
    var handed := SaPointerDevice.hands_the_focus(tools, colour, true)
    assert_true(handed, "From the docker the pick focused, Tool Options takes the focus")
    assert_true(SaPointerDevice.hands_the_focus(main_window, colour, true), "and so does the canvas the pen crosses on the way")
    _pen_at(root, Vector2(40.0, 40.0))
    assert_true(SaPointerDevice.hands_the_focus(tools, root, true), "from which the pen takes it on into Tool Options")
    assert_false(SaPointerDevice.hands_the_focus(tools, colour, false), "Never from a window that does not have it")
    assert_false(SaPointerDevice.hands_the_focus(colour, colour, true), "and never to the window that has it")


func test_a_press_on_the_canvas_keeps_the_focus_there() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var tools := _let_out()

    _pick_in(root, Vector2(40.0, 40.0))
    assert_false(SaPointerDevice.hands_the_focus(tools, root, true), "The eyedropper's press keeps the keyboard on the canvas")
    _pick_in(tools, IN_TOOLS)
    assert_true(SaPointerDevice.hands_the_focus(root, tools, true), "A press in a docker lets it follow the pen")
    _pick_in(root, Vector2(40.0, 40.0))
    assert_false(SaPointerDevice.hands_the_focus(tools, root, true), "and a press back on the canvas puts it down again")


func test_a_list_a_modal_window_a_text_field_and_a_mouse_keep_the_focus() -> void:
    var colour := _let_out()
    var tools := _let_out()
    var list := PopupMenu.new()
    _loose.append(list)

    _pick_in(colour, ON_A_SWATCH)
    assert_false(SaPointerDevice.hands_the_focus(list, colour, true), "A list is heard open or not, so it takes nothing")
    assert_false(SaPointerDevice.hands_the_focus(tools, list, true), "and gives nothing up")
    colour.exclusive = true
    assert_false(SaPointerDevice.hands_the_focus(tools, colour, true), "A window that holds the others off keeps it")
    colour.exclusive = false
    assert_false(SaPointerDevice.hands_the_focus(null, colour, true), "and no window is not a crash")

    SaCursorPolicy.forget_pointer_device()
    _button(colour, ON_A_SWATCH, true)
    _button(colour, ON_A_SWATCH, false)
    assert_false(SaPointerDevice.hands_the_focus(tools, colour, true), "A mouse's press decides nothing for the pen")


func test_a_text_field_with_the_focus_keeps_the_keys() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var colour := _docker(COLOUR_AT, COLOUR_SIZE)
    var tools := _let_out()
    var field := LineEdit.new()
    field.size = Vector2(120.0, 30.0)
    colour.add_child(field)

    _pick_in(colour, ON_A_SWATCH)
    assert_true(SaPointerDevice.hands_the_focus(tools, colour, true), "With no text field focused the focus follows the pen")
    field.grab_focus()
    assert_eq(colour.gui_get_focus_owner(), field, "The hex field has the docker's keyboard")
    assert_false(SaPointerDevice.hands_the_focus(tools, colour, true), "and keeps it while the pen goes elsewhere")
