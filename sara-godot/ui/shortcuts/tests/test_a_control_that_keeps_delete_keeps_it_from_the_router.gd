## The router leaves a bare Delete to the control holding the focus when that
## control says it keeps it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A docker's window hands the router a key before its own controls see it, so
## the Delete that took a curve point or a ramp stop away emptied the layer as
## well. The control says it keeps Delete with a meta, and the router asks.
extends "res://tests/test_framework.gd"


func _delete(ctrl: bool = false) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_DELETE
    event.pressed = true
    event.ctrl_pressed = ctrl
    return event


func test_a_focused_control_that_keeps_delete_keeps_it() -> void:
    var editor := SaCurveEditor.new()

    assert_true(ShortcutRouter.delete_keeps(editor, _delete()), "the curve graph keeps it")
    editor.free()


func test_a_control_that_does_not_say_so_keeps_nothing() -> void:
    var plain := Control.new()

    assert_false(ShortcutRouter.delete_keeps(plain, _delete()), "an ordinary control does not")
    assert_false(ShortcutRouter.delete_keeps(null, _delete()), "and nothing focused does not")
    plain.free()


func test_a_chord_and_another_key_are_not_kept() -> void:
    var editor := SaCurveEditor.new()
    var other := InputEventKey.new()
    other.keycode = KEY_BACKSPACE

    assert_false(ShortcutRouter.delete_keeps(editor, _delete(true)), "Ctrl+Delete is a chord")
    assert_false(ShortcutRouter.delete_keeps(editor, other), "and Backspace is not Delete")
    editor.free()


func test_the_ramp_bar_keeps_delete() -> void:
    var control := SaColorRampControl.new()

    var bar := control.find_child("Bar", true, false) as Control

    assert_true(ShortcutRouter.delete_keeps(bar, _delete()), "the ramp's bar keeps it")
    control.free()
