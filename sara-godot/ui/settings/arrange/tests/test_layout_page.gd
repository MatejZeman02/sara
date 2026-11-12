## The layout pages: where the pinned rows go, and the one Layouts and dockers
## page the thirteen docker pages folded into.
##
## The reorder needs a pointer and a window, so it is proved by
## `scenarios/docker-layout-rows.json` against the running app rather than
## here. What is here is the case no capture can reach, a profile stored before
## either pinned element existed, and the fold: one page with a line per docker,
## an Elements… button on each and Options… on the dockers that have options,
## each opening its part in the page area with a Back row to the line. The
## running app's proof is
## `scenarios/the-thirteen-docker-pages-fold-into-one-layouts-and-dockers-page.json`.
extends "res://tests/test_framework.gd"

## A docker a module would declare at runtime, which has to get a line the way a
## built-in does.
const PROBE := "ProbeDocker"
const PROBE_TITLE := "Layouts Probe"

## An option of the probe's own, the way a docker registers one when it is
## built, so a line with Options… does not hang on which suites built a docker
## before this one.
const PROBE_OPTION := "probe_switch"


## The Toolbox's options are registered by the docker as it builds, which a
## running app has always done before Preferences opens, and a suite has not.
func before_each() -> void:
    SaToolBoxGrid.register_options()


func after_each() -> void:
    SaSettings.unregister_docker_option(PROBE, PROBE_OPTION)
    SaSettings.unregister_layout_category(PROBE)


## The probe docker, with an option of its own when *with_option* says so.
func _register_probe(elements: Array, with_option: bool = false) -> void:
    SaSettings.register_layout_category(PROBE, PROBE_TITLE, elements)
    if with_option:
        var spec := {"title": "Probe switch", "hint": "", "kind": SaSettingsLayout.OPTION_SWITCH, "default": false}
        SaSettings.register_docker_option(PROBE, PROBE_OPTION, spec)


# --- The pinned pair ---------------------------------------------------------


func test_pinned_elements_come_first() -> void:
    var hoisted := SaLayoutPage.pinned_first(["Layer List", "Blend Mode", "Drag Handle", "Resizer"])
    assert_eq(hoisted, ["Drag Handle", "Resizer", "Layer List", "Blend Mode"], "the pinned pair leads the list")


func test_pinned_order_is_handle_then_resizer() -> void:
    var hoisted := SaLayoutPage.pinned_first(["Resizer", "Layer List", "Drag Handle"])
    assert_eq(hoisted, ["Drag Handle", "Resizer", "Layer List"], "the handle is above the resizer, whatever was stored")


func test_the_rest_keeps_its_order() -> void:
    var hoisted := SaLayoutPage.pinned_first(["Swatches", "Drag Handle", "Hex Input", "Recent Colours"])
    assert_eq(hoisted, ["Drag Handle", "Swatches", "Hex Input", "Recent Colours"], "hoisting reorders nothing else")


func test_a_category_without_the_pair_is_untouched() -> void:
    var order := ["File", "Edit", "View"]
    assert_eq(SaLayoutPage.pinned_first(order), order, "the top bar has neither element, so nothing moves")


func test_the_default_orders_already_satisfy_the_rule() -> void:
    for category: String in SaSettings.DEFAULT_ORDERS:
        var order: Array = SaSettings.DEFAULT_ORDERS[category]
        assert_eq(SaLayoutPage.pinned_first(order), order, "%s ships with the pinned pair already first" % category)


# --- The sidebar ---------------------------------------------------------------


