## Preferences reads a catalogue's new words after Modules > Reload Modules
## brings it back edited.
##
## A reload that picks up an edited `.po` must not leave the list of pages
## down the left of Preferences with the old word. The registry's notice
## reaches the tree, so what is needed is the window's answer to it. The
## window writes its words translated and is built once, so the engine's own
## translation of a button's text took the old Czech word for a key and found
## nothing for it, and a window first opened in Czech kept the page list's,
## the group headings', the open page's and its own title's old words.
##
## The reload is done the way `ModuleLoader.reload_user_modules` does it: the
## module's context takes every registration away, the `.po` on disk is
## edited, and the module registers the same path again.
extends "res://tests/test_framework.gd"

## The module the catalogue is registered under.
const MODULE := &"t9-catalogue-fixture"

## The sentences the catalogue translates, each a word Preferences draws
## itself rather than a row of a page: the window's title, a page of the
## sidebar, a group heading and a page both, the button under the list, the
## search field's placeholder and the line a search that finds nothing shows.
const SENTENCES := [
    "Preferences",
    "Languages",
    "Interface",
    "Reset all preferences...",
    "Search settings",
    "Nothing matches",
]

## Where the catalogue is written. A plain `var`, never a `static var`, for
## the reason `test_structure_budget.gd` gives.
var scratch_po: String = SaDataRoot.path("test_catalogue.po")

## The case's module context, emptied after it. A registry the case drops is
## not freed at once, so its catalogue would stay installed, and the next
## case's `load` of the same path would be handed it from the cache.
var held: SaContext = null


func after_each() -> void:
    if held != null:
        held.remove_all_registrations()
        held = null
    TranslationServer.set_locale("en")
    if FileAccess.file_exists(scratch_po):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_po))


## The catalogue of Czech for *sentences*, each translated to its English with
## *mark* after it, so the old and the new word of one sentence differ.
func _write_po(sentences: Array, mark: String) -> void:
    var lines := PackedStringArray(
        [
            'msgid ""',
            'msgstr ""',
            '"Language: cs\\n"',
            '"Content-Type: text/plain; charset=UTF-8\\n"',
            '"Plural-Forms: nplurals=3; plural=(n==1) ? 0 : (n>=2 && n<=4) ? 1 : 2;\\n"',
        ]
    )
    for sentence: String in sentences:
        lines.append("")
        lines.append('msgid "%s"' % sentence)
        lines.append('msgstr "%s %s"' % [sentence, mark])
    var file := FileAccess.open(scratch_po, FileAccess.WRITE)
    file.store_string("\n".join(lines) + "\n")
    file.close()


## What a sentence reads as under the catalogue written with *mark*.
func _as(sentence: String, mark: String) -> String:
    return "%s %s" % [sentence, mark]


## A registry with the catalogue of *sentences* registered for the fixture
## module, Czech set, and the module's context, which the reload empties.
func _registered(registries: SaRegistries, sentences: Array) -> SaContext:
    _write_po(sentences, "old")
    var scoped := registries.context.for_module(MODULE)
    held = scoped
    assert_true(scoped.register_translation(scratch_po), "the catalogue registers from its file")
    assert_eq(TranslationServer.translate("Languages"), "Languages", "and English still reads English")
    TranslationServer.set_locale("cs")
    assert_eq(tr("Languages"), _as("Languages", "old"), "while Czech reads the file as written")
    return scoped


## Modules > Reload Modules for one module: put down, its `.po` edited on
## disk, and registered again from the same path.
func _reload(scoped: SaContext, sentences: Array) -> void:
    scoped.remove_all_registrations()
    _write_po(sentences, "new")
    assert_true(scoped.register_translation(scratch_po), "the edited catalogue registers again")
    assert_eq(tr("Languages"), _as("Languages", "new"), "and tr() reads the edited file, not a cached one")


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(Callable(), Callable())
    return registries


## A window over a registry of its own, in the tree and embedded, the way
## `test_the_preferences_sidebar_hears_a_module_come_and_go.gd` opens one.
func _open(registries: SaRegistries) -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "SettingsTestHost"
    EventBus.add_child(host)
    var window := SaSettingsWindow.new(SaUIRegistry.new())
    window.translations_registry = registries.translations
    host.add_child(window)
    return [window, host, was_embedding]


func _close(opened: Array) -> void:
    (opened[1] as Node).free()
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = opened[2]


func _button(window: SaSettingsWindow, page_title: String) -> Button:
    return window.category_buttons[window.categories.find(page_title)]


func _page_title(window: SaSettingsWindow) -> String:
    return (window.content_container.get_node(^"PageTitle") as Label).text


func _bar_title(window: SaSettingsWindow) -> String:
    return (window.drag_handle.find_child("TitleLabel", true, false) as Label).text


