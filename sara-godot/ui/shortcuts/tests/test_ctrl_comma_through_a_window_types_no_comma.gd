## Ctrl+comma pressed over and over typed commas into the Preferences
## search.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Toggling Preferences with Ctrl+comma several times wrote commas into
## the search bar inside it. Eight toggles through a virtual keyboard left `,,,,` in
## the field, one comma for every toggle that shut the window, whichever key was
## let go last (`scripts/virtual_keyboard.py`).
##
## **The route.** An embedded window hands a key to `window_input` first and to
## its own tree after, in `Window::_window_input`. The router answered the chord
## from the signal and called `set_input_as_handled()`, and `Viewport.push_input`
## clears that flag before it does anything else. So the chord went on into
## Preferences, the focused search turned it down in `gui_input` because Ctrl
## was held, and `LineEdit.unhandled_key_input` typed its unicode, which is how
## Godot lets AltGr type, and Ctrl+comma has no control character to stand in
## for the comma. The Preferences toggle came after, deferred. A held chord was
## worse: its repeats were never the router's, so every one typed a comma.
##
## The keys go in through the root, `push_input` on the main window with
## Preferences the focused embedded window, which is the way the desktop's keys
## reach it. Opens real windows, and only a run with a RenderingDevice has one.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## The two ways a painter lets go of the chord, the two the row asks for.
const ORDERS: Array[String] = ["ctrl-last", "comma-last"]

var _host: Node = null
var _router: ShortcutRouter = null
var _was_embedding: bool = false
var _added_action: bool = false
var _toggles: int = 0


## A host in the tree with a router watching every window that joins it, and a
## registry holding Preferences' own chord, whose answer is counted rather than
## performed. Embedding is forced the way the other dialog suites force it.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _toggles = 0
    _host = Node.new()
    _host.name = "CtrlCommaHost"
    EventBus.add_child(_host)
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return null
    _host.add_child(_router)
    _router.watch_windows(tree)
    _added_action = not InputMap.has_action(&"edit_preferences")
    var commands := SaCommandRegistry.new()
    var preferences := SaCommandDescriptor.create(&"edit_preferences", "Preferences", _count_a_toggle)
    preferences.default_events = [SaAppCommands.chord(KEY_COMMA, true)]
    commands.register(preferences)
    _router.bind_commands(commands)


func after_each() -> void:
    _host.free()
    _host = null
    _router = null
    if _added_action:
        InputMap.erase_action(&"edit_preferences")
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


func _count_a_toggle() -> bool:
    _toggles += 1
    return true


## A key as the desktop hands it. A comma keeps its unicode with Ctrl held,
## since Ctrl+comma has no control character, and that unicode is what the
## search typed.
static func _key(keycode: Key, pressed: bool, ctrl: bool, echo: bool = false) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = keycode
    key.physical_keycode = keycode
    key.pressed = pressed
    key.echo = echo
    key.ctrl_pressed = ctrl
    if keycode == KEY_COMMA:
        key.unicode = KEY_COMMA
    return key


## Into the main window, which hands a key to the embedded window that has the
## keyboard.
static func _push(event: InputEvent) -> void:
    (Engine.get_main_loop() as SceneTree).root.push_input(event)


## One Ctrl+comma, let go in *order*.
static func _toggle(order: String) -> void:
    _push(_key(KEY_CTRL, true, true))
    _push(_key(KEY_COMMA, true, true))
    if order == "ctrl-last":
        _push(_key(KEY_COMMA, false, true))
        _push(_key(KEY_CTRL, false, false))
    else:
        _push(_key(KEY_CTRL, false, false))
        _push(_key(KEY_COMMA, false, false))


## Preferences open and its search holding the keyboard, as the toggle that
## opens it leaves them.
func _open_preferences() -> Dictionary:
    var prefs := SaSettingsWindow.new()
    _host.add_child(prefs)
    prefs.show()
    prefs.grab_focus()
    var field := prefs.find_child("PreferencesSearch", true, false) as LineEdit
    assert_not_null(field, "Preferences has its search box")
    field.grab_focus()
    field.edit()
    return {"prefs": prefs, "field": field}


