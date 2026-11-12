## The search field over the Preferences category list.
##
## Three things are pinned here as numbers: the
## list narrows to the pages holding the word, opening one marks and focuses the
## first matching row, and clearing puts every category back. A screenshot of a
## shorter list cannot say what it was shorter than.
##
## The words a painter types, 29 into the box, must find the page and row
## each one means, not nothing or the wrong page. Each is read here landing where Enter takes it.
extends "res://tests/test_framework.gd"

## It opens a real window, and only a run with a RenderingDevice has one.
const REQUIRES_GPU := true

## A word no page carries, so the empty result is a result and not a typo.
const NO_SUCH_WORD := "quokka"

## `{typed: [the page Enter opens, the rows it may mark there]}`. No rows is a
## page found by its own title, which has nothing to mark.
##
## The top bar's words land on its line in the top bar's section of Layouts and
## dockers, whose Elements… button leads to the list that carries the brush's own
## Smoothing and Stabilizer elements and the Stabilizer Toggle button. The
## bar's list is behind that line, which says the words of every part behind it.
const LANDINGS := {
    "tablet": ["Pen and tablet", []],
    "performance": ["Performance", []],
    "hide": ["Layouts and dockers", ["Hide button"]],
    "close": ["Layouts and dockers", ["Hide button"]],
    "backup": ["Files", ["Previous versions kept"]],
    "hdr": ["Canvas and colour", ["View transform"]],
    "colour management": ["Canvas and colour", ["Display profile"]],
    "color management": ["Canvas and colour", ["Display profile"]],
    "dark mode": [SaSettingsWindow.INTERFACE_PAGE, ["Colour theme"]],
    "brush size": ["Keyboard shortcuts", ["Larger brush"]],
    "smoothing": ["Layouts and dockers", ["Top bar"]],
    "stabiliser": ["Layouts and dockers", ["Top bar"]],
    "stabilizer": ["Layouts and dockers", ["Top bar"]],
}


## A Preferences window in the tree, embedded, with a host to free it by.
##
## Copied from `test_settings_window_frame.gd`, including both of its reasons:
## without the embedding `add_child` maps a real OS window and the run blocks
## until the watchdog, and the parent is an autoload because a node mid-`_ready`
## rejects `add_child` and leaves the child orphaned.
func _open_window() -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return []
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true

    var host := Node.new()
    host.name = "PreferencesSearchTestHost"
    EventBus.add_child(host)

    var window := SaSettingsWindow.new()
    host.add_child(window)
    window.show()
    return [window, host, was_embedding]


## Freed here and now rather than queued, for the reason the frame suite gives:
## a Window is its parent's exclusive child until it is gone.
func _close_window(opened: Array) -> void:
    if opened.is_empty():
        return
    var window := opened[0] as Window
    if is_instance_valid(window):
        window.hide()
    var host := opened[1] as Node
    host.free()
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = bool(opened[2])


## The page buttons left showing, read from `category_buttons` because the
## list holds a heading per group as well.
func _shown_categories(window: SaSettingsWindow) -> int:
    var shown := 0
    for btn: Button in window.category_buttons:
        if btn.visible:
            shown += 1
    return shown


func test_a_word_on_one_page_narrows_the_list_to_it() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    var all_of_them := _shown_categories(window)
    assert_true(all_of_them > 8, "Every category shows before a search")

    window.search.apply("gamut")
    var narrowed := _shown_categories(window)
    assert_true(narrowed > 0, "A word Preferences carries leaves something showing")
    assert_true(narrowed < all_of_them, "and fewer categories than the list had")

    var report: Dictionary = window.search.report()
    assert_eq(int(report["categories_in_all"]), all_of_them, "The report counts what the list held")
    assert_eq(PackedStringArray(report["categories"]).size(), narrowed, "and what is left of it")

    _close_window(opened)


## The word follows the row it describes. "gamut" leaves Colour Spaces in the
## list and leaves Display instead once the mapping row moved, because the index is built from what a page's rows say.
##
## Display is Canvas and colour, and Colour Spaces is not a
## page of Preferences at all, its browser having gone to Help.
func test_the_gamut_mapping_row_is_found_on_canvas_and_colour() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.search.apply("gamut")
    var pages := PackedStringArray(window.search.report()["categories"])
    assert_true(pages.has("Canvas and colour"), "Canvas and colour carries the word and is left showing")
    assert_false(window.categories.has("Colour Spaces"), "and Colour Spaces is no page to leave")

    _close_window(opened)


