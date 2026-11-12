## Quick Favourites, added from a menu row's right click and
## opened on Shift+Q, kept with the shortcut profile. Blender's Quick Favourites
## on Q is the inspiration, on Shift+Q here because Q alone is the Pan tool, and
## no code of Blender's is taken.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Redo is added before Undo, the reverse of the Edit menu and of the alphabet,
## so the order read back can only be the order they were added in. The list
## lives in the profile's own file beside its chords, which is why it comes back
## when the profile is loaded afresh and stays through a rebind saved over it.
## Most cases open the offer through `ask_row`, and one presses it the two ways
## a hand does, a right press on the row's button and the Menu key on the
## highlighted row given to the list's window.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_dir: String = SaDataRoot.path("test_quick_favourites")

var _registries: SaRegistries = null
var _bar: TopMenuBar = null
var _saved_events: Dictionary = {}
var _saved_profile: String = ""
var _lists: Array[SaChoicePopup] = []
var _host: Node = null
var _was_embedding := false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U40FavouritesHost"
    EventBus.add_child(_host)
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
    for list: SaChoicePopup in _lists:
        if is_instance_valid(list):
            list.free()
    _lists.clear()
    _bar.free()
    _bar = null
    _host.free()
    _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding
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


## The Edit menu's row for *command_id*.
func _edit_row(command_id: StringName) -> StringName:
    var edit := _bar.menu("Edit")
    for row_id: StringName in edit.popup.row_ids():
        if edit.row_command(row_id) == command_id:
            return row_id
    return &""


## What a right press on the Edit menu's row for *command_id* opens.
func _right_click(command_id: StringName) -> SaChoicePopup:
    var row_id := _edit_row(command_id)
    assert_false(row_id.is_empty(), "The Edit menu has a row for %s" % command_id)
    return _bar.menu("Edit").ask_row(row_id)


## The list Shift+Q opens, as it would open now.
func _favourites() -> SaChoicePopup:
    var list := SaQuickCommands.favourites_list()
    _lists.append(list)
    return list


func _shown(list: SaChoicePopup) -> Array[StringName]:
    return list.row_ids().filter(func(row_id: StringName) -> bool: return row_id != QuickFavourites.EMPTY_ROW)


func test_two_rows_added_from_the_menu_are_listed_in_the_order_added() -> void:
    assert_eq(_shown(_favourites()), [] as Array[StringName], "Nothing is a favourite before a row is added")

    var asked := _right_click(&"edit_redo")
    assert_eq(
        asked.row_ids(),
        [SaQuickCommands.ROW_ADD, SaQuickCommands.ROW_ASSIGN] as Array[StringName],
        "A right click on a menu row offers Add to Quick Favourites and Assign Shortcut"
    )
    assert_true(asked.press_row(SaQuickCommands.ROW_ADD), "Add to Quick Favourites can be pressed")
    assert_true(_right_click(&"edit_undo").press_row(SaQuickCommands.ROW_ADD), "and the second row is added the same way")

    var list := _favourites()
    assert_eq(_shown(list), [&"edit_redo", &"edit_undo"] as Array[StringName], "Shift+Q lists both, in the order added")
    assert_eq(list.label_button(&"edit_redo").text, "Redo", "under their menu words")
    assert_eq(list.row_of(&"edit_undo").hint_text(), "Ctrl+Z", "with their chords")
    assert_eq(
        SaSettings.shortcuts_profile,
        SaShortcutStore.target_profile(SaShortcutStore.DEFAULT_PROFILE),
        "The first favourite forks the shipped profile, as the first rebind does"
    )


func test_the_favourites_come_back_when_the_profile_is_loaded_afresh() -> void:
    _right_click(&"edit_redo").press_row(SaQuickCommands.ROW_ADD)
    _right_click(&"edit_undo").press_row(SaQuickCommands.ROW_ADD)
    var fork := SaSettings.shortcuts_profile

    SaShortcutStore.set_chords(&"edit_redo", ["Ctrl+Y"])
    SaShortcutStore.remember_edit()
    assert_eq(SaShortcutStore.load_profile(fork).get("edit_redo", []), ["Ctrl+Y"], "A rebind saved over the profile")
    SaSettings.shortcuts_profile = "Photoshop"
    SaShortcutStore.apply_profile("Photoshop")
    assert_eq(_shown(_favourites()), [] as Array[StringName], "Another profile holds its own favourites, none here")

    SaSettings.shortcuts_profile = fork
    SaShortcutStore.apply_profile(fork)

    var list := _favourites()
    assert_eq(_shown(list), [&"edit_redo", &"edit_undo"] as Array[StringName], "The profile loaded afresh lists both again")
    assert_eq(list.row_of(&"edit_redo").hint_text(), "Ctrl+Y", "beside the chord the rebind saved")


func test_a_favourite_offers_its_removal_on_its_own_right_click() -> void:
    _right_click(&"edit_redo").press_row(SaQuickCommands.ROW_ADD)
    _right_click(&"edit_undo").press_row(SaQuickCommands.ROW_ADD)
    assert_eq(
        _right_click(&"edit_redo").row_ids(),
        [SaQuickCommands.ROW_REMOVE, SaQuickCommands.ROW_ASSIGN] as Array[StringName],
        "A menu row already a favourite offers its removal instead"
    )

    var list := _favourites()
    var asked := SaQuickCommands.offer(list, &"edit_redo", &"edit_redo")
    assert_true(asked.press_row(SaQuickCommands.ROW_REMOVE), "A row of the Shift+Q menu offers Remove from Quick Favourites")

    assert_eq(_shown(_favourites()), [&"edit_undo"] as Array[StringName], "and leaves the other where it was")


func test_a_right_press_or_the_menu_key_on_a_row_opens_the_offer() -> void:
    var edit := _bar.menu("Edit")
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_RIGHT
    press.pressed = true
    edit.popup.label_button(_edit_row(&"edit_redo")).gui_input.emit(press)
    var asked := edit.popup.child_list
    assert_true(asked != null, "A right press on a menu row's own button opens a list beside it")
    assert_true(asked.press_row(SaQuickCommands.ROW_ADD), "whose Add to Quick Favourites keeps the row")
    assert_eq(SaQuickCommands.favourites(), [&"edit_redo"] as Array[StringName], "so Redo is a favourite")

    var list := _favourites()
    _host.add_child(list)
    list.popup(Rect2i(Vector2i(40, 40), Vector2i(320, 200)))
    assert_true(list.set_highlight(&"edit_redo"), "The keyboard is put on the Shift+Q menu's row")
    var key := InputEventKey.new()
    key.keycode = KEY_MENU
    key.pressed = true
    list.push_input(key)
    asked = list.child_list
    assert_true(asked != null and asked.visible, "The Menu key on the highlighted row opens the same list, on screen")
    assert_true(asked.press_row(SaQuickCommands.ROW_REMOVE), "whose Remove from Quick Favourites is pressed")
    assert_eq(SaQuickCommands.favourites(), [] as Array[StringName], "and takes Redo off again")


func test_a_row_no_command_stands_behind_offers_nothing_to_keep() -> void:
    var asked := SaQuickCommands.offer(_bar.menu("Edit").popup, &"no_such_row", &"")
    assert_true(asked.is_disabled(SaQuickCommands.ROW_ADD), "A row with no command cannot be kept")
    assert_true(asked.is_disabled(SaQuickCommands.ROW_ASSIGN), "or given a chord")
