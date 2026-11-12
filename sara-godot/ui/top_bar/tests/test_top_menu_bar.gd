## The top menu bar's state, where a menu mirrors something the app also stores.
##
## A menu item that displays a setting is a second front end for that setting,
## and the failure mode is always the same: it reads the value once when it is
## built and then lies for the rest of the session. Worse than cosmetic, because
## a check item toggles from what it is *showing*, so a stale checkmark makes the
## next click write back the value that was already set and do nothing at all.
##
## Built detached and `_ready()`ed by hand. A PopupMenu is a Window, and putting
## one in the tree is only safe while the root viewport embeds subwindows
## (a known engine hazard). Nothing here needs it: item bookkeeping works
## the same on a detached popup.
extends "res://tests/test_framework.gd"


func before_each() -> void:
    SaSettings.tonemap_highlights = false
    SaSettings.window_button_position = "auto"


## Back to a fresh profile's rolloff, which is on, so the
## suites after this one see the default.
func after_each() -> void:
    SaSettings.tonemap_highlights = true
    SaSettings.window_button_position = "auto"


func _make_bar() -> TopMenuBar:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    return bar


func test_the_view_menu_starts_showing_what_the_setting_says() -> void:
    SaSettings.tonemap_highlights = true
    var bar := _make_bar()

    var view_popup: SaChoicePopup = bar.menus.get("View")
    assert_not_null(view_popup, "The View menu exists")
    var idx := SaMenu.key(TopMenuBar.VIEW_ID_TONEMAP)
    view_popup = SaMenu.list_holding(view_popup, idx)
    assert_not_null(view_popup, "and carries the Tonemap Highlights item")
    assert_true(view_popup.is_checked(idx), "which comes up checked for a profile that had it on")

    bar.free()


## The bug: Preferences > Display holds the same toggle, and the View menu was
## not subscribed to it. Flipping it there left this checkmark on the value it
## was built with.
func test_the_view_menu_follows_a_change_made_in_preferences() -> void:
    var bar := _make_bar()
    var view_popup: SaChoicePopup = bar.menus.get("View")
    var idx := SaMenu.key(TopMenuBar.VIEW_ID_TONEMAP)
    view_popup = SaMenu.list_holding(view_popup, idx)
    assert_false(view_popup.is_checked(idx), "Starts off")

    # What the Preferences checkbox does. It never touches the menu.
    SaSettings.tonemap_highlights = true
    assert_true(view_popup.is_checked(idx), "The menu has to hear about it")

    SaSettings.tonemap_highlights = false
    assert_false(view_popup.is_checked(idx), "and about the way back")

    bar.free()


## The consequence of the stale checkmark, pinned separately because it is the
## symptom a user reports: the menu item stops working rather than looking wrong.
func test_a_click_after_a_preferences_change_still_flips_the_setting() -> void:
    var bar := _make_bar()

    SaSettings.tonemap_highlights = true
    bar._on_view_menu_id_pressed(TopMenuBar.VIEW_ID_TONEMAP)
    assert_false(SaSettings.tonemap_highlights, "One click after Preferences turned it on must turn it off")

    bar._on_view_menu_id_pressed(TopMenuBar.VIEW_ID_TONEMAP)
    assert_true(SaSettings.tonemap_highlights, "and the next click back on")

    bar.free()


## Both directions, so neither front end can be the only one that works.
func test_clicking_the_menu_reaches_the_setting_and_the_canvas() -> void:
    var bar := _make_bar()
    var seen: Array[bool] = []
    var listener := func(enabled: bool) -> void: seen.append(enabled)
    EventBus.tonemap_changed.connect(listener)

    bar._on_view_menu_id_pressed(TopMenuBar.VIEW_ID_TONEMAP)

    EventBus.tonemap_changed.disconnect(listener)
    assert_true(SaSettings.tonemap_highlights, "The click writes the setting")
    assert_eq(seen, [true], "and the setting is what tells the canvas")

    bar.free()


