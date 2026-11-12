## New Document names the colour space Sara opens on.
##
## At factory settings the dialog once read Colour space "Custom", Transfer
## "Gamma 3.0" and Coordinates "Oklab". The default takes its gamut from the display profile, so on an sRGB
## screen it is Oklab and the cube root over sRGB's primaries, and no preset was
## that. `SaColorSpace.presets()` has it now, and both choosers read the list, so
## this suite holds what they show and that picking the neighbouring entry still
## moves the curve. The descriptors are in
## `core/api/color/tests/test_the_default_space_has_a_name.gd`.
extends "res://tests/test_framework.gd"

## The dialog builds a colour space browser, which draws a gamut.
const REQUIRES_GPU := true

var _saved_profile: String = ""


func before_each() -> void:
    _saved_profile = SaSettings.display_profile
    SaSettings.display_profile = "srgb"


func after_each() -> void:
    SaSettings.display_profile = _saved_profile


## The three rows the dialog reads, at factory settings on an sRGB display.
func test_the_dialog_at_factory_settings_names_the_space() -> void:
    var dialog := NewDocumentDialog.new()
    var preset_name := SaColorSpace.display_name(SaColorSpace.ID_OKLAB_SRGB_GAMMA30)
    assert_eq(dialog.row_option(&"space").text, preset_name, "the Colour space row names the default")
    assert_true(dialog.row_option(&"space").text != NewDocumentDialog.CUSTOM_LABEL, "and does not read Custom")
    assert_eq(dialog.row_option(&"transfer").text, "Gamma 3.0", "the Transfer row still reads Gamma 3.0")
    assert_eq(dialog.row_option(&"coordinates").text, "Oklab", "and the Coordinates row Oklab")
    var described := dialog.selected_space()
    assert_eq(str(described.id), str(SaColorSpace.ID_OKLAB_SRGB_GAMMA30), "the space it describes is the preset")
    assert_eq(described.depth, SaColorSpace.Depth.F16, "at the depth the default has")
    dialog.free()


## The Colour Spaces chooser shows the same name for the same space.
func test_the_colour_spaces_chooser_names_the_same_default() -> void:
    var browser := SaColorSpaceBrowser.new()
    browser.show_space(SaEasel.default_space())
    var shown := browser.option.text
    browser.free()
    assert_eq(shown, SaColorSpace.display_name(SaColorSpace.ID_OKLAB_SRGB_GAMMA30), "the chooser and the dialog say one name")


## The note's last clause: "Oklab over sRGB" moves the transfer to the sRGB
## curve, and the entry beside it moves it back to the cube root.
func test_the_two_oklab_over_srgb_entries_differ_in_the_curve_alone() -> void:
    var dialog := NewDocumentDialog.new()
    assert_true(dialog.select_row(&"space", SaColorSpace.display_name(SaColorSpace.ID_OKLAB)), "Oklab over sRGB is a row")
    assert_eq(dialog.row_option(&"transfer").text, "sRGB", "it puts the transfer on the sRGB curve")
    assert_eq(dialog.row_option(&"coordinates").text, "Oklab", "and keeps the coordinates")
    assert_eq(dialog.row_option(&"gamut").text, SaGamut.srgb().display_name, "over the same gamut")

    var cube_root := SaColorSpace.display_name(SaColorSpace.ID_OKLAB_SRGB_GAMMA30)
    assert_true(dialog.select_row(&"space", cube_root), "the new entry is a row")
    assert_eq(dialog.row_option(&"transfer").text, "Gamma 3.0", "it puts the transfer back on the cube root")
    assert_eq(dialog.row_option(&"gamut").text, SaGamut.srgb().display_name, "over the same gamut")
    assert_eq(dialog.row_option(&"space").text, cube_root, "and still reads its name")
    dialog.free()


## A curve changed by hand leaves the preset, which is what Custom is for.
func test_a_hand_changed_curve_still_reads_custom() -> void:
    var dialog := NewDocumentDialog.new()
    assert_true(dialog.select_row(&"transfer", "Linear"), "the Transfer row has a Linear entry")
    var custom := NewDocumentDialog.CUSTOM_LABEL
    assert_eq(dialog.row_option(&"space").text, custom, "Oklab over sRGB through a linear curve is no preset")
    dialog.free()