## "Nothing on screen says the search found nothing rather than broke".
## The list empties, and the page area says so in place of the page that was
## open, which comes back once the field is cleared.
func test_a_word_nobody_carries_says_nothing_matches() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.search.apply(NO_SUCH_WORD)
    assert_eq(_shown_categories(window), 0, "'no results' is an answer and 'all of them' is not")
    assert_true(window.nothing_matches.visible, "The page area says nothing matched")
    assert_eq((window.nothing_matches.get_node(^"NothingMatchesTitle") as Label).text, "Nothing matches", "in those words")
    assert_false(window.content_container.visible, "and the page that was open is not left beside it")
    assert_false(window._nothing_why.visible, "A word Sara knows nothing of gets no reason under it")

    window.search.apply("")
    assert_false(window.nothing_matches.visible, "Clearing the field takes the line away")
    assert_true(window.content_container.visible, "and puts the page back")

    _close_window(opened)


## "language" finds the Languages page, and so does each word the line
## answered.
func test_language_finds_the_languages_page() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    for word: String in ["language", "english", "translation"]:
        window.search.apply(word)
        assert_false(window.nothing_matches.visible, "'%s' matches a page" % word)
        assert_eq(window.search.first_page(), SaLanguagesPage.TITLE, "and it is Languages")

    _close_window(opened)


## A page opened while the search matches nothing is shown, since opening it
## is what the painter asked for. A door to a page is the way that happens.
func test_a_page_opened_over_nothing_matches_is_shown() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.search.apply(NO_SUCH_WORD)
    assert_true(window.show_page("Canvas and colour"), "Canvas and colour opens")
    assert_true(window.content_container.visible, "and is on screen")
    assert_false(window.nothing_matches.visible, "with no line over it")

    _close_window(opened)


## Each of a painter's words, typed and entered, lands on the page and the row it
## means.
func test_a_painters_words_land_on_their_rows() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    for typed: String in LANDINGS:
        var want: Array = LANDINGS[typed]
        window.search.apply(typed)
        window.search.field.text_submitted.emit(window.search.field.text)
        var report: Dictionary = window.search.report()
        assert_eq(String(report["open_page"]), String(want[0]), "'%s' opens %s" % [typed, want[0]])
        var rows: Array = want[1]
        if not rows.is_empty():
            var marked := String(report["highlighted_row"])
            assert_true(rows.has(marked), "'%s' marks one of %s, and marked '%s'" % [typed, rows, marked])

    _close_window(opened)


## "size" alone reaches the brush size chords as well, among the pages whose
## rows say size. Read as a landing "size" finds rather than as the row
## marked, because a full run's modules register Image Canvas Size above it.
func test_size_reaches_the_brush_size_chords() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.search.apply("size")
    assert_true(PackedStringArray(window.search.report()["categories"]).has("Keyboard shortcuts"), "Keyboard shortcuts is left")
    assert_true(window.show_page("Keyboard shortcuts"), "and opens")
    var found := false
    for landing: Control in SaSettingsSearch.landings(window.content_scroll):
        if SaSettingsSearch.landing_title(landing) == "Larger brush":
            found = SaSettingsSearch.matches(SaSettingsSearch.haystack(landing), "size")
    assert_true(found, "and 'size' finds its Larger brush chord")

    _close_window(opened)


## "pen" left nine pages by the "pen" inside "open", "happens", "expensive"
## and "OpenRaster". A word matches where a word starts.
func test_a_word_matches_where_a_word_starts() -> void:
    assert_false(SaSettingsSearch.matches("open happens expensive openraster", "pen"), "pen inside a word is not pen")
    assert_true(SaSettingsSearch.matches("the pen's buttons", "pen"), "pen as a word is")
    assert_true(SaSettingsSearch.matches("the tablet driver", "tab"), "a word's start finds it while it is typed")
    assert_true(SaSettingsSearch.matches("drag-and-drop", "drop"), "after a hyphen is a word's start")

    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    # Brushes is not among them. Once the brush module has registered its
    # presets, its slots offer Pencil and Inked Pen, where "pen" starts a word.
    # Nor is Keyboard shortcuts, whose Gestures rows turn the view
    # "with the pen or the left button", nor Interface, whose Pen
    # pressure line is the door to Pen and tablet.
    window.search.apply("pen")
    var pages := PackedStringArray(window.search.report()["categories"])
    for page: String in ["Files", "Canvas and colour"]:
        assert_false(pages.has(page), "'pen' leaves %s out, which matched it only inside a word" % page)
    assert_true(pages.has("Pen and tablet"), "and keeps Pen and tablet, whose rows are the pen's")
    assert_true(pages.has(SaSettingsWindow.INTERFACE_PAGE), "and Interface, whose Calibrate the pen… opens it")

    _close_window(opened)


