## A dialog keeps the size it was resized to when the interface scale moves,
## as `DockerWindow` does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `SaDialogWindow.apply_window_scale` re-derives `size` from `logical_size`, and
## nothing wrote `logical_size` after the constructor, so a dialog dragged to a
## size snapped back to its default the next time the scale moved.
## `_track_logical_size` now reads a resize back in logical units.
##
## Built and never put in the tree, because a `Window` in a headless tree hangs,
## so `size_changed` is not wired and the tracker is called by hand the way
## `test_a_scale_write_keeps_the_restored_size.gd` calls the docker's. A real
## dialog rather than a subclass, for the reason `test_dialog_font_scale.gd`
## gives. The running app is
## `scenarios/a-resized-dialog-loses-its-size-when-the-interface-scales.json`.
extends "res://tests/test_framework.gd"

var _saved_override: float = -1.0
var _saved_user: float = 1.0


func before_each() -> void:
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0


func after_each() -> void:
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


## A dialog at scale 1 that a hand has just dragged to 1400 by 700.
func _resized() -> SaCanvasSizeDialog:
    var dialog := SaCanvasSizeDialog.new()
    dialog.apply_window_scale()
    dialog.size = Vector2i(1400, 700)
    dialog._track_logical_size()
    return dialog


func test_a_resize_writes_the_logical_size() -> void:
    var dialog := _resized()
    assert_eq(
        dialog.logical_size, Vector2i(1400, 700), "A dialog dragged to 1400 by 700 at scale 1 is that size in logical units"
    )
    dialog.free()


func test_a_scale_change_after_a_resize_keeps_the_resized_size() -> void:
    var dialog := _resized()

    SaUI.user_scale = 1.25
    dialog.apply_window_scale()

    assert_eq(dialog.logical_size, Vector2i(1400, 700), "The logical size is still the one the hand left")
    var factor := SaUI.window_scale(dialog)
    assert_eq(
        dialog.size,
        Vector2i(ceili(1400 * factor), ceili(700 * factor)),
        "and the window is that size at the new scale, not the constructor's"
    )
    dialog.free()


func test_the_class_does_not_read_its_own_derivation_back_as_a_resize() -> void:
    var dialog := _resized()

    SaUI.user_scale = 1.5
    dialog.apply_window_scale()
    # What `size_changed` would call after the derivation above, had the dialog
    # been in the tree: the flag has to have already let go, and the size the
    # class just wrote divided by the scale it applied is the same logical size.
    dialog._track_logical_size()

    assert_eq(dialog.logical_size, Vector2i(1400, 700), "Re-reading the derived size lands on the same logical size")
    dialog.free()


func test_an_untouched_dialog_keeps_its_constructor_size_across_a_scale_change() -> void:
    var dialog := SaCanvasSizeDialog.new()
    var opened := dialog.logical_size
    dialog.apply_window_scale()

    SaUI.user_scale = 1.25
    dialog.apply_window_scale()

    assert_eq(dialog.logical_size, opened, "A dialog nobody dragged still re-derives from the size it opened at")
    dialog.free()
