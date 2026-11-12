## A module registers a translation, and Preferences > Languages switches to it
## while Sara runs.
##
## The idea: every language other than English is a module that
## registers a catalogue for one locale through the registries, and the
## Languages page lists what is registered. The language
## switches with no restart, and where two catalogues carry one sentence the
## one registered last wins, the page listing them in that order. The fixture
## under `tests/fixtures/modules/language-fixture/` is the module, with a Czech
## `.po` of the page's own words and the top bar's menu names.
extends "res://tests/test_framework.gd"

const LanguageFixture = preload("res://tests/fixtures/modules/language-fixture/module.gd")

## The module id the second catalogue of the order case registers under.
const LATER_MODULE := &"later-language-fixture"


## The fixture module registered into *registries* the way the loader does it,
## with a context of its own, which `remove_all_registrations` empties again.
func _register_fixture(registries: SaRegistries) -> SaContext:
    var module: SaModule = LanguageFixture.new()
    var scoped := registries.context.for_module(module.get_id())
    module.context = scoped
    module.register(scoped)
    return scoped


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(Callable(), Callable())
    return registries


## The first case: registered, its locale set, a sentence of it
## read through `tr()` in Czech and its plural through `tr_n()` in each of the
## three Czech forms, then the module unloaded and the same sentence read in
## English.
func test_the_fixtures_catalogue_is_read_through_tr_until_its_module_unloads() -> void:
    var registries := _registries()
    var scoped := _register_fixture(registries)
    var held := registries.translations.catalogues()
    assert_eq(held.size(), 1, "the fixture registers one catalogue")
    assert_eq(String(held[0]["locale"]), LanguageFixture.LOCALE, "for Czech")
    assert_eq(held[0]["module"], &"language-fixture", "under its own module")
    var locale := TranslationServer.get_locale()
    TranslationServer.set_locale(LanguageFixture.LOCALE)

    assert_eq(tr("Languages"), "Jazyky", "the page's title reads in Czech through tr()")
    assert_eq(tr("Edit"), "Úpravy", "and so does a menu name")
    assert_eq(tr_n("%d sentence", "%d sentences", 1) % 1, "1 věta", "one is the first Czech form")
    assert_eq(tr_n("%d sentence", "%d sentences", 3) % 3, "3 věty", "three the second")
    assert_eq(tr_n("%d sentence", "%d sentences", 5) % 5, "5 vět", "and five the third, the catalogue's own plural rule")

    scoped.remove_all_registrations()
    assert_true(registries.translations.catalogues().is_empty(), "unloading the module takes its catalogue")
    assert_eq(tr("Languages"), "Languages", "and the same sentence reads in English again")
    TranslationServer.set_locale(locale)


## The second clause: two catalogues of one locale carrying one sentence, the
## later one's is shown, a sentence only the earlier carries still is, and
## taking the later one away uncovers the earlier one's. The page lists both
## in the order they came.
func test_the_catalogue_registered_last_wins_and_the_page_lists_them_in_order() -> void:
    var registries := _registries()
    _register_fixture(registries)
    var later := Translation.new()
    later.locale = LanguageFixture.LOCALE
    later.add_message("Languages", "Řeči")
    var later_context := registries.context.for_module(LATER_MODULE)
    assert_true(later_context.register_translation(later), "a second module registers a catalogue of the same locale")
    var locale := TranslationServer.get_locale()
    TranslationServer.set_locale(LanguageFixture.LOCALE)

    assert_eq(tr("Languages"), "Řeči", "the one registered last is the one read")
    assert_eq(tr("Edit"), "Úpravy", "and a sentence only the first carries is still read from it")

    var page := SaLanguagesPage.new(registries.translations)
    var first := page.page.row(&"catalogue_1")
    var second := page.page.row(&"catalogue_2")
    assert_not_null(first, "the page lists the first catalogue")
    assert_not_null(second, "and the second")
    if first != null and second != null:
        assert_true(first.label.begins_with("1. "), "the first in the first place: %s" % first.label)
        assert_true(second.label.begins_with("2. "), "the second in the second: %s" % second.label)
        var first_line := (first.custom_control as Label).text
        var second_line := (second.custom_control as Label).text
        var named := first_line.contains("language-fixture") and first_line.contains("cs.po")
        assert_true(named, "with its module and file: %s" % first_line)
        assert_true(second_line.contains(String(LATER_MODULE)), "and the later one with its module: %s" % second_line)
    var ids: Array = SaLanguagesPage.choices(registries.translations).map(func(entry: Dictionary) -> String: return entry["id"])
    assert_eq(ids, ["en_GB", "cs"], "the Language row offers English and the registered locale, once")
    page.free()

    later_context.remove_all_registrations()
    assert_eq(tr("Languages"), "Jazyky", "taking the later one away uncovers the earlier one's sentence")
    TranslationServer.set_locale(locale)


## A pick on the page's Language row is the setting, the locale at once, and
## the page asking to be drawn again in it.
func test_a_pick_on_the_page_switches_the_locale_at_once_and_is_kept() -> void:
    var registries := _registries()
    _register_fixture(registries)
    var stored := SaSettings.ui_language
    var locale := TranslationServer.get_locale()
    var page := SaLanguagesPage.new(registries.translations)
    var asked := [0]
    page.rebuild_requested.connect(func() -> void: asked[0] += 1)
    var row := page.page.row(&"language")
    assert_not_null(row, "the page has its Language row")
    if row != null:
        # By the row's index, as a hand's press and a scenario's step drive a
        # choice: English is the first, Czech the second.
        row.drive(1)
        assert_eq(SaSettings.ui_language, "cs", "the pick is kept as the setting")
        assert_eq(TranslationServer.get_locale(), "cs", "and the locale switched with it")
        assert_eq(tr("Languages"), "Jazyky", "so the next tr() reads Czech")
        assert_eq(asked[0], 1, "and the page asked to be drawn again in it")
    page.free()
    SaSettings.ui_language = stored
    TranslationServer.set_locale(locale)


## English is the text every catalogue translates from, so a catalogue of
## `en` is refused, and so is a path that loads no catalogue.
func test_a_catalogue_of_english_and_a_path_of_nothing_are_refused() -> void:
    var registries := SaTranslationRegistry.new()
    var english := Translation.new()
    english.locale = "en"
    english.add_message("Colour", "Color")
    assert_false(registries.register(english, &"x"), "a catalogue of en is refused")
    assert_false(registries.register("res://no/such/catalogue.po", &"x"), "and a path that loads none")
    assert_true(registries.catalogues().is_empty(), "and nothing is held")