func _nothing_title(window: SaSettingsWindow) -> String:
    return (window.nothing_matches.get_node(^"NothingMatchesTitle") as Label).text


## Every word of `SENTENCES` the window draws, read as *mark*'s catalogue
## writes it, *when* saying at which point of the case.
func _reads(window: SaSettingsWindow, mark: String, when: String) -> void:
    assert_eq(_button(window, "Languages").text, _as("Languages", mark), "%s the page list's Languages reads %s" % [when, mark])
    assert_eq(_button(window, "Interface").text, _as("Interface", mark), "%s so does its Interface" % when)
    assert_eq(window.group_headings[&"interface"].text, _as("Interface", mark), "%s and the group heading over it" % when)
    assert_eq(_bar_title(window), _as("Preferences", mark), "%s the window's title bar" % when)
    assert_eq(window.title, _as("Preferences", mark), "%s and its title" % when)
    assert_eq(window.reset_button.text, _as("Reset all preferences...", mark), "%s the button under the list" % when)
    assert_eq(window.search.field.placeholder_text, _as("Search settings", mark), "%s the search field" % when)
    assert_eq(_nothing_title(window), _as("Nothing matches", mark), "%s and the line a search that finds nothing shows" % when)


## The first case: the catalogue registered, Preferences built
## with it in use and open on a page whose title it translates, the catalogue
## reloaded with its entries changed, and the page list read in the new words,
## with the open page's title and every other word the window writes itself.
func test_an_open_preferences_reads_the_reloaded_catalogues_new_words() -> void:
    var registries := _registries()
    var scoped := _registered(registries, SENTENCES)
    var opened := _open(registries)
    var window := opened[0] as SaSettingsWindow
    assert_true(window.show_page("Languages"), "Languages opens")
    _reads(window, "old", "built in Czech,")
    assert_eq(_page_title(window), _as("Languages", "old"), "and the open page's title reads the old word")

    _reload(scoped, SENTENCES)
    _reads(window, "new", "after the reload,")
    assert_eq(_page_title(window), _as("Languages", "new"), "the open page's title reads the new word")
    assert_eq(window.categories[window.current], "Languages", "and the open page is still Languages")
    assert_true(_button(window, "Languages").flat == false, "with its button still the one marked")
    _close(opened)


## The window is built on the first request for it and kept in the tree,
## hidden while closed, so the window a later opening shows is the one the
## reload found closed, and its words have to follow while it is hidden.
func test_a_closed_preferences_opened_after_the_reload_reads_the_new_words() -> void:
    var registries := _registries()
    var scoped := _registered(registries, SENTENCES)
    var opened := _open(registries)
    var window := opened[0] as SaSettingsWindow
    assert_false(window.visible, "the window is built closed")
    _reload(scoped, SENTENCES)
    _reads(window, "new", "hidden through the reload,")
    _close(opened)


## The page on screen is drawn again by the request that drew it, so a
## docker's part stays a docker's part, under its title in the new word,
## rather than falling back to the sidebar's Layouts and dockers.
func test_a_dockers_part_stays_open_under_its_new_title() -> void:
    var docker: Dictionary = SaDockersPage.dockers()[0]
    var docker_title := String(docker["title"])
    var sentences := SENTENCES + [docker_title]
    var registries := _registries()
    var scoped := _registered(registries, sentences)
    var opened := _open(registries)
    var window := opened[0] as SaSettingsWindow
    assert_true(window.show_docker(String(docker["id"]), SaLayoutPage.OPTIONS), "the docker's options open")
    assert_eq(_page_title(window), _as(docker_title, "old"), "under the docker's title in the old word")

    _reload(scoped, sentences)
    assert_eq(_page_title(window), _as(docker_title, "new"), "after the reload under its title in the new word")
    assert_eq(window.categories[window.current], SaDockersPage.TITLE, "with Layouts and dockers still marked")
    _close(opened)


## Under English a reload of a Czech catalogue changes no word, and the
## window builds nothing again: the registry tells the tree only when the
## catalogue is the locale's in use.
func test_under_english_a_reload_leaves_every_word_english() -> void:
    var registries := _registries()
    var scoped := _registered(registries, SENTENCES)
    TranslationServer.set_locale("en")
    var opened := _open(registries)
    var window := opened[0] as SaSettingsWindow
    var list := window.menu_list
    scoped.remove_all_registrations()
    _write_po(SENTENCES, "new")
    scoped.register_translation(scratch_po)
    assert_eq(_button(window, "Languages").text, "Languages", "the page list reads English")
    assert_eq(window.title, "Preferences", "and so does the title")
    assert_true(window.menu_list == list, "and the sidebar was not built again")
    _close(opened)
