## A module's page in Preferences, through the door the skeleton's ten use.
##
## Hard rule 6: a built-in registers exactly the way a third-party module does.
## The pages are registered, not a list and a `match` in `SaSettingsWindow`, so a
## module can add one. The fixture under
## `tests/fixtures/modules/settings-page-fixture/` is the third-party half.
##
## The sidebar has ten pages in three groups and the door takes a group argument. A built-in names its group
## the way a module does, and a
## module that names none goes under Files and system.
extends "res://tests/test_framework.gd"

## It opens a real window, and only a run with a RenderingDevice has one.
const REQUIRES_GPU := true

const FIXTURE_MODULE = preload("res://tests/fixtures/modules/settings-page-fixture/module.gd")

## The group each of the ten names at the door, in the sidebar's order.
## MIDI comes in through the door as a module's page does, and Modules is the
## eleventh.
const GROUPS := {
    "Interface": &"interface",
    "Layouts and dockers": &"interface",
    "Keyboard shortcuts": &"interface",
    "Languages": &"interface",
    "Brushes": &"painting",
    "Pen and tablet": &"painting",
    "Canvas and colour": &"painting",
    "Files": &"files_and_system",
    "Performance": &"files_and_system",
    "Recorder": &"files_and_system",
    "Modules": &"files_and_system",
}


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


## A Preferences window in the tree, embedded, with a host to free it by. The
## shape and both of its reasons are `test_preferences_search.gd`'s.
func _open_window(ui_registry: SaUIRegistry) -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return []
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "C19TestHost"
    EventBus.add_child(host)
    var window := SaSettingsWindow.new(ui_registry)
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


func test_the_ten_come_through_the_door_each_naming_its_group() -> void:
    var registry := SaSettingsWindow.register_builtins(null)
    var titles: Array = []
    for entry: Dictionary in registry.list_settings_pages():
        var title := String(entry["title"])
        titles.append(title)
        assert_eq(String(entry["module"]), "", "'%s' is the skeleton's own" % title)
        assert_eq(entry["group"], GROUPS.get(title, &""), "'%s' names its group at the door" % title)
    assert_eq(titles, SaSettingsWindow.FIXED_PAGES, "the registry lists the eleven, in the order the list names them")
    assert_eq(titles, GROUPS.keys(), "which is this suite's table of the eleven")
    SaSettingsWindow.register_builtins(registry)
    assert_eq(
        registry.list_settings_pages().size(),
        SaSettingsWindow.FIXED_PAGES.size(),
        "asked twice, it registers nothing the second time"
    )


func test_a_window_made_with_no_registry_still_lists_the_ten_in_three_groups() -> void:
    var opened := _open_window(null)
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    assert_eq(window.categories, SaSettingsWindow.FIXED_PAGES, "the eleven are the sidebar, and nothing else is listed")
    for i in window.categories.size():
        assert_eq(window.category_groups[i], GROUPS[String(window.categories[i])], "'%s' under its group" % window.categories[i])
    assert_eq(window.group_headings.keys(), SaUIRegistry.SETTINGS_GROUPS, "under three headings, in the door's order")
    var said: Array[String] = []
    for heading: Label in window.group_headings.values():
        said.append(heading.text)
    assert_eq(said, ["Interface", "Painting", "Files and system"] as Array[String], "which read as the groups are called")
    _close_window(opened)


