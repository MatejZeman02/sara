## The not-carried tag a converted or imported preset wears reads in the
## painter's language wherever the chooser shows it, and stays the stored English
## word underneath, since the filter, a rename and the profile name that word.
##
## A catalogue that marks every message it is asked for, as the test language
## does, stands in for a language.
extends "res://tests/test_framework.gd"

const LOCALE := "eo"


## A catalogue of one locale that marks every message it is asked for.
class Marking:
    extends Translation

    func _get_message(src_message: StringName, _context: StringName) -> StringName:
        return StringName("‹%s›" % src_message)


var _catalogue: Translation
var _locale_before := ""


func before_each() -> void:
    SaTagLabels.register(SaNotCarried.PREFIX, Callable(SaNotCarried, &"label"), &"test_not_carried")
    _locale_before = TranslationServer.get_locale()
    _catalogue = Marking.new()
    _catalogue.locale = LOCALE


func after_each() -> void:
    SaTagLabels.unregister_module(&"test_not_carried")
    TranslationServer.set_locale(_locale_before)
    TranslationServer.remove_translation(_catalogue)


func _in_the_marking_language() -> void:
    TranslationServer.add_translation(_catalogue)
    TranslationServer.set_locale(LOCALE)


func test_the_english_of_a_tag_is_the_word_stored() -> void:
    for stored: String in [
        "not carried: image tip", "not carried: pattern png", "not carried: grain field", "not carried: strength"
    ]:
        assert_eq(SaTagLabels.label(stored), stored, "'%s' reads as stored in English" % stored)


func test_a_tag_a_painter_wrote_is_shown_as_it_is() -> void:
    _in_the_marking_language()
    assert_eq(SaTagLabels.label("mine"), "mine", "a painter's own word is never translated")
    assert_eq(SaTagLabels.label("not carried"), "not carried", "nor a word that only looks like one")


func test_every_phrase_a_conversion_or_an_import_stores_is_marked() -> void:
    _in_the_marking_language()
    for phrase: String in [
        "image tip",
        "colour source",
        "pattern png",
        "blend mode dodge",
        "tip: a.gbr could not be read.",
        "grain field",
        "bristle field",
        "picture field",
        "strength",
        "picture rotation",
        "second channel",
    ]:
        var shown := SaTagLabels.label(SaNotCarried.PREFIX + phrase)
        assert_true(shown.begins_with("‹"), "'%s' is marked as a whole sentence: %s" % [phrase, shown])
        assert_true(
            shown.contains("‹%s›" % SaNotCarried.reason(phrase).trim_prefix("‹").trim_suffix("›")),
            "its reason is marked too: %s" % shown
        )


func test_the_stored_tag_is_the_filter_word_whatever_the_language() -> void:
    _in_the_marking_language()
    assert_true(SaNotCarried.is_tag("not carried: image tip"), "the stored spelling is what is recognised")
    assert_false(
        SaNotCarried.is_tag(SaNotCarried.label("not carried: image tip")), "a shown label is never taken for a stored tag"
    )
