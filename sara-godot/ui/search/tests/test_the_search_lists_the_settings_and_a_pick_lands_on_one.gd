## The search lists the settings Preferences' own search finds,
## and a pick opens Preferences on the page with the setting's row marked.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The search works for settings items too. Here the list
## is read from a registry with the built-in pages, and a pick is Enter in the
## field. The rows are built ahead of an opening, so the
## suite builds them first. What a painter sees is
## `scenarios/the-search-lists-the-settings-too-and-opens-preferences-on-the-one.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")


## The settings rows are listed as settings, each with its page, and found by a
## word of the Preferences search, the painter's word "backup" included.
func test_the_settings_are_listed_with_their_pages() -> void:
    var built := _build()
    var window: SaSearchWindow = built["window"]
    window.open()
    var settings := 0
    for entry: SaSearchIndex.Entry in window.entries:
        if entry.kind == SaSearchIndex.SETTING:
            settings += 1
    print("The search lists %d settings of %d rows" % [settings, window.entries.size()])
    assert_true(settings > 100, "Preferences' places are rows of the list")

    _type(window, "display profile")
    var marked := window.shown[window.marked_at]
    assert_eq(marked.title, "Display profile", "Display profile is the row marked")
    assert_eq(marked.kind, SaSearchIndex.SETTING, "and it says it is a setting")
    assert_eq(marked.place, "Canvas and colour", "on its page")

    _type(window, "backup")
    var found: Array[String] = []
    for entry: SaSearchIndex.Entry in window.shown:
        found.append("%s on %s" % [entry.title, entry.place])
    assert_true(found.has("Previous versions kept on Files"), "backup finds Previous versions kept, got %s" % [found])
    _tear_down(built)


## A chord row of Keyboard shortcuts is the command found twice, so it is left
## out, and a row the page has of its own is listed.
func test_a_chord_row_is_not_listed_twice() -> void:
    var built := _build()
    var window: SaSearchWindow = built["window"]
    window.open()
    var chords := 0
    var own := 0
    for entry: SaSearchIndex.Entry in window.entries:
        if entry.kind == SaSearchIndex.SETTING and entry.place == SaSettingsWindow.FIXED_PAGES[2]:
            own += 1
        if entry.title == "Flip view horizontally":
            chords += 1
    assert_eq(chords, 1, "Flip view horizontally is one row, the command")
    assert_true(own > 0, "while the page's own rows are listed")
    _tear_down(built)


## A pick asks Preferences' door for the page and the row's title and closes.
func test_a_pick_asks_preferences_for_the_page_and_the_title() -> void:
    var built := _build()
    var window: SaSearchWindow = built["window"]
    var asked: Array = []
    var listen := func(page: String, row: StringName) -> void: asked.append([page, String(row)])
    # The runner passes no frame between suites, so a request an earlier suite
    # deferred, an Alt double click on a docker's grip for one, is still waiting
    # and would reach this listener in the frame below. One frame first
    # sends those out.
    await (Engine.get_main_loop() as SceneTree).process_frame
    EventBus.settings_row_requested.connect(listen)
    window.open()
    _type(window, "display profile")
    window.field.text_submitted.emit(window.field.text)
    await (Engine.get_main_loop() as SceneTree).process_frame
    EventBus.settings_row_requested.disconnect(listen)
    assert_eq(asked, [["Canvas and colour", "Display profile"]], "the door is asked for the page and the title")
    assert_false(window.visible, "and the window closes")
    _tear_down(built)


## The landing by title marks the row on its page, as a key's landing does.
func test_the_landing_by_title_marks_the_row() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var preferences := SaSettingsWindow.new()
    EventBus.add_child(preferences)
    assert_true(preferences.show_page("Canvas and colour", &"Display profile"), "the page opens")
    var state := preferences.search.report()
    assert_eq(state["open_page"], "Canvas and colour", "on its page")
    assert_eq(state["highlighted_row"], "Display profile", "with the row marked by its title")
    preferences.free()
    tree.root.gui_embed_subwindows = embedded


## The catalogue is never built by an opening: before it is warmed the list
## has no setting and says the rows are stale, and once warmed a second opening
## reads the same rows, kept on the index, without building a page again.
func test_the_catalogue_is_built_out_of_sight_and_kept() -> void:
    var built := _build(false)
    var window: SaSearchWindow = built["window"]
    assert_true(window.index.settings_stale(), "Nothing is built before the warm")
    var t0 := Time.get_ticks_usec()
    window.open()
    var t1 := Time.get_ticks_usec()
    var settings := 0
    for entry: SaSearchIndex.Entry in window.entries:
        if entry.kind == SaSearchIndex.SETTING:
            settings += 1
    assert_eq(settings, 0, "and the opening builds none")
    window.hide()
    var pages := 0
    while not window.index.warm_page() and pages < 10000:
        pages += 1
    assert_true(pages < 10000, "The warm ends within ten thousand pages")
    var t2 := Time.get_ticks_usec()
    var kept: Array[SaSearchIndex.Entry] = window.index._settings.duplicate()
    assert_true(pages > 5, "The warm builds a page a call, %d calls" % pages)
    assert_false(window.index.settings_stale(), "and then the rows are those of the pages there are")
    window.open()
    var t3 := Time.get_ticks_usec()
    print(
        (
            "The opening takes %d ms, the warm %d ms and an opening after it %d ms"
            % [int((t1 - t0) / 1000.0), int((t2 - t1) / 1000.0), int((t3 - t2) / 1000.0)]
        )
    )
    assert_eq(window.index._settings, kept, "the opening after it reads the same setting rows")
    assert_true(window.index._settings.size() > 100, "the catalogue is kept on the index")
    _tear_down(built)


func _type(window: SaSearchWindow, text: String) -> void:
    window.field.text = text
    window.field.text_changed.emit(text)


## The search over the application's commands, its settings' rows built
## unless *warmed* is false.
func _build(warmed: bool = true) -> Dictionary:
    var tree := Engine.get_main_loop() as SceneTree
    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "F2SearchHost"
    EventBus.add_child(host)
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_id: StringName) -> void: pass, Callable())
    var window := SaSearchWindow.new(SaSearchIndex.new(registries.context))
    host.add_child(window)
    if warmed:
        window.index.warm()
    return {"tree": tree, "embedded": embedded, "host": host, "window": window}


func _tear_down(built: Dictionary) -> void:
    (built["host"] as Node).free()
    (built["tree"] as SceneTree).root.gui_embed_subwindows = bool(built["embedded"])
