## Every menu under the top bar opens with a search field, the short ones as
## well as the long.
##
## A list shows the field only over
## twenty rows, so a short menu such as Tools would have none. The bar builds
## every menu's popup searched, and a list that is not a menu keeps the twenty
## row line, which the last test reads.
##
## Built on a detached bar with a bound machine, the way
## `test_the_stabilizer_s_modes_read_as_a_choice_of_one.gd` builds it, so the Tools menu has
## the registered tools in it. Typed with `text_changed`, which is what a key
## in the focused field emits.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _bar: TopMenuBar = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _bar = TopMenuBar.new()
    _bar._ready()
    var tools := _bar.menu("Tools") as SaToolsMenu
    if tools != null:
        tools.machine = _machine


func after_each() -> void:
    if _bar != null:
        _bar.free()
        _bar = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func test_the_tools_menu_has_a_field_and_pen_leaves_only_the_rows_that_hold_it() -> void:
    var menu := _bar.menu("Tools")
    assert_not_null(menu, "The bar has a Tools menu")
    if menu == null:
        return
    menu.populate()
    var popup := menu.popup
    assert_true(popup.search.visible, "The Tools menu shows a search field")
    assert_true(popup.row_ids().size() <= SaChoiceSearch.MIN_ROWS, "and is short enough that only the menu rule gives it one")
    # No built-in tool's name holds "pen" today, so the needle "pen"
    # leaves every row hidden, and "er" is asked as well so that a filter
    # which hid everything for any needle could not pass.
    for needle: String in ["pen", "er"]:
        popup.search.text = needle
        popup.search.text_changed.emit(needle)
        var kept: Array[String] = []
        for id: StringName in popup.row_ids():
            var label := popup.label_button(id).text
            var holds := label.to_lower().contains(needle)
            assert_eq(
                popup.is_row_shown(id), holds, "Under %s, row %s is shown exactly when it holds the needle" % [needle, label]
            )
            if holds:
                kept.append(label)
        if needle == "er":
            assert_true(kept.has("Eraser"), "and er leaves the Eraser, among %s" % [kept])


func test_every_menu_on_the_bar_has_the_field() -> void:
    for menu_name: String in TopMenuBar.MENU_NAMES:
        var menu := _bar.menu(menu_name)
        assert_not_null(menu, "The bar has a %s menu" % menu_name)
        if menu == null:
            continue
        menu.populate()
        assert_true(menu.popup.search.visible, "The %s menu shows a search field" % menu_name)


func test_a_short_list_that_is_not_a_menu_still_opens_without_one() -> void:
    var popup := SaChoicePopup.new()
    for index in 9:
        popup.add_row(StringName("row_%d" % index), "Row %d" % index)
    assert_false(popup.search.visible, "Nine rows of a plain list carry no field")
    popup.free()
