## Rebinding leaves no key dead, and Start again means the
## shipped map.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Three sweeps met it on Preferences › Keyboard Shortcuts. Redo put on Ctrl+Z
## left both rows on Ctrl+Z and forked the profile, and Start again then applied
## the fork, which took Ctrl+Z off Undo and left it with no chord at all. A key
## another command held was taken with nothing asked. Here the page asks first,
## Start again applies the shipped profile it names, and a clash saved into a
## profile comes back as it was saved. The Brush on E, whose answer needs a tool
## machine and so a card, is `test_a_clash_says_which_command_a_press_goes_to.gd`
## beside this.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_dir: String = SaDataRoot.path("test_taken_chord_profiles")

## Whether the app's commands are in the `InputMap` already. Once per run, as in
## `test_shortcut_editor.gd`, because a second registration of an id is refused.
var _commands_built: bool = false

## The events themselves, put back after each case, because the map is global
## and a restore from text would move a physically bound key to a keycode one.
var _saved_events: Dictionary = {}
var _saved_profile: String = ""

## The registries a page is bound to, held for the length of a case, so a row
## reads as the command's own title, Undo rather than Edit Undo.
var _registries: SaRegistries = null


func _build_app_commands() -> void:
    if _commands_built:
        return
    _commands_built = true
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var router := ShortcutRouter.new()
    router.bind_commands(registries.commands)
    router.free()


func before_each() -> void:
    _build_app_commands()
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    SaShortcutStore.dir_override = scratch_dir
    SaShortcutStore.capture_defaults()
    _saved_profile = SaSettings.shortcuts_profile
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)


func after_each() -> void:
    ShortcutRouter.capture_in_progress = false
    # Krita's table names the four filters a module registers, and applying it
    # makes their actions when no module has, so a case that went to Krita
    # leaves them behind for the next suite to save into a profile.
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


## A page bound to the menus' commands, the way Preferences binds it.
func _page() -> SaShortcutsPage:
    _registries = Fixtures.make_menu_registries()
    var page := SaShortcutsPage.new()
    page.bind_tools(_registries.tools, _registries.filters, _registries.commands)
    return page


## The press a keyboard sends for *chord*.
func _press(chord: String) -> InputEventKey:
    var event := SaShortcutStore.parse_chord(chord)
    event.physical_keycode = event.keycode
    event.pressed = true
    return event


## Every row reads what the store holds, "Set…" for a command with no chord.
## The page's own promise, asked after every step below: it never shows a chord
## the store does not hold.
func _rows_match_the_store(page: SaShortcutsPage, when: String) -> void:
    var wrong: Array[String] = []
    for group: Array in SaShortcutsPage.GROUPS:
        for action: StringName in SaShortcutsPage.actions_for(String(group[0])):
            var held := SaShortcutStore.chords_for(action)
            var expected: Array[String] = held.duplicate()
            if expected.is_empty():
                expected.append(SaShortcutsPage.NO_CHORD_TEXT)
            if page.chords_shown(action) != expected:
                wrong.append("%s shows %s, holds %s" % [action, page.chords_shown(action), held])
    assert_eq(wrong, [] as Array[String], "%s, every row shows what the store holds" % when)


func _start_again_button(page: SaShortcutsPage) -> Button:
    return page.find_child("ResetAllButton", true, false) as Button


