## The first page Preferences opens holds what a painter changes
## in their first sessions, the most used first, and the settings folder is at
## the foot of Files, not the first thing the window shows.
##
## The rows are read by their keys, because the two sliders carry their value
## in their titles, and each setting is looked for on every page by what its
## row writes, so a row that moved and left a copy behind fails here.
extends "res://tests/test_framework.gd"

## The first page's rows, in the order `SaGeneralPage` gives the reason for.
const FIRST_ROWS: Array[StringName] = [
    &"coming_from",
    &"ui_scale",
    &"font_size",
    &"interface_font",
    &"theme",
    &"calibrate_pen",
    &"history_depth",
    &"visibility_in_history",
    &"advanced",
    &"experimental_tools",
    &"welcome_at_start",
    &"show_last_session",
]

## The first page's custom rows, which hold their own value and so name no
## binding: each is looked for by its key on every other page.
const OWN_VALUE_ROWS: Array[StringName] = [&"coming_from", &"ui_scale", &"font_size", &"theme", &"advanced"]

var _saved_ceiling: float = SaTablet.DEFAULT_MAX_PRESSURE


func before_each() -> void:
    _saved_ceiling = SaSettings.tablet_max_pressure
    # A fresh profile's pen, which nobody has calibrated.
    SaSettings.tablet_max_pressure = SaTablet.DEFAULT_MAX_PRESSURE


func after_each() -> void:
    SaSettings.tablet_max_pressure = _saved_ceiling


## A Preferences window in the tree, embedded, with a host to free it by, the
## way `test_preferences_search.gd` opens one: a row a door lands on takes the
## keyboard, and a control outside the tree cannot.
func _open_window() -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "FirstPreferencesPageTestHost"
    EventBus.add_child(host)
    var window := SaSettingsWindow.new()
    host.add_child(window)
    window.show()
    return [window, host, was_embedding]


func _close_window(opened: Array) -> void:
    (opened[0] as Window).hide()
    (opened[1] as Node).free()
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = bool(opened[2])


## The page *window* has open, the last child of its content column after the
## title.
func _open_page(window: SaSettingsWindow) -> Control:
    return window.content_container.get_child(window.content_container.get_child_count() - 1) as Control


## Every declared page drawn under *root*, in the order a painter reads them,
## so the Interface page's three parts come back as three.
func _declared(root: Node) -> Array[SaSettingsPage]:
    var out: Array[SaSettingsPage] = []
    if root is SaSettingsPage:
        out.append(root as SaSettingsPage)
    for child: Node in root.get_children():
        out.append_array(_declared(child))
    return out


## The rows of the page *window* has open, top to bottom.
func _rows_open(window: SaSettingsWindow) -> Array[SaPageRow]:
    var rows: Array[SaPageRow] = []
    for part: SaSettingsPage in _declared(_open_page(window)):
        rows.append_array(part.page.rows())
    return rows


func test_preferences_opens_on_the_first_page() -> void:
    var window := SaSettingsWindow.new()
    assert_eq(String(window.categories[window.current]), SaSettingsWindow.INTERFACE_PAGE, "Preferences opens on Interface")
    var title := window.content_container.get_child(0) as Label
    assert_eq(title.text, "Interface", "under the title the page is given")
    window.free()


func test_the_first_pages_rows_read_in_the_chosen_order() -> void:
    var window := SaSettingsWindow.new()
    var keys: Array[StringName] = []
    for row: SaPageRow in _rows_open(window):
        if row.kind != SaPageRow.Kind.NOTE:
            keys.append(row.key)
    assert_eq(
        keys,
        FIRST_ROWS,
        "the sizes, the theme, the pen, undo, advanced, the experimental tools and what shows at start, in that order"
    )
    window.free()


func test_no_path_row_is_on_the_first_page() -> void:
    var window := SaSettingsWindow.new()
    for row: SaPageRow in _rows_open(window):
        assert_true(row.kind != SaPageRow.Kind.PATH, "%s is no path" % row.key)
        assert_true(row.label != "Folder", "and the settings folder is not among them")
    assert_null(_open_page(window).find_child("SaPathRow", true, false), "nothing on the page draws a path")
    window.free()