func test_a_modules_page_goes_under_the_group_it_names_or_files_and_system() -> void:
    var registries := _registries()
    var module: SaModule = FIXTURE_MODULE.new()
    # Before the ten, the way a module loaded at boot is, so the order below is
    # the rule's and not an accident of who registered first.
    module.register(registries.context.for_module(module.get_id()))
    var opened := _open_window(registries.ui)
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    var at := window.categories.find(FIXTURE_MODULE.PAGE_TITLE)
    assert_eq(at, window.categories.size() - 1, "a page naming no group ends the list")
    assert_eq(window.category_groups[at], SaUIRegistry.DEFAULT_SETTINGS_GROUP, "under Files and system")
    assert_eq(String(window.categories[at - 1]), "Modules", "after the skeleton's own pages of that group")

    var painting := window.categories.find(FIXTURE_MODULE.PAINTING_PAGE_TITLE)
    assert_eq(window.category_groups[painting], &"painting", "a page naming Painting goes under it")
    assert_eq(String(window.categories[painting - 1]), "Canvas and colour", "after the group's own pages")
    assert_eq(String(window.categories[painting + 1]), "Files", "and before the next group")
    assert_eq(window.category_buttons.size(), window.categories.size(), "each has a button like any other")

    assert_true(window.show_page(FIXTURE_MODULE.PAGE_TITLE), "it opens by its title")
    # The page that was open is queued and still a child until the frame ends.
    var live: Array = []
    for child in window.content_container.get_children():
        if not child.is_queued_for_deletion():
            live.append(child)
    assert_eq(live.size(), 2, "a title and the factory's Control under it")
    assert_eq((live[0] as Label).text, FIXTURE_MODULE.PAGE_TITLE, "the open page says its name")

    window.search.apply(FIXTURE_MODULE.ROW_WORD)
    var shown: Array = []
    for i in window.category_buttons.size():
        if window.category_buttons[i].visible:
            shown.append(String(window.categories[i]))
    assert_eq(shown, [FIXTURE_MODULE.PAGE_TITLE], "the search finds the module's row, and only there")
    for group: StringName in window.group_headings:
        var heading := window.group_headings[group]
        assert_eq(
            heading.visible, group == SaUIRegistry.DEFAULT_SETTINGS_GROUP, "'%s' shows only over a page left" % heading.text
        )
    _close_window(opened)


func test_a_group_the_door_does_not_know_is_files_and_system() -> void:
    var registry := SaUIRegistry.new()
    # The warning prints, which is what it is for.
    var ok := registry.register_settings_page(&"stray", "Stray", func(_w: Node) -> Control: return null, &"", &"sculpting")
    assert_true(ok, "the page is not refused for it")
    assert_eq(registry.list_settings_pages()[0]["group"], SaUIRegistry.DEFAULT_SETTINGS_GROUP, "and goes where no group does")


func test_the_page_leaves_with_its_module() -> void:
    var registries := _registries()
    var module: SaModule = FIXTURE_MODULE.new()
    var scoped := registries.context.for_module(module.get_id())
    module.register(scoped)
    assert_true(registries.ui.has_settings_page(FIXTURE_MODULE.PAGE_ID), "registered through SaContext")
    scoped.remove_all_registrations()
    assert_false(registries.ui.has_settings_page(FIXTURE_MODULE.PAGE_ID), "and gone with the module")
    assert_false(registries.ui.has_settings_page(FIXTURE_MODULE.PAINTING_PAGE_ID), "both of its pages")

    var opened := _open_window(registries.ui)
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    assert_eq(window.categories.find(FIXTURE_MODULE.PAGE_TITLE), -1, "a window made afterwards does not list it")
    assert_false(window.show_page(FIXTURE_MODULE.PAGE_TITLE), "and cannot open it")
    _close_window(opened)


func test_a_second_page_under_one_title_is_refused() -> void:
    var registry := SaSettingsWindow.register_builtins(null)
    # The refusal prints, which is what a refusal is for.
    var ok := registry.register_settings_page(
        &"another_interface", SaSettingsWindow.INTERFACE_PAGE, func(_w: Node) -> Control: return null
    )
    assert_false(ok, "show_page asks by title, so a title is taken once")
    assert_eq(registry.list_settings_pages().size(), SaSettingsWindow.FIXED_PAGES.size(), "and the list did not grow")


## A title the sidebar carries comes before a former one: a module's page
## called Tablet opens, where the old name would otherwise reach Pen and
## tablet.
func test_a_modules_page_under_a_former_title_opens_itself() -> void:
    var registry := SaSettingsWindow.register_builtins(null)
    registry.register_settings_page(
        &"tablet_extras", "Tablet", func(_w: Node) -> Control: return VBoxContainer.new(), &"tablet-extras"
    )
    var opened := _open_window(registry)
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    assert_true(window.show_page("Tablet"), "it opens")
    assert_eq(String(window.categories[window.current]), "Tablet", "and it is the module's page, not Pen and tablet")
    _close_window(opened)