## "The sidebar lists no docker pages": Layouts and dockers is a page of its own
## under Interface, which holds what was Workspace, the top bar has no page and
## is a section of it, and no docker's title is a category, a
## module's docker included.
func test_the_sidebar_lists_layouts_and_dockers_and_no_docker() -> void:
    _register_probe(["Drag Handle", "Resizer"])
    var window := SaSettingsWindow.new()

    var at := window.categories.find(SaDockersPage.TITLE)
    assert_true(at != -1, "Layouts and dockers is in the sidebar")
    assert_eq(
        window.categories.find(SaSettingsWindow.INTERFACE_PAGE) + 1, at, "under Interface, which held the layouts before it"
    )
    assert_false(window.categories.has("Top Menu Bar"), "and the top bar has no page, it is a section of this one")
    # Recorder is the one docker title a page carries, the recorder's folder,
    # settle and cap, named for the docker because the Timelapse page and
    # the docker's own page of two elements are one.
    for entry: Dictionary in SaDockersPage.dockers():
        if entry["title"] == "Recorder":
            continue
        assert_false(window.categories.has(entry["title"]), "%s has no page in the sidebar" % entry["title"])
    assert_eq(window.categories, SaSettingsWindow.FIXED_PAGES, "and the sidebar is the ten and nothing else")
    window.free()


# --- One page, a line per docker ---------------------------------------------


## The Done clause: one page with a line per docker, each line an Elements…
## button and Options… where the docker registered options, and for the top bar,
## which is no docker, a line of its own in its section.
func test_the_page_carries_one_line_per_docker() -> void:
    _register_probe(["Drag Handle", "Resizer"], true)
    var page := SaDockersPage.new()

    var dockers := SaDockersPage.dockers()
    assert_true(dockers.size() >= 5, "the four const dockers and the probe are the floor")
    for entry: Dictionary in dockers:
        var category := String(entry["id"])
        var line := page.page.row(SaDockersPage.line_key(category))
        assert_not_null(line, "%s has a line" % category)
        if line == null:
            continue
        assert_eq(line.label, String(entry["title"]), "under the title its page had")
        assert_not_null(page.find_child("Elements_%s" % category, true, false), "%s's line has Elements…" % category)
        var options := page.find_child("Options_%s" % category, true, false)
        var has_options := not SaSettings.docker_options(category).is_empty()
        assert_eq(options != null, has_options, "%s has Options… exactly when it has options" % category)
    assert_not_null(page.page.row(SaDockersPage.line_key(SaDockersPage.TOP_BAR)), "the top bar's line is in its own section")
    assert_not_null(page.find_child("Elements_TopMenuBar", true, false), "with an Elements… button")
    assert_null(page.find_child("Options_TopMenuBar", true, false), "and no Options…")
    assert_not_null(page.page.row(SaDockersPage.line_key(PROBE)), "and a module's docker gets one the way a built-in does")
    assert_not_null(page.find_child("Options_%s" % PROBE, true, false), "with Options… for the option it registered")
    assert_not_null(page.find_child("Options_ToolBoxDocker", true, false), "the Toolbox's options are behind its line")
    assert_null(page.find_child("Options_LayersDocker", true, false), "and Layers, which has none, offers no Options…")
    page.free()


## The lines read down by the title a painter reads, not by the order the
## dockers registered in.
func test_the_lines_run_in_the_order_their_titles_read() -> void:
    var titles: Array[String] = []
    for entry: Dictionary in SaDockersPage.dockers():
        titles.append(String(entry["title"]))
    var sorted := titles.duplicate()
    sorted.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
    assert_eq(titles, sorted, "the lines are in the order of their titles")


## The shared rows and the layouts came off Workspace, so the search for any of
## them finds one page.
func test_the_layouts_and_the_shared_rows_leave_the_workspace_page() -> void:
    var workspace := SaWorkspacePage.new()
    var dockers := SaDockersPage.new()
    for key: StringName in [&"hide_button", &"maximise_button", &"borrow_dwell", &"borrow_distance"]:
        assert_null(workspace.page.row(key), "Workspace has no '%s' row" % key)
        assert_not_null(dockers.page.row(key), "and Layouts and dockers has it")
    assert_null(workspace.find_child("WorkspacePresetOpt", true, false), "Workspace has no layouts")
    assert_not_null(dockers.find_child("WorkspacePresetOpt", true, false), "Layouts and dockers has them")
    workspace.free()
    dockers.free()


