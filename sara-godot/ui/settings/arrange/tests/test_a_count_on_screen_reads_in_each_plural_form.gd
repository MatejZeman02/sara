## A sentence on screen that carries a count goes through the plural form.
##
## Czech has three plural forms, "1 vrstva", "2 vrstvy" and "5 vrstev", and a
## translator cannot make them from one string with the number already in it.
## So a count goes through `tr_n()` with the count. The top bar page's overflow
## sentence is one that went from `tr()` with a `%d` to `tr_n()`, and here it is
## read under a Czech catalogue built in code, which carries its three forms
## and Czech's plural rule, for 1, 3 and 5.
extends "res://tests/test_framework.gd"

const LOCALE := "cs"
const MODULE := &"t4-plural-fixture"
## Czech's rule as a `.po` header writes it: one, two to four, and the rest.
const CZECH_RULE := "nplurals=3; plural=(n==1) ? 0 : (n>=2 && n<=4) ? 1 : 2;"
const ONE := "%d control is in the overflow list, behind the button at the end of the bar."
const FORMS: Array[String] = [
    "%d ovládací prvek je v seznamu přetečení, za tlačítkem na konci lišty.",
    "%d ovládací prvky jsou v seznamu přetečení, za tlačítkem na konci lišty.",
    "%d ovládacích prvků je v seznamu přetečení, za tlačítkem na konci lišty.",
]


func test_the_overflow_sentence_reads_one_three_and_five_in_their_three_forms() -> void:
    var registries := SaRegistries.new()
    registries.build_context(Callable(), Callable())
    var catalogue := Translation.new()
    catalogue.locale = LOCALE
    catalogue.set_plural_rules_override(CZECH_RULE)
    catalogue.add_plural_message(ONE, PackedStringArray(FORMS))
    var scoped := registries.context.for_module(MODULE)
    assert_true(scoped.register_translation(catalogue), "the catalogue built in code registers")
    var locale := TranslationServer.get_locale()
    TranslationServer.set_locale(LOCALE)
    var page := SaTopBarPage.new()

    assert_eq(page.fit_sentence(1, [], ""), FORMS[0] % 1, "one control reads the first form")
    assert_eq(page.fit_sentence(3, [], ""), FORMS[1] % 3, "three the second")
    assert_eq(page.fit_sentence(5, [], ""), FORMS[2] % 5, "and five the third, by the catalogue's own rule")

    scoped.remove_all_registrations()
    TranslationServer.set_locale(locale)
    var english := page.fit_sentence(5, [], "")
    assert_eq(english, "5 controls are in the overflow list, behind the button at the end of the bar.", "and English again after")
    page.free()
