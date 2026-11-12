## A word with two meanings carries a context, so a catalogue can translate
## each one.
##
## "Open" on the welcome window opens a document and "Open" in the filter
## browser opens a filter, so the two ask for it under two contexts. A
## catalogue that gives the word a different translation in each context is
## read by each button under its own, and under British and American English
## both buttons still read "Open".
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const AmericanEnglish = preload("res://modules/sara-base-modules/language-en-us/module.gd")

## A locale no catalogue of the tree holds, so the test's own is the only one.
const LOCALE := "cs_CZ"
const DOCUMENT := "Otevřít dokument"
const FILTER := "Spustit filtr"

var _locale := ""
var _catalogue: Translation = null
var _loaded: Array[SaModule] = []


func before_each() -> void:
    _locale = TranslationServer.get_locale()


func after_each() -> void:
    if _catalogue != null:
        TranslationServer.remove_translation(_catalogue)
        _catalogue = null
    while not _loaded.is_empty():
        var module: SaModule = _loaded.pop_back()
        module.unregister(module.context)
        module.context.remove_all_registrations()
    TranslationServer.set_locale(_locale)


## The welcome window's Open button and the filter browser's, built under the
## locale set now, as `[welcome, browser]` texts. The welcome window also reads
## its words again as a change of language makes it, so the context it keeps
## for a later change is read too.
func _both_buttons() -> Array[String]:
    var window := SaWelcomeWindow.new()
    var welcome := window.find_child("OpenButton", true, false) as Button
    var built := welcome.text
    window.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
    assert_eq(welcome.text, built, "and a change of language reads the welcome window's Open under the same context")
    var browser := SaFilterBrowser.new()
    var texts: Array[String] = [welcome.text, browser.open_button.text]
    window.free()
    browser.free()
    return texts


func test_a_catalogue_translates_open_differently_in_its_two_contexts() -> void:
    _catalogue = Translation.new()
    _catalogue.locale = LOCALE
    _catalogue.add_message("Open", DOCUMENT, "open a document")
    _catalogue.add_message("Open", FILTER, "open a filter")
    TranslationServer.add_translation(_catalogue)
    TranslationServer.set_locale(LOCALE)
    var texts := _both_buttons()
    assert_eq(texts[0], DOCUMENT, "The welcome window's Open reads the document's translation")
    assert_eq(texts[1], FILTER, "and the filter browser's Open reads the filter's")


func test_british_and_american_english_both_read_open() -> void:
    var registries := Fixtures.make_registries()
    var module: SaModule = AmericanEnglish.new()
    var scoped := registries.context.for_module(module.get_id())
    module.context = scoped
    module.register(scoped)
    _loaded.append(module)
    for locale: String in [AmericanEnglish.BRITISH, AmericanEnglish.LOCALE]:
        TranslationServer.set_locale(locale)
        var texts := _both_buttons()
        assert_eq(texts[0], "Open", "Under %s the welcome window's button reads Open" % locale)
        assert_eq(texts[1], "Open", "and so does the filter browser's")
