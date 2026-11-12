## The Info docker names the depth, the gamut and the white point.
##
## Numbers alone tell a painter nothing. Three
## chromaticity pairs are a gamut only to somebody who already knows the four
## sets by heart, and `0.3127, 0.3290` is D65 only to the same person. These
## cases are the lookup that turns each into a word, and the two rows that
## read it.
##
## `SaColorNames` is deliberately not `SaGamut.from_primaries`. That one
## compares with `is_equal_approx`, which is about a millionth, and every real
## file writes four decimals, so it answers null on documents that plainly are
## sRGB. The cases below pin both halves of that: the exact primaries and the
## rounded ones.
extends "res://tests/test_framework.gd"

const DOCKER := preload("res://ui/dockers/panels/info_docker.gd")


## Primaries that are no gamut in the table, chosen a long way from all five so
## the case says "unrecognised" rather than "just outside the tolerance", which
## is a different test below.
func _invented_primaries() -> PackedVector2Array:
    return PackedVector2Array([Vector2(0.500, 0.400), Vector2(0.250, 0.550), Vector2(0.200, 0.100)])


func _docker() -> InfoDocker:
    var docker: InfoDocker = DOCKER.new()
    docker.name = "InfoDockerNamesUnderTest"
    return docker


## All five, including the one no document can be created in.
##
## Adobe RGB is the reason the table is not just `SaGamut.presets()`: a file can
## arrive tagged with it, and before this the rows called it custom.
func test_the_five_known_gamuts_are_named_from_their_primaries() -> void:
    assert_eq(SaColorNames.gamut_name(SaGamut.srgb().primaries), "sRGB / Rec. 709", "sRGB is named")
    assert_eq(SaColorNames.gamut_name(SaGamut.display_p3().primaries), "Display P3", "Display P3 is named")
    assert_eq(SaColorNames.gamut_name(SaGamut.ap1().primaries), "ACES AP1", "ACEScg's primaries are named")
    assert_eq(SaColorNames.gamut_name(SaGamut.rec2020().primaries), "Rec. 2020", "Rec. 2020 is named")
    assert_eq(
        SaColorNames.gamut_name(SaColorNames.adobe_rgb_primaries()), "Adobe RGB", "and Adobe RGB, which no SaGamut preset holds"
    )


## The four names come from `SaGamut` itself rather than from a second table,
## so this is the case that fails if anyone writes one.
func test_the_four_offerable_gamuts_are_called_what_the_chooser_calls_them() -> void:
    for gamut: SaGamut in SaGamut.presets():
        assert_eq(
            SaColorNames.gamut_name(gamut.primaries),
            gamut.display_name,
            "The Info docker and a gamut chooser agree about %s" % gamut.id
        )


## Adobe RGB shares sRGB's red and blue exactly and differs only in green, so a
## lookup that stopped at the first two primaries would name one the other.
func test_adobe_rgb_is_not_mistaken_for_srgb() -> void:
    var srgb := SaGamut.srgb().primaries
    var adobe := SaColorNames.adobe_rgb_primaries()
    assert_true(srgb[0].is_equal_approx(adobe[0]), "The two share a red primary")
    assert_true(srgb[2].is_equal_approx(adobe[2]), "and a blue one")
    assert_eq(SaColorNames.gamut_name(adobe), "Adobe RGB", "and the green primary is what tells them apart")


func test_primaries_in_no_table_read_as_custom() -> void:
    assert_eq(SaColorNames.gamut_name(_invented_primaries()), "custom", "An unknown set is named custom")
    assert_eq(
        SaColorNames.gamut_name(PackedVector2Array([Vector2(0.64, 0.33)])),
        "custom",
        "and so is a space that carries fewer than three primaries at all"
    )


## D65 and D60 are read out of `SaColorSpace`, so a change to Sara's white
## cannot leave the row naming a light the document is not under. D50 is this
## file's own, because no preset there is normalised to it.
func test_the_three_illuminants_are_named_from_their_chromaticities() -> void:
    assert_eq(SaColorNames.illuminant_name(SaColorSpace.WHITE_D65), "D65", "Sara's own white is D65")
    assert_eq(SaColorNames.illuminant_name(SaColorNames.WHITE_D50), "D50", "The print illuminant is D50")
    assert_eq(SaColorNames.illuminant_name(SaColorSpace.WHITE_D60), "D60", "and ACES is D60")


## The case the tolerance exists for. A `.sad` header, an ICC profile and every
## printed table write four decimals, and Sara's D65 is (0.312727, 0.329023).
func test_a_white_rounded_to_four_decimals_is_still_its_illuminant() -> void:
    assert_eq(SaColorNames.illuminant_name(Vector2(0.3127, 0.3290)), "D65", "The written form of D65 is D65")
    assert_eq(SaColorNames.illuminant_name(Vector2(0.3457, 0.3585)), "D50", "and of D50 is D50")
    assert_eq(SaColorNames.illuminant_name(Vector2(0.3217, 0.3377)), "D60", "and of D60 is D60")


