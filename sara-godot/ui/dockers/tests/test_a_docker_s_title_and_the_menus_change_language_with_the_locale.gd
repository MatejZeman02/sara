## A docker's title, the top bar's menu names and the toolbox's tooltips change
## language with the locale.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The debt: "a docker title set once in `_ready`" is not translated again. A run that switched from English to another
## language already showed most of it in that language, because a label holding
## an English key is translated by the engine on every change. What stayed was a
## run begun in another language: the menu names were written through `tr()`
## while the bar was built, so a switch to English left them as they were, and a
## catalogue registered after the dockers were built reached no docker, since
## the engine announces a change of locale and not a translation added. The
## fixture under `tests/fixtures/modules/language-fixture/` is the language,
## Czech. The running app's proof is
## `scenarios/docker-titles-and-the-menus-change-language-with-the-locale.json`.
extends "res://tests/test_framework.gd"

## Real windows go in the tree.
const REQUIRES_GPU := true

const LanguageFixture = preload("res://tests/fixtures/modules/language-fixture/module.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")

var _host: Control = null
var _was_embedding: bool = false
var _locale: String = ""


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _locale = TranslationServer.get_locale()
    TranslationServer.set_locale("en")
    _host = Control.new()
    _host.name = "T3LanguageHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
    _host = null
    TranslationServer.set_locale(_locale)
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


## The fixture module registered into registries of its own, the way the
## loader does it, with the context its unload empties again.
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


## The Undo History docker, a docker Sara ships, in the tree.
func _undo_docker() -> UndoDocker:
    var docker := UndoDocker.new()
    _host.add_child(docker)
    return docker


## The words the docker's drag bar shows.
func _title_of(docker: DockerWindow) -> String:
    var words := docker.drag_handle.find_child("TitleLabel", true, false) as Label
    return words.text if words != null else ""


## The first case: a docker built with the fixture's catalogue
## installed reads its title in Czech once the locale switches, and in English
## once it switches back. The window's own `title` stays the English, the key.
func test_a_docker_s_title_reads_in_the_fixture_s_language_and_back_in_english() -> void:
    var registries := _registries()
    _register_fixture(registries)
    var docker := _undo_docker()
    assert_eq(_title_of(docker), "Undo History", "built in English, the title is English")

    TranslationServer.set_locale(LanguageFixture.LOCALE)
    assert_eq(_title_of(docker), "Historie kroků", "a switch to Czech reads it in Czech")
    assert_eq(docker.title, "Undo History", "while the window keeps the English as its key")

    TranslationServer.set_locale("en")
    assert_eq(_title_of(docker), "Undo History", "and the switch back reads it in English")


## A docker built while the locale was Czech, as every docker of a run begun in
## Czech is, reads English after the switch. Its title was the translated
## words once, and a label holding those has no English to go back to.
func test_a_docker_built_in_czech_reads_english_after_the_switch() -> void:
    var registries := _registries()
    _register_fixture(registries)
    TranslationServer.set_locale(LanguageFixture.LOCALE)
    var docker := _undo_docker()
    assert_eq(_title_of(docker), "Historie kroků", "built in Czech, the title is Czech")

    TranslationServer.set_locale("en")
    assert_eq(_title_of(docker), "Undo History", "and the switch to English reads it in English")


## A run begun in Czech sets the locale before any module has registered the
## catalogue, so every docker is built in English. The catalogue arriving is
## what has to reach them, and its module unloading takes the Czech away again.
func test_a_catalogue_registered_after_the_docker_is_built_reaches_its_title() -> void:
    TranslationServer.set_locale(LanguageFixture.LOCALE)
    var docker := _undo_docker()
    assert_eq(_title_of(docker), "Undo History", "with no catalogue yet, the title is English")

    var registries := _registries()
    var scoped := _register_fixture(registries)
    assert_eq(_title_of(docker), "Historie kroků", "the catalogue arriving reads it in Czech at once")

    scoped.remove_all_registrations()
    assert_eq(_title_of(docker), "Undo History", "and its module unloading reads it in English again")


## The top bar's menu names, both ways and from a bar built in Czech, which is
## the case that failed: the titles were Czech words with no key behind them.
func test_the_menu_names_follow_the_locale_from_a_bar_built_in_czech() -> void:
    var registries := _registries()
    _register_fixture(registries)
    TranslationServer.set_locale(LanguageFixture.LOCALE)
    var bar := TopMenuBar.new()
    _host.add_child(bar)
    var file_title: Button = bar.menu_buttons["File"]
    var window_title: Button = bar.menu_buttons["Window"]
    assert_eq(file_title.text, "Soubor", "a bar built in Czech names File in Czech")

    TranslationServer.set_locale("en")
    assert_eq(file_title.text, "File", "the switch to English names it in English")
    assert_eq(window_title.text, "Window", "and Window with it")

    TranslationServer.set_locale(LanguageFixture.LOCALE)
    assert_eq(window_title.text, "Okno", "and a switch back reads Czech again")


## The toolbox says its own name on hover, its bar having room for the wrench
## alone, and each button the names of its tools. Both are read in the locale
## set now. A button's tooltip is composed again when the pointer arrives, so
## the report's line, which is what that hover composes, is the one read.
func test_the_toolbox_s_tooltips_follow_the_locale() -> void:
    var registries := _registries()
    _register_fixture(registries)
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    _host.add_child(docker)
    assert_eq(docker.drag_handle.tooltip_text, "Toolbox", "in English the bar says Toolbox")

    TranslationServer.set_locale(LanguageFixture.LOCALE)
    assert_eq(docker.drag_handle.tooltip_text, "Panel nástrojů", "and in Czech its Czech name")
    var fills := _tooltip_of(docker, "fill")
    assert_true(fills.begins_with("Výplň"), "the fills' button names the Fill in Czech: %s" % fills)
    assert_true(fills.contains("Přechod"), "and the Gradient behind it: %s" % fills)

    TranslationServer.set_locale("en")
    assert_eq(docker.drag_handle.tooltip_text, "Toolbox", "the switch back says Toolbox again")
    assert_true(_tooltip_of(docker, "fill").begins_with("Fill"), "and the fills' button names the Fill")


## What the toolbox's button for *category* says on hover, from its report.
func _tooltip_of(docker: ToolBoxDocker, category: String) -> String:
    for entry: Dictionary in docker.toolbox_report().get("buttons", []):
        if entry.get("category", "") == category:
            return String(entry["tooltip"])
    return ""
