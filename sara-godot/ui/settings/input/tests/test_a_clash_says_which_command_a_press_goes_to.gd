## The Brush put on E names the Eraser and its toggle, says which
## of them E goes to, and a press of E does what the line says.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The sweeps bound the Brush to E. The row turned orange and named nobody,
## because the names were in a tooltip, and E went on toggling the eraser: the
## toggle is a command, and the router asks the commands before any tool's key.
## So the Brush had no working key and nothing on the page said so. The line
## under the row is `SaShortcutsPage.clash_line`, and its answer is
## `SaShortcutRows.first_to_answer`, which reads the router's order rather than
## asking it. This presses E through a real router and holds the two together.
##
## The wiring is `tools/tests/test_the_e_key_ticks_the_erase_row.gd`'s: the stamp
## module registered through the door, a tool machine on a surface and a router
## bound to the same commands.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

var _saved_events: Dictionary = {}
var _saved_profile: String = ""

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _module: SaModule = null
var _machine: ToolMachine = null
var _router: ShortcutRouter = null
var _page: SaShortcutsPage = null


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    SaShortcutStore.dir_override = SaDataRoot.path("test_clash_profiles")
    SaShortcutStore.capture_defaults()
    _saved_profile = SaSettings.shortcuts_profile
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE

    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _module = load("res://modules/sara-base-modules/stamp-brush/module.gd").new()
    _module.register(_registries.context.for_module(_module.get_id()))
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _machine.set_active_tool(&"brush")
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return _machine
    _router.bind_commands(_registries.commands)

    _page = SaShortcutsPage.new()
    _page.bind_tools(_registries.tools, _registries.filters, _registries.commands)


func after_each() -> void:
    _page.free()
    _module.unregister(_registries.context)
    Fixtures.teardown(_surface, _machine)
    _router.free()
    _page = null
    _router = null
    _machine = null
    _module = null
    _registries = null
    _surface = null

    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    var dir := DirAccess.open(SaShortcutStore.dir_path())
    if dir != null:
        for file: String in dir.get_files():
            dir.remove(file)
    SaShortcutStore.dir_override = ""
    SaSettings.shortcuts_profile = _saved_profile


func _key_e() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_E
    event.physical_keycode = KEY_E
    event.pressed = true
    return event


## The action a press of E went to, by the command that took it, or by the tool
## the machine is on when no command did.
func _pressed_e() -> StringName:
    _registries.commands.last_command = &""
    assert_true(_router.handle(_key_e()), "E is somebody's")
    var command := _registries.commands.get_descriptor(_registries.commands.last_command)
    if command != null:
        return command.action
    var tool := _registries.tools.get_descriptor(_machine.active_tool_name)
    return tool.activate_action if tool != null else &""


## Shared, with no question asked: the line names both
## halves of the eraser's pair and says the toggle takes the key, and E does.
func test_the_brush_on_e_names_the_eraser_and_its_toggle_and_e_does_what_the_line_says() -> void:
    _page.offer(&"tool_brush", "E")
    assert_not_null(_page.question, "E is taken, so the page asks")
    var asked := _page.question.text_label.text
    assert_true(asked.contains("Eraser") and asked.contains("Toggle"), "The question names both holders: %s" % asked)
    _page.question.buttons[SaShortcutsPage.ANSWER_SHARE].pressed.emit()
    assert_eq(SaShortcutStore.chords_for(&"tool_brush"), ["E"] as Array[String], "Shared, the Brush holds E")

    var line := _page.clash_line(&"tool_brush")
    assert_true(line.contains("E is also used by"), "The Brush's row has a line about E: %s" % line)
    assert_true(line.contains("Eraser"), "that names the Eraser")
    var toggle_words := SaShortcutsPage.label_for("brush_toggle_eraser", null, null, _registries.commands)
    assert_true(line.contains(toggle_words), "and its toggle")
    var holders := ["tool_brush", "brush_toggle_eraser", "tool_eraser"]
    var first := SaShortcutRows.first_to_answer(holders, _registries.commands, _registries.tools)
    assert_eq(first, &"brush_toggle_eraser", "The router's order puts the toggle first")
    assert_true(line.contains("E runs %s." % toggle_words), "and the line says so: %s" % line)

    var eraser_line := _page.clash_line(&"tool_eraser")
    assert_true(
        eraser_line.contains("Brush") and eraser_line.contains(toggle_words),
        "The Eraser's row names the Brush and its own toggle: %s" % eraser_line
    )

    # On the Brush, E toggles its eraser. On the Eraser, it stays there. Never
    # the Brush, which is what the line tells the painter.
    assert_eq(_pressed_e(), first, "On the Brush, a press of E goes where the line says")
    assert_eq(_machine.active_tool_name, &"brush", "and the Brush stays the tool")
    assert_true(_machine.active_tool.eraser_toggled, "with its eraser toggled")
    _machine.set_active_tool(&"eraser")
    assert_eq(_pressed_e(), first, "On the Eraser, it goes to the toggle as well")
    assert_eq(_machine.active_tool_name, &"eraser", "which leaves the Eraser where it is")


## Moved, E is the Brush's alone: no line on any of the three rows, and E picks
## the Brush from the Eraser.
func test_the_brush_moved_onto_e_takes_it_and_e_picks_the_brush() -> void:
    _page.offer(&"tool_brush", "E")
    _page.question.buttons[SaShortcutsPage.ANSWER_MOVE].pressed.emit()
    assert_eq(SaShortcutStore.chords_for(&"tool_brush"), ["E"] as Array[String], "Moved, the Brush holds E")
    assert_eq(SaShortcutStore.chords_for(&"tool_eraser"), [] as Array[String], "the Eraser let it go")
    var toggle := SaShortcutStore.chords_for(&"brush_toggle_eraser")
    assert_eq(toggle, [] as Array[String], "and so did its toggle, the pair moving as one")
    for action: StringName in [&"tool_brush", &"tool_eraser", &"brush_toggle_eraser"]:
        assert_eq(_page.clash_line(action), "", "No line on %s's row" % action)

    _machine.set_active_tool(&"eraser")
    assert_eq(_pressed_e(), &"tool_brush", "A press of E goes to the Brush")
    assert_eq(_machine.active_tool_name, &"brush", "and picks it")