## The menu is named for what it lists. "Extensions" was a second word for the
## thing the loader, the API and the docs all call a module, and the submenu
## under it said "Submodules", which was a third.
func test_the_modules_menu_exists_and_lists_what_is_loaded() -> void:
    var bar := _make_bar()

    assert_true(bar.menus.has("Modules"), "The menu is called Modules")
    assert_false(bar.menus.has("Extensions"), "and nothing is still called Extensions")

    var modules_popup: SaChoicePopup = bar.menus["Modules"]
    assert_eq(modules_popup.row_labels()[0], "Active Modules", "The loaded list's row is the first")

    bar.free()


## Empty by default, and that is the intended state rather than a stub: every
## built-in command already has a home in the UI, so nothing opts in.
func test_the_modules_menu_offers_no_actions_of_its_own() -> void:
    var bar := _make_bar()
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()

    bar.bind_commands(registries.commands)

    var modules_popup: SaChoicePopup = bar.menus["Modules"]
    # The Active Modules row, the actions and the Develop rows. Nothing
    # a module put there, which is what this asks.
    assert_false(modules_popup.row_labels().has("Do The Thing"), "Nothing but what the loader listed")

    bar.free()


## Krita's Tools > Scripts, in Sara's shape: a module ships an action with
## nowhere else to live and it appears here, under the module's own name, and
## running it goes through the registry so the menu item and the same command's
## keyboard shortcut cannot drift apart.
func test_a_module_action_reaches_the_menu_and_runs_from_it() -> void:
    var bar := _make_bar()
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var ctx := registries.context.for_module(&"menu-test-module")

    var fired: Array[bool] = []
    var command := SaCommandDescriptor.create(&"menu_test_action", "Do The Thing", func() -> void: fired.append(true))
    command.show_in_modules_menu = true
    assert_true(ctx.register_command(command), "A module may register a command")

    bar.bind_commands(registries.commands)

    var modules_popup: SaChoicePopup = bar.menus["Modules"]
    var row := modules_popup.row_labels().find("Do The Thing")
    assert_true(row >= 0, "The action the module asked to show is in the menu")
    assert_false(modules_popup.section_titles().has("Do The Thing"), "as a real row rather than a heading")

    bar._on_modules_menu_id_pressed(SaMenu.id_of(modules_popup.row_ids()[row]))
    assert_eq(fired, [true], "and clicking it runs the module's handler through the registry")

    bar.free()


## A command that did not opt in stays out. Most commands are shortcuts for
## things that already have a home, and a menu listing every registered command
## is a menu nobody reads.
func test_a_command_that_did_not_ask_for_a_menu_entry_stays_out() -> void:
    var bar := _make_bar()
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var ctx := registries.context.for_module(&"menu-test-module")

    var command := SaCommandDescriptor.create(&"menu_test_quiet", "Not In The Menu", func() -> void: pass)
    assert_true(ctx.register_command(command), "It registers like any other")

    bar.bind_commands(registries.commands)

    var modules_popup: SaChoicePopup = bar.menus["Modules"]
    assert_false(modules_popup.row_labels().has("Not In The Menu"), "but it is not offered in the menu")

    bar.free()


## The registry is bound after this node's _ready, and a module can register
## later still. A menu built once at startup would show neither.
func test_the_menu_picks_up_a_command_registered_after_it_was_built() -> void:
    var bar := _make_bar()
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    bar.bind_commands(registries.commands)

    var modules_popup: SaChoicePopup = bar.menus["Modules"]
    assert_false(modules_popup.row_labels().has("Arrived Late"), "Nothing on offer yet")

    var ctx := registries.context.for_module(&"late-module")
    var command := SaCommandDescriptor.create(&"menu_test_late", "Arrived Late", func() -> void: pass)
    command.show_in_modules_menu = true
    ctx.register_command(command)

    assert_true(modules_popup.row_labels().has("Arrived Late"), "A module that loads later still gets its entry")

    bar.free()


