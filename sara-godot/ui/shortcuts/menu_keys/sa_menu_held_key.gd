## A plain key an open menu holds back from a command says so in the corner.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A Tools menu opened by a press a few pixels too
## high leaves Insert, Page Up and Page Down doing nothing, with
## nothing on screen saying why. The open popup keeps the plain keys on
## purpose, `ShortcutRouter.handle_popup_input` says why, so the key stays the
## menu's and this only tells the painter: "A menu is open, so Insert did
## nothing. Press Escape to close it."
##
## Silent for the keys a menu uses: the arrows, Enter, Space, Escape, Tab,
## which the popup's buttons pass the focus by, and any key that types a
## character, which is a row's letter, the type-ahead or the search field's
## text. Silent for a key no command of the profile in force is bound to, since
## it would have done nothing anyway. A search field on screen holding the focus
## keeps its editing keys too, Backspace, Delete, Home and End. A chord is the
## router's, which passes it on.
##
## A command's key is any action of the map except the engine's own `ui_*`
## ones, which bind Page Up and the arrows to walking a list and are no command.
class_name SaMenuHeldKey
extends RefCounted

## The keys a menu answers itself, so a press of one is the menu working.
const MENU_KEYS: Array[Key] = [
    KEY_UP,
    KEY_DOWN,
    KEY_LEFT,
    KEY_RIGHT,
    KEY_ENTER,
    KEY_KP_ENTER,
    KEY_SPACE,
    KEY_ESCAPE,
    KEY_TAB,
]

## The keys a menu's search field edits by, kept while the field is on screen
## and holds the focus.
const FIELD_KEYS: Array[Key] = [KEY_BACKSPACE, KEY_DELETE, KEY_HOME, KEY_END]


## Writes the corner line when *event*, pressed over the open *popup*, is a
## plain key a command is bound to.
static func tell(popup: Window, event: InputEvent) -> void:
    var line := line_for(popup, event)
    if not line.is_empty():
        EventBus.corner_notice.emit(line)


## The corner line for *event* over *popup*, or an empty string when the press
## says nothing.
static func line_for(popup: Window, event: InputEvent) -> String:
    var key := event as InputEventKey
    if key == null or not key.pressed or key.echo or SaShortcutKeys.is_chord(key):
        return ""
    if popup == null or MENU_KEYS.has(key.keycode) or _types_a_character(key) or not _bound(key):
        return ""
    if _typing_into(popup.gui_get_focus_owner()) and FIELD_KEYS.has(key.keycode):
        return ""
    return tr_line() % SaCommandRegistry.format_events([key], 1)


## The sentence, apart so a suite reads the words the corner gets.
static func tr_line() -> String:
    return TranslationServer.translate("A menu is open, so %s did nothing. Press Escape to close it.")


## Whether *focus* is a text box on screen. The bar's menus open with their
## search field shown and focused, so a field on screen is the usual case, and
## it is the menu's own way of being used, which keeps only its editing keys.
static func _typing_into(focus: Control) -> bool:
    return (focus is LineEdit or focus is TextEdit) and focus.is_visible_in_tree()


## A key that types, a row's letter or the type-ahead's, as the popup reads it.
static func _types_a_character(key: InputEventKey) -> bool:
    if key.unicode >= 32:
        return not char(key.unicode).strip_edges().is_empty()
    return (key.keycode >= KEY_A and key.keycode <= KEY_Z) or (key.keycode >= KEY_0 and key.keycode <= KEY_9)


## Whether an action of the profile in force answers *key* exactly.
static func _bound(key: InputEventKey) -> bool:
    for action: StringName in InputMap.get_actions():
        if String(action).begins_with("ui_"):
            continue
        if InputMap.event_is_action(key, action, true):
            return true
    return false