## The retake's own steps: Redo on Ctrl+Z, shared on purpose,
## then Start again.
func test_start_again_after_redo_on_ctrl_z_puts_both_back() -> void:
    var page := _page()
    assert_eq(_start_again_button(page).text, "Back to Sara Default", "Start again names the map it goes back to")

    page.offer(&"edit_redo", "Ctrl+Z")
    page.question.buttons[SaShortcutsPage.ANSWER_SHARE].pressed.emit()
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), ["Ctrl+Z"] as Array[String], "Shared, Undo keeps Ctrl+Z")
    assert_eq(SaShortcutStore.chords_for(&"edit_redo"), ["Ctrl+Z"] as Array[String], "and Redo has it too")
    assert_eq(page.active_profile(), "Sara Default (custom)", "The edit forked the shipped profile")
    assert_eq(_start_again_button(page).text, "Back to Sara Default", "and the button still names the shipped one")
    _rows_match_the_store(page, "After the share")

    _start_again_button(page).pressed.emit()
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), ["Ctrl+Z"] as Array[String], "Start again leaves Undo on Ctrl+Z")
    assert_eq(SaShortcutStore.chords_for(&"edit_redo"), ["Ctrl+Shift+Z"] as Array[String], "and Redo on its shipped chord")
    assert_eq(page.active_profile(), SaShortcutStore.DEFAULT_PROFILE, "The dropdown is on the shipped profile")
    assert_true(SaShortcutStore.list_profiles().has("Sara Default (custom)"), "and the fork is kept, not deleted")
    assert_eq(SaShortcutStore.all_conflicts().size(), 0, "Nothing clashes after it")
    _rows_match_the_store(page, "After Start again")
    page.free()


## A fork of Krita goes back to Krita, which is the profile it came from, and a
## profile of the painter's own goes back to Sara Default, whose map its file is
## a difference from.
func test_start_again_names_and_applies_the_profile_the_fork_came_from() -> void:
    assert_eq(SaShortcutStore.shipped_source("Krita (custom)"), "Krita", "A Krita fork comes from Krita")
    assert_eq(SaShortcutStore.shipped_source("Photoshop"), "Photoshop", "a shipped profile from itself")
    assert_eq(SaShortcutStore.shipped_source("Mine"), SaShortcutStore.DEFAULT_PROFILE, "and a painter's own from Sara Default")
    assert_eq(SaShortcutStore.shipped_source("default"), SaShortcutStore.DEFAULT_PROFILE, "as does the old settings word")

    var page := _page()
    page.select_profile("Krita")
    var krita_deselect := SaShortcutStore.chords_for(&"select_none")
    page.rebind(&"select_none", "Ctrl+Alt+F9")
    assert_eq(page.active_profile(), "Krita (custom)", "An edit on Krita forks Krita")
    assert_eq(_start_again_button(page).text, "Back to Krita", "and Start again names Krita")

    _start_again_button(page).pressed.emit()
    assert_eq(page.active_profile(), "Krita", "It goes back to Krita")
    assert_eq(SaShortcutStore.chords_for(&"select_none"), krita_deselect, "with Krita's own Deselect")
    assert_eq(_start_again_button(page).text, "Back to Krita", "The button keeps naming it")
    _rows_match_the_store(page, "After Start again on Krita")
    page.free()


## The third case: a taken chord asks before it moves, the row shows
## what the store holds while it asks, and each answer does what it says.
func test_a_taken_chord_asks_before_it_moves() -> void:
    var page := _page()
    page.begin_capture(&"edit_redo")
    page._input(_press("Ctrl+Z"))
    assert_not_null(page.question, "Ctrl+Z, which Undo holds, asks before it lands")
    assert_true(page.question.text_label.text.contains("Undo"), "The question names Undo: %s" % page.question.text_label.text)
    assert_true(page.question.text_label.text.contains("Redo"), "and the row that asked")
    assert_eq(page.question.buttons[SaShortcutsPage.ANSWER_MOVE].text, "Use for Redo", "Its first answer moves the shortcut")
    assert_eq(SaShortcutStore.chords_for(&"edit_redo"), ["Ctrl+Shift+Z"] as Array[String], "Nothing moved while it asks")
    assert_eq(page.listening, &"", "and the row stopped listening")
    _rows_match_the_store(page, "While the question is up")

    page.question.buttons[SaShortcutsPage.ANSWER_MOVE].pressed.emit()
    assert_null(page.question, "The answer closes the question")
    assert_eq(SaShortcutStore.chords_for(&"edit_redo"), ["Ctrl+Z"] as Array[String], "Moved, Redo answers Ctrl+Z")
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), [] as Array[String], "and Undo has let it go")
    assert_eq(page.conflicting_actions(), [] as Array[StringName], "so no row is marked")
    _rows_match_the_store(page, "After the move")

    # The second half of a swap, which no longer passes through a clash:
    # Ctrl+Shift+Z is free since Redo gave it up.
    page.begin_capture(&"edit_undo")
    page._input(_press("Ctrl+Shift+Z"))
    assert_null(page.question, "A free chord lands without a question")
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), ["Ctrl+Shift+Z"] as Array[String], "so the swap is done")

    page.begin_capture(&"edit_copy")
    page._input(_press("Ctrl+N"))
    assert_not_null(page.question, "Ctrl+N, which New holds, asks too")
    page.question.buttons[SaShortcutsPage.ANSWER_CANCEL].pressed.emit()
    assert_eq(SaShortcutStore.chords_for(&"edit_copy"), ["Ctrl+C"] as Array[String], "Cancel leaves Copy on Ctrl+C")
    assert_eq(SaShortcutStore.chords_for(&"file_new"), ["Ctrl+N"] as Array[String], "and New on Ctrl+N")
    _rows_match_the_store(page, "After Cancel")
    page.free()


