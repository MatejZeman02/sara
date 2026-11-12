## Enter at the depth question opens the picture rather than cancelling it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The question opened with its outline on Cancel, because every dropdown in it
## takes no focus and the open mode hides the two rows that do, so Cancel was
## the first control the Tab walk reached. Enter presses the button the outline
## is on (`SaDialogWindow._unhandled_key_input`), and the painted document
## stayed. A `Window` added to the tree in a headless run hangs, so the dialog
## here is detached and what it can hold is where the focus is told to go and
## what that button does when Enter's release presses it. The outline itself is
## read off the running app by
## `scenarios/an-exr-export-holds-linear-srgb.json`, which presses Enter.
extends "res://tests/test_framework.gd"


func test_the_open_question_puts_the_keyboard_on_open() -> void:
    var dialog := SaImportFitDialog.new()
    dialog.configure_open(Vector2i(640, 480), SaColorSpace.linear_srgb(), SaColorSpace.Depth.F16)
    var cancel := dialog.find_child("CancelButton", true, false) as Button
    assert_not_null(cancel, "The question has a Cancel button")
    assert_not_null(dialog.first_focus, "The question names where the keyboard starts")
    assert_false(dialog.first_focus == cancel, "and it is not Cancel")
    assert_eq(dialog.first_focus, dialog.default_button, "It is the default, so the outline and Enter agree")
    assert_eq((dialog.first_focus as Button).text, tr("Open"), "and the default reads Open in this question")
    dialog.free()


func test_enter_on_the_first_focus_calls_the_depth_callback() -> void:
    var dialog := SaImportFitDialog.new()
    dialog.configure_open(Vector2i(640, 480), SaColorSpace.linear_srgb(), SaColorSpace.Depth.F16)
    var chosen: Array[SaColorSpace] = []
    dialog.depth_chosen.connect(func(space: SaColorSpace) -> void: chosen.append(space))
    var was := SaSettings.import_depth
    # What Enter's release does to the button with the outline.
    (dialog.first_focus as Button).pressed.emit()
    assert_eq(chosen.size(), 1, "The depth callback is called once")
    assert_eq(chosen[0].depth, SaColorSpace.Depth.F16, "with the depth the row opened on")
    assert_eq(String(chosen[0].id), String(SaColorSpace.linear_srgb().id), "and the gamut the file was read as")
    SaSettings.import_depth = was
    dialog.free()


## The fit question had the same walk with another end: the "Do not ask again"
## box was first, and Enter ticked it instead of placing the picture.
func test_the_fit_question_starts_on_place_as_well() -> void:
    var dialog := SaImportFitDialog.new()
    dialog.configure(Vector2i(640, 480), Vector2i(1024, 768), SaColorSpace.srgb())
    assert_eq(dialog.first_focus, dialog.default_button, "The fit question starts on its default too")
    assert_eq((dialog.first_focus as Button).text, tr("Place"), "which reads Place")
    dialog.free()
