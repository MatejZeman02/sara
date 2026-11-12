## Repeat Last on Shift+R runs the last command again, and undo,
## redo and Repeat Last itself are never the last command. Blender's Repeat Last
## on Shift+R is the inspiration, and no code of Blender's is taken.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every press goes through the router, the door a painter's keys reach, and the
## undo is also handed on the way the Edit menu's row hands it, so the command
## before it is read back whichever way the undo came. Two commands of the suite's own count their
## runs, because a built-in's effect needs a canvas and its count does not.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const OWLS := &"count_the_owls"
const CROWS := &"count_the_crows"

var _registries: SaRegistries = null
var _router: ShortcutRouter = null
var _bar: TopMenuBar = null
var _saved_events: Dictionary = {}
## How many times each counting command ran, command id -> runs.
var _runs: Dictionary = {}


## A filter of the suite's own, because the skeleton registers none.
class HootFilter:
    extends SaFilter

    func title() -> String:
        return "Hoot"

    func run(_ctx: SaFilterContext) -> void:
        pass


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _runs = {OWLS: 0, CROWS: 0}
    _registries = Fixtures.make_menu_registries()
    _register(OWLS, "Count the Owls", KEY_F9)
    _register(CROWS, "Count the Crows", KEY_F10)
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return null
    _router.bind_commands(_registries.commands)
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(_registries.commands)


func after_each() -> void:
    _bar.free()
    _bar = null
    _router.free()
    _router = null
    _registries = null
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


func _register(command_id: StringName, label: String, keycode: Key) -> void:
    var command := SaCommandDescriptor.create(command_id, label, _count.bind(command_id))
    command.label = label
    command.default_events = [_key(keycode, false, true, true)]
    _registries.commands.register(command)


func _count(command_id: StringName) -> bool:
    _runs[command_id] += 1
    return true


func _key(keycode: Key, shift: bool, ctrl: bool = false, alt: bool = false) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.shift_pressed = shift
    event.ctrl_pressed = ctrl
    event.alt_pressed = alt
    event.pressed = true
    return event


func _shift_r() -> bool:
    return _router.handle(_key(KEY_R, true))


## The Edit menu's row id for *command_id*.
func _edit_id(command_id: StringName) -> int:
    var edit := _bar.menu("Edit")
    for row_id: StringName in edit.popup.row_ids():
        if edit.row_command(row_id) == command_id:
            return SaMenu.id_of(row_id)
    return -1


func test_shift_r_runs_the_command_a_chord_ran_a_second_time() -> void:
    assert_true(_router.handle(_key(KEY_F9, false, true, true)), "The owls' chord is answered")
    assert_eq(_runs[OWLS], 1, "and counts the owls once")

    assert_true(_shift_r(), "Shift+R is answered")

    assert_eq(_runs[OWLS], 2, "and the owls are counted twice")
    assert_eq(SaQuickCommands.last_run, OWLS, "Repeat Last is never the last command, so the owls still are")
    _shift_r()
    assert_eq(_runs[OWLS], 3, "and a third press counts them again")


func test_after_an_undo_shift_r_runs_the_command_before_the_undo() -> void:
    # A history with a step in it, reached the one way `handle` reaches a
    # document, through the canvas, so the undo below is a real one. Nothing of
    # the view is read but the document, as `test_shortcut_router.gd` found.
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var history := easel.document.undo_redo
    history.create_action("Paint")
    history.add_do_method(func() -> void: pass)
    history.add_undo_method(func() -> void: pass)
    history.commit_action()
    var canvas := SaCanvas.new()
    canvas.easel = easel
    _router.canvas_provider = func() -> SaCanvas: return canvas
    _router.handle(_key(KEY_F9, false, true, true))
    _router.handle(_key(KEY_F10, false, true, true))
    assert_eq(_runs[CROWS], 1, "The crows were counted last")

    assert_true(_router.handle(_key(KEY_Z, false, true)), "Ctrl+Z undoes the step")
    assert_eq(history.get_current_action(), -1, "and the history stands before it")
    assert_true(_router.handle(_key(KEY_Z, true, true)), "and Ctrl+Shift+Z redoes it")
    # What the Edit menu's Undo and Redo rows hand on once they ran, which is
    # read rather than pressed, because the suite's registries keep no handler
    # behind those two rows.
    SaQuickCommands.note_run(&"edit_undo")
    SaQuickCommands.note_run(&"edit_redo")

    assert_eq(SaQuickCommands.last_run, CROWS, "Undo by its chord or its row, and redo, are never the last command")
    assert_true(_shift_r(), "so Shift+R after them")
    assert_eq(_runs[CROWS], 2, "counts the crows again")
    assert_eq(_runs[OWLS], 1, "and not the owls before them")
    _router.canvas_provider = func() -> SaCanvas: return null
    canvas.free()
    easel.free()


func test_a_menu_row_is_a_last_command_and_its_repeat_row_dims_until_one_ran() -> void:
    var edit := _bar.menu("Edit")
    var repeat_id := _edit_id(SaQuickCommands.REPEAT)
    assert_true(repeat_id >= 0, "The Edit menu has a Repeat Last row")
    assert_false(SaQuickCommands.can_repeat(), "A fresh registry has run nothing")
    assert_true(edit.popup.is_disabled(SaMenu.key(repeat_id)), "so the row is dimmed")

    edit.on_id_pressed(_edit_id(&"fill_foreground"))

    assert_eq(SaQuickCommands.last_run, &"fill_foreground", "A command run from its menu row is the last command")
    assert_true(SaQuickCommands.can_repeat(), "and there is something to repeat")


func test_a_filter_repeats_as_apply_again_with_its_last_settings() -> void:
    _registries.context.for_module(&"owl_module").register_filter(HootFilter.new())
    var keys := _registries.filters.list_keys()
    assert_eq(keys.size(), 1, "The suite registered a filter")
    var filter_command := SaFilterRegistry.command_for(keys[0], _registries.filters.get_filter(keys[0]))

    SaQuickCommands.note_run(filter_command)

    assert_eq(
        SaQuickCommands.last_run,
        SaFilterAgain.COMMAND,
        "A filter is kept as Apply Again, which runs it with its last settings and no dialog"
    )
