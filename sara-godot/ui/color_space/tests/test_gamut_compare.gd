## The two shapes on the Colour Spaces page, and the chooser over them.
##
## The graph should show two shapes. One is the selected gamut dimmed and the
## second is the potentially bigger one in colour, so if sRGB is selected, P3 is
## displayed. The graph is useless if there is nothing to compare it to.
##
## Both shapes were being drawn all along. What was missing is measured in
## `scenarios/gamut-second-shape.json`: the
## chooser named a space the page was not drawing, the volume was drawn a fifth
## of its control wide, and nothing said which shape was which.
extends "res://tests/test_framework.gd"


## A document opens at F16 and every preset is F32, so a chooser matching on
## full equality never followed a real document: Preferences drew Display P3
## and read "sRGB" over the top of it.
func test_the_chooser_follows_a_document_of_any_depth() -> void:
    var browser := SaColorSpaceBrowser.new()
    var document_space := SaColorSpace.oklab_p3().with_depth(SaColorSpace.Depth.F16)
    browser.show_space(document_space)
    assert_eq(
        browser.option.text,
        SaColorSpace.display_name(SaColorSpace.ID_OKLAB_P3),
        "the chooser names the space the page is drawing"
    )
    browser.free()


## Both drawings carry two shapes and the report says
## how far apart they are, because a screenshot of two nested outlines and one
## of a single outline drawn twice are the same screenshot.
func test_srgb_draws_two_distinct_shapes() -> void:
    var browser := SaColorSpaceBrowser.new()
    browser.show_space(SaColorSpace.srgb())
    browser.diagram.size = Vector2(800, 250)
    browser.solid.size = Vector2(800, 340)

    var diagram: Dictionary = browser.diagram.report()
    assert_eq(diagram["compare"], "display_p3", "sRGB compares against P3, which is the example")
    assert_true(diagram["distinct"], "and the two triangles are apart: %s" % diagram["spread"])

    var solid: Dictionary = browser.solid.report()
    assert_eq(solid["compare"], "display_p3", "the volume compares against the same gamut")
    assert_true(solid["distinct"], "and its two wireframes are apart: %s" % solid["spread"])
    browser.free()


## Which shape is which, in words. The pair only answers if a reader
## can tell them apart, and a nested wireframe cannot say it on its own.
func test_the_legend_names_the_wider_shape() -> void:
    var browser := SaColorSpaceBrowser.new()
    browser.show_space(SaColorSpace.srgb())
    var text := browser.legend.text
    assert_true(text.contains("Display P3"), "the legend names the comparison: %s" % text)
    assert_true(text.contains("sRGB"), "and the selection: %s" % text)
    assert_true(text.begins_with("Bright and outermost: Display P3"), "the wider one first, as it is drawn: %s" % text)
    browser.free()


## A painter may pick a narrower gamut from the dropdown, and then the bright
## outer shape is the smaller one. The legend says that rather than repeating
## the sentence that assumes otherwise.
func test_the_legend_says_when_the_comparison_is_narrower() -> void:
    var browser := SaColorSpaceBrowser.new()
    browser.show_space(SaColorSpace.display_p3())
    var srgb_index := -1
    var gamuts := SaGamut.presets()
    for i in gamuts.size():
        if gamuts[i].id == SaGamut.ID_SRGB:
            srgb_index = i
    browser._on_compare_selected(srgb_index)
    var text := browser.legend.text
    assert_true(text.contains("narrower than the selection"), "the legend owns up to the order: %s" % text)
    browser.free()
