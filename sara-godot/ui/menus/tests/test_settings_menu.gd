## The Settings menu is not on the bar and its rows live in Help.
##
## What this suite holds is that the bar makes no Settings menu, that Help
## carries the three doors (Display, Tablet and Keyboard Shortcuts pages of
## Preferences) once each and that every one names a page Preferences has, and
## that a profile whose stored bar layout names Settings loads without it,
## every other menu where the profile put it.
##
## Each door names the row it lands on. The cases at the foot open Preferences
## through the methods `MainDialogs` answers the three requests with and read
## the row each marks. Where the row then stands in the pane is a frame's work,
## which a suite cannot wait for, so
## `scenarios/every-door-to-preferences-lands-on-its-row.json` reads it, in
## the dump's `highlighted_at` and `highlighted_in_view`.
##
## Display Settings... lands on Canvas and colour, Tablet Settings... on Pen and
## tablet, and the colour space browser is Help's own Colour Spaces..., a window
## of its own.
##
## Built detached and `_ready()`ed by hand, the way `test_tools_menu.gd`
## builds its bar: a popup is a `Window`, and a bar in the tree hangs a headless
## run. A press is `emit.call_deferred`, which nothing here waits for: a test
## that awaits drops every assertion after the await (a Godot trap), so what is read
## is the page each row's handler is bound to, and the frame that opens it is
## `scenarios/the-settings-menu-leaves-the-bar-and-its-rows-go-to-help.json`,
## which presses the three rows and reads Preferences back on each page.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
## An older profile, its menus in an order of the painter's own with Help
## first, Settings where it used to stand, and Modules hidden.
const STORED_ORDER: Array[String] = [
    "Help",
    "File",
    "Edit",
    "View",
    "Window",
    "Image",
    "Layer",
    "Select",
    "Tools",
    "Settings",
    "Filter",
    "Modules",
]

var scratch_path: String = SaDataRoot.path("test_d2_settings_leave_the_bar.cfg")

var _bar: TopMenuBar = null
var _help: SaHelpMenu = null


func before_each() -> void:
    _bar = TopMenuBar.new()
    _bar._ready()
    var note_mode := SaNoteMode.new()
    _bar.add_child(note_mode)
    _bar.bind_commands(SaTestFixtures.make_menu_registries(note_mode).commands)
    _help = _bar.menu("Help") as SaHelpMenu


func after_each() -> void:
    _help = null
    if _bar != null:
        _bar.free()
        _bar = null


func test_the_bar_makes_no_settings_menu() -> void:
    assert_false(TopMenuBar.MENU_NAMES.has("Settings"), "Settings is not among the bar's menus")
    assert_eq(TopMenuBar.MENU_NAMES.size(), 11, "which are eleven")
    assert_null(_bar.menu("Settings"), "nothing fills a Settings menu")
    assert_false(_bar.menus.has("Settings"), "the bar builds no list for one")
    assert_false(_bar.menu_buttons.has("Settings"), "and no button on the row")
    # A default order naming a button nobody builds is a Preferences row for a
    # control that does not exist, the trap the Dockers menu's line names.
    var order: Array = SaSettingsLayout.DEFAULT_ORDERS["TopMenuBar"]
    assert_false(order.has("Settings"), "and the fresh layout does not name it")
    assert_eq(order.find("Filter"), order.find("Tools") + 1, "Filter follows Tools where Settings stood")


## The three doors stand together between two lines, above About, and the
## Keyboard Shortcuts page has one row, where the bar used to offer it twice.
func test_help_holds_display_tablet_and_one_keyboard_shortcuts_row() -> void:
    assert_not_null(_help, "The bar builds the Help menu")
    if _help == null:
        return
    var labels := _help.popup.row_labels()
    assert_true(labels.has("Display Settings..."), "Help has the Display row, named as a settings page")
    assert_true(labels.has("Tablet Settings..."), "and the Tablet row, named the same way")
    var shortcuts := 0
    for label: String in labels:
        if label.begins_with("Keyboard Shortcuts"):
            shortcuts += 1
    assert_eq(shortcuts, 1, "and exactly one Keyboard Shortcuts row")
    var ids: Array[int] = []
    for row_id: StringName in _help.popup.row_ids():
        ids.append(SaMenu.id_of(row_id))
    var at := ids.find(SaHelpMenu.ID_DISPLAY)
    assert_eq(
        ids.slice(at, at + 4),
        [SaHelpMenu.ID_DISPLAY, SaHelpMenu.ID_TABLET, SaHelpMenu.ID_SHORTCUTS, SaHelpMenu.ID_ABOUT],
        "Display, Tablet and Keyboard Shortcuts are one group, above About"
    )


