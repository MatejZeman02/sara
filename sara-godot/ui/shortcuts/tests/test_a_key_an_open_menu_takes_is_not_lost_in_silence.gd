## A plain key an open menu takes from a command says so in
## the corner, a key the menu uses says nothing, and a chord still runs.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A press a few pixels high opens the Tools menu, and
## Insert, Page Up, Page Down and Ctrl+Shift+N then did nothing in silence. The
## File menu here is the bar's own list, a real window in the root with
## embedding forced, as `test_an_open_menu_gives_way_to_the_title_the_pointer_moves_onto.gd`
## stands it, and the router watches it as it watches every window the app
## opens. A key reaches the router through the popup's `window_input`, which is
## where the engine hands it. Everything is asked in one frame, since a suite
## that awaits drops every assertion after the await.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The layers live on a document, and the lists are real windows.
const REQUIRES_GPU := true

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _router: ShortcutRouter = null
var _host: Control = null
var _bar: TopMenuBar = null
var _lines: Array = []
var _was_embedding: bool = false
var _saved_events: Dictionary = {}


## The application's commands before the map is saved, because a profile makes
## any action it names that does not exist yet.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _registries = Fixtures.make_registries(_surface)
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _lines.clear()
    EventBus.corner_notice.connect(_on_corner)


func after_each() -> void:
    EventBus.corner_notice.disconnect(_on_corner)
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    if _host != null:
        _host.free()
    _host = null
    _bar = null
    if _router != null:
        _router.free()
    _router = null
    _registries = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


func _on_corner(line: String) -> void:
    _lines.append(line)


## The bar and the router in the root's tree, with the File menu open and the
## router watching its window. Returns the open list.
func _open_file_menu(profile: String) -> SaChoicePopup:
    SaShortcutStore.apply_profile(profile)
    _router = ShortcutRouter.new()
    _router.tool_machine_provider = func() -> ToolMachine: return _machine
    _router.bind_commands(_registries.commands)
    _host = Control.new()
    _host.name = "U522BarHost"
    _host.size = Vector2((Engine.get_main_loop() as SceneTree).root.size)
    EventBus.add_child(_host)
    _host.add_child(_router)
    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(_registries.commands)
    _bar._on_menu_button_pressed("File")
    var menu: SaChoicePopup = _bar.menus["File"]
    assert_true(menu.visible, "The File menu is open")
    _router.watch_window(menu)
    return menu


func _press(menu: Window, keycode: Key, ctrl: bool = false, shift: bool = false) -> void:
    var key := InputEventKey.new()
    key.keycode = keycode
    key.physical_keycode = keycode
    key.ctrl_pressed = ctrl
    key.shift_pressed = shift
    key.pressed = true
    menu.window_input.emit(key)
    var up := key.duplicate() as InputEventKey
    up.pressed = false
    menu.window_input.emit(up)


func _layer_count() -> int:
    return SaLayerOps.new(_surface.easel.document).layers().size()


func test_insert_in_the_krita_profile_leaves_the_document_and_says_a_menu_is_open() -> void:
    var menu := _open_file_menu("Krita")
    assert_true(InputMap.action_has_event(&"layer_new_paint", _bare(KEY_INSERT)), "Krita binds Insert to a new paint layer")
    var before := _layer_count()
    _press(menu, KEY_INSERT)
    assert_eq(_layer_count(), before, "Insert over the open menu adds no layer")
    assert_eq(_lines.size(), 1, "and the corner gets one line: %s" % [_lines])
    var line: String = _lines[0] if not _lines.is_empty() else ""
    assert_true(line.contains("Insert") and line.contains("menu"), "naming Insert and the menu: %s" % line)
    assert_true(line.contains("Escape"), "and the key that closes it")


## The running app opens the bar's menus with their search field shown and
## focused, and a field takes the characters and the editing keys, not Insert.
func test_insert_with_the_search_field_focused_still_says_so() -> void:
    var menu := _open_file_menu("Krita")
    menu.search.show()
    menu.search.grab_focus()
    assert_true(menu.gui_get_focus_owner() == menu.search, "The search field holds the focus")
    _press(menu, KEY_INSERT)
    assert_eq(_lines.size(), 1, "Insert names itself over the field: %s" % [_lines])


## Page Up is the engine's own `ui_page_up` as well as Krita's layer walk, and
## the Krita binding is what makes it a command's key.
func test_page_up_in_the_krita_profile_says_so_too() -> void:
    var menu := _open_file_menu("Krita")
    _press(menu, KEY_PAGEUP)
    assert_eq(_lines.size(), 1, "Page Up names itself: %s" % [_lines])


func test_an_arrow_enter_and_a_letter_over_the_open_menu_say_nothing() -> void:
    var menu := _open_file_menu("Krita")
    _press(menu, KEY_DOWN)
    _press(menu, KEY_UP)
    _press(menu, KEY_B)
    assert_eq(_lines, [], "The keys the menu walks and jumps by write no line")


## A key no command holds would have done nothing with the menu shut as well.
func test_a_key_no_command_holds_says_nothing() -> void:
    var menu := _open_file_menu("Krita")
    _press(menu, KEY_F20)
    assert_eq(_lines, [], "An unbound key writes no line")


## Sara's own chord for a new paint layer, which the Krita profile leaves
## unbound because Krita gives the layer to Insert. So that dead
## key was not lost to the menu: it was pressed in a profile where it is nobody's.
func test_ctrl_shift_n_over_the_open_menu_runs_the_new_layer() -> void:
    var menu := _open_file_menu(SaShortcutStore.DEFAULT_PROFILE)
    assert_true(InputMap.action_has_event(&"layer_new_paint", _bare(KEY_N, true, true)), "Sara Default binds Ctrl+Shift+N")
    var before := _layer_count()
    _press(menu, KEY_N, true, true)
    assert_eq(_layer_count(), before + 1, "Ctrl+Shift+N over the open menu adds a layer")
    assert_eq(_lines, [], "and the corner says nothing about the menu")


func test_ctrl_shift_n_is_bound_to_nothing_in_the_krita_profile() -> void:
    _open_file_menu("Krita")
    var chord := _bare(KEY_N, true, true)
    var holders: Array = []
    for action: StringName in InputMap.get_actions():
        if InputMap.event_is_action(chord, action, true):
            holders.append(action)
    assert_eq(holders, [], "No action of the Krita profile holds Ctrl+Shift+N")


func _bare(keycode: Key, ctrl: bool = false, shift: bool = false) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = keycode
    key.physical_keycode = keycode
    key.ctrl_pressed = ctrl
    key.shift_pressed = shift
    key.pressed = true
    return key