## Renaming a menu renames a string a stored profile holds. Without a migration
## a profile that had ever reordered the menu bar would keep an entry for a menu
## that no longer exists and lose its say over the one that replaced it.
##
## The old menu leads the stored three, where a fresh bar never puts Modules.
## The read seats a menu a profile lacks among its own, so a profile
## that lost the name would read Modules back after Filter, its place in a
## fresh bar, and only a name renamed in place reads it first.
func test_a_stored_layout_naming_the_old_menu_is_migrated() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", 2)
    config.set_value("profile_order", "TopMenuBar", ["Extensions", "File", "Help"])
    config.set_value("profile_visibility", "TopMenuBar_Extensions", false)

    var path := SaDataRoot.path("test_settings_menu_migration.cfg")
    config.save(path)

    var previous_path: String = SaSettings.settings_path
    SaSettings.settings_path = path
    SaSettings.load_settings()

    var order := SaSettings.get_layout_order("TopMenuBar")
    # The stored three keep their order. The menus the profile lacks are seated
    # among them, each after the nearest menu before it in a fresh bar,
    # and every other default it lacks follows in default order.
    var stored := ["Modules", "File", "Help"]
    var kept := order.filter(func(element: Variant) -> bool: return stored.has(element))
    assert_eq(kept, stored, "The renamed menu keeps its position")
    assert_eq(order[0], "Modules", "at the head, where the old name stood")
    assert_false(order.has("Extensions"), "and the old name is gone")
    var menus: Array = ["Modules"]
    menus.append_array(TopMenuBar.MENU_NAMES.filter(func(menu: String) -> bool: return menu != "Modules"))
    assert_eq(order.slice(0, menus.size()), menus, "The menus it lacked are seated after File, among its own")
    assert_true(order.find(SaSettings.ROW_SENTINEL) >= menus.size(), "and the defaults it lacked follow, the sentinel among them")
    assert_false(SaSettings.get_element_visible("TopMenuBar", "Modules"), "and keeps the visibility it was given")

    SaSettings.settings_path = previous_path
    SaSettings.load_settings()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A refused module is in the list, unticked and dimmed with its
## reason, rather than absent from an always-ticked list.
##
## The list is under a heading in the Modules menu itself, not a submenu of its
## own, so this reads the one popup rather than a child of it.
func test_the_modules_list_shows_a_refusal_with_its_reason() -> void:
    ModuleLoader.failed_modules[&"broken"] = "module.gd does not extend SaModule"
    var bar := _make_bar()
    # The list Active Modules opens beside the menu.
    var modules_popup := (bar.menu("Modules") as SaModulesMenu).show_modules()
    var labels := modules_popup.row_labels()
    var row := -1
    for i in labels.size():
        if labels[i].begins_with("broken: "):
            row = i
    assert_true(row >= 0, "The refused module is listed")
    if row < 0:
        ModuleLoader.failed_modules.erase(&"broken")
        bar.free()
        return
    var row_id: StringName = modules_popup.row_ids()[row]
    assert_false(modules_popup.is_checked(row_id), "unticked")
    assert_true(modules_popup.is_disabled(row_id), "dimmed, which is disabled")
    assert_true(labels[row].ends_with("does not extend SaModule"), "with the reason")
    var switch := labels.find("Turn Modules On or Off...")
    assert_true(switch > row, "and the switch row is below the list")
    ModuleLoader.failed_modules.erase(&"broken")
    bar.free()


## The child names of *container*, in order. `get_child_index()` is avoided
## here: called on a bar that was never added to the tree (this whole file's
## own detached style, see the header) it leaves the RenderingServer 13
## Viewports short at exit, reproducible and unrelated to the code under test.
## `get_children()` does not, so that is what every check here reads.
func _child_names(container: Node) -> Array:
    var names: Array = []
    for child in container.get_children():
        names.append(String(child.name))
    return names