## Every door names a page Preferences has, by the title `FIXED_PAGES` holds.
##
## Display and Tablet emit the title their handler is bound to, read off the
## descriptor, and Keyboard Shortcuts is Help's own row, which asks `MainDialogs`
## and is answered with the page of that title.
func test_every_row_opens_preferences_on_its_page() -> void:
    assert_not_null(_help, "The bar builds the Help menu")
    if _help == null:
        return
    var pages := {SaHelpMenu.ID_DISPLAY: "Canvas and colour", SaHelpMenu.ID_TABLET: "Pen and tablet"}
    for id: int in pages:
        var command_id := _help.command_at(id)
        assert_true(SaMenuCommands.SETTINGS_PAGES.has(command_id), "item %d is a settings command" % id)
        var descriptor := _help.commands.get_descriptor(command_id)
        assert_not_null(descriptor, "and the registry holds it")
        if descriptor == null:
            continue
        var bound := descriptor.handler.get_bound_arguments()
        assert_eq(bound[0] if not bound.is_empty() else null, pages[id], "item %d opens the %s page" % [id, pages[id]])
        assert_true(SaSettingsWindow.FIXED_PAGES.has(pages[id]), "'%s' is a page Preferences has" % pages[id])
    assert_eq(SaMenuCommands.SETTINGS_PAGES.size(), 2, "and the two are the whole table")

    assert_eq(_help.command_at(SaHelpMenu.ID_SHORTCUTS), &"help_shortcuts", "Keyboard Shortcuts is Help's own row")
    var dialogs := FileAccess.get_file_as_string("res://ui/main/main_dialogs.gd")
    assert_true(dialogs.contains('open_preferences("Keyboard shortcuts"'), "which MainDialogs opens on its page")
    assert_true(SaSettingsWindow.FIXED_PAGES.has("Keyboard shortcuts"), "a page Preferences has")


## The three commands the Settings menu listed are gone from the registry, so
## no list of commands offers a row for a menu nobody builds.
func test_no_command_is_left_for_the_settings_menu() -> void:
    for command_id: StringName in [&"settings_display", &"settings_tablet", &"settings_shortcuts"]:
        assert_false(_help.commands.has(command_id), "%s is not registered" % command_id)


## The version-20 step over a profile alone: Settings out of the order and its
## visibility key with it, the rest of the order as stored.
func test_the_migration_takes_settings_out_of_a_stored_order() -> void:
    var config := ConfigFile.new()
    config.set_value("profile_order", "TopMenuBar", STORED_ORDER.duplicate())
    config.set_value("profile_visibility", "TopMenuBar_Settings", false)
    config.set_value("profile_visibility", "TopMenuBar_Modules", false)
    SaSettingsMigrations.apply(config, 19)

    var expected: Array = STORED_ORDER.duplicate()
    expected.erase("Settings")
    assert_eq(config.get_value("profile_order", "TopMenuBar"), expected, "Settings leaves and the rest keep their order")
    assert_false(config.has_section_key("profile_visibility", "TopMenuBar_Settings"), "its visibility key goes with it")
    assert_eq(config.get_value("profile_visibility", "TopMenuBar_Modules"), false, "and another menu's stays")
    assert_eq(int(config.get_value("meta", "version")), SaSettings.SETTINGS_VERSION, "stamped current")


## The whole load, from a file on disk to the bar's row: the profile opens
## without the menu and every other one where it stood.
func test_a_stored_layout_naming_settings_loads_with_the_rest_in_order() -> void:
    ScratchFolder.remove_saved(scratch_path)
    var config := ConfigFile.new()
    config.set_value("meta", "version", 19)
    config.set_value("profile_order", "TopMenuBar", STORED_ORDER.duplicate())
    config.set_value("profile_visibility", "TopMenuBar_Settings", true)
    config.set_value("profile_visibility", "TopMenuBar_Modules", false)
    config.save(scratch_path)

    var previous_path: String = SaSettings.settings_path
    SaSettings.settings_path = scratch_path
    SaSettings.load_settings()

    var expected: Array = STORED_ORDER.duplicate()
    expected.erase("Settings")
    var order := SaSettings.get_layout_order("TopMenuBar")
    assert_false(order.has("Settings"), "The loaded order has no Settings")
    assert_eq(order.slice(0, expected.size()), expected, "and the other menus open where the profile put them")
    assert_false(SaSettings.get_element_visible("TopMenuBar", "Modules"), "a hidden menu stays hidden")

    var bar := TopMenuBar.new()
    bar._ready()
    var drawn: Array = []
    for child: Node in bar.menu_bar.get_children():
        drawn.append(String(child.name))
    assert_eq(drawn, expected, "and the bar draws its buttons in that order")
    bar.free()

    SaSettings.settings_path = previous_path
    SaSettings.load_settings()
    ScratchFolder.remove_saved(scratch_path)


