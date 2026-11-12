## One Escape closes Preferences under every shipped profile.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A switch to Krita on the Keyboard
## Shortcuts page, then Escape, once left Preferences open. The key was
## heard, and the profile had nothing to do with it: Preferences opened with the
## keyboard in its search box, the first control Tab reaches, and a text box
## holding the keyboard keeps the first Escape for itself. Preferences now opens
## with the keyboard on the open page's button in the sidebar, so the first
## Escape is the window's whichever profile is active.
##
## The key reaches the window the way the engine hands it on, `window_input`
## first, which the router watches, then the window's own tree.
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
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    _host.free()
    _host = null
    _router = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


static func _escape() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_ESCAPE
    key.physical_keycode = KEY_ESCAPE
    key.pressed = true
    return key


static func _press(window: Window, event: InputEvent) -> void:
    window.window_input.emit(event)
    window.push_input(event)


## Preferences opened on Keyboard shortcuts with *profile* applied, the focus
## where the open puts it. The open's own focus call is deferred, and a suite
## cannot await a frame, so it is made here as the frame after the open makes it.
func _open_under(profile: String) -> SaSettingsWindow:
    SaShortcutStore.apply_profile(profile)
    var prefs := SaSettingsWindow.new()
    _host.add_child(prefs)
    prefs.show_page("Keyboard shortcuts")
    prefs.show()
    prefs.focus_first_control()
    return prefs


func test_every_shipped_profile_lists_sara_default_krita_and_photoshop() -> void:
    var shipped: Array[String] = [SaShortcutStore.DEFAULT_PROFILE]
    shipped.append_array(SaShortcutStore.SHIPPED_PROFILES.keys())
    assert_true(shipped.has("Krita"), "Krita is a shipped profile")
    assert_true(shipped.has("Photoshop"), "Photoshop is a shipped profile")
    for profile in shipped:
        assert_true(SaShortcutStore.is_shipped(profile), "%s is shipped" % profile)


func test_one_escape_closes_preferences_under_each_shipped_profile() -> void:
    var shipped: Array[String] = [SaShortcutStore.DEFAULT_PROFILE]
    shipped.append_array(SaShortcutStore.SHIPPED_PROFILES.keys())
    for profile in shipped:
        var prefs := _open_under(profile)
        assert_true(prefs.visible, "Preferences is open under %s" % profile)
        var focused := prefs.gui_get_focus_owner()
        var in_a_box := focused is LineEdit or focused is TextEdit
        assert_false(in_a_box, "Under %s no text box holds the keyboard on open: %s" % [profile, focused])
        _press(prefs, _escape())
        assert_false(prefs.visible, "One Escape closes Preferences under %s" % profile)
        prefs.free()


## The other dialogs that close on Escape under Sara Default close the same way
## under every shipped profile, since the router's path to a dialog reads no
## profile: the Brush Editor on one Escape, and the layer kind browser, whose
## search takes the keyboard on purpose, on the second.
func test_the_other_dialogs_answer_escape_alike_under_each_shipped_profile() -> void:
    var shipped: Array[String] = [SaShortcutStore.DEFAULT_PROFILE]
    shipped.append_array(SaShortcutStore.SHIPPED_PROFILES.keys())
    for profile in shipped:
        SaShortcutStore.apply_profile(profile)
        var editor := SaBrushEditorWindow.new()
        _host.add_child(editor)
        editor.show()
        editor.gui_release_focus()
        _press(editor, _escape())
        assert_false(editor.visible, "Escape closes the Brush Editor under %s" % profile)
        editor.free()

        var browser := SaLayerKindBrowser.new()
        _host.add_child(browser)
        browser.show()
        (browser.find_child("BrowserSearch", true, false) as LineEdit).grab_focus()
        _press(browser, _escape())
        assert_true(browser.visible, "The browser's search lets go first under %s" % profile)
        _press(browser, _escape())
        assert_false(browser.visible, "and the next Escape closes the browser under %s" % profile)
        browser.free()


## The keyboard lands on the open page's button, so Tab starts from the sidebar
## and the search is one click or one Shift+Tab away.
func test_preferences_opens_with_the_keyboard_on_the_open_page_s_button() -> void:
    var prefs := _open_under("Krita")
    var at := prefs.categories.find("Keyboard shortcuts")
    assert_true(at >= 0, "Keyboard shortcuts is a page")
    assert_eq(prefs.gui_get_focus_owner(), prefs.category_buttons[at], "the open page's button has the keyboard")
    prefs.free()


## A search the painter clicked into keeps the first Escape, as the rule has it, under Krita as under Sara Default.
func test_a_search_the_painter_clicked_into_still_lets_go_first_under_krita() -> void:
    var prefs := _open_under("Krita")
    var field := prefs.find_child("PreferencesSearch", true, false) as LineEdit
    field.grab_focus()
    _press(prefs, _escape())
    assert_false(field.has_focus(), "The first Escape lets the search go")
    assert_true(prefs.visible, "and Preferences stays")
    _press(prefs, _escape())
    assert_false(prefs.visible, "The second closes it")
    prefs.free()
