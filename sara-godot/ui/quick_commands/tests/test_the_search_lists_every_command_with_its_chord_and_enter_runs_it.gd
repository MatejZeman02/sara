## F3 searches every command, a module's as well. Blender's Menu
## Search on F3 is the inspiration, and no code of Blender's is taken.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The list is read from the command registry and only asks the bar where a
## command sits, so a command a module registers with no menu row is found the
## same way an Edit row is. The field is typed into key by key and Enter is a
## key the open list is given, the way `test_space_in_a_search.gd` gives them.
## F3 opens `SaSearchWindow`, the one search the loupe
## opens too, whose rows are its entries by title, with the place and the chord
## in columns of their own.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const MODULE := &"owl_module"
const OWLS := &"count_the_owls"
const DIMMED := &"dimmed_owls"

var _registries: SaRegistries = null
var _bar: TopMenuBar = null
var _window: SaSearchWindow = null
var _host: Node = null
var _was_embedding := false
var _actions_before: Array[StringName] = []
## How many times the module's command ran, in a box a lambda can write.
var _owls: Array[int] = [0]


## A filter of the module's own, so the search has one to list under its
## section. Its members are written in `_init` alone.
class HootFilter:
    extends SaFilter

    func title() -> String:
        return "Hoot"

    func family() -> StringName:
        return &"owls"

    func run(_ctx: SaFilterContext) -> void:
        pass


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U40SearchHost"
    EventBus.add_child(_host)
    _actions_before = InputMap.get_actions()
    _owls[0] = 0
    _registries = Fixtures.make_menu_registries()
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(_registries.commands)
    (_bar.menu("Filter") as SaFilterMenu).filters = _registries.filters
    var module := _registries.context.for_module(MODULE)
    var owls := SaCommandDescriptor.create(OWLS, "Count the owls", _count_owls)
    owls.label = "Count the Owls"
    var chord := InputEventKey.new()
    chord.keycode = KEY_F11
    chord.ctrl_pressed = true
    chord.alt_pressed = true
    owls.default_events = [chord]
    module.register_command(owls)
    var dimmed := SaCommandDescriptor.create(DIMMED, "Count the dimmed owls", _count_owls)
    dimmed.label = "Count the Dimmed Owls"
    dimmed.enabled = func() -> bool: return false
    module.register_command(dimmed)
    module.register_filter_section(&"owls", "Owls", 900)
    module.register_filter(HootFilter.new())


func after_each() -> void:
    if _bar != null:
        _bar.free()
        _bar = null
    _host.free()
    _window = null
    _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding
    _registries.commands.unregister_module(MODULE)
    _registries = null
    for action: StringName in InputMap.get_actions():
        if not _actions_before.has(action):
            InputMap.erase_action(action)


func _count_owls() -> bool:
    _owls[0] += 1
    return true


## The search opened in the tree, its field holding the keyboard.
func _open() -> SaSearchWindow:
    _window = SaSearchWindow.new(SaSearchIndex.new(_registries.context), _bar)
    _host.add_child(_window)
    _window.open()
    _window.search.grab_focus()
    return _window


func _press(list: SaChoicePopup, keycode: Key, unicode: int = 0) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.unicode = unicode
    event.pressed = true
    list.push_input(event)


func _type(list: SaChoicePopup, text: String) -> void:
    for i in text.length():
        var letter := text[i]
        var keycode := KEY_SPACE if letter == " " else OS.find_keycode_from_string(letter.to_upper())
        _press(list, keycode, text.unicode_at(i))
    list.search.text_changed.emit(list.search.text)


## The drawn row titled *title*, or `&""`.
func _row(list: SaSearchWindow, title: String) -> StringName:
    for row_id: StringName in list.row_ids():
        if list.is_row_shown(row_id) and list.label_button(row_id).text == title:
            return row_id
    return &""


## The text of *row*'s column *cell*, Kind, Place or Chord.
func _cell(list: SaSearchWindow, row: StringName, cell: String) -> String:
    return (list.row_of(row).get_node(cell) as Label).text


func test_part_of_a_label_finds_the_command_with_its_menu_path_and_chord() -> void:
    var list := _open()
    assert_true(list.search.visible, "The search carries its field however few commands there are")

    _type(list, "redo")

    var redo := _row(list, "Redo")
    assert_false(redo.is_empty(), "Typing part of Redo's label lists Redo")
    assert_eq(list.entry_of(redo).command, &"edit_redo", "as the command it is")
    assert_eq(_cell(list, redo, "Place"), "Edit", "under the menu it sits in")
    assert_eq(_cell(list, redo, "Chord"), _bar.menu("Edit").chord_of(&"edit_redo"), "with the chord its menu row names")
    assert_eq(_cell(list, redo, "Chord"), "Ctrl+Shift+Z", "which is Ctrl+Shift+Z on the shipped map")
    assert_true(_row(list, "Undo").is_empty(), "and Undo, which the letters do not spell, is left out")


func test_enter_runs_the_command_the_letters_found_a_modules_too() -> void:
    var list := _open()

    _type(list, "the owls")

    var owls := _row(list, "Count the owls")
    assert_false(owls.is_empty(), "A module's command is listed though no menu holds it")
    assert_eq(list.entry_of(owls).command, OWLS, "as the module's command")
    assert_eq(_cell(list, owls, "Chord"), "Ctrl+Alt+F11", "with the chord the module gave it")
    assert_eq(list.highlighted(), owls, "and the keyboard is on it")

    _press(list, KEY_ENTER)

    assert_eq(_owls[0], 1, "Enter runs the command the field left the keyboard on")
    assert_false(list.visible, "and closes the search")
    assert_eq(SaQuickCommands.last_run, OWLS, "and Repeat Last keeps it")


func test_a_dimmed_command_is_listed_dimmed_and_does_not_run() -> void:
    var list := _open()

    _type(list, "dimmed owls")

    var dimmed := _row(list, "Count the dimmed owls")
    assert_false(dimmed.is_empty(), "A command that cannot run now is still listed")
    assert_true(list.is_disabled(dimmed), "dimmed")
    assert_false(list.press_row(dimmed), "and a press on it is refused")
    assert_false(SaQuickCommands.run(DIMMED), "as is running it from the search's own door")
    assert_eq(_owls[0], 0, "so it never ran")


func test_the_search_lists_a_filter_under_its_section() -> void:
    var list := _open()
    _type(list, "hoot")
    var keys := _registries.filters.list_keys()
    assert_eq(keys.size(), 1, "The module registered one filter")
    var hoot := _row(list, "Hoot")
    assert_false(hoot.is_empty(), "and the search lists it")
    assert_eq(_cell(list, hoot, "Place"), "Filter > Owls", "under the Filter menu's section for it")
    var command_id := SaFilterRegistry.command_for(keys[0], _registries.filters.get_filter(keys[0]))
    assert_eq(list.entry_of(hoot).command, command_id, "as the command its row runs")
    list.search.text = "repeat last"
    list.search.text_changed.emit(list.search.text)
    var commands: Array[StringName] = []
    for entry: SaSearchIndex.Entry in list.shown:
        commands.append(entry.command)
    assert_true(commands.has(SaQuickCommands.REPEAT), "Repeat Last is a command like any other")
