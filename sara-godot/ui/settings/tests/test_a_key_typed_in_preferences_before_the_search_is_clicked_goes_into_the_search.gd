## A key typed in Preferences before the search is clicked goes into the
## search, and Escape still closes the window at once.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Photoshop hour, finding 19: "Typing in Preferences before clicking its
## search goes nowhere." Preferences opens with the keyboard on the open page's
## button so the first Escape is the window's, and `SaSettingsTypeAhead`
## hands a printable key from there to the search. The keys reach the window the
## way the engine hands them on, `window_input` first, which the router watches,
## then the window's own tree.
extends "res://tests/test_framework.gd"

## Opens real windows, and only a run with a RenderingDevice has one.
const REQUIRES_GPU := true

var _host: Node = null
var _router: ShortcutRouter = null
var _was_embedding: bool = false


## A host with a router watching every window that joins it, and embedding
## forced, so `add_child` maps no OS window and the run never blocks.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "TestHost"
    EventBus.add_child(_host)
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return null
    _host.add_child(_router)
    _router.watch_windows(tree)


func after_each() -> void:
    _host.free()
    _host = null
    _router = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


static func _key(keycode: Key, unicode: int = 0, pressed: bool = true, ctrl: bool = false) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = keycode
    key.physical_keycode = keycode
    key.unicode = unicode
    key.pressed = pressed
    key.ctrl_pressed = ctrl
    return key


static func _press(window: Window, event: InputEvent) -> void:
    window.window_input.emit(event)
    window.push_input(event)


## A press and its release, the way a hand types a key.
static func _tap(window: Window, keycode: Key, unicode: int = 0, ctrl: bool = false) -> void:
    _press(window, _key(keycode, unicode, true, ctrl))
    _press(window, _key(keycode, unicode, false, ctrl))


## Preferences opened, the focus where the open puts it. The open's own focus
## call is deferred, and a suite cannot await a frame, so it is made here as the
## frame after the open makes it.
func _open() -> SaSettingsWindow:
    var prefs := SaSettingsWindow.new()
    _host.add_child(prefs)
    prefs.show()
    prefs.focus_first_control()
    return prefs


func _field(prefs: SaSettingsWindow) -> LineEdit:
    return prefs.find_child("PreferencesSearch", true, false) as LineEdit


func test_a_b_typed_on_opening_lands_in_the_search_with_the_keyboard() -> void:
    var prefs := _open()
    assert_eq(prefs.gui_get_focus_owner(), prefs.category_buttons[prefs.current], "Preferences opens on the open page's button")
    _tap(prefs, KEY_B, "b".unicode_at(0))
    var field := _field(prefs)
    assert_eq(field.text, "b", "the search holds the b")
    assert_true(field.has_focus(), "and has the keyboard")
    assert_eq(prefs.search.text, "b", "and the search narrowed on it")
    _tap(prefs, KEY_R, "r".unicode_at(0))
    assert_eq(field.text, "br", "the next letter follows it in the field")
    _press(prefs, _key(KEY_ESCAPE))
    assert_true(prefs.visible, "an Escape lets go of the typed search first")
    assert_false(field.has_focus(), "and the field lets the keyboard go")
    prefs.free()


func test_a_letter_typed_with_the_keyboard_on_no_control_lands_in_the_search() -> void:
    var prefs := _open()
    prefs.gui_release_focus()
    _tap(prefs, KEY_T, "t".unicode_at(0))
    assert_eq(_field(prefs).text, "t", "the search holds the t")
    assert_true(_field(prefs).has_focus(), "and has the keyboard")
    prefs.free()


func test_escape_at_once_on_a_second_window_closes_it() -> void:
    var first := _open()
    first.free()
    var prefs := _open()
    _press(prefs, _key(KEY_ESCAPE))
    assert_false(prefs.visible, "one Escape closes Preferences straight after it opens")
    assert_eq(_field(prefs).text, "", "and the search took nothing")
    prefs.free()


func test_enter_and_space_on_a_sidebar_button_open_its_page_and_leave_the_search() -> void:
    var prefs := _open()
    var field := _field(prefs)
    var start := prefs.current
    var other := (start + 1) % prefs.category_buttons.size()
    prefs.category_buttons[other].grab_focus()
    _tap(prefs, KEY_ENTER)
    assert_eq(prefs.current, other, "Enter on a sidebar button opens its page")
    assert_eq(field.text, "", "and the search is unchanged")
    assert_false(field.has_focus(), "and does not take the keyboard")
    prefs.category_buttons[start].grab_focus()
    _tap(prefs, KEY_SPACE, " ".unicode_at(0))
    assert_eq(prefs.current, start, "Space on a sidebar button opens its page")
    assert_eq(field.text, "", "and the search is unchanged")
    assert_false(field.has_focus(), "and does not take the keyboard")
    prefs.free()


func test_a_ctrl_chord_is_no_text() -> void:
    var prefs := _open()
    _tap(prefs, KEY_K, "k".unicode_at(0), true)
    assert_eq(_field(prefs).text, "", "Ctrl+K leaves the search unchanged")
    assert_false(_field(prefs).has_focus(), "and the keyboard where it was")
    prefs.free()


func test_tab_and_the_arrows_carry_no_character() -> void:
    for keycode: Key in [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_ESCAPE]:
        assert_eq(SaSettingsTypeAhead.typed(_key(keycode)), "", "%s types nothing" % OS.get_keycode_string(keycode))
    assert_eq(SaSettingsTypeAhead.typed(_key(KEY_SPACE, 32)), "", "Space types nothing here")
    var alt := _key(KEY_B, "b".unicode_at(0))
    alt.alt_pressed = true
    assert_eq(SaSettingsTypeAhead.typed(alt), "", "an Alt chord types nothing")
    var capital := _key(KEY_B, "B".unicode_at(0))
    capital.shift_pressed = true
    assert_eq(SaSettingsTypeAhead.typed(capital), "B", "Shift types a capital")