## Display Settings... names the profile row, and both rows a door opens
## the Display page on are rows that page declares, so a row renamed under a
## door fails here rather than opening the page at its top with a warning.
func test_the_display_doors_name_rows_the_display_page_declares() -> void:
    var descriptor := _help.commands.get_descriptor(&"help_display") if _help != null else null
    assert_not_null(descriptor, "Help's Display row is registered")
    if descriptor == null:
        return
    assert_eq(
        descriptor.handler.get_bound_arguments(),
        ["Canvas and colour", &"display_profile"],
        "and opens Canvas and colour on the profile"
    )
    var tablet := _help.commands.get_descriptor(&"help_tablet")
    assert_eq(
        tablet.handler.get_bound_arguments() if tablet != null else [],
        ["Pen and tablet"],
        "Tablet's row opens Pen and tablet at the top"
    )
    var page := SaDisplayPage.new()
    for key: StringName in [SaDisplayPage.PROFILE_ROW, SaDisplayPage.STOPS_ROW]:
        assert_not_null(SaSettingsSearch.row_line(page, key), "the Display page declares a row '%s'" % key)
    var stops := SaSettingsSearch.row_line(page, SaDisplayPage.STOPS_ROW)
    assert_eq(SaSettingsSearch.landing_title(stops), "Stops", "the stops row is the slider's")
    page.free()


## Each of the three doors opens Preferences with its row marked, its
## control holding the keyboard where it takes it, through the methods
## `MainDialogs` answers the requests with. A fourth opens the Display door over
## a Preferences already open, which lands as well, and a door naming a row the
## page lacks opens the page with nothing marked.
func test_every_door_opens_preferences_marked_on_its_row() -> void:
    if RenderingServer.get_rendering_device() == null:
        skip("no RenderingDevice, so Preferences cannot open and no door's row can be read marked")
        return
    var opened := _open_dialogs()
    var dialogs := opened[0] as MainDialogs

    dialogs.connect_event_bus()
    assert_true(EventBus.settings_row_requested.is_connected(dialogs.open_preferences), "the row request reaches Preferences")

    # Help > Display Settings...: what the bus hands `open_preferences`.
    dialogs.open_preferences.callv(_help.commands.get_descriptor(&"help_display").handler.get_bound_arguments())
    var window := dialogs._settings_window as SaSettingsWindow
    assert_not_null(window, "the door builds Preferences")
    if window == null:
        _close_dialogs(opened)
        return
    _read_landing(window, "Canvas and colour", "Display profile", "Help > Display Settings...")

    dialogs.open_display_page()
    _read_landing(window, "Canvas and colour", "Stops", "View > Exposure Stops...")
    var stops := SaSettingsSearch.row_line(window.content_scroll, SaDisplayPage.STOPS_ROW)
    assert_true(window.gui_get_focus_owner() is HSlider, "and the stops slider has the keyboard")
    assert_true(stops != null and stops.is_ancestor_of(window.gui_get_focus_owner()), "on the stops row")

    # The first chord's title is the command registry's name for File > New,
    # New document in the app, and this fixture has no registry to name it by.
    dialogs.open_shortcuts()
    var chords := window.content_scroll.find_child("ShortcutRows", true, false)
    var first := SaSettingsSearch.landings(chords)[0] if chords != null else null
    _read_landing(window, "Keyboard shortcuts", SaSettingsSearch.landing_title(first), "Help > Keyboard Shortcuts")
    assert_eq(window.search.highlighted, first, "the row marked is the first chord's")
    assert_true(first != null and first.is_ancestor_of(window.gui_get_focus_owner()), "and its chord button has the keyboard")

    dialogs.open_preferences.callv(_help.commands.get_descriptor(&"help_display").handler.get_bound_arguments())
    assert_true(window.is_open(), "a door over an open Preferences leaves it open")
    _read_landing(window, "Canvas and colour", "Display profile", "the Display door again")

    window.toggle("Canvas and colour", &"no_such_row")
    assert_null(window.search.highlighted, "a row the page lacks marks nothing")
    assert_eq(window.content_scroll.scroll_vertical, 0, "and leaves the page at its top")
    _close_dialogs(opened)