## A clash shared on purpose is saved as it stands. A profile holding Redo
## alone would, applied again, take Ctrl+Z off Undo, which the page had shown
## holding it: the next launch would have left Undo with no chord.
func test_a_shared_chord_comes_back_from_the_profile_as_it_was_saved() -> void:
    SaShortcutStore.set_chords(&"edit_redo", ["Ctrl+Z"])
    SaShortcutStore.save_profile("Shared")
    var stored := SaShortcutStore.load_profile("Shared")
    assert_eq(stored.get("edit_undo", []), ["Ctrl+Z"], "The file names Undo beside the override that shares its key")

    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    SaShortcutStore.apply_profile("Shared")
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), ["Ctrl+Z"] as Array[String], "Applied again, Undo keeps Ctrl+Z")
    assert_eq(SaShortcutStore.chords_for(&"edit_redo"), ["Ctrl+Z"] as Array[String], "and Redo has it as saved")


## The line under a clashing row names every holder and says which of them a
## press goes to, by the router's order: the history before any command.
func test_a_clash_left_standing_names_every_holder_under_the_row() -> void:
    var page := _page()
    page.offer(&"edit_redo", "Ctrl+Z")
    page.question.buttons[SaShortcutsPage.ANSWER_SHARE].pressed.emit()
    var redo_line := page.clash_line(&"edit_redo")
    assert_true(
        redo_line.contains("Ctrl+Z is also used by") and redo_line.contains("Undo"), "Redo's line names Undo: %s" % redo_line
    )
    assert_true(redo_line.contains("Ctrl+Z runs Undo."), "and says a press runs Undo, which the router reads first")
    var undo_line := page.clash_line(&"edit_undo")
    assert_true(undo_line.contains("Ctrl+Z runs this command."), "Undo's own line says the press is its: %s" % undo_line)
    var shown := page.find_child("ClashLine", true, false)
    assert_not_null(shown, "The line is a label on the page")
    var visible_lines: Array[String] = []
    for node: Node in page.find_children("ClashLine", "Label", true, false):
        if (node as Label).visible:
            visible_lines.append((node as Label).text)
    assert_eq(visible_lines.size(), 2, "Two rows show a line, Undo's and Redo's: %s" % str(visible_lines))
    assert_true(visible_lines.has(redo_line), "and Redo's shows what clash_line says")

    page.reset_action(&"edit_redo")
    assert_eq(page.clash_line(&"edit_redo"), "", "Reset clears the line")
    visible_lines.clear()
    for node: Node in page.find_children("ClashLine", "Label", true, false):
        if (node as Label).visible:
            visible_lines.append((node as Label).text)
    assert_eq(visible_lines, [] as Array[String], "and hides it on every row")
    page.free()
