## The white point row of the New Document dialog.
##
## A gamut in Sara carries no white, and every gamut it offers has a
## conventional partner, which picking the gamut moves the row to. The row is
## still a choice, because a space can be the same lights at another white.
extends "res://tests/test_framework.gd"

## The dialog builds a colour space browser, which draws a gamut.
const REQUIRES_GPU := true


## The pairing itself, named per gamut rather than fixed at D65 in general,
## which is the one thing worth getting right in the answer.
func test_each_gamut_names_the_white_it_is_normalised_to() -> void:
    for gamut: SaGamut in SaGamut.presets():
        var expected := SaColorSpace.WHITE_D60 if gamut.id == SaGamut.ID_AP1 else SaColorSpace.WHITE_D65
        assert_true(
            gamut.default_white().is_equal_approx(expected), "%s is normalised to its conventional white" % gamut.display_name
        )


## The row is a sentence a reader can check, not a name they have to trust.
func test_the_row_carries_the_name_and_the_coordinates() -> void:
    assert_eq(SaColorSpacePicker.white_point_text(SaColorSpace.WHITE_D65), "D65 (0.3127, 0.3290)", "D65 is named and given as xy")
    assert_eq(SaColorSpacePicker.white_point_text(SaColorSpace.WHITE_D60), "D60 (0.3217, 0.3377)", "D60 is named and given as xy")
    # A white neither standard names still reaches the row, as coordinates
    # alone. Nothing in the dialog can reach one today, and a loaded document
    # can, so the row must not print an empty name beside them.
    assert_eq(SaColorSpacePicker.white_point_text(Vector2(0.3, 0.3)), "(0.3000, 0.3000)", "an unnamed white is its coordinates")


## The row follows the gamut row until the painter picks a white of their own.
## The dialog is never added to the tree here: a test that maps a real window
## hangs the run.
func test_the_row_follows_the_gamut_row() -> void:
    var dialog := NewDocumentDialog.new()
    assert_true(dialog.select_gamut("Display P3"), "The gamut row takes Display P3")
    assert_eq(dialog.row_option(&"white").text, "D65", "Display P3 reads D65")

    assert_true(dialog.select_gamut("ACES AP1"), "and ACES AP1")
    assert_eq(dialog.row_option(&"white").text, "D60", "ACES AP1 reads D60")
    assert_eq(
        dialog.picker.capture_state()["white"],
        SaColorSpacePicker.white_point_text(SaColorSpace.WHITE_D60),
        "and the capture gives it as coordinates"
    )

    assert_true(dialog.select_gamut("Rec. 2020"), "and Rec. 2020")
    assert_eq(dialog.row_option(&"white").text, "D65", "Rec. 2020 reads D65 again")
    assert_false(dialog.select_gamut("ACEScg"), "The row is named for the gamut, and ACEScg is a space rather than one")
    dialog.free()


## The white is a row of its own and not implied by the gamut, because a space
## no preset names can be any lights at any white, and a space for print is
## sRGB's lights at D50. Picking a white moves the space's white and nothing
## else.
func test_the_white_is_a_choice_of_its_own() -> void:
    var dialog := NewDocumentDialog.new()
    assert_true(dialog.select_gamut("ACES AP1"), "The gamut row takes ACES AP1")
    assert_true(dialog.selected_space().white.is_equal_approx(SaColorSpace.WHITE_D60), "and the white follows the gamut, D60")
    assert_true(dialog.select_row(&"white", "D50"), "The white row offers D50")
    assert_true(
        dialog.selected_space().white.is_equal_approx(SaColorSpacePicker.WHITE_D50), "and the space takes the white picked"
    )
    assert_true(dialog.selected_space().gamut().matches(SaGamut.ap1()), "while the primaries stay those of the gamut chosen")
    assert_eq(dialog.row_option(&"space").text, SaColorSpacePicker.CUSTOM_LABEL, "and the preset row names no preset")
    dialog.free()
