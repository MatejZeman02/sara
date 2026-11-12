## A colour popup built by hand is opaque.
##
## The engine opens a `PopupPanel` as a transparent window, and the ground
## swatches of the Layers docker let the docker read through their picker. The
## colour ramp's stop and the palette filter's chip build their popups by hand,
## and the suite holds that both turn the window's transparency off. Their box is
## the shared theme's `PopupPanel` box, which the suite beside the ground rows
## holds.
extends "res://tests/test_framework.gd"


func test_the_ramp_stop_popup_draws_no_transparency() -> void:
    var control := SaColorRampControl.new()
    control.bind_ramp(SaColorRamp.from_pair(Color.RED, Color.BLUE))
    control._build_popup()
    assert_false(control._popup.transparent, "the stop's popup window draws no transparency")
    assert_false(control._popup.transparent_bg, "nor a transparent ground")
    control.free()


func test_the_palette_chip_editor_draws_no_transparency() -> void:
    var dialog := SaPalettePanel.new([Color.RED, Color.BLUE])
    var holder := Control.new()
    holder.add_child(dialog)
    assert_false(dialog._chip_editor.transparent, "the chip editor's window draws no transparency")
    assert_false(dialog._chip_editor.transparent_bg, "nor a transparent ground")
    holder.free()
