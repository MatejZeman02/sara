## The pen's buttons can be bound. Every button is bound in turn
## to every action, and a synthetic press and release of it has to do the bound
## action and nothing else: no menu it was not bound to, no view moved, no tool
## swapped and no event reaching the tool. The defaults are checked against what
## the buttons did before they could be bound.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A machine holding the built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _probe: Probe = null
var _stored: Dictionary = {}
var _stored_mouse_middle: String = ""
var _menus: Array = []


## A tool that paints nothing and counts what reaches it, so a button whose
## event leaks through to the active tool is seen.
class Probe:
    extends ToolState

    var seen: Array = []

    func handle_input(event: InputEvent) -> void:
        seen.append(event)


func before_each() -> void:
    _stored = SaSettings.pen_buttons.duplicate()
    _stored_mouse_middle = SaSettings.mouse_middle
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _probe = Probe.new()
    _machine.register_tool(&"probe", _probe)
    _machine.set_active_tool(&"probe")
    _menus.clear()
    _machine.context_menu_requested.connect(func(at: Vector2) -> void: _menus.append(at))


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    SaSettings.pen_buttons = _stored
    SaSettings.mouse_middle = _stored_mouse_middle
    _probe = null
    Fixtures.teardown(_surface, _machine)


func _button(index: MouseButton, pressed: bool, at: Vector2 = Vector2(100, 100)) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = index
    event.pressed = pressed
    event.position = at
    event.global_position = at
    event.button_mask = MouseButtonMask.MOUSE_BUTTON_MASK_RIGHT if pressed and index == MOUSE_BUTTON_RIGHT else 0
    return event