func test_the_settings_folder_is_at_the_foot_of_files() -> void:
    var page := SaFilesPage.new()
    var last := page.page.sections[-1]
    assert_eq(last.title, "Settings folder", "the last section of Files")
    var folder := page.page.row(&"folder")
    assert_not_null(folder, "holds the folder")
    if folder != null:
        assert_eq(folder.kind, SaPageRow.Kind.PATH, "as the path row it was")
        assert_eq(folder.read(), SaSettings.get_settings_dir(), "reading where the settings are")
        assert_true(last.rows.has(folder), "under that heading")
    var restart := page.page.row(&"restart")
    assert_false(restart.line.visible, "The restart note waits for a change")
    # The row's own signal rather than a drive, which would write the pointer a
    # painter's next launch reads.
    page.page.row_changed.emit(&"folder", "/somewhere/else")
    assert_true(restart.line.visible, "and shows once the folder changed")
    page.free()


## Each setting keeps one row across Preferences: every row that writes a
## setting is read on each of the ten pages, and none is on two. The first
## page's own-value rows are looked for by their keys.
func test_each_setting_is_on_one_page_only() -> void:
    var window := SaSettingsWindow.new()
    var pages_of: Dictionary = {}
    var keys_of: Dictionary = {}
    for title: String in SaSettingsWindow.FIXED_PAGES:
        window.show_page(title)
        for part: SaSettingsPage in _declared(_open_page(window)):
            for row: SaPageRow in part.page.rows():
                keys_of[row.key] = keys_of.get(row.key, []) + [title]
                if row.target == SaSettings:
                    pages_of[row.bound_to()] = pages_of.get(row.bound_to(), []) + [title]
    assert_true(pages_of.size() > 30, "the bound rows of every page were read, %d of them" % pages_of.size())
    for bound: String in pages_of:
        assert_eq((pages_of[bound] as Array).size(), 1, "%s has one row, on %s" % [bound, pages_of[bound]])
    for key: StringName in OWN_VALUE_ROWS:
        assert_eq(keys_of.get(key, []), [SaSettingsWindow.INTERFACE_PAGE], "%s is on Interface alone" % key)
    assert_eq(pages_of.get("sa_settings.embed_subwindows", []), [SaDockersPage.TITLE], "embedding is on Layouts and dockers")
    window.free()


## The pen's ceiling stays on Pen and tablet, the page about the pen, and the
## first page holds a door to it: a button with no value of its own.
func test_calibrate_the_pen_opens_pen_and_tablet_at_its_calibration() -> void:
    var opened := _open_window()
    var window := opened[0] as SaSettingsWindow
    var door: SaPageRow = null
    for row: SaPageRow in _rows_open(window):
        if row.key == &"calibrate_pen":
            door = row
    assert_not_null(door, "the first page has the pen's door")
    if door == null:
        _close_window(opened)
        return
    assert_eq(door.kind, SaPageRow.Kind.ACTION, "a button and not a second ceiling")
    var button := door.control as Button
    assert_eq(button.text, "Calibrate the pen...", "that says where it goes")
    assert_false(button.disabled, "live in a window that can open the page")
    button.pressed.emit()
    assert_eq(String(window.categories[window.current]), "Pen and tablet", "and opens Pen and tablet")
    assert_eq(String(window.search.report()["open_page"]), "Pen and tablet", "which the search reads as open")
    var marked: Control = window.search.highlighted
    assert_true(marked != null and is_instance_valid(marked), "with the calibration marked")
    var tablet := _open_page(window) as SaTabletPage
    assert_not_null(tablet, "the page drawn is the pen's")
    if tablet != null:
        assert_eq(marked, tablet.page.row(&"calibration").line, "on the strip, the maximum and the curve")
    _close_window(opened)


## Built with no window there is no page to open, so the button is dimmed
## rather than a press that does nothing.
func test_the_door_is_dimmed_with_no_window() -> void:
    var page := SaGeneralPage.new()
    var button := page.page.row(&"calibrate_pen").control as Button
    assert_true(button.disabled, "nothing to open")
    page.free()


func test_the_pens_line_says_where_full_pressure_is() -> void:
    var page := SaGeneralPage.new()
    assert_true(page.pen_sentence().begins_with("Full pressure is the pen's maximum"), "a fresh pen is said to be unmeasured")
    assert_true(page.pen_sentence().contains("Pen and tablet"), "and the line says where the button goes")
    page.free()
    SaSettings.tablet_max_pressure = 0.8
    page = SaGeneralPage.new()
    assert_true(page.pen_sentence().begins_with("Full pressure at 0.80"), "a calibrated one by its ceiling")
    assert_eq(page.page.row(&"calibrate_pen").explanation, page.pen_sentence(), "which is what the row says")
    page.free()