## Empty rather than `custom`: a white that is not a standard light is a thing a
## document may legitimately declare, and the numbers are then the whole answer.
func test_a_white_that_is_no_illuminant_is_left_as_its_numbers() -> void:
    assert_eq(SaColorNames.illuminant_name(Vector2(0.3400, 0.3400)), "", "An invented white names nothing")
    assert_eq(
        SaColorNames.illuminant_name(Vector2(SaColorSpace.WHITE_D65.x + 0.002, SaColorSpace.WHITE_D65.y)),
        "",
        "and a pair two thousandths off D65 is not D65, which is what the tolerance is for"
    )


## The Document block's whole reason for a depth row is that it agrees with the
## Colour space block's, so the two read one function.
func test_both_depth_rows_read_the_same_source() -> void:
    var docker := _docker()
    var space := SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16)
    var doc := SaDocument.new()
    doc.color_space = space
    var document := docker._section_boxes["Document"]
    var colour := docker._section_boxes["Colour space"]

    document._document_rows(doc)
    colour._colour_rows(space)
    assert_eq((document.rows["Depth"][1] as Label).text, "F16", "The Document block reads the depth")
    assert_eq((colour.rows["Depth"][1] as Label).text, "F16", "and the Colour space block reads the same one")

    doc.color_space = SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F32)
    document._document_rows(doc)
    colour._colour_rows(doc.color_space)
    assert_eq((document.rows["Depth"][1] as Label).text, "F32", "F32 reaches both rows too")
    assert_eq((colour.rows["Depth"][1] as Label).text, "F32", "and neither can drift from the other")

    doc.free()
    docker.free()


## The name in front and the numbers behind it. The name alone cannot be checked
## against a file header, and the numbers alone were the fault.
func test_the_white_row_names_the_illuminant_and_keeps_the_numbers() -> void:
    var docker := _docker()
    var space := SaColorSpace.srgb()
    var colour := docker._section_boxes["Colour space"]

    colour._colour_rows(space)
    assert_eq(
        (colour.rows["White"][1] as Label).text, "D65 (0.3127, 0.3290)", "The white point is a name and the pair it was read from"
    )
    assert_eq((colour.rows["Gamut"][1] as Label).text, "sRGB / Rec. 709", "and the gamut is a name")

    space.white = Vector2(0.3400, 0.3400)
    space.primaries = _invented_primaries()
    colour._colour_rows(space)
    assert_eq(
        (colour.rows["White"][1] as Label).text,
        "0.3400, 0.3400",
        "A white that is no illuminant keeps the numbers and grows no empty parentheses"
    )
    assert_eq((colour.rows["Gamut"][1] as Label).text, "custom", "and unknown primaries say custom")
    docker.free()


## The white the Colour Spaces page's readout prints, without its label.
func _page_white(page: SaColorSpacesPage) -> String:
    for line: String in page.browser.readout.text.split("\n"):
        if line.begins_with("White: "):
            return line.trim_prefix("White: ")
    return ""


## The audit found the docker's name with no source on the page
## that describes the spaces, which printed the pair alone. Both now print
## `SaColorNames.white_point_text`, so this is the case that fails if either
## goes back to a format string of its own. Three lights and a white that is
## none, because the pair-alone form is the other half of the one call.
func test_the_colour_spaces_page_and_the_docker_print_one_white() -> void:
    var docker := _docker()
    var page := SaColorSpacesPage.new()
    var primaries := SaGamut.srgb().primaries
    var d50 := SaColorSpace.create(SaColorSpace.ID_CUSTOM, primaries, SaColorNames.WHITE_D50, SaTransferFunction.srgb())
    var none := SaColorSpace.create(SaColorSpace.ID_CUSTOM, primaries, Vector2(0.3400, 0.3400), SaTransferFunction.srgb())
    var cases := [
        [SaColorSpace.srgb(), "D65 (0.3127, 0.3290)"],
        [SaColorSpace.acescg(), "D60 (0.3217, 0.3377)"],
        [d50, "D50 (0.3457, 0.3585)"],
        [none, "0.3400, 0.3400"],
    ]
    for entry: Array in cases:
        var space := entry[0] as SaColorSpace
        page.browser.show_space(space)
        docker._section_boxes["Colour space"]._colour_rows(space)
        var page_white := _page_white(page)
        assert_eq(page_white, entry[1] as String, "The Colour Spaces page names the white and keeps the pair")
        assert_eq(page_white, SaColorNames.white_point_text(space.white), "and prints it from the one call")
        assert_eq(
            (docker._section_boxes["Colour space"].rows["White"][1] as Label).text,
            page_white,
            "and the Info docker's white row is the same string for %s" % entry[1]
        )
        assert_eq(String(page.browser.capture_state()["white"]), page_white, "and a dump carries it as printed")
    page.free()
    docker.free()