## A line says what its docker has hidden, and nothing when every part is drawn.
func test_a_line_names_the_parts_its_docker_hides() -> void:
    _register_probe(["Drag Handle", "Resizer", "Probe Part"])
    var page := SaDockersPage.new()
    assert_eq(page.hidden_parts(PROBE), "", "every part drawn says nothing")
    SaSettings.set_element_visible(PROBE, "Probe Part", false)
    assert_eq(page.hidden_parts(PROBE), "Probe Part is hidden.", "one hidden part is named")
    SaSettings.set_element_visible(PROBE, "Resizer", false)
    assert_eq(page.hidden_parts(PROBE), "Resizer and Probe Part are hidden.", "and two in the list's order")
    for element: String in ["Resizer", "Probe Part"]:
        SaSettings.set_element_visible(PROBE, element, true)
    page.free()


# --- The two buttons -----------------------------------------------------------


## Elements… draws the docker's list in the page area under the docker's title,
## with Layouts and dockers still marked in the sidebar, and Back returns to the
## line, marked.
func test_elements_opens_the_list_and_back_lands_on_the_line() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    var at := window.categories.find(SaDockersPage.TITLE)

    assert_true(window.show_page(SaDockersPage.TITLE), "Layouts and dockers opens")
    var overview := _open_page(window) as SaDockersPage
    assert_not_null(overview, "and it is the dockers page")
    (overview.find_child("Elements_LayersDocker", true, false) as Button).pressed.emit()

    var list := _open_page(window) as SaLayoutPage
    assert_not_null(list, "Elements… puts a layout page in the page area")
    if list != null:
        assert_eq(list.category, "LayersDocker", "the Layers docker's")
        assert_eq(list.part, SaLayoutPage.ELEMENTS, "its element list")
        assert_not_null(list.row_for("Layer List"), "with the Layers docker's own parts in it")
        assert_eq(_page_title(window), "Layers", "under the docker's title")
        assert_eq(window.current, at, "and the sidebar still on Layouts and dockers")

        (list.find_child("BackToDockers", true, false) as Button).pressed.emit()
    assert_true(_open_page(window) is SaDockersPage, "Back is Layouts and dockers again")
    assert_eq(String(window.search.report()["highlighted_row"]), "Layers", "on the Layers line, marked")
    _close_window(opened)


## The top bar is a section of Layouts and dockers, with its
## Elements… button on a line of its own. The button draws the bar's list in the
## page area under the bar's title, with Layouts and dockers marked in the
## sidebar, the list carries no window button row, and Back lands on the bar's
## line, marked.
func test_the_top_bars_elements_open_its_list_and_back_lands_on_its_line() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    var at := window.categories.find(SaDockersPage.TITLE)

    window.show_page(SaDockersPage.TITLE)
    var overview := _open_page(window) as SaDockersPage
    assert_not_null(overview.find_child("WindowButtonPositionOpt", true, false), "the section holds the position row")
    assert_not_null(overview.find_child("WindowButtonStyleOpt", true, false), "and the style row")
    (overview.find_child("Elements_TopMenuBar", true, false) as Button).pressed.emit()

    var list := _open_page(window) as SaTopBarPage
    assert_not_null(list, "Elements… puts the bar's list page in the page area")
    if list != null:
        assert_not_null(list.row_for("File"), "with the bar's menus in it")
        assert_null(list.find_child("WindowButtonPositionOpt", true, false), "and no second window button row")
        assert_eq(_page_title(window), "Top Bar", "under the bar's title")
        assert_eq(window.current, at, "and the sidebar still on Layouts and dockers")
        (list.find_child("BackToDockers", true, false) as Button).pressed.emit()
    assert_true(_open_page(window) is SaDockersPage, "Back is Layouts and dockers again")
    assert_eq(String(window.search.report()["highlighted_row"]), "Top bar", "on the bar's line, marked")
    _close_window(opened)


