## Reset all preferences was one unasked click among the file
## rows on Files, under Author, where a painter looking for how to reset one page
## would press it. It sits at the foot of the sidebar now, and asks first.
##
## The reset keeps what it does, and an approve dialog saying what will change
## appears. So each case
## presses the button the way a hand does, reads the question, and answers it:
## Cancel leaves every setting and the keymap as they were, Reset puts both
## back. The keymap is the half that was wrong before, the setting saying Sara
## Default while the chords of the profile before it still answered.
##
## The window is opened inside the real tree with subwindows embedded, the way
## `test_preferences_fits_its_pane_and_opens_each_page_at_the_top.gd` opens one,
## because whether a question is up means nothing outside a tree. `SaSettings`
## is pointed at a scratch file for every case, so a setter's save never reaches
## the run's own profile. The case that resets loads that profile back, as
## `test_a_module_keeps_its_own_preferences.gd` does, because a reset rewrites
## every value the suites after this one read. The others put back by hand the
## few they moved, because loading the run's profile back is what costs: with a
## load in every case the suite took 24 seconds of a full run.
extends "res://tests/test_framework.gd"

static var scratch_path: String = SaDataRoot.path("test_reset_all_preferences.cfg")

## The profile the cases move to before the question, and an action it moves.
## Photoshop's `tool_zoom` is the bare Z, which Sara's own map does not give it.
const PROFILE := "Photoshop"
const MOVED_ACTION := &"tool_zoom"

## Settings away from their defaults, one from each of three pages, so a reset
## that did nothing and a cancel that did something both show.
const MOVED := {
    &"sad_versions": 5,
    &"export_author": "Ada",
    &"show_grid": true,
}

var _saved_path: String
var _saved_values: Dictionary = {}
var _saved_events: Dictionary = {}

## Whether the case pressed Reset, which only a load of the run's own profile
## undoes.
var _reset := false
var _was_embedding := true
var _host: Node = null
var _window: SaSettingsWindow = null
var _heard_shortcuts := 0


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _saved_values.clear()
    for property: StringName in MOVED.keys() + [&"shortcuts_profile"]:
        _saved_values[property] = SaSettings.get(String(property))
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    SaSettings.settings_path = _scratch()
    _reset = false

    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "ResetTestHost"
    EventBus.add_child(_host)
    _window = SaSettingsWindow.new()
    _host.add_child(_window)
    _window.show()
    _heard_shortcuts = 0
    EventBus.shortcuts_changed.connect(_on_shortcuts_changed)


func after_each() -> void:
    EventBus.shortcuts_changed.disconnect(_on_shortcuts_changed)
    _window.hide()
    _host.free()
    _host = null
    _window = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding

    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    if _reset:
        SaSettings.config = ConfigFile.new()
        SaSettings.settings_path = _saved_path
        SaSettings.load_settings()
    else:
        for property: StringName in _saved_values:
            SaSettings.set(String(property), _saved_values[property])
        SaSettings.settings_path = _saved_path
    DirAccess.remove_absolute(_scratch())
    DirAccess.remove_absolute(_scratch() + SaSettings.BACKUP_SUFFIX)


func _scratch() -> String:
    return ProjectSettings.globalize_path(scratch_path)


func _on_shortcuts_changed() -> void:
    _heard_shortcuts += 1


## Every setting in `MOVED` away from its default, and the keymap on `PROFILE`
## the way choosing it on the Keyboard Shortcuts page puts it there.
func _move_away() -> void:
    for property: StringName in MOVED:
        SaSettings.set(String(property), MOVED[property])
    SaSettings.shortcuts_profile = PROFILE
    SaShortcutStore.apply_profile(PROFILE)


## Whether each setting in `MOVED` still holds the value `_move_away` gave it.
func _still_moved() -> Dictionary:
    var out := {}
    for property: StringName in MOVED:
        out[property] = SaSettings.get(String(property)) == MOVED[property]
    return out


## The keymap's actions that answer differently from the shipped map, by name.
func _actions_off_the_shipped_map() -> Array[String]:
    var shipped := SaShortcutStore.defaults()
    var off: Array[String] = []
    var now := SaShortcutStore.current_map()
    for action: String in shipped:
        if now.has(action) and now[action] != shipped[action]:
            off.append(action)
    return off


## The page on the right, the last child of the content column.
func _open_page() -> Node:
    return _window.content_container.get_child(_window.content_container.get_child_count() - 1)


func test_the_button_is_at_the_foot_of_the_sidebar_and_not_in_the_list() -> void:
    var button := _window.reset_button
    assert_not_null(button, "The window has a reset button")
    if button == null:
        return
    var column := button.get_parent()
    assert_eq(String(column.name), "Sidebar", "in the sidebar's own column")
    assert_eq(button.get_index(), column.get_child_count() - 1, "as its last child, under the list")
    assert_false(_window.menu_list.is_ancestor_of(button), "and not one of the page buttons")
    assert_eq(_window.category_buttons.size(), _window.categories.size(), "so the list still holds one button per page")
    assert_eq(button.text, "Reset all preferences...", "It says what it does and that it asks")
    assert_false(button.tooltip_text.is_empty(), "and carries a tooltip")