func _drag(to: Vector2, relative: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = to
    event.relative = relative
    return event


func _bind(button_id: String, action: String) -> void:
    var table := SaSettings.pen_buttons.duplicate()
    table[button_id] = action
    SaSettings.pen_buttons = table


## A pen's hover, which is what the cursor overlay hands the device note for
## every motion in a window and what tells a middle press the pen's.
func _pen_hovers() -> void:
    var hover := InputEventMouseMotion.new()
    hover.tilt = Vector2(0.2, 0.1)
    SaCursorPolicy.note_pointer_device(hover)


## Presses the button, drags it forty pixels right and releases it, and answers
## what came of it: menus asked for, the pan the view moved by, the tool active
## while it was down and what reached the probe. The press is a pen's, which is
## the only kind these buttons are bound for but the wheel's.
func _use(index: MouseButton) -> Dictionary:
    _pen_hovers()
    var pan_before := _surface.view.get_pan()
    _machine.handle_input(_button(index, true))
    var held := _machine.active_tool_name
    _machine.handle_input(_drag(Vector2(140, 100), Vector2(40, 0)))
    var moved := _surface.view.get_pan() - pan_before
    _probe.seen = _probe.seen.filter(func(event: InputEvent) -> bool: return not (event is InputEventMouseMotion))
    _machine.handle_input(_button(index, false))
    var after := _machine.active_tool_name
    return {"menus": _menus.size(), "moved": moved, "held": held, "after": after, "reached": _probe.seen.size()}


func test_each_button_does_its_bound_action_and_nothing_else() -> void:
    for button: Dictionary in SaSettingsPenButtons.BUTTONS:
        var id := String(button["id"])
        var index: MouseButton = button["index"]
        for entry: Dictionary in SaSettingsPenButtons.ACTIONS:
            var action := String(entry["id"])
            _bind(id, action)
            _menus.clear()
            _probe.seen.clear()
            var got := _use(index)
            var where := "%s bound to %s" % [id, action]
            assert_eq(got["menus"], 1 if action == SaSettingsPenButtons.CONTEXT_MENU else 0, "%s: the menu" % where)
            assert_eq(got["moved"] != Vector2.ZERO, action == SaSettingsPenButtons.PAN, "%s: the view" % where)
            var tool := SaSettingsPenButtons.tool_for(action, _machine)
            assert_eq(got["held"], tool if tool != &"" else &"probe", "%s: the tool while held" % where)
            assert_eq(got["after"], &"probe", "%s: the tool after the release" % where)
            assert_eq(got["reached"], 0, "%s: no press or release reached the tool" % where)
        _bind(id, String(button["default"]))


## The held actions find their tools by what the tool does: the
## base modules' Eyedropper sets `picks_colour` and their Eraser `erases`, and
## a stand-in under another id that sets the flag takes the button instead.
func test_a_held_action_picks_its_tool_by_the_descriptor_s_flag() -> void:
    var eyedropper := SaSettingsPenButtons.EYEDROPPER
    var eraser := SaSettingsPenButtons.ERASER
    var picks := SaSettingsPenButtons.tool_for(eyedropper, _machine)
    assert_eq(picks, _machine.picker_tool_name(), "Eyedropper while held is the picker")
    assert_true(_machine.get_descriptor(_machine.eraser_tool_name()).erases, "and Eraser while held a tool that erases")
    assert_false(_machine.get_descriptor(&"brush").erases, "which the Brush is not")
    assert_eq(SaSettingsPenButtons.tool_for(SaSettingsPenButtons.PAN, _machine), &"", "Pan holds no tool")
    assert_eq(SaSettingsPenButtons.tool_for(eraser, null), &"", "and no machine has none to give")

    var picker_script: Script = _machine.get_descriptor(_machine.picker_tool_name()).tool_script
    var eraser_script: Script = _machine.get_descriptor(_machine.eraser_tool_name()).tool_script
    _machine.registry.unregister(_machine.picker_tool_name())
    _machine.registry.unregister(_machine.eraser_tool_name())
    assert_eq(SaSettingsPenButtons.tool_for(eyedropper, _machine), &"", "With no picker the button has no tool")
    _bind("right", eyedropper)
    _reseat_probe()
    assert_eq(_use(MOUSE_BUTTON_RIGHT)["held"], &"probe", "and a press leaves the tool in hand")

    var picker := SaToolDescriptor.create(&"stand_in_picker", picker_script)
    picker.picks_colour = true
    _machine.registry.register(picker)
    var rubber := SaToolDescriptor.create(&"stand_in_rubber", eraser_script)
    rubber.erases = true
    _machine.registry.register(rubber)
    _reseat_probe()
    var picked := _use(MOUSE_BUTTON_RIGHT)
    assert_eq(picked["held"], &"stand_in_picker", "A stand-in picker under another id takes the Eyedropper button")
    assert_eq(picked["after"], &"probe", "and hands the tool back on the release")
    _bind("right", eraser)
    var erased := _use(MOUSE_BUTTON_RIGHT)
    assert_eq(erased["held"], &"stand_in_rubber", "A stand-in eraser under another id takes the Eraser button")
    assert_eq(erased["after"], &"probe", "and hands the tool back on the release")


## A registry change rebuilds the machine's tools from the descriptors and
## drops the probe, which has none, so it goes back in the hand.
func _reseat_probe() -> void:
    _machine.register_tool(&"probe", _probe)
    _machine.set_active_tool(&"probe")


func test_the_defaults_are_the_buttons_of_before() -> void:
    SaSettings.pen_buttons = {}
    assert_eq(SaSettings.pen_buttons, SaSettingsPenButtons.defaults(), "An empty table is the defaults")
    var right := _use(MOUSE_BUTTON_RIGHT)
    assert_eq(right["menus"], 1, "A right press opens the context menu")
    assert_eq(right["moved"], Vector2.ZERO, "and moves nothing")
    _menus.clear()
    var middle := _use(MOUSE_BUTTON_MIDDLE)
    assert_true(middle["moved"] != Vector2.ZERO, "A middle drag pans")
    assert_eq(middle["menus"], 0, "and opens no menu")
    for index: MouseButton in [MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
        var extra := _use(index)
        assert_eq([extra["menus"], extra["moved"], extra["held"]], [0, Vector2.ZERO, &"probe"], "An extra button does nothing")

    var mid_stroke := _button(MOUSE_BUTTON_RIGHT, true)
    mid_stroke.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
    _menus.clear()
    _machine.handle_input(mid_stroke)
    assert_eq(_menus.size(), 0, "No menu opens over a stroke in progress")


func test_a_left_press_is_no_pen_button_and_reaches_the_tool() -> void:
    for button: Dictionary in SaSettingsPenButtons.BUTTONS:
        _bind(String(button["id"]), SaSettingsPenButtons.NOTHING)
    _probe.seen.clear()
    _machine.handle_input(_button(MOUSE_BUTTON_LEFT, true))
    _machine.handle_input(_button(MOUSE_BUTTON_LEFT, false))
    assert_eq(_probe.seen.size(), 2, "The left button is the tool's whatever the pen's buttons are bound to")


## The Tablet page carries the mouse's wheel press as a row
## of its own, beside the pen's Middle row, with the same actions.
func test_the_tablet_page_has_a_row_for_the_mouse_s_wheel_press() -> void:
    SaSettings.mouse_middle = SaSettingsPenButtons.PAN
    var page := SaTabletPage.new()
    var row := page.page.row(&"mouse_middle")
    assert_not_null(row, "Preferences > Tablet has the mouse middle row")
    if row != null:
        assert_eq(row.read(), SaSettingsPenButtons.PAN, "It reads Pan by default")
        row.write(SaSettingsPenButtons.ERASER)
        assert_eq(SaSettings.mouse_middle, SaSettingsPenButtons.ERASER, "and a choice writes the setting")
        assert_eq(SaSettings.pen_buttons["middle"], SaSettingsPenButtons.PAN, "leaving the pen's Middle row alone")
        var middle := page.page.row(&"pen_middle")
        assert_true(middle != null and middle.explanation.contains("row below"), "The Middle row sends the wheel to it")
    page.free()


func test_a_stored_table_is_held_to_the_four_buttons() -> void:
    SaSettings.pen_buttons = {"right": "eyedropper", "middle": "juggle", "thumb": "pan"}
    var want := SaSettingsPenButtons.defaults()
    want["right"] = SaSettingsPenButtons.EYEDROPPER
    assert_eq(SaSettings.pen_buttons, want, "An unknown action keeps the default and an unknown button is dropped")
    var garbled := SaSettingsPenButtons.bound("not a table")
    assert_eq(garbled, SaSettingsPenButtons.defaults(), "and a stored value that is no table is the defaults")
    assert_eq(SaSettingsKeys.place_of(&"pen_buttons"), ["input", "pen_buttons"], "The table is stored in the profile")


func test_a_focus_loss_hands_back_a_tool_a_button_held() -> void:
    _bind("extra1", SaSettingsPenButtons.EYEDROPPER)
    _machine.handle_input(_button(MOUSE_BUTTON_XBUTTON1, true))
    assert_eq(_machine.active_tool_name, &"eyedropper", "The eyedropper is in while the button is down")
    _machine.clear_held_keys()
    assert_eq(_machine.active_tool_name, &"probe", "and a focus loss that swallowed the release hands it back")


func test_the_tablet_page_has_a_row_a_button() -> void:
    SaSettings.pen_buttons = {}
    var page := SaTabletPage.new()
    for button: Dictionary in SaSettingsPenButtons.BUTTONS:
        var key := StringName("pen_" + String(button["id"]))
        assert_not_null(page.page.row(key), "Preferences > Tablet has the %s row" % key)
    var right := page.page.row(&"pen_right")
    assert_eq(right.read(), SaSettingsPenButtons.CONTEXT_MENU, "The right row reads the stored binding")
    right.write(SaSettingsPenButtons.ERASER)
    assert_eq(SaSettings.pen_buttons["right"], SaSettingsPenButtons.ERASER, "and a choice writes the table")
    assert_eq(SaSettings.pen_buttons["middle"], SaSettingsPenButtons.PAN, "leaving the other buttons alone")
    page.free()


## Every button row says which button of a usual pen it is.
## The four rows were Right, Middle, First extra and Second extra with no hint,
## the one set of rows on any page that had none, and "extra" says nothing of
## which button to press. The hint is the table's, so the row and the
## vocabulary cannot come to say different things, and it is read off the row
## the page built and off the line drawn under its title.
func test_every_button_row_says_which_button_it_is() -> void:
    var page := SaTabletPage.new()
    var said: Array[String] = []
    for button: Dictionary in SaSettingsPenButtons.BUTTONS:
        var id := String(button["id"])
        var hint := SaSettingsPenButtons.hint(button)
        assert_false(hint.is_empty(), "%s carries a hint" % id)
        said.append(hint)
        var row := page.page.row(StringName("pen_" + id))
        assert_not_null(row, "Preferences > Tablet has the %s row" % id)
        if row == null:
            continue
        assert_eq(row.explanation, hint, "the %s row says its own hint" % id)
        var drawn := row.line.get_node_or_null(^"Labels/Hint") as Label
        assert_eq(drawn.text if drawn != null else "", hint, "and draws it under its title")
    assert_true(said[0].contains("lower button"), "Right is the barrel's lower button, '%s'" % said[0])
    assert_true(said[1].contains("upper button"), "Middle is the barrel's upper one, '%s'" % said[1])
    for extra: String in said.slice(2):
        assert_true(extra.begins_with("No button of a usual pen"), "an extra says no usual pen sends it, '%s'" % extra)
    var note := page.page.row(&"pen_buttons_note")
    assert_true(note != null and note.explanation.contains("eraser end"), "the note says the eraser end is no button of these")
    page.free()
