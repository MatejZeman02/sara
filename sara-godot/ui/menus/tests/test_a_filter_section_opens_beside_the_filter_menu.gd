## A filter section opens as a list beside the Filter menu, and the menu stays
## open while it does.
##
## The bar stands in a tree with embedding forced, the way
## `test_a_second_click_closes_the_list.gd` stands its button, so the menu
## and its child are real windows the suite can see open and close. Everything
## is asked in one frame, since a test that awaits one drops every assertion
## after the await. The hover delay and the keys a painter presses
## are the scenario's, `scenarios/a-filter-section-opens-beside-the-filter-menu.json`.
extends "res://tests/test_framework.gd"

## Real windows go in the tree.
const REQUIRES_GPU := true


## A filter with a title and a section of the suite's choosing. Public members,
## written in `_init` alone.
class SortedFilter:
    extends SaFilter
    var entry_title: String
    var entry_section: StringName

    func _init(text: String, section_id: StringName) -> void:
        entry_title = text
        entry_section = section_id

    func title() -> String:
        return entry_title

    func family() -> StringName:
        return entry_section

    func run(_ctx: SaFilterContext) -> void:
        pass


var _host: Control = null
var _was_embedding: bool = false
var _bar: TopMenuBar = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true


func after_each() -> void:
    if _host != null:
        _host.free()
    _host = null
    _bar = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


## The bar in a tree with a Blur and a Glitch section, and the Filter menu open.
func _open_menu() -> SaFilterMenu:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    SaShortcutCommands.new(Callable(), Callable(), Callable(), null).register_into(registries.commands)
    var alpha := registries.context.for_module(&"alpha")
    alpha.register_filter_section(&"blur", "Blur", 400)
    alpha.register_filter(SortedFilter.new("Smear", &"blur"))
    alpha.register_filter(SortedFilter.new("Streak", &"blur"))
    alpha.register_filter_section(&"glitch", "Glitch", 450)
    alpha.register_filter(SortedFilter.new("Scramble", &"glitch"))
    # Not `tree.root`, which is mid-`_ready` when a suite runs.
    _host = Control.new()
    _host.name = "U1FilterSectionHost"
    EventBus.add_child(_host)
    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(registries.commands)
    var menu := _bar.menu("Filter") as SaFilterMenu
    menu.filters = registries.filters
    _bar._on_menu_button_pressed("Filter")
    return menu


func test_a_section_opens_beside_the_menu_with_the_menu_still_open() -> void:
    var menu := _open_menu()
    var popup: SaChoicePopup = _bar.menus["Filter"]
    assert_true(popup.visible, "the Filter menu is open")
    var blur := SaMenu.key(menu.section_item(&"blur"))
    var list := menu.show_section(menu.section_item(&"blur"))
    assert_true(list.visible, "the Blur list opened")
    assert_true(popup.visible, "and the menu is still open beside it")
    assert_eq(Array(list.row_labels()), ["Smear", "Streak"], "holding the section's filters")
    assert_true(
        list.position.x >= popup.position.x + popup.size.x - 1,
        "right of the menu: %s against %s" % [list.position, Rect2i(popup.position, popup.size)]
    )
    var row := SaPopupRect.of_anchor(popup.row_of(blur))
    assert_true(
        absf(float(list.position.y) - row.position.y) <= 1.0,
        "level with its row: %d against %d" % [list.position.y, row.position.y]
    )
    assert_eq(list.content_scale_factor, popup.content_scale_factor, "and at the menu's scale")


func test_another_section_takes_the_place_of_the_first() -> void:
    var menu := _open_menu()
    var popup: SaChoicePopup = _bar.menus["Filter"]
    menu.show_section(menu.section_item(&"blur"))
    var list := menu.show_section(menu.section_item(&"glitch"))
    assert_true(list.visible and popup.visible, "the Glitch list is open beside the menu")
    assert_eq(Array(list.row_labels()), ["Scramble"], "with Glitch's filter in place of Blur's")
    assert_eq(popup.child_row, SaMenu.key(menu.section_item(&"glitch")), "hanging from the Glitch row")


func test_closing_the_child_leaves_the_menu_and_closing_the_menu_takes_the_child() -> void:
    var menu := _open_menu()
    var popup: SaChoicePopup = _bar.menus["Filter"]
    var list := menu.show_section(menu.section_item(&"blur"))
    list.hide()
    assert_true(popup.visible, "escape on the list closes the list alone")
    assert_false(popup.has_open_child(), "and the menu has no child open")
    list = menu.show_section(menu.section_item(&"blur"))
    assert_true(list.visible, "the list opens again")
    popup.hide()
    assert_false(list.visible, "and the menu closing takes it along")


func test_a_filter_picked_from_the_list_closes_both() -> void:
    var menu := _open_menu()
    var popup: SaChoicePopup = _bar.menus["Filter"]
    var list := menu.show_section(menu.section_item(&"blur"))
    assert_true(list.press_row(list.row_ids()[0]), "Smear takes a press")
    assert_false(list.visible, "the list closed on the choice")
    assert_false(popup.visible, "and the menu with it")


func test_a_section_row_pressed_in_the_open_menu_keeps_it_open() -> void:
    var menu := _open_menu()
    var popup: SaChoicePopup = _bar.menus["Filter"]
    assert_true(popup.press_row(SaMenu.key(menu.section_item(&"blur"))), "the Blur row takes a press")
    assert_true(popup.visible, "and the menu is still open, the list being on its way")
