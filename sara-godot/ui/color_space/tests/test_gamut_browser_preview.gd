## A dump of the gamut browser says which of the two browsers it is, and
## the preview's legend does not claim a comparison it never draws.
##
## `SaColorSpaceBrowser` is built twice with two jobs. The Preferences page gets
## the full one, with a "Compare with" dropdown and two shapes on every drawing.
## The Colour Space dialog gets a preview, which has no
## second dropdown, because a chooser beside a dialog is about the one space
## being chosen.
##
## The two answered the same `capture_state()` shape, so sixteen dumps of
## `scenarios/colour-space.json` read `distinct: false` and a legend saying
## Display P3 is the widest gamut Sara has. Both readings are the preview being
## a preview, and neither is a fault.
extends "res://tests/test_framework.gd"


## The key that tells the two apart, which nothing carried before.
func test_a_dump_says_which_of_the_two_browsers_it_is() -> void:
    var page := SaColorSpaceBrowser.new()
    page.show_space(SaColorSpace.srgb())
    assert_false(page.capture_state()["preview"], "The Preferences page's browser is not a preview")

    var preview := SaColorSpaceBrowser.new(true)
    preview.show_space(SaColorSpace.srgb())
    assert_true(preview.capture_state()["preview"], "and the dialog's is")

    page.free()
    preview.free()


## The two readings that were being misread, side by side, so the difference is
## a property of the control rather than of the moment a dump was taken.
##
## Read on `compare` rather than on `distinct`, for the reason
## `test_srgb_compares_against_display_p3` gives one file over: a browser that
## was never added to a tree has no size, so both triangles project onto the
## same point and `spread` is zero whatever the gamuts are. `compare` is the
## shape the control was handed and it does not care about layout.
func test_the_preview_draws_one_shape_and_the_page_draws_two() -> void:
    var page := SaColorSpaceBrowser.new()
    page.show_space(SaColorSpace.srgb())
    var page_state: Dictionary = page.capture_state()
    assert_eq(String(page_state["diagram"]["compare"]), "display_p3", "The page hands the slice a second gamut")
    assert_true(String(page_state["compare_chooser"]) != "", "and its dropdown says which")

    var preview := SaColorSpaceBrowser.new(true)
    preview.show_space(SaColorSpace.srgb())
    var preview_state: Dictionary = preview.capture_state()
    assert_eq(String(preview_state["diagram"]["compare"]), "", "The preview hands it none, which is by design and not a fault")
    assert_eq(String(preview_state["compare_chooser"]), "", "and it has no dropdown to say otherwise")

    page.free()
    preview.free()


## The user-visible half. The legend is a string the dialog puts on screen, and
## it was making a claim about the gamut registry that is false for three of the
## four gamuts Sara ships.
func test_the_previews_legend_makes_no_claim_about_the_widest_gamut() -> void:
    var preview := SaColorSpaceBrowser.new(true)
    for space: SaColorSpace in [SaColorSpace.srgb(), SaColorSpace.display_p3()]:
        preview.show_space(space)
        assert_false(
            preview.legend.text.contains("widest"),
            "A preview of %s claims nothing about which gamut is widest: %s" % [space.id, preview.legend.text]
        )
        assert_true(preview.legend.text.contains("Help > Colour Spaces"), "and says where two can be compared instead")
    preview.free()


## The page keeps the sentence, because there the claim is true: it has drawn
## every larger gamut it could find and there was none.
func test_the_page_still_says_when_nothing_is_wider() -> void:
    var page := SaColorSpaceBrowser.new()
    page.show_space(SaColorSpace.acescg())
    assert_true(page.legend.text.contains("nothing larger"), "AP1 has nothing larger: %s" % page.legend.text)
    page.free()
