## A module that brings a Preferences page, enabled
## or disabled after the window was built, shows or takes away its row in the
## sidebar without a restart.
##
## The window is kept and shown again, so before this a gone module's row stayed
## and built an empty page, and a new module's row never appeared.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, because the search index builds every page and the
## Canvas and colour page draws its gamut solids.
const REQUIRES_GPU := true

const MODULE := &"test_module"
const TITLE := "Test Page"


## A window over a registry of its own, in the tree and embedded, the way
## `test_settings_window_frame.gd` opens one.
func _open(registry: SaUIRegistry) -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "SettingsTestHost"
    EventBus.add_child(host)
    var window := SaSettingsWindow.new(registry)
    host.add_child(window)
    return [window, host, was_embedding]


func _close(opened: Array) -> void:
    (opened[1] as Node).free()
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = opened[2]


## The page buttons' titles, read from `category_buttons` because the list
## holds a heading per group as well.
func _row_titles(window: SaSettingsWindow) -> PackedStringArray:
    var out := PackedStringArray()
    for btn: Button in window.category_buttons:
        out.append(btn.text)
    return out


func _page(_window: Node) -> Control:
    var page := VBoxContainer.new()
    page.name = "TestPage"
    return page


## The page's own title label, the first child of the content column.
func _open_title(window: SaSettingsWindow) -> String:
    return (window.content_container.get_child(0) as Label).text


func test_a_page_registered_after_the_build_gets_its_row() -> void:
    var registry := SaUIRegistry.new()
    var opened := _open(registry)
    var window := opened[0] as SaSettingsWindow
    assert_false(_row_titles(window).has(TITLE), "no row before the module comes")

    registry.register_settings_page(&"preferences_test", TITLE, _page, MODULE)
    assert_true(_row_titles(window).has(TITLE), "the module's row is in the sidebar")
    assert_eq(_row_titles(window).size(), window.categories.size(), "one row per category")
    assert_true(window.show_page(TITLE), "and its page opens")
    assert_eq(_open_title(window), TITLE, "under its own title")
    _close(opened)


func test_a_page_taken_away_takes_its_row_and_the_selection_falls_back() -> void:
    var registry := SaUIRegistry.new()
    registry.register_settings_page(&"preferences_test", TITLE, _page, MODULE)
    var opened := _open(registry)
    var window := opened[0] as SaSettingsWindow
    window.show_page(TITLE)

    registry.unregister_module(MODULE)
    assert_false(_row_titles(window).has(TITLE), "the module's row is gone")
    assert_true(window.current >= 0 and window.current < window.categories.size(), "the selection is on a page that exists")
    assert_eq(window.current, 0, "the first page")
    assert_eq(_open_title(window), String(window.categories[0]), "and it is the page on screen")
    assert_false(window.category_buttons[0].flat, "drawn as the selected row")
    _close(opened)


func test_the_page_on_screen_stays_open_and_unbuilt_when_another_comes() -> void:
    var registry := SaUIRegistry.new()
    var opened := _open(registry)
    var window := opened[0] as SaSettingsWindow
    window.show_page("Pen and tablet")
    var page := window.content_container.get_child(window.content_container.get_child_count() - 1)

    registry.register_settings_page(&"preferences_test", TITLE, _page, MODULE)
    assert_eq(String(window.categories[window.current]), "Pen and tablet", "Pen and tablet is still the current page")
    var last := window.content_container.get_child(window.content_container.get_child_count() - 1)
    assert_eq(last, page, "the page is the same node, not built again")
    var btn := window.category_buttons[window.current]
    assert_false(btn.flat, "its row is drawn selected")
    _close(opened)


## The titles of the rows the search left on screen.
func _shown_rows(window: SaSettingsWindow) -> PackedStringArray:
    var out := PackedStringArray()
    for btn: Button in window.category_buttons:
        if btn.visible:
            out.append(btn.text)
    return out


func test_the_search_indexes_the_new_page_and_keeps_its_words() -> void:
    var registry := SaUIRegistry.new()
    var opened := _open(registry)
    var window := opened[0] as SaSettingsWindow
    window.search.apply("pressure")
    var shown := _shown_rows(window)
    assert_true(not shown.is_empty() and shown.size() < window.categories.size(), "the search narrows the list")
    var before := window.search
    registry.register_settings_page(&"preferences_test", TITLE, _page, MODULE)
    assert_true(window.search != before, "a new search over the new categories")
    assert_eq(window.search.field.text, "pressure", "carrying what the painter had typed")
    assert_true(window.search.index.has(TITLE), "whose index has the new page")
    assert_eq(_shown_rows(window), shown, "and the list narrowed to the same rows")
    _close(opened)


func test_the_window_hears_nothing_out_of_the_tree_and_catches_up_on_the_way_in() -> void:
    var registry := SaUIRegistry.new()
    var opened := _open(registry)
    var window := opened[0] as SaSettingsWindow
    var host := opened[1] as Node
    host.remove_child(window)
    var heard := registry.settings_pages_changed.is_connected(Callable(window, "_on_settings_pages_changed"))
    assert_false(heard, "the connection goes with the tree")

    registry.register_settings_page(&"preferences_test", TITLE, _page, MODULE)
    assert_false(_row_titles(window).has(TITLE), "nothing rebuilt while out")
    host.add_child(window)
    assert_true(_row_titles(window).has(TITLE), "the row is there on the way back in")
    _close(opened)