## The row's own reading: eight toggles from inside Preferences, four let go
## each way, and the search is empty after every one.
func test_ctrl_comma_let_go_either_way_types_no_comma_into_the_search() -> void:
    var opened := _open_preferences()
    var field := opened.field as LineEdit
    var after: Array[String] = []
    for order in ORDERS:
        for i in 4:
            _toggle(order)
            after.append(field.text)

    assert_eq(_toggles, 8, "The router answered every Ctrl+comma, so the chord is the router's")
    assert_eq(after, ["", "", "", "", "", "", "", ""], "and the search read empty after every toggle")


## A chord held past the desktop's repeat delay repeats, and a painter can let
## Ctrl go first and keep the comma down. Every repeat belongs to the chord the
## router took, so the search stays empty and the toggle is one.
func test_a_held_ctrl_comma_types_no_comma_whichever_key_goes_up_first() -> void:
    var opened := _open_preferences()
    var field := opened.field as LineEdit
    _push(_key(KEY_CTRL, true, true))
    _push(_key(KEY_COMMA, true, true))
    for i in 3:
        _push(_key(KEY_COMMA, true, true, true))
    var with_ctrl := field.text
    _push(_key(KEY_CTRL, false, false))
    for i in 3:
        _push(_key(KEY_COMMA, true, false, true))
    _push(_key(KEY_COMMA, false, false))

    assert_eq(_toggles, 1, "A held chord is one toggle")
    assert_eq(with_ctrl, "", "Its repeats with Ctrl down typed nothing")
    assert_eq(field.text, "", "and nor did the comma's repeats once Ctrl was up")


## The toggle that opens Preferences comes in through the main window, whose
## keys Main hands the router, and a held chord's repeats then arrive in
## Preferences with the search holding the keyboard.
func test_a_chord_held_from_the_main_window_into_preferences_types_nothing() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var press := _key(KEY_COMMA, true, true)
    _router.handle_viewport_input(press, tree.root)
    assert_eq(_toggles, 1, "The main window's Ctrl+comma is the router's")

    var opened := _open_preferences()
    var field := opened.field as LineEdit
    for i in 4:
        _push(_key(KEY_COMMA, true, true, true))
    _push(_key(KEY_COMMA, false, false))

    assert_eq(field.text, "", "The repeats of the chord that opened Preferences typed nothing into its search")
    assert_eq(_toggles, 1, "and toggled nothing")


## A pop-up is a window of its own with the same door, so a search in one, a
## dropdown's, kept no comma from the chord either.
func test_ctrl_comma_over_a_search_in_a_pop_up_types_no_comma() -> void:
    var popup := PopupPanel.new()
    var field := LineEdit.new()
    field.custom_minimum_size = Vector2(160.0, 24.0)
    popup.add_child(field)
    _host.add_child(popup)
    popup.popup(Rect2i(40, 40, 200, 40))
    field.grab_focus()
    field.edit()
    for order in ORDERS:
        _toggle(order)

    assert_eq(_toggles, 2, "The router answered Ctrl+comma over the pop-up")
    assert_eq(field.text, "", "and the pop-up's search kept no comma")
    _push(_key(KEY_COMMA, true, false))
    assert_eq(field.text, ",", "while a plain comma is still typed there")


## The half that must not break: a comma with no Ctrl held is a comma, alone and
## after a toggle was let go.
func test_a_comma_with_no_ctrl_held_is_typed_into_the_search() -> void:
    var opened := _open_preferences()
    var field := opened.field as LineEdit
    _push(_key(KEY_COMMA, true, false))
    _push(_key(KEY_COMMA, false, false))
    assert_eq(field.text, ",", "A plain comma types one")

    _toggle("comma-last")
    _push(_key(KEY_COMMA, true, false))
    _push(_key(KEY_COMMA, false, false))
    assert_eq(_toggles, 1, "The chord between was the router's")
    assert_eq(field.text, ",,", "and the next plain comma types one more")
