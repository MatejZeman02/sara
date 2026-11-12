## A menu reuses its rows rather than building each one on
## every open.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Layer, View and Window menus' frames read 47 to 51 ms on a large
## document, 17 to 19.5 ms of it `menu build`, sixty `SaChoiceRow`s built
## afresh before every open. A menu under the bar now keeps its rows in
## `SaChoiceKeep` and makes each over. The row asks for a suite that opens a menu
## twice and counts the rows built the second time, and that a row whose label or
## tick changed between the opens shows the new one.
##
## The bar's own menus are opened through `_show_menu`, the path a click takes,
## and a menu of the suite's own stands in for a menu whose words change, built on
## `SaMenu` as every menu on the bar is.
extends "res://tests/test_framework.gd"

## Real windows go in the tree.
const REQUIRES_GPU := true

var _host: Control = null
var _was_embedding: bool = false


## A menu whose rows the suite writes between two opens: a tick row, a plain row
## with a chord, a row that goes and a row that comes.
class ChangingMenu:
    extends SaMenu

    var grid_words := "Grid"
    var grid_ticked := false
    var snap_off := false
    var with_old := true
    var with_new := false
    var with_grid := true

    func _add_items() -> void:
        if with_grid:
            add_check_item(grid_words, 1, grid_ticked)
        add_item("Snap", 2, snap_off, "Ctrl+;")
        add_separator()
        add_heading("Guides")
        if with_old:
            add_item("Old Guide", 3)
        if with_new:
            add_item("New Guide", 4)
        add_item("Clear Guides", 5)


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Control.new()
    _host.name = "Host"
    _host.size = Vector2(tree.root.size)
    EventBus.add_child(_host)


func after_each() -> void:
    _host.free()
    _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


func _make_bar() -> TopMenuBar:
    var bar := TopMenuBar.new()
    _host.add_child(bar)
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    return bar


## Every row of *popup* by id, as the node it is, so a second open can say
## whether it drew the same nodes.
static func _nodes(popup: SaChoicePopup) -> Dictionary:
    var out := {}
    for id: StringName in popup.row_ids():
        out[id] = popup.row_of(id).get_instance_id()
    return out


func test_the_layer_view_and_window_menus_build_no_row_the_second_time() -> void:
    var bar := _make_bar()
    for menu_name: String in ["Layer", "View", "Window"]:
        var popup: SaChoicePopup = bar.menus[menu_name]
        assert_not_null(popup.row_keep, "%s keeps its rows" % menu_name)
        bar._show_menu(menu_name)
        var first := _nodes(popup)
        var labels := popup.row_labels()
        assert_true(first.size() > 0, "%s opened with its rows, %d" % [menu_name, first.size()])
        popup.hide()
        bar._show_menu(menu_name)
        assert_eq(popup.row_keep.built, 0, "%s built no row on its second open" % menu_name)
        assert_eq(popup.row_keep.reused, first.size(), "and made over every one it had")
        assert_eq(_nodes(popup), first, "%s drew the same nodes" % menu_name)
        assert_eq(popup.row_labels(), labels, "with the same words")
        popup.hide()


