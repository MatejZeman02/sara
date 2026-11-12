## A letter typed into Preferences before its search is clicked goes into the
## search.
##
## Preferences opens with the keyboard on the open page's button in the sidebar,
## so the first Escape closes the window. A painter coming from Photoshop
## types the word they want at once, and the letter landed on that button and
## did nothing. So a printable key arriving while the keyboard is on a sidebar
## button, or on no control at all, is handed to the search: the field takes the
## keyboard with the character in it, and from there it is a clicked search,
## which lets go of the first Escape.
##
## Enter, Tab, the arrows and Space keep their button's meaning, because none of
## them is text here: Space is a button's press, and the rest carry no character.
## A chord with Ctrl, Alt or Meta held is a command and is left to it. Shift is
## how a capital is typed, so it passes.
##
## A node the window adds to itself, reading the window's search and buttons at
## each key rather than holding them, because the window builds both again when
## a module brings or takes a page. It listens in `_unhandled_key_input`, after
## the focused control and every shortcut have passed on the key, so nothing a
## control answers is taken from it.
class_name SaSettingsTypeAhead
extends Node

var _window: SaSettingsWindow


func _init(window: SaSettingsWindow) -> void:
    _window = window


func _unhandled_key_input(event: InputEvent) -> void:
    var character := typed(event)
    if character.is_empty() or not _keyboard_is_free():
        return
    var field := _window.search.field
    if not field.is_visible_in_tree() or not field.editable:
        return
    field.grab_focus()
    field.caret_column = field.text.length()
    field.insert_text_at_caret(character)
    # The insert sends no `text_changed`, which is what a typed key narrows by.
    _window.search.apply(field.text)
    get_viewport().set_input_as_handled()


## The character *event* types, or "" when it is no text: a release, a key
## with no character, Space, or a chord with Ctrl, Alt or Meta held. A held key
## repeats into the field once the first press has moved the keyboard there.
static func typed(event: InputEvent) -> String:
    var key := event as InputEventKey
    if key == null or not key.pressed:
        return ""
    if key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
        return ""
    if key.unicode <= 32 or key.unicode == 127:
        return ""
    return String.chr(key.unicode)


## Whether the keyboard is on a button of the sidebar's page list, or on no
## control, the two places a letter means nothing today.
func _keyboard_is_free() -> bool:
    var focused := _window.gui_get_focus_owner()
    return focused == null or _window.category_buttons.has(focused)
