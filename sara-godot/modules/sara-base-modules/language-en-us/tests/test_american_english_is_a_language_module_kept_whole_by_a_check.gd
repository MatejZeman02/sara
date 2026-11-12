## American English is a language module kept whole by a check.
##
## The module registers `en_US.po`, which `scripts/write_en_us.py` writes from
## the tree, the way any language module registers its catalogue. Under
## `en_US` a British word reads American, a sentence with none reads as itself,
## and under `en` nothing changes. A blend mode's hover adds no "In English"
## line under a variant of English, and keeps it under Czech.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const AmericanEnglish = preload("res://modules/sara-base-modules/language-en-us/module.gd")
const LanguageFixture = preload("res://tests/fixtures/modules/language-fixture/module.gd")
const REQUIRES_GPU := true

var _locale := ""

## The modules [method _register] loaded, unloaded again after each test.
var _loaded: Array[SaModule] = []


func before_each() -> void:
    _locale = TranslationServer.get_locale()


func after_each() -> void:
    _unload_all()
    TranslationServer.set_locale(_locale)


## *script*'s module registered into *registries* the way the loader does it,
## with a context of its own, which [method _unload_all] takes out again the
## way the loader does.
func _register(registries: SaRegistries, script: GDScript) -> SaContext:
    var module: SaModule = script.new()
    var scoped := registries.context.for_module(module.get_id())
    module.context = scoped
    module.register(scoped)
    _loaded.append(module)
    return scoped


## Every module this test loaded, unregistered and its registrations removed,
## the last loaded first.
func _unload_all() -> void:
    while not _loaded.is_empty():
        var module: SaModule = _loaded.pop_back()
        module.unregister(module.context)
        module.context.remove_all_registrations()


func test_the_module_registers_its_catalogue_for_en_us() -> void:
    var registries := Fixtures.make_registries()
    _register(registries, AmericanEnglish)
    var held := registries.translations.catalogues()
    assert_eq(held.size(), 1, "the module registers one catalogue")
    assert_eq(String(held[0]["locale"]), AmericanEnglish.LOCALE, "for en_US")
    assert_eq(held[0]["module"], &"language-en-us", "under its own module")


## The fifth shot's line on the Languages page: the catalogue names its module
## and its file, and counts as many sentences as `en_US.po` has entries, each
## entry one `msgid` line after the header's.
func test_the_languages_page_counts_every_entry_of_the_catalogue() -> void:
    var registries := Fixtures.make_registries()
    _register(registries, AmericanEnglish)
    var entries := -1
    for line in FileAccess.get_file_as_string(AmericanEnglish.new().catalogue_path()).split("\n"):
        if line.begins_with("msgid "):
            entries += 1
    assert_true(entries > 100, "the file holds the generated entries")
    var held := registries.translations.catalogues()
    assert_eq(int(held[0]["sentences"]), entries, "the registry counts every entry")
    TranslationServer.set_locale(SaSettingsValues.BRITISH)
    assert_eq(
        SaLanguagesPage.catalogue_line(held[0]),
        "From the module language-en-us, in en_US.po. %d sentences" % entries,
        "the page's line names the module, the file and the count",
    )


## The first clause of Done when, its sentences: the Select menu's row, a
## message carrying `%s`, one with no British word, and under `en` each as it is.
func test_a_british_word_reads_american_under_en_us_and_british_under_en() -> void:
    var registries := Fixtures.make_registries()
    _register(registries, AmericanEnglish)
    var formatted := "%s gets its colour from its own simulation data, so this rule cannot change it."
    TranslationServer.set_locale(AmericanEnglish.LOCALE)
    assert_eq(tr("Colour Range..."), "Color Range...", "the Select menu's row reads American")
    assert_eq(
        tr(formatted),
        "%s gets its color from its own simulation data, so this rule cannot change it.",
        "a British word respelt and the %s left whole"
    )
    assert_eq(tr(formatted) % "Fluid", "Fluid gets its color from its own simulation data, so this rule cannot change it.")
    assert_eq(tr("Languages"), "Languages", "a sentence with no British word reads as itself")
    assert_eq(tr("Grey masses"), "Gray masses", "the case of a word is kept")
    TranslationServer.set_locale(SaSettingsValues.BRITISH)
    assert_eq(tr("Colour Range..."), "Colour Range...", "under en_GB the row is British")
    assert_eq(tr(formatted), formatted, "and so is every sentence")
    assert_eq(tr("Languages"), "Languages", "the one with no British word as well")
    assert_eq(tr_n("%d sentence", "%d sentences", 3), "%d sentences", "and a plural picks its English form")


## The Answer of 2026-10-15: a profile's plain `en` is kept as `en_GB`, and
## Czech falls back to British English for a sentence its catalogue lacks.
func test_a_stored_en_and_czech_s_fallback_read_british() -> void:
    var registries := Fixtures.make_registries()
    _register(registries, AmericanEnglish)
    _register(registries, LanguageFixture)
    var settings := SaSettingsValues.new()
    settings.ui_language = "en"
    assert_eq(settings.ui_language, SaSettingsValues.BRITISH, "a stored en reads as en_GB")
    settings.ui_language = ""
    assert_eq(settings.ui_language, SaSettingsValues.BRITISH, "and so does none")
    settings.free()
    assert_eq(ProjectSettings.get_setting("internationalization/locale/fallback"), "en_GB", "the fallback is British")
    TranslationServer.set_locale(LanguageFixture.LOCALE)
    assert_eq(tr("Languages"), "Jazyky", "Czech reads Czech")
    assert_eq(tr("Colour Range..."), "Colour Range...", "and falls back to British for what it lacks")
    assert_false(TranslationServer.get_loaded_locales().has("en"), "no catalogue for a plain en is installed")


## The first clause of Done when, the hover: under `en_US` Colour Dodge reads
## Color Dodge with no "In English" line, and under Czech Multiply keeps one.
func test_a_blend_modes_hover_has_no_english_line_under_a_variant_of_english() -> void:
    var registries := Fixtures.make_registries()
    _register(registries, AmericanEnglish)
    _register(registries, LanguageFixture)
    var button := BlendModeButton.new()
    button.registry = registries.blend_modes
    button.space = SaColorSpace.srgb()
    TranslationServer.set_locale(AmericanEnglish.LOCALE)
    button.refresh()
    var tip := button.popup.label_button(&"color_dodge").tooltip_text
    assert_true(tip.begins_with("Color Dodge\n"), "Colour Dodge reads American: %s" % tip)
    assert_false(tip.contains("In English"), "with no English line under en_US: %s" % tip)
    TranslationServer.set_locale(LanguageFixture.LOCALE)
    button.refresh()
    var multiply := button.popup.label_button(&"multiply").tooltip_text
    assert_true(multiply.contains("\nAnglicky: Multiply\n"), "Czech keeps its English line: %s" % multiply)
    button.free()
