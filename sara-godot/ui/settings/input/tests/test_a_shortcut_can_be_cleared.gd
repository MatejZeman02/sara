## A shortcut can be cleared, and Backspace and Delete clear a
## capture.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The `shell` sweep's F2. A painter clicked the key button of Clear the layer
## and pressed Backspace, then Delete, and was asked whether to move a key off
## another command each time, because both were taken as chords. Krita and
## Photoshop clear the binding instead, so here an unmodified Backspace or Delete
## takes the chord off the row it was captured on, a Clear button does the same
## for the whole row, and Reset is the way Delete comes back. The cleared state
## is what a profile holds as an empty list, so it has to survive a reload.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_dir: String = SaDataRoot.path("test_cleared_shortcut_profiles")

## Once per run, as in the suites beside this one: a second registration of a
## command's id is refused.
var _commands_built: bool = false

## The events themselves, put back after each case, because the map is global.
var _saved_events: Dictionary = {}
var _saved_profile: String = ""
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


func _button(page: SaShortcutsPage, node_name: String) -> Button:
    return page.find_child(node_name, true, false) as Button


## The two keys, one after the other on a fresh capture each time, with Reset
## between them, the way the sweep pressed them.
func test_backspace_and_delete_clear_the_chord_they_are_captured_on() -> void:
    var page := _page()
    var shipped := SaShortcutStore.chords_for(&"layer_clear")
    assert_true(shipped.has("Delete") and shipped.has("Backspace"), "Clear the layer ships on both keys: %s" % str(shipped))
    for key: String in ["Backspace", "Delete"]:
        page.begin_capture(&"layer_clear")
        assert_eq(page.chords_shown(&"layer_clear")[0], SaShortcutsPage.LISTENING_TEXT, "The row waits for a key")
        page._input(_press(key))
        assert_null(page.question, "%s asks nothing" % key)
        assert_eq(page.listening, &"", "and ends the capture")
        assert_false(ShortcutRouter.capture_in_progress, "handing the keys back")
        assert_eq(SaShortcutStore.chords_for(&"layer_clear"), [] as Array[String], "%s leaves the command with no chord" % key)
        assert_eq(page.chords_shown(&"layer_clear"), [SaShortcutsPage.NO_CHORD_TEXT] as Array[String], "so the row reads Set…")
        assert_false(_button(page, "Reset_layer_clear").disabled, "with Reset lit")
        assert_true(_button(page, "Clear_layer_clear").disabled, "and Clear dimmed, nothing being left to clear")

        _button(page, "Reset_layer_clear").pressed.emit()
        assert_eq(SaShortcutStore.chords_for(&"layer_clear"), shipped, "Reset gives the shipped chords back after %s" % key)
        assert_true(_button(page, "Reset_layer_clear").disabled, "and dims again")
        assert_false(_button(page, "Clear_layer_clear").disabled, "while Clear lights")
    page.free()


## Escape is the way out of a capture and stays it.
func test_escape_leaves_the_chord_alone() -> void:
    var page := _page()
    var shipped := SaShortcutStore.chords_for(&"layer_clear")
    page.begin_capture(&"layer_clear")
    page._input(_press("Escape"))
    assert_eq(SaShortcutStore.chords_for(&"layer_clear"), shipped, "Escape leaves the chords where they were")
    assert_eq(page.chords_shown(&"layer_clear"), shipped, "and the row says so")
    assert_null(page.question, "with no question")
    assert_eq(page.listening, &"", "and no capture left running")
    assert_eq(page.active_profile(), SaShortcutStore.DEFAULT_PROFILE, "and nothing forked")
    page.free()


## With a modifier held the two keys are chords like any other.
func test_a_modified_delete_or_backspace_is_still_a_chord() -> void:
    var page := _page()
    page.begin_capture(&"layer_clear")
    page._input(_press("Ctrl+Delete"))
    assert_eq(SaShortcutStore.chords_for(&"layer_clear"), ["Ctrl+Delete"] as Array[String], "Ctrl+Delete is bound")
    page.begin_capture(&"layer_clear")
    page._input(_press("Shift+Backspace"))
    assert_eq(SaShortcutStore.chords_for(&"layer_clear"), ["Shift+Backspace"] as Array[String], "so is Shift+Backspace")
    page.free()


