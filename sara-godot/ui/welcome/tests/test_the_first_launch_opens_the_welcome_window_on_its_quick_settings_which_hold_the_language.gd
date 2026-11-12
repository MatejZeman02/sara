## The Quick settings pane holds the language, and a
## profile's first launch opens the welcome window on that pane.
##
## The window is built and never added to a tree, for the reason
## `test_welcome_window.gd` gives: a `Window` in a suite hangs the whole run.
## So the write that follows a show is asked of `remember_first_launch`, the
## call the window's own `_on_shown` makes, rather than of a real show.
extends "res://tests/test_framework.gd"

const LanguageFixture = preload("res://tests/fixtures/modules/language-fixture/module.gd")

var _saved_language: String = ""
var _saved_done: bool = false
var _saved_locale: String = ""


func before_each() -> void:
    _saved_language = SaSettings.ui_language
    _saved_done = SaSettings.first_launch_done
    _saved_locale = TranslationServer.get_locale()


## The running app's settings and locale, put back even after a failed assertion.
func after_each() -> void:
    SaSettings.ui_language = _saved_language
    SaSettings.first_launch_done = _saved_done
    TranslationServer.set_locale(_saved_locale)


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(Callable(), Callable())
    return registries


## The fixture's Czech registered the way the loader registers a module.
func _register_fixture(registries: SaRegistries) -> SaContext:
    var module: SaModule = LanguageFixture.new()
    var scoped := registries.context.for_module(module.get_id())
    module.context = scoped
    module.register(scoped)
    return scoped


## The first case: the pane's language row lists what the
## Languages page lists, for a registry holding the fixture's Czech, and a
## pick writes the one setting, which reaches `TranslationServer`.
func test_the_language_row_lists_the_pages_locales_and_a_pick_sets_the_locale() -> void:
    var registries := _registries()
    var scoped := _register_fixture(registries)
    var pane := WelcomeQuickSettingsPane.new()
    pane.follow_catalogues(registries.translations)
    var want: Array = []
    for entry: Dictionary in SaLanguagesPage.choices(registries.translations, SaSettings.ui_language):
        want.append(entry["id"])
    assert_eq(pane.language_opt.name, "LanguageOpt", "the Languages page's own name, so one capture step drives either")
    assert_eq(pane.language_opt.choice_values(), want, "the same locales as SaLanguagesPage.choices, in its order")
    assert_true(want.has(LanguageFixture.LOCALE), "the fixture's Czech among them")

    SaSettings.ui_language = SaSettingsValues.BRITISH
    pane.language_opt.select_value(SaSettingsValues.BRITISH)
    assert_true(pane.language_opt.pick_row(want.find(LanguageFixture.LOCALE)), "the Czech row takes the press")
    assert_eq(SaSettings.ui_language, LanguageFixture.LOCALE, "the pick writes SaSettings.ui_language")
    assert_eq(TranslationServer.get_locale(), LanguageFixture.LOCALE, "and the locale is set on TranslationServer at once")
    assert_eq(tr("Languages"), "Jazyky", "so the next tr() reads Czech")

    SaSettings.ui_language = SaSettingsValues.BRITISH
    scoped.remove_all_registrations()
    assert_false(pane.language_opt.choice_values().has(LanguageFixture.LOCALE), "a catalogue taken away leaves the row")
    pane.free()


## The pane is built again in the language it picked, so its words follow.
func test_the_panes_words_follow_the_language() -> void:
    var registries := _registries()
    var scoped := _register_fixture(registries)
    TranslationServer.set_locale(SaSettingsValues.BRITISH)
    var pane := WelcomeQuickSettingsPane.new()
    pane.follow_catalogues(registries.translations)
    var first := pane.language_opt
    TranslationServer.set_locale(LanguageFixture.LOCALE)
    pane.follow_language()
    assert_true(pane.language_opt != first, "the rows were built again")
    var titles: Array[String] = []
    for node in pane.find_children("*", "HBoxContainer", true, false):
        if node.has_meta(SaSettingsRows.ROW_META):
            titles.append(String(node.get_meta(SaSettingsRows.TITLE_META)))
    assert_eq(titles.size(), 9, "nine rows and not eighteen, the old ones gone")
    assert_eq(titles[1], "Jazyk", "and the language row's title reads in Czech")
    TranslationServer.set_locale(_saved_locale)
    scoped.remove_all_registrations()
    pane.free()


## The second clause: false in a fresh profile, true only once the window has
## shown the Quick settings pane, the first launch's window on that pane and
## any other on Recent, with `wanted_at_start`'s four answers unchanged.
func test_the_first_launch_boolean_and_the_tab_it_opens_on() -> void:
    var fresh := SaSettingsValues.new()
    assert_false(fresh.first_launch_done, "a fresh profile is a first launch")
    assert_eq(SaSettingsKeys.KEYS["first_launch_done"], ["ui", "first_launch_done"], "kept in the profile")
    fresh.free()

    SaSettings.first_launch_done = false
    var first := SaWelcomeWindow.new(true, true)
    assert_eq(first.tabs.get_current_tab_control(), first.quick_settings_pane, "the first launch opens on Quick settings")
    first.remember_first_launch(false)
    assert_false(SaSettings.first_launch_done, "not before the window is shown")
    first.remember_first_launch(true)
    assert_true(SaSettings.first_launch_done, "and true once it has been shown on the pane")
    first.free()

    SaSettings.first_launch_done = false
    var later := SaWelcomeWindow.new(true, false)
    assert_eq(later.tabs.get_current_tab_control(), later.recent_pane, "any other launch opens on Recent")
    later.remember_first_launch(true)
    assert_false(SaSettings.first_launch_done, "and a window shown on Recent never writes it")
    later.free()

    assert_false(SaWelcomeWindow.wanted_at_start(false, "", false, false), "the setting off still refuses")
    assert_false(SaWelcomeWindow.wanted_at_start(true, "", true, false), "a capture run still refuses")
    assert_false(SaWelcomeWindow.wanted_at_start(true, "", false, true), "a suite still refuses")
    assert_false(SaWelcomeWindow.wanted_at_start(true, "/tmp/asked-for.sad", false, false), "a named document still refuses")
    assert_true(SaWelcomeWindow.wanted_at_start(true, "", false, false), "and a plain start still opens it")