## Left draws close, minimise, zoom at the bar's left edge, in macOS's own
## order, ahead of the menus.
func test_left_puts_close_minimize_zoom_at_the_bars_left_edge() -> void:
    SaSettings.window_button_position = "left"
    var bar := _make_bar()

    assert_eq(bar.rows.main_row.get_children()[0], bar.window_buttons, "the controls are the first child")
    assert_eq(_child_names(bar.window_buttons), ["CloseBtn", "MinimizeBtn", "MaximizeBtn"], "close, minimise, zoom")

    bar.free()


## Right is the arrangement this bar has always drawn: minimise, maximise,
## close, at the far end past everything else.
func test_right_keeps_the_windows_and_gnome_order_at_the_end() -> void:
    SaSettings.window_button_position = "right"
    var bar := _make_bar()

    var children := bar.rows.main_row.get_children()
    assert_eq(children[children.size() - 1], bar.window_buttons, "the controls are the last child")
    assert_eq(_child_names(bar.window_buttons), ["MinimizeBtn", "MaximizeBtn", "CloseBtn"], "minimise, maximise, close")

    bar.free()


## Auto reads the platform: Left on a stubbed macOS, Right anywhere
## else, since there is no Mac on hand to launch this on.
func test_auto_resolves_against_the_platform() -> void:
    var bar := _make_bar()

    bar.window_buttons.os_name_override = "macOS"
    assert_eq(bar.window_buttons.effective_side(), "left", "Auto picks Left on macOS")

    bar.window_buttons.os_name_override = "Linux"
    assert_eq(bar.window_buttons.effective_side(), "right", "and Right everywhere else")

    bar.free()


## A title with a font scale of 11 / 20 would draw File and Edit at 55 percent
## of every other label on the bar. A title is a button like its
## neighbours, so it carries no scale below one and the theme pass gives it
## the interface's own size.
func test_the_menu_titles_are_drawn_at_the_interface_font_size() -> void:
    var bar := _make_bar()
    assert_false(bar.menu_buttons.is_empty(), "The bar builds its menu titles")
    for m_name: String in bar.menu_buttons:
        var button: Button = bar.menu_buttons[m_name]
        var factor := float(button.get_meta(SaUI.FONT_SCALE_META, 1.0))
        assert_true(factor >= 1.0, "%s carries no font scale below one, found %.2f" % [m_name, factor])

    var size := SaUI.get_font_size()
    SaUI._apply_recursive(bar, size, SaUI.px(8))
    for m_name: String in bar.menu_buttons:
        var button: Button = bar.menu_buttons[m_name]
        assert_eq(
            button.get_theme_font_size("font_size"),
            size,
            "%s is drawn at the interface's font size after the theme pass" % m_name
        )

    bar.free()


## The titles read as separate words at rest. Every title but the
## last draws a divider down its right edge in its normal box, and the divider is
## drawn inside the 4 units of margin the title already had, so no title is wider
## than it was and none is folded for it.
func test_a_menu_title_at_rest_carries_a_divider_that_costs_no_width() -> void:
    var bar := _make_bar()
    var names: Array = TopMenuBar.MENU_NAMES
    for i in names.size():
        var button: Button = bar.menu_buttons[names[i]]
        assert_false(button.flat, "%s draws its normal box, which a flat button never does" % names[i])
        var box := button.get_theme_stylebox("normal")
        assert_eq(box.get_margin(SIDE_LEFT), float(SaUI.px(4)), "%s keeps the 4 unit margin on its left" % names[i])
        assert_eq(box.get_margin(SIDE_RIGHT), float(SaUI.px(4)), "and on its right, so the divider is no wider")
        var flat_box := box as StyleBoxFlat
        if i < names.size() - 1:
            assert_not_null(flat_box, "%s has a divider" % names[i])
            assert_true(flat_box.border_width_right >= 1, "drawn on its right edge")
            assert_false(flat_box.draw_center, "and nothing behind the word")
        else:
            assert_null(flat_box, "the last title, %s, ends the row with no divider" % names[i])

    bar.free()