## A command with several chords loses the one whose button was clicked.
func test_a_capture_on_one_of_several_chords_clears_only_that_one() -> void:
    var page := _page()
    var clear_chords := SaShortcutStore.chords_for(&"layer_clear")
    page.begin_capture(&"layer_clear", clear_chords.find("Delete"))
    page._input(_press("Backspace"))
    assert_eq(SaShortcutStore.chords_for(&"layer_clear"), ["Backspace"] as Array[String], "Delete went and Backspace stayed")
    assert_false(_button(page, "Clear_layer_clear").disabled, "so Clear stays lit")
    page.reset_action(&"layer_clear")
    var before := SaShortcutStore.chords_for(&"view_zoom_in")
    assert_true(before.size() >= 2, "Zoom in answers to more than one chord: %s" % str(before))
    page.begin_capture(&"view_zoom_in", 1)
    page._input(_press("Backspace"))
    var expected := before.duplicate()
    expected.remove_at(1)
    assert_eq(SaShortcutStore.chords_for(&"view_zoom_in"), expected, "only the second chord went")
    page.free()


## The row's own button, for a painter who would rather click.
func test_the_clear_button_takes_every_chord_off_the_row() -> void:
    var page := _page()
    var clear := _button(page, "Clear_view_zoom_in")
    assert_not_null(clear, "A row has a Clear button")
    assert_false(clear.disabled, "lit while the row holds a chord")
    clear.pressed.emit()
    assert_eq(SaShortcutStore.chords_for(&"view_zoom_in"), [] as Array[String], "and it takes them all")
    assert_true(_button(page, "Clear_view_zoom_in").disabled, "then dims")

    # A row nobody bound cannot be cleared, and a refused clear writes nothing.
    var profile := page.active_profile()
    page.clear(&"tool_eyedropper")
    page.clear(&"view_zoom_in")
    assert_eq(page.active_profile(), profile, "Clearing a row with nothing on it forks no profile")
    page.free()


## The restart case: the cleared state is in the saved profile as an empty
## list and a reload gives it back, rather than falling to the shipped chord.
func test_a_cleared_default_survives_a_reload() -> void:
    var page := _page()
    var shipped := SaShortcutStore.chords_for(&"layer_clear")
    page.begin_capture(&"layer_clear")
    page._input(_press("Backspace"))
    var forked := page.active_profile()
    assert_eq(forked, "Sara Default (custom)", "The clear forked the shipped profile")
    assert_true(SaShortcutStore.overrides_now().has("layer_clear"), "and the store sees the difference")
    assert_eq(SaShortcutStore.overrides_now()["layer_clear"], [], "as an empty list")

    var stored := SaShortcutStore.load_profile(forked)
    assert_true(stored.has("layer_clear"), "The saved file names the action")
    assert_eq(stored["layer_clear"], [], "with an empty list, not a missing entry")

    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(SaShortcutStore.chords_for(&"layer_clear"), shipped, "Sara Default has its chords again")
    SaShortcutStore.apply_profile(forked)
    assert_eq(SaShortcutStore.chords_for(&"layer_clear"), [] as Array[String], "and the fork applied clears it again")
    page.free()

    var next_launch := _page()
    assert_eq(next_launch.chords_shown(&"layer_clear"), [SaShortcutsPage.NO_CHORD_TEXT] as Array[String], "A new page shows Set…")
    assert_false(_button(next_launch, "Reset_layer_clear").disabled, "with Reset lit")
    # A profile switch puts the shipped chord back, which is the other way home.
    next_launch.select_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(SaShortcutStore.chords_for(&"layer_clear"), shipped, "Switching to Sara Default gives Delete back")
    next_launch.free()


## A capture and a question both begin while an earlier question is up, because
## it is a window and not a modal one. The page holds only the last, so the
## first would be left on screen with nothing to answer it.
func test_a_second_capture_answers_the_standing_question_cancel() -> void:
    var page := _page()
    page.begin_capture(&"edit_redo")
    page._input(_press("Ctrl+Z"))
    var first := page.question
    assert_not_null(first, "Ctrl+Z asks, Undo holds it")

    page.begin_capture(&"edit_copy")
    assert_null(page.question, "A new capture leaves no question standing on the page")
    assert_false(first.visible, "and the window itself is closed")
    assert_eq(SaShortcutStore.chords_for(&"edit_redo"), ["Ctrl+Shift+Z"] as Array[String], "Redo is as it was, which is Cancel")
    page._input(_press("Ctrl+N"))
    var second := page.question
    assert_not_null(second, "Ctrl+N asks in turn")
    page.offer(&"edit_copy", "Ctrl+Z")
    assert_false(second.visible, "and a second question closes the first")
    assert_not_null(page.question, "keeping only its own")
    page.question.buttons[SaShortcutsPage.ANSWER_CANCEL].pressed.emit()
    assert_null(page.question, "which answers as before")
    page.free()