## The old title lands on the bar's section and the words of the window buttons
## find Layouts and dockers, and nothing else.
func test_the_old_title_and_the_window_button_words_land_on_the_section() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    var at := window.categories.find(SaDockersPage.TITLE)

    assert_true(window.show_page("Top Menu Bar"), "the old title opens something")
    assert_eq(window.current, at, "Layouts and dockers")
    assert_true(_open_page(window) is SaDockersPage, "drawn as that page")
    assert_eq(String(window.search.report()["highlighted_row"]), "Window button position", "at the bar's section")
    window.search.apply("window button")
    var found := Array(window.search.report()["categories"])
    assert_eq(found, [SaDockersPage.TITLE], "the search for 'window button' finds that page alone")
    _close_window(opened)


## Options… draws the options alone, and the elements part draws none, so each
## button leads to one thing.
func test_options_opens_the_options_alone() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.show_page(SaDockersPage.TITLE)
    (_open_page(window).find_child("Options_ToolBoxDocker", true, false) as Button).pressed.emit()
    var options := _open_page(window) as SaLayoutPage
    assert_not_null(options, "Options… puts a layout page in the page area")
    if options != null:
        assert_eq(options.part, SaLayoutPage.OPTIONS, "the options part")
        assert_not_null(options.below_control("Orientation"), "holding the Toolbox's orientation")
        assert_null(options.row_for("Brush"), "and no element list")
        assert_eq(_page_title(window), "Toolbox", "under the docker's title")

    window.show_docker("ToolBoxDocker", SaLayoutPage.ELEMENTS)
    var elements := _open_page(window) as SaLayoutPage
    assert_true(elements != null and elements.below_control("Orientation") == null, "and the element list carries no option row")
    _close_window(opened)


## A door or a scenario written while a docker had a page names it by its title,
## and lands on its part: the list, or the options when the row it names is one.
func test_a_dockers_old_title_still_opens_its_part() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    assert_true(window.show_page("Colour Picker"), "the Colour Picker's title opens")
    var list := _open_page(window) as SaLayoutPage
    assert_true(list != null and list.part == SaLayoutPage.ELEMENTS, "its element list")
    assert_true(window.show_page("Toolbox", &"orientation"), "the Toolbox's title with an option's key opens")
    var options := _open_page(window) as SaLayoutPage
    assert_true(options != null and options.part == SaLayoutPage.OPTIONS, "its options")
    assert_eq(String(window.search.report()["highlighted_row"]), "Orientation", "on that row, marked")
    assert_false(window.show_page("No Such Docker"), "and a title that is nothing opens nothing")
    _close_window(opened)


# --- Helpers ---------------------------------------------------------------------


## The page the window has open: the last child of its content column.
func _open_page(window: SaSettingsWindow) -> Control:
    var content := window.content_container
    return content.get_child(content.get_child_count() - 1) as Control


## The title over the open page, the first child of the content column.
func _page_title(window: SaSettingsWindow) -> String:
    var label := window.content_container.get_child(0) as Label
    return label.text if label != null else ""


## A Preferences window in the tree, embedded, with a host to free it by, the
## recipe of `test_preferences_search.gd` and for its two reasons.
##
## The Back row and the landing on a line give the keyboard to a control, which
## only a window in the tree has, and only a run with a RenderingDevice has one,
## so a run without one skips those cases and says so.
func _open_window() -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null or RenderingServer.get_rendering_device() == null:
        skip("a run without a RenderingDevice has no window in the tree to open a page in")
        return []
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "TestHost"
    EventBus.add_child(host)
    var window := SaSettingsWindow.new()
    host.add_child(window)
    window.show()
    return [window, host, was_embedding]


func _close_window(opened: Array) -> void:
    if opened.is_empty():
        return
    var window := opened[0] as Window
    if is_instance_valid(window):
        window.hide()
    (opened[1] as Node).free()
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = bool(opened[2])
