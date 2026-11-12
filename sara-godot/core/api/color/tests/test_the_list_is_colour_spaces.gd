## What the Colour Spaces page's first chooser is a list of.
##
## A painter's note, on the row reading "Oklab": "oklab is not gamut. OKlab is
## completely gamut independent. Why is it in this list then?"
##
## The answer is that the list was never a gamut list and the words around it
## said it was. `SaColorSpace.presets()` answers eight colour spaces, and a colour space here is primaries, a
## white point, a transfer
## curve and a coordinate system together. Three of the eight are in Oklab
## coordinates, and each carries a gamut of its own: sRGB's for two, Display
## P3's for the other.
## So this is a naming fix. Taking Oklab out would take away the coordinate
## system documents actually paint in.
##
## What this file grades is the words. The picture is
## `scenarios/oklab-is-a-colour-space-and-not-a-gamut.json`.
extends "res://tests/test_framework.gd"


## The heart of it. Neither Oklab row may read as a gamut on its own, and every
## row has to name something a painter can pick.
func test_every_preset_names_itself_and_the_oklab_rows_name_their_gamut() -> void:
    var names: Array[String] = []
    for space: SaColorSpace in SaColorSpace.presets():
        names.append(SaColorSpace.display_name(space.id))
    assert_eq(names.size(), 8, "eight colour spaces on offer")
    assert_eq(
        names,
        [
            "sRGB",
            "Linear sRGB",
            "Display P3",
            "ACEScg",
            "Rec. 2020",
            "Oklab over sRGB",
            "Oklab over Display P3",
            "Oklab over sRGB, cube root"
        ],
        "and each says what it is"
    )


## The note's own row. "Oklab" alone was the whole complaint: it named a
## coordinate system where every other row named a colour space.
func test_no_row_is_the_bare_word_oklab() -> void:
    for space: SaColorSpace in SaColorSpace.presets():
        var shown := SaColorSpace.display_name(space.id)
        assert_true(shown != "Oklab", "'%s' is not the bare coordinate system's name" % shown)


## The Oklab entries really do carry the gamuts their names claim, so
## the words are a description and not a label.
func test_the_oklab_rows_carry_the_gamuts_they_name() -> void:
    assert_true(SaColorSpace.oklab().gamut().matches(SaGamut.srgb()), "Oklab over sRGB is sRGB's primaries in Oklab coordinates")
    assert_true(SaColorSpace.oklab_p3().gamut().matches(SaGamut.display_p3()), "and Oklab over Display P3 is Display P3's")
    assert_true(SaColorSpace.oklab_srgb_gamma30().gamut().matches(SaGamut.srgb()), "and the cube root one is sRGB's again")
    assert_eq(SaColorSpace.oklab().coordinates, SaColorSpace.Coordinates.OKLAB, "all are in Oklab coordinates")
    assert_eq(SaColorSpace.oklab_p3().coordinates, SaColorSpace.Coordinates.OKLAB, "which is what they share")
    assert_eq(SaColorSpace.oklab_srgb_gamma30().coordinates, SaColorSpace.Coordinates.OKLAB, "the third among them")


## The coordinate system keeps its own bare name, which is the one place the
## word is right. The New Document dialog's Coordinates row reads it.
func test_the_coordinate_system_is_still_called_oklab() -> void:
    assert_eq(
        SaColorSpace.coordinates_name(SaColorSpace.Coordinates.OKLAB), "Oklab", "the coordinate system is Oklab and says so"
    )
    assert_eq(SaColorSpace.coordinates_name(SaColorSpace.Coordinates.RGB), "RGB", "and the other one is RGB")


## The section over the chooser, and the chooser itself. The heading said
## "Gamut" over a list of colour spaces, which is the other half of the note.
## The chooser is the colour space picker's own row, in place of the browser's,
## and the picker's Gamut row under it really does choose a gamut.
func test_the_page_heading_and_the_chooser_name_a_colour_space() -> void:
    var page := SaColorSpacesPage.new()
    var heading := _first_label(page, "Colour space")
    assert_not_null(heading, "the section over the chooser is headed 'Colour space'")

    var chooser := page.find_child("GamutOption", true, false) as SaChoiceButton
    assert_not_null(chooser, "the node name stays, because scenarios reach it by that")
    if chooser != null:
        assert_true(chooser.visible, "on the picker's row, which is the one shown")
        assert_true(
            chooser.choice_labels().has(SaColorSpace.display_name(SaColorSpace.ID_OKLAB)),
            "and it lists colour spaces, Oklab among them: %s" % [chooser.choice_labels()]
        )
    assert_false(page.browser.option.visible, "the browser's own chooser gives way to the picker")
    page.free()


## The second chooser is over `SaGamut.presets()`, which really is a list of
## gamuts, so it keeps the word.
func test_the_compare_chooser_still_says_gamut() -> void:
    var browser := SaColorSpaceBrowser.new()
    assert_true(browser.compare_option.tooltip_text.contains("gamut"), "the compare chooser compares gamuts and says so")
    for gamut: SaGamut in SaGamut.presets():
        assert_true(gamut.primaries.size() >= 3, "%s has primaries, which is what makes it a gamut" % gamut.display_name)
    browser.free()


## The caption under the diagram, which is where the two words meet: the
## horseshoe is every chromaticity, the triangle is the gamut, and the row above
## chooses the space that triangle belongs to.
func test_the_caption_says_the_triangle_is_the_gamut() -> void:
    var browser := SaColorSpaceBrowser.new()
    var caption := _first_label(browser, "CIE 1931 xy", true)
    assert_not_null(caption, "the diagram has a caption")
    assert_true(caption.text.contains("the gamut this space holds"), "which calls the triangle the gamut: %s" % caption.text)
    browser.free()


## The first Label under *node* whose text is *wanted*, or begins with it when
## *prefix* is true.
func _first_label(node: Node, wanted: String, prefix: bool = false) -> Label:
    var label := node as Label
    if label != null and (label.text == wanted or (prefix and label.text.begins_with(wanted))):
        return label
    for child in node.get_children():
        var found := _first_label(child, wanted, prefix)
        if found != null:
            return found
    return null