## Help > Colour Spaces... is the browser that was a page of Preferences, a
## row beside the manual that asks `MainDialogs` the way the manual's does, and
## Preferences has no page of that name to open.
func test_colour_spaces_is_helps_own_row_and_no_page_of_preferences() -> void:
    assert_not_null(_help, "The bar builds the Help menu")
    if _help == null:
        return
    assert_true(_help.popup.row_labels().has("Colour Spaces..."), "Help has the Colour Spaces row")
    assert_eq(_help.command_at(SaHelpMenu.ID_COLOR_SPACES), &"help_color_spaces", "under its own command")
    var descriptor := _help.commands.get_descriptor(&"help_color_spaces")
    var bound := descriptor.handler.get_bound_arguments() if descriptor != null else []
    assert_eq(bound, [EventBus.color_spaces_requested], "which asks for the window on the bus")
    var dialogs := FileAccess.get_file_as_string("res://ui/main/main_dialogs.gd")
    assert_true(
        dialogs.contains("EventBus.color_spaces_requested.connect(open_color_spaces)"), "and MainDialogs opens the window"
    )
    assert_false(SaSettingsWindow.FIXED_PAGES.has("Colour Spaces"), "Preferences lists no Colour Spaces page")
    var window := SaSettingsWindow.new()
    assert_false(window.show_page("Colour Spaces"), "and opens none by that name")
    window.free()


## The window the row opens: built on the first ask and kept, never modal, the
## browser inside it.
func test_the_colour_spaces_window_holds_the_browser_and_is_built_once() -> void:
    if RenderingServer.get_rendering_device() == null:
        skip("no RenderingDevice, so the browser's gamut solid cannot be drawn")
        return
    var opened := _open_dialogs()
    var dialogs := opened[0] as MainDialogs
    dialogs.open_color_spaces()
    var window := dialogs._color_spaces_window
    assert_not_null(window, "the row builds the window")
    if window != null:
        assert_true(window.visible, "and shows it")
        assert_false(window.exclusive, "never modal, so the painting goes on beside it")
        assert_not_null(window.page, "the browser is in it")
        assert_true(window.content.is_ancestor_of(window.page), "inside the window's content")
        dialogs.open_color_spaces()
        assert_eq(dialogs._color_spaces_window, window, "a second ask shows the same window")
        window.hide()
    _close_dialogs(opened)


## The page open, the row marked with the search's own mark, and the report's
## name for it.
func _read_landing(window: SaSettingsWindow, page: String, title: String, door: String) -> void:
    var report := window.search.report()
    assert_eq(report["open_page"], page, "%s opens %s" % [door, page])
    assert_eq(report["highlighted_row"], title, "%s marks %s" % [door, title])
    var marked := window.search.highlighted
    var label := marked.get_child(0).get_child(0) as Label if marked != null else null
    assert_true(label != null and label.has_theme_color_override("font_color"), "%s paints the row's title" % door)
    if label != null and label.has_theme_color_override("font_color"):
        assert_eq(label.get_theme_color("font_color"), SaTheme.palette.accent_primary, "%s in the accent" % door)


## `MainDialogs` in the tree, embedded, so the Preferences it builds can open:
## the fixture of `ui/settings/tests/test_preferences_search.gd` with the
## dialogs node between, for both of that suite's reasons.
func _open_dialogs() -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "N78DoorsTestHost"
    EventBus.add_child(host)
    var dialogs := MainDialogs.new(null, func() -> SaCanvas: return null)
    host.add_child(dialogs)
    return [dialogs, host, was_embedding]


## Freed here and now, a Window being its parent's exclusive child until it is
## gone.
func _close_dialogs(opened: Array) -> void:
    var dialogs := opened[0] as MainDialogs
    var window := dialogs._settings_window
    if window != null and is_instance_valid(window):
        window.hide()
    (opened[1] as Node).free()
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = bool(opened[2])