## The search narrows the page list and leaves the way back to every default
## where it was, since a button no page owns matches no page's words.
func test_a_search_leaves_the_button_showing() -> void:
    _window.search.apply("tablet")
    assert_true(_window.reset_button.is_visible_in_tree(), "A search for a page leaves the reset showing")
    _window.search.apply("")


## Files has no reset answer of its own.
func test_files_has_no_reset_row() -> void:
    _window.show_page("Files")
    var files := _open_page() as SaFilesPage
    assert_not_null(files, "Files is open")
    if files == null:
        return
    for row: SaPageRow in files.page.rows():
        assert_false(row.label.contains("Reset"), "and '%s' is not a reset" % row.label)


## A press asks and changes nothing, and the question says what will go back
## and what will stay, naming the three things the sweep asked about.
func test_a_press_asks_and_the_question_names_what_goes_and_what_stays() -> void:
    _move_away()
    _window.reset_button.pressed.emit()
    var question := _window.reset_question
    assert_not_null(question, "The press asks")
    if question == null:
        return
    assert_true(question.visible, "and the question is up")
    assert_eq(question.title, "Reset all preferences", "under the button's own words")
    var text := question.text_label.text
    for goes: String in ["every setting on every page", "theme", "shortcut profile in use", "brush slots", "recent files"]:
        assert_true(text.to_lower().contains(goes), "It says '%s' goes back" % goes)
    for stays: String in ["layouts", "shortcut profiles", "palettes", "pressure curves"]:
        assert_true(text.contains(stays), "and that your %s stay" % stays)
    assert_eq(question.buttons.size(), 2, "Two answers")
    assert_eq(question.buttons[SaSettingsWindow.RESET_CANCEL].text, "Cancel", "Cancel")
    assert_eq(question.buttons[SaSettingsWindow.RESET_CONFIRM].text, "Reset", "and Reset")
    for property: StringName in MOVED:
        assert_true(_still_moved()[property], "Asking moved nothing, %s is as it was" % property)
    question.buttons[SaSettingsWindow.RESET_CANCEL].pressed.emit()


## A second press while the question is up leaves the one question up.
func test_a_second_press_asks_once() -> void:
    _window.reset_button.pressed.emit()
    var first := _window.reset_question
    _window.reset_button.pressed.emit()
    assert_true(_window.reset_question == first, "The second press keeps the first question")
    var questions := 0
    for child in _window.get_children():
        if child is SaMessage and not child.is_queued_for_deletion():
            questions += 1
    assert_eq(questions, 1, "and only one is up")
    first.buttons[SaSettingsWindow.RESET_CANCEL].pressed.emit()


func test_cancel_changes_nothing() -> void:
    _move_away()
    var off_before := _actions_off_the_shipped_map()
    assert_eq(SaShortcutStore.chords_for(MOVED_ACTION), ["Z"] as Array[String], "%s answers Z on %s" % [MOVED_ACTION, PROFILE])
    _window.reset_button.pressed.emit()
    _window.reset_question.buttons[SaSettingsWindow.RESET_CANCEL].pressed.emit()

    assert_null(_window.reset_question, "The question is answered")
    var kept := _still_moved()
    for property: StringName in kept:
        assert_true(kept[property], "Cancel kept %s" % property)
    assert_eq(SaSettings.shortcuts_profile, PROFILE, "and the profile")
    assert_eq(_actions_off_the_shipped_map(), off_before, "and the keymap")
    assert_eq(SaShortcutStore.chords_for(MOVED_ACTION), ["Z"] as Array[String], "%s still answers Z" % MOVED_ACTION)
    assert_eq(_heard_shortcuts, 0, "and nothing announced a new keymap")


## Escape, the close button and every other way out answer Cancel.
func test_closing_the_question_changes_nothing() -> void:
    _move_away()
    _window.reset_button.pressed.emit()
    _window.reset_question.hide()

    var kept := _still_moved()
    for property: StringName in kept:
        assert_true(kept[property], "Closing kept %s" % property)
    assert_eq(SaSettings.shortcuts_profile, PROFILE, "and the profile")


## Reset puts every setting back, and the keymap is Sara Default's at once
## rather than at the next launch, and the page on screen is drawn again over
## the values that are true now.
func test_reset_puts_the_settings_and_the_keymap_back() -> void:
    _move_away()
    _window.show_page("Files")
    var before := _open_page()
    assert_false(_actions_off_the_shipped_map().is_empty(), "%s moves some chords off Sara Default's" % PROFILE)
    _window.reset_button.pressed.emit()
    _reset = true
    _window.reset_question.buttons[SaSettingsWindow.RESET_CONFIRM].pressed.emit()

    var fresh := SaSettingsValues.new()
    for property: StringName in MOVED:
        assert_eq(SaSettings.stored(String(property)), fresh.stored(String(property)), "Reset put %s back" % property)
    assert_eq(SaSettings.shortcuts_profile, fresh.shortcuts_profile, "and the profile")
    fresh.free()
    assert_eq(_actions_off_the_shipped_map(), [] as Array[String], "The keymap is Sara Default's")
    assert_true(SaShortcutStore.chords_for(MOVED_ACTION) != (["Z"] as Array[String]), "so %s no longer answers Z" % MOVED_ACTION)
    assert_eq(_heard_shortcuts, 1, "and the new keymap was announced once")

    var after := _open_page()
    assert_true(after is SaFilesPage, "The page on screen is Files again")
    assert_true(after != before, "built anew over the values that are true now")
