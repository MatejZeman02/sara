## Escape cancels the edit before anything else hears it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A dialog that closes on every Escape leaves no way to escape a slider value
## edit or a brush preset rename. A dialog once took every Escape in its own
## `_input`, which Godot runs before any `_gui_input`, so the focused field never
## saw the key. Declining while a text field has the keyboard was not enough: the
## router releases a focused field from the window's `window_input` signal, which
## runs earlier still, so by the time the dialog looked there was nothing focused
## and the Preferences search bar lost its window on every press.
##
## The dialogs close on Escape once no field holds the keyboard, which
## `ui/dialogs/tests/test_escape_closes_a_dialog.gd` reads: the field is let go
## by the first Escape and the window closed by the second. The cases here are
## the field's own: the slider's field cancels rather than committing, and the
## preset name field accepts the key.
##
## **The order still matters and it is not obvious.** `window_input`, then
## `_input`, then `_gui_input`, then `_unhandled_key_input`. The field has to
## accept the key for nothing behind it to answer, which is what `accept_event`
## in `factor_slider.gd` is for.
extends "res://tests/test_framework.gd"

## Kept from when the suite opened Preferences, which only a run with a
## RenderingDevice can.
const REQUIRES_GPU := true


## A host in the tree for the controls each case builds. A `LineEdit` refuses
## `grab_focus` outside a tree, and `_start_editing` grabs, so a detached slider
## logged `Condition "!is_inside_tree()" is true` once per case and the runner
## read the whole suite as a script error.
##
## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func _host() -> Node:
    var host := Node.new()
    host.name = "EscapeCancelTestHost"
    EventBus.add_child(host)
    return host


## A slider at 40 of 100, in the tree, ready to be typed into.
func _slider(host: Node) -> FactorSlider:
    var slider := FactorSlider.new()
    host.add_child(slider)
    slider.min_value = 0.0
    slider.max_value = 100.0
    slider.value = 40.0
    return slider


## An Escape press, spelled the way `SaShortcutKeys.is_escape` reads it and the
## way a scenario's `key` step sends it: both keycode fields set.
static func _escape() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_ESCAPE
    key.physical_keycode = KEY_ESCAPE
    key.pressed = true
    return key


## The slider's value field cancels: the value is the one that was there and the
## field is closed.
func test_escape_out_of_a_slider_field_keeps_the_old_value() -> void:
    var host := _host()
    var slider := _slider(host)

    slider.start_editing()
    assert_true(slider._line_edit.visible, "The field is open")
    slider._line_edit.text = "99"

    slider._on_line_edit_gui_input(_escape())
    assert_false(slider._line_edit.visible, "Escape closes the field")
    assert_almost_eq(slider.value, 40.0, 1e-6, "and leaves the value where it was")

    host.free()


## Submitting still commits, so the cancel did not take the accept with it. The
## pair is the point: one key confirms and the other abandons.
func test_submitting_a_slider_field_still_commits() -> void:
    var host := _host()
    var slider := _slider(host)

    slider.start_editing()
    slider._line_edit.text = "99"
    slider._on_line_edit_submitted("99")
    assert_almost_eq(slider.value, 99.0, 1e-6, "Enter writes what was typed")

    host.free()


## **The order the cancel depends on.** `release_focus` emits `focus_exited`,
## which is wired to the commit, so the field is hidden first and the commit
## returns at once for an invisible field. A cancel that released the focus first
## would write the typed number and read as no cancel at all.
func test_the_cancel_survives_the_focus_leaving_the_field() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    var host := _host()
    var slider := _slider(host)
    slider.start_editing()
    slider._line_edit.text = "99"
    assert_true(slider._line_edit.has_focus(), "The field has the keyboard")

    slider._on_line_edit_gui_input(_escape())
    assert_false(slider._line_edit.has_focus(), "Escape hands it back")
    assert_almost_eq(slider.value, 40.0, 1e-6, "and the focus_exited it caused committed nothing")

    host.free()


## The preset name field closes on Escape and does not save what was typed.
func test_escape_out_of_the_preset_name_field_closes_it() -> void:
    var host := _host()
    var presets := ToolOptionsPresets.new()
    host.add_child(presets)
    presets._open_preset_name_field()
    assert_true(presets.preset_name_edit.visible, "The name field is open")

    presets.preset_name_edit.text = "Nameless"
    presets._on_preset_name_gui_input(_escape())
    assert_false(presets.preset_name_edit.visible, "Escape closes it")
    assert_false(presets.preset_names().has("Nameless"), "and saves nothing under what was typed")

    host.free()


## A key that is not Escape is left alone by all three, which is what keeps a
## painter able to type.
func test_every_other_key_is_left_alone() -> void:
    var typed := InputEventKey.new()
    typed.keycode = KEY_7
    typed.physical_keycode = KEY_7
    typed.pressed = true

    var host := _host()
    var slider := _slider(host)
    slider.start_editing()
    slider._on_line_edit_gui_input(typed)
    assert_true(slider._line_edit.visible, "A digit does not close the slider's field")

    var presets := ToolOptionsPresets.new()
    host.add_child(presets)
    presets._open_preset_name_field()
    presets._on_preset_name_gui_input(typed)
    assert_true(presets.preset_name_edit.visible, "nor the preset name field")

    var released := _escape()
    released.pressed = false
    var second := _slider(host)
    second.start_editing()
    second._on_line_edit_gui_input(released)
    assert_true(second._line_edit.visible, "and an Escape release is not a press")

    host.free()
