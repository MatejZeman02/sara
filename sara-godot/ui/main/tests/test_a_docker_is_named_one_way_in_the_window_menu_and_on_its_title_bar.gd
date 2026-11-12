## The Window menu's row and the docker's title bar spell a docker's name the
## same way, in British English, in American English, and after the language
## changes under a title bar that is already built.
##
## The bar translated its words once, at the moment it was made, so a locale
## applied afterwards left "Colour Picker" on the bar and "Color Picker" in the
## menu, or the other way round. The bar now hands its label the source string,
## which the label translates every time it is drawn, and the menu asks
## `SaDockerIds.display_name`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const AmericanEnglish = preload("res://modules/sara-base-modules/language-en-us/module.gd")
const REQUIRES_GPU := true

## A title with a British word in it, which the American catalogue respells.
const TITLE := "Colour Picker"

var _locale := ""
var _module: SaModule = null


func before_each() -> void:
    _locale = TranslationServer.get_locale()
    var registries := Fixtures.make_registries()
    _module = AmericanEnglish.new()
    var scoped := registries.context.for_module(_module.get_id())
    _module.context = scoped
    _module.register(scoped)


func after_each() -> void:
    _module.unregister(_module.context)
    _module.context.remove_all_registrations()
    TranslationServer.set_locale(_locale)


## What the bar's label draws, which is the translation of the text it holds.
func _drawn(bar: Control) -> String:
    var lbl := bar.find_child("TitleLabel", true, false) as Label
    return lbl.atr(lbl.text)


func test_the_menu_row_and_the_bar_agree_in_both_spellings() -> void:
    for locale: String in [AmericanEnglish.BRITISH, AmericanEnglish.LOCALE]:
        TranslationServer.set_locale(locale)
        var bar := DockerUtils.make_drag_bar(TITLE)
        assert_eq(_drawn(bar), SaDockerIds.display_name(TITLE), "%s: the bar says what the menu row says" % locale)
        bar.free()
    TranslationServer.set_locale(AmericanEnglish.LOCALE)
    assert_eq(SaDockerIds.display_name(TITLE), "Color Picker", "and American English is the one that respells it")
    TranslationServer.set_locale(AmericanEnglish.BRITISH)
    assert_eq(SaDockerIds.display_name(TITLE), TITLE, "while British keeps it")


func test_a_bar_built_before_the_language_changed_follows_it() -> void:
    TranslationServer.set_locale(AmericanEnglish.BRITISH)
    var bar := DockerUtils.make_drag_bar(TITLE)
    TranslationServer.set_locale(AmericanEnglish.LOCALE)
    assert_eq(_drawn(bar), SaDockerIds.display_name(TITLE), "the bar built under British now says the American spelling too")
    bar.free()


## The other direction: the system's locale is en_US, so the bar is
## built American, and Sara then applies the profile's British. A label holding
## the finished American words has no source string left to translate back.
func test_a_bar_built_american_follows_the_language_back_to_british() -> void:
    TranslationServer.set_locale(AmericanEnglish.LOCALE)
    var bar := DockerUtils.make_drag_bar(TITLE)
    TranslationServer.set_locale(AmericanEnglish.BRITISH)
    assert_eq(_drawn(bar), TITLE, "the bar built American reads British once the language is British")
    assert_eq(_drawn(bar), SaDockerIds.display_name(TITLE), "and says what the menu row says")
    bar.free()


func test_every_built_in_docker_agrees_in_both_spellings() -> void:
    var registry := SaUIRegistry.new()
    var dockers := MainDockers.new(registry)
    dockers.register_builtin_dockers()
    var titles: Array[String] = []
    for entry: Dictionary in registry.list_dockers():
        titles.append(String(entry["title"]))
    dockers.free()
    assert_true(titles.size() > 10, "the built-in list gave its titles")
    for locale: String in [AmericanEnglish.BRITISH, AmericanEnglish.LOCALE]:
        TranslationServer.set_locale(locale)
        for title: String in titles:
            var bar := DockerUtils.make_drag_bar(title)
            assert_eq(_drawn(bar), SaDockerIds.display_name(title), "%s: %s" % [locale, title])
            bar.free()