## A section heading is found when no row under it says the word, and is the
## landing marked.
func test_a_section_heading_is_found_and_marked() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.search.apply("starting")
    # General is a part of Interface.
    var interface := SaSettingsWindow.INTERFACE_PAGE
    assert_true(PackedStringArray(window.search.report()["categories"]).has(interface), "General's Starting section is found")
    assert_true(window.show_page(interface), "Interface opens")
    assert_eq(String(window.search.report()["highlighted_row"]), "Starting", "and its heading is marked")

    _close_window(opened)


## Every word the search adds for a painter is keyed by a title a page draws,
## so a row retitled under its key fails here rather than going unfound.
func test_every_painters_word_names_a_title_a_page_draws() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    var drawn := PackedStringArray()
    for category: String in window.categories:
        var page := window.build_page(category)
        if page == null:
            continue
        for landing: Control in SaSettingsSearch.landings(page):
            drawn.append(SaSettingsSearch.landing_title(landing))
        page.free()
    for title: String in SaSettingsSearch.PAINTER_WORDS:
        assert_true(drawn.has(title), "'%s' is a title some page draws" % title)

    _close_window(opened)


func test_clearing_the_field_puts_every_category_back() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    var all_of_them := _shown_categories(window)
    window.search.apply("gamut")
    assert_true(_shown_categories(window) < all_of_them, "The list narrowed")
    window.search.apply("")
    assert_eq(_shown_categories(window), all_of_them, "and clearing brings the whole list back")

    var report: Dictionary = window.search.report()
    assert_eq(String(report["highlighted_row"]), "", "with nothing left marked")

    _close_window(opened)


## What a narrowed list does not answer: opening a page highlights and focuses
## the first matching row.
func test_opening_a_matching_page_marks_its_first_matching_row() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.search.apply("gamut")
    var report: Dictionary = window.search.report()
    var pages := PackedStringArray(report["categories"])
    assert_true(pages.size() > 0, "There is a page to open")

    assert_true(window.show_page(pages[0]), "The first page the search left opens")
    report = window.search.report()
    assert_eq(String(report["open_page"]), pages[0], "It is the open page")
    assert_true(not String(report["highlighted_row"]).is_empty(), "and one of its rows is marked")

    # The mirror: a page the search left out has nothing to mark, so the
    # highlight follows the search rather than being put on the first row of
    # whatever is open.
    var missing := ""
    for category: String in window.FIXED_PAGES:
        if not pages.has(category):
            missing = category
            break
    if not missing.is_empty():
        assert_true(window.show_page(missing), "A page the search left out still opens")
        report = window.search.report()
        assert_eq(String(report["highlighted_row"]), "", "and carries no mark, holding no match")

    _close_window(opened)


## The index is every page built once and thrown away, so a page that cannot be
## built off the tree would leave a category that can never be found.
func test_every_category_is_indexed() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.search.apply(NO_SUCH_WORD)
    var report: Dictionary = window.search.report()
    assert_eq(int(report["indexed"]), int(report["categories_in_all"]), "Every category is in the index")

    _close_window(opened)


## Enter jumps to the first page the search left, the way a click on its
## button would: the search owns the field and asks the window through
## `page_wanted` rather than the window reaching into the field for the key.
func test_enter_opens_the_first_page_the_search_left() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.search.apply("gamut")
    var pages := PackedStringArray(window.search.report()["categories"])
    assert_true(pages.size() > 0, "There is a page for Enter to reach")

    window.search.field.text_submitted.emit(window.search.field.text)
    assert_eq(String(window.search.report()["open_page"]), pages[0], "Enter opened the first page the search left")

    _close_window(opened)
