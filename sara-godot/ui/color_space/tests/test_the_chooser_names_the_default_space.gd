## The Colour Spaces chooser names the space the page is showing.
##
## The chooser must not say "sRGB" while the readout under it shows Gamma 3.0
## and Oklab, and New Document calls the same space "Custom". The easel's default under an sRGB display is Oklab and
## Gamma 3.0 over sRGB's primaries, which no preset names, and the chooser only
## moved on a match, so it kept the first row it was built on. That
## combination has a preset of its own, so under an sRGB display the
## chooser names it, and a display no preset has a match for is where Custom is
## still the true word.
extends "res://tests/test_framework.gd"


## The default under an sRGB display, built rather than read, so the suite does
## not depend on the profile the machine running it has.
func _default_over_srgb() -> SaColorSpace:
    return SaColorSpace.oklab_p3().with_depth(SaColorSpace.Depth.F16).with_gamut(SaColorSpace.srgb().gamut())


## The default under a Rec. 2020 display, which is Oklab and the cube root over
## primaries no preset pairs them with, so Custom is what it is.
func _default_over_rec2020() -> SaColorSpace:
    return SaColorSpace.oklab_p3().with_depth(SaColorSpace.Depth.F16).with_gamut(SaColorSpace.rec2020().gamut())


func test_the_default_over_srgb_is_a_preset_the_chooser_names() -> void:
    var browser := SaColorSpaceBrowser.new()
    browser.show_space(_default_over_srgb())
    var text := browser.option.text
    browser.free()

    var named := SaColorSpace.display_name(SaColorSpace.ID_OKLAB_SRGB_GAMMA30)
    assert_eq(text, named, "the chooser names the space a fresh install paints in")
    assert_true(text != SaColorSpaceBrowser.CUSTOM_LABEL, "and no longer says Custom for it")


func test_a_default_no_preset_names_puts_the_chooser_on_custom() -> void:
    var browser := SaColorSpaceBrowser.new()
    var space := _default_over_rec2020()
    browser.show_space(space)
    var text := browser.option.text
    var readout := browser.readout.text
    browser.free()

    assert_eq(text, SaColorSpaceBrowser.CUSTOM_LABEL, "the chooser says Custom, as New Document does")
    assert_true(readout.contains("Oklab"), "over the readout of the space it is showing, %s" % readout)


## Whatever the machine's display profile makes of the default, the chooser is
## on the preset that names it or on Custom, never on sRGB.
func test_the_easels_default_is_never_called_srgb() -> void:
    var browser := SaColorSpaceBrowser.new()
    var space := SaEasel.default_space()
    browser.show_space(space)
    var text := browser.option.text
    browser.free()

    var named := false
    for preset in SaColorSpace.presets():
        if preset.with_depth(space.depth).matches(space):
            named = text == SaColorSpace.display_name(preset.id)
    assert_true(named or text == SaColorSpaceBrowser.CUSTOM_LABEL, "the chooser reads %s for the default" % text)
    assert_true(text != SaColorSpace.display_name(SaColorSpace.srgb().id), "and never sRGB")


## Custom is a row like the others: picked, it puts back the space it stands
## for, and a preset picked after it moves the button off it.
func test_the_custom_row_puts_back_the_space_it_stands_for() -> void:
    var browser := SaColorSpaceBrowser.new()
    var space := _default_over_rec2020()
    browser.show_space(space)
    browser.select_space(0)
    var on_preset := browser.option.text
    browser.select_space(browser.presets.size())
    var back: Dictionary = browser.capture_state()
    var text := browser.option.text
    browser.free()

    assert_true(on_preset != SaColorSpaceBrowser.CUSTOM_LABEL, "a preset picked leaves Custom")
    assert_eq(text, SaColorSpaceBrowser.CUSTOM_LABEL, "Custom picked again reads Custom")
    assert_eq(back["coordinates"], SaColorSpace.coordinates_name(space.coordinates), "and draws the space it stood for")
    assert_eq(back["gamut"], String(space.gamut().id), "over the gamut it had")
