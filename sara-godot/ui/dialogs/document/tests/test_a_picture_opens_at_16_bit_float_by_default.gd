## A picture opens at 16-bit float unless the painter chose otherwise.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Open the picture window's Bit depth row defaults to 16-bit float. Three defaults said F32,
## the dialog's starting depth, the fallback of `depth_from_setting` and the setting's own default and
## fallback, and all three are held here. A stored "f32" is a painter's answer
## and still opens on 32-bit.
##
## `configure_open` reads `SaSettings`, the profile Sara runs on, so the fresh
## case reads its default off a new `SaSettingsValues` and puts that on the
## autoload for the length of the case, which is what a fresh settings file
## loads into it.
extends "res://tests/test_framework.gd"

## The size a dialog is shown for, which the depth question does not read.
const IMAGE_SIZE := Vector2i(64, 48)


func test_a_fresh_settings_file_opens_the_dialog_on_16_bit_float() -> void:
    var fresh := SaSettingsValues.new()
    var default_word := fresh.import_depth
    fresh.free()
    assert_eq(default_word, "f16", "A fresh profile stores 16-bit float")
    assert_eq(_opened_on(default_word), SaColorSpace.Depth.F16, "and the open question starts on it")

    var dialog := SaImportFitDialog.new()
    assert_eq(dialog.wanted_depth, SaColorSpace.Depth.F16, "So does the dialog before anything configures it")
    dialog.free()


func test_a_stored_f32_still_opens_on_32_bit() -> void:
    assert_eq(_opened_on("f32"), SaColorSpace.Depth.F32, "A painter who chose 32-bit keeps it")


func test_an_unknown_word_falls_back_to_16_bit() -> void:
    var fresh := SaSettingsValues.new()
    fresh.import_depth = "f8"
    assert_eq(fresh.import_depth, "f16", "The setting takes a word it does not know as the default")
    fresh.free()
    assert_eq(SaImportFitDialog.depth_from_setting("f8"), SaColorSpace.Depth.F16, "and so does the dialog's reading of it")
    assert_eq(SaImportFitDialog.setting_for_depth(-1), "f16", "and a depth nothing names is written as the default")


## The depth the open question's row is on after `configure_open` for a picture
## that names none, with *stored* as the profile's word.
func _opened_on(stored: String) -> int:
    var was := SaSettings.import_depth
    SaSettings.import_depth = stored
    var dialog := SaImportFitDialog.new()
    dialog.configure_open(IMAGE_SIZE, SaColorSpace.srgb())
    var depth := dialog.chosen_depth()
    var row_reads: Variant = dialog.page.row(&"depth").reads()
    assert_eq(int(row_reads), depth, "The row shows the depth the dialog will store at")
    dialog.free()
    SaSettings.import_depth = was
    return depth