func test_a_row_whose_label_or_tick_changed_shows_the_new_one() -> void:
    var popup := SaChoicePopup.new(true, false, true, true)
    _host.add_child(popup)
    var menu := ChangingMenu.new(popup)
    menu.populate()
    popup.open_under(_host)
    var grid_node := popup.row_of(SaMenu.key(1)).get_instance_id()
    var old_node := popup.row_of(SaMenu.key(3))
    assert_eq(popup.label_button(SaMenu.key(1)).text, "Grid", "the tick row reads Grid")
    assert_false(popup.is_checked(SaMenu.key(1)), "unticked")
    assert_false(popup.is_disabled(SaMenu.key(2)), "and Snap takes a press")
    popup.hide()

    menu.grid_words = "Grid Lines"
    menu.grid_ticked = true
    menu.snap_off = true
    menu.with_old = false
    menu.with_new = true
    menu.populate()
    popup.open_under(_host)

    assert_eq(popup.row_keep.built, 1, "only the row that came was built")
    assert_eq(popup.row_of(SaMenu.key(1)).get_instance_id(), grid_node, "the tick row is the node it was")
    assert_eq(popup.label_button(SaMenu.key(1)).text, "Grid Lines", "and reads its new words")
    assert_true(popup.is_checked(SaMenu.key(1)), "with its new tick")
    assert_true(popup.is_disabled(SaMenu.key(2)), "Snap is dimmed now")
    assert_true(popup.label_button(SaMenu.key(2)).disabled, "and its button takes no press")
    assert_eq(popup.row_of(SaMenu.key(2)).hint_text(), "Ctrl+;", "keeping its chord")
    assert_eq(popup.row_ids(), [SaMenu.key(1), SaMenu.key(2), SaMenu.key(4), SaMenu.key(5)], "the rows in the order listed")
    assert_true(old_node.is_queued_for_deletion() or old_node.get_parent() == null, "the row that went is gone from the list")
    var column := popup.row_of(SaMenu.key(1)).get_parent()
    var order: Array[String] = []
    for child in column.get_children():
        if child.is_queued_for_deletion():
            continue
        order.append(String(child.name) if not child is HSeparator else "---")
    assert_eq(
        order,
        ["Row_item_1", "Row_item_2", "---", "SectionGuides", "Row_item_4", "Row_item_5"],
        "the column holds what was listed and nothing the last open left"
    )
    for id: StringName in popup.row_ids():
        var letter := SaChoiceLetters.letter_of(popup.row_of(id))
        assert_true(
            letter.is_empty() or popup.label_button(id).text.to_lower().contains(letter), "%s's letter is one of its words" % id
        )
    popup.hide()


## A plain row keeps one slot for a tick while the menu holds a tick row, and
## gives it back once the menu holds none, so the labels start at one edge.
func test_a_kept_row_keeps_its_tick_slot_while_the_menu_wants_one() -> void:
    var popup := SaChoicePopup.new(true, false, true, true)
    _host.add_child(popup)
    var menu := ChangingMenu.new(popup)
    for open in 2:
        menu.populate()
        popup.open_under(_host)
        var snap := popup.row_of(SaMenu.key(2))
        var slots := snap.get_children().filter(
            func(child: Node) -> bool: return child.name == "TickSlot" and not child.is_queued_for_deletion()
        )
        assert_eq(slots.size(), 1, "open %d: Snap keeps one slot for a tick" % (open + 1))
        assert_eq(snap.get_child(0).name, "TickSlot", "at its left")
        popup.hide()
    menu.with_grid = false
    menu.populate()
    popup.open_under(_host)
    var bare := popup.row_of(SaMenu.key(2))
    var left := bare.get_children().filter(
        func(child: Node) -> bool: return child.name == "TickSlot" and not child.is_queued_for_deletion()
    )
    assert_eq(left.size(), 0, "with no tick row left, Snap gives its slot back")
    popup.hide()


## A search's hiding is not carried into the next open, and a row it found is
## not kept.
func test_a_search_leaves_nothing_behind_in_the_next_open() -> void:
    var popup := SaChoicePopup.new(true, false, true, true)
    _host.add_child(popup)
    var menu := ChangingMenu.new(popup)
    menu.populate()
    popup.open_under(_host)
    popup.filter("snap")
    assert_false(popup.is_row_shown(SaMenu.key(1)), "the search hid Grid")
    popup.hide()
    menu.populate()
    popup.open_under(_host)
    assert_eq(popup.row_keep.built, 0, "nothing was built again")
    for id: StringName in popup.row_ids():
        assert_true(popup.is_row_shown(id), "%s shows again" % id)
    popup.hide()
