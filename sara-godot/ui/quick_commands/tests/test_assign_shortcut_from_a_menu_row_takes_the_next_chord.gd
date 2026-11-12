## Assign Shortcut on a menu row's right click takes the next
## chord into the profile in use, and asks first, naming the holder, when
## another command has the chord. Blender's Assign Shortcut, on a menu item's
## right click, is the inspiration, and no code of Blender's is taken.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The right click is pressed on the Edit menu's rows and the chord is handed to
## the listener it started, the way its window's key would hand it. The window
## itself opens a frame later, which no suite here reaches, and a listener that
## heard its chord first leaves without opening it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_dir: String = SaDataRoot.path("test_assign_shortcut")

## A chord nothing holds in Sara Default, which the first case checks first.
const FREE_CHORD := "Ctrl+Alt+Shift+F7"

var _registries: SaRegistries = null
var _bar: TopMenuBar = null
var _saved_events: Dictionary = {}
var _saved_profile: String = ""


func before_each() -> void:
    _registries = Fixtures.make_menu_registries()
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    SaShortcutStore.dir_override = scratch_dir
    SaShortcutStore.capture_defaults()
    _saved_profile = SaSettings.shortcuts_profile
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(_registries.commands)


func after_each() -> void:
    ShortcutRouter.capture_in_progress = false
    _bar.free()
    _bar = null
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    SaShortcutStore.dir_override = ""
    SaSettings.shortcuts_profile = _saved_profile
    _registries = null
    var dir := DirAccess.open(scratch_dir)
    if dir != null:
        for file: String in dir.get_files():
            dir.remove(file)


## Presses Assign Shortcut on the right click of the Edit menu's row for
## *command_id*, and answers the listener it started.
func _assign_from_the_menu(command_id: StringName) -> QuickAssign:
    var edit := _bar.menu("Edit")
    var row := &""
    for row_id: StringName in edit.popup.row_ids():
        if edit.row_command(row_id) == command_id:
            row = row_id
    assert_false(row.is_empty(), "The Edit menu has a row for %s" % command_id)
    var asked := edit.ask_row(row)
    assert_true(asked.press_row(SaQuickCommands.ROW_ASSIGN), "Assign Shortcut can be pressed on it")
    var listening := SaQuickCommands.assigning
    assert_not_null(listening, "and it listens for the next chord")
    assert_eq(listening.command_id, command_id, "for that row's command")
    return listening


func test_a_free_chord_is_taken_into_the_profile() -> void:
    assert_true(SaShortcutStore.conflicts(FREE_CHORD).is_empty(), "Nothing holds %s on the shipped map" % FREE_CHORD)
    var listening := _assign_from_the_menu(&"edit_copy_merged")

    var question := listening.hear(FREE_CHORD)

    assert_null(question, "A chord nothing holds is taken without a question")
    assert_eq(SaShortcutStore.chords_for(&"edit_copy_merged"), [FREE_CHORD] as Array[String], "and replaces the row's own chord")
    var profile := SaSettings.shortcuts_profile
    assert_eq(profile, SaShortcutStore.target_profile(SaShortcutStore.DEFAULT_PROFILE), "in the profile in use, forked")
    assert_eq(
        SaShortcutStore.load_profile(profile).get("edit_copy_merged", []),
        [FREE_CHORD],
        "and saved where the next launch reads it"
    )
    assert_false(ShortcutRouter.capture_in_progress, "and the router answers keys again")


func test_a_held_chord_names_its_holder_before_taking_it() -> void:
    var listening := _assign_from_the_menu(&"edit_copy_merged")

    var question := listening.hear("Ctrl+Z")

    assert_not_null(question, "A chord another command holds is asked about first")
    assert_true(
        question.text_label.text.contains("Ctrl+Z is already used by Undo"),
        "naming the command that holds it: %s" % question.text_label.text
    )
    assert_true(
        question.text_label.text.contains("Use it for Copy merged instead?"),
        "and the one it would go to, in the Shortcuts page's words"
    )
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), ["Ctrl+Z"] as Array[String], "Nothing moves while it asks")

    question.buttons[QuickAssign.ANSWER_MOVE].pressed.emit()

    assert_eq(
        SaShortcutStore.chords_for(&"edit_copy_merged"),
        ["Ctrl+Z"] as Array[String],
        "Taking it gives the chord to the row's command"
    )
    assert_false(SaShortcutStore.chords_for(&"edit_undo").has("Ctrl+Z"), "and takes it from Undo")
    assert_eq(
        SaShortcutStore.load_profile(SaSettings.shortcuts_profile).get("edit_copy_merged", []), ["Ctrl+Z"], "into the profile"
    )


func test_cancel_and_escape_leave_the_map_as_it_was() -> void:
    var question := _assign_from_the_menu(&"edit_copy_merged").hear("Ctrl+Z")
    question.buttons[QuickAssign.ANSWER_CANCEL].pressed.emit()
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), ["Ctrl+Z"] as Array[String], "Cancel leaves Undo its chord")

    var before := SaShortcutStore.chords_for(&"edit_copy_merged")
    assert_null(_assign_from_the_menu(&"edit_copy_merged").hear(""), "Escape asks nothing")
    assert_eq(SaShortcutStore.chords_for(&"edit_copy_merged"), before, "and changes nothing")
    assert_eq(SaSettings.shortcuts_profile, SaShortcutStore.DEFAULT_PROFILE, "nor forks the profile")
