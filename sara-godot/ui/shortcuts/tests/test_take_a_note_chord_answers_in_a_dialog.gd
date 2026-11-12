## Ctrl+Alt+N answers while Preferences has the keyboard.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A dialog gets the chords `ShortcutRouter.WINDOW_CHORDS` names and Escape,
## nothing else, so a chord left off the list died at `handle_docker_input`
## before the command registry heard it. This holds both halves: the note chord
## passes, read by its action so a rebound one follows, and a document chord
## still does not.
extends "res://tests/test_framework.gd"


func _chord(keycode: Key, ctrl: bool, alt: bool, shift: bool = false) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = true
    event.ctrl_pressed = ctrl
    event.alt_pressed = alt
    event.shift_pressed = shift
    return event


func test_the_note_chord_is_one_a_dialog_still_answers() -> void:
    assert_true(
        ShortcutRouter.WINDOW_CHORDS.has("ui_take_note"), "the action is named, so a rebound chord is the one that passes"
    )
    assert_true(ShortcutRouter._is_window_chord(_chord(KEY_N, true, true)), "Ctrl+Alt+N passes the dialog's gate")


func test_a_document_chord_still_stops_at_a_dialog() -> void:
    assert_false(ShortcutRouter._is_window_chord(_chord(KEY_T, true, false)), "Ctrl+T stays out")
    assert_false(ShortcutRouter._is_window_chord(_chord(KEY_U, true, false)), "Ctrl+U stays out")
    assert_false(ShortcutRouter._is_window_chord(_chord(KEY_N, true, false)), "Ctrl+N without ALT is the new document")
    assert_false(ShortcutRouter._is_window_chord(_chord(KEY_N, false, false)), "a bare N is a letter in a box")


func test_the_chord_follows_a_rebinding() -> void:
    var original := InputMap.action_get_events(&"ui_take_note")
    InputMap.action_erase_events(&"ui_take_note")
    InputMap.action_add_event(&"ui_take_note", _chord(KEY_J, true, true))

    assert_true(ShortcutRouter._is_window_chord(_chord(KEY_J, true, true)), "the rebound chord passes")
    assert_false(ShortcutRouter._is_window_chord(_chord(KEY_N, true, true)), "and the old one no longer does")

    InputMap.action_erase_events(&"ui_take_note")
    for event in original:
        InputMap.action_add_event(&"ui_take_note", event)
