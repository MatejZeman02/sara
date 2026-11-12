## A long menu's scrollbar sits beside its
## rows and not over their shortcuts, and every row of a menu that has a tick
## starts its label at one x.
##
## Laid out by hand, the way `test_the_tip_grid_scrolls_in_a_frame_of_its_own_
## once_the_tips_outgrow_it` does, because a suite cannot await a frame. Embedded
## on purpose: a window added to the tree otherwise maps a real OS window.
extends "res://tests/test_framework.gd"

var _hosts: Array[Node] = []
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true


func after_each() -> void:
    for host in _hosts:
        host.free()
    _hosts.clear()
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


## A node under `EventBus` for the popups and anchors of one call, freed after the
## test, because a test that builds two menus keeps only the last of them if each
## replaces one shared field.
func _new_host() -> Node:
    var host := Node.new()
    EventBus.add_child(host)
    _hosts.append(host)
    return host


func _menu(rows: int, ticked_every: int) -> SaChoicePopup:
    var host := _new_host()
    var popup := SaChoicePopup.new(true, false)
    host.add_child(popup)
    for i in rows:
        popup.add_row(
            StringName("row_%d" % i),
            "Row %d" % i,
            ticked_every > 0 and i % ticked_every == 0,
            i % 2 == 0,
            "",
            "Ctrl+Shift+%d" % i
        )
    popup.size = Vector2i(300, 240)
    _lay_out(popup)
    return popup


func _lay_out(node: Node) -> void:
    for _pass in 4:
        _sort(node)


func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort(child)
    if node is Control:
        (node as Control).update_minimum_size()


## The first row of a menu with a tick is a box, and an unticked row's first
## child is an empty slot as wide, so the words start where the boxes end on
## every row.
func test_every_row_of_a_menu_with_a_tick_starts_with_a_slot_as_wide_as_the_box() -> void:
    var popup := _menu(12, 3)
    var width := float(SaUI.px(SaChoicePopup.TICK_SLOT))
    for id: StringName in popup.row_ids():
        var row := popup.find_child("Row_" + String(id), true, false) as Control
        var first := row.get_child(0) as Control
        assert_true(
            first.name == &"Check" or first.name == &"TickSlot", "%s: the tick or its slot comes first, %s" % [id, first.name]
        )
        assert_eq(first.custom_minimum_size.x, width, "%s: and takes the slot's width" % id)
        var label_at := row.get_child(1) as Control
        assert_eq(label_at.name, &"Label", "%s: the label is next" % id)


## A menu with no tick keeps no gutter, so a plain command menu is as narrow as
## its words.
func test_a_menu_with_no_tick_keeps_no_slot() -> void:
    var popup := _menu(6, 0)
    for id: StringName in popup.row_ids():
        var row := popup.find_child("Row_" + String(id), true, false) as Control
        assert_true(row.get_node_or_null("TickSlot") == null, "%s: no slot" % id)
    popup.clear()
    popup.add_row(&"late", "Late", true)
    popup.add_row(&"later", "Later")
    assert_true(
        popup.find_child("Row_later", true, false).get_node_or_null("TickSlot") != null,
        "a tick that arrives makes the next row keep the slot"
    )
    popup.clear()
    popup.add_row(&"plain", "Plain")
    assert_true(popup.find_child("Row_plain", true, false).get_node_or_null("TickSlot") == null, "and clear takes it back")


## A dropdown's list, which is capped and whose box is its own control, keeps the
## box at the right, where it was.
func test_a_capped_list_keeps_its_box_at_the_right() -> void:
    var host := _new_host()
    var popup := SaChoicePopup.new(true, true)
    host.add_child(popup)
    popup.add_row(&"a", "A", true, true)
    var row := popup.find_child("Row_a", true, false) as Control
    assert_eq(row.get_child(row.get_child_count() - 1).name, &"Check", "the box is the last child")


## A list taller than the room it opens in is given its bar's width on top of
## what the rows asked for, and a list that fits is not.
func test_a_list_that_scrolls_is_widened_by_its_bar_and_one_that_fits_is_not() -> void:
    var popup := _menu(60, 0)
    var anchor := Control.new()
    anchor.size = Vector2(60.0, 24.0)
    popup.get_parent().add_child(anchor)
    assert_true(SaPopupRect.bar_width(popup) > 0, "the bar has a width")
    var room := SaPopupRect.room_for(popup)
    var asked := popup.wanted_size(60.0)
    var placed := SaPopupRect.place(anchor, popup, popup.wanted_size)
    if room.size == Vector2i.ZERO or placed.size.y >= asked.y:
        assert_eq(placed.size.x, asked.x, "a list that fits is as wide as it asked")
    else:
        assert_eq(placed.size.x, asked.x + SaPopupRect.bar_width(popup), "a list that scrolls is a bar wider")
    var few := _menu(3, 0)
    var few_anchor := Control.new()
    few_anchor.size = Vector2(60.0, 24.0)
    few.get_parent().add_child(few_anchor)
    assert_eq(
        SaPopupRect.place(few_anchor, few, few.wanted_size).size.x,
        few.wanted_size(60.0).x,
        "three rows have no bar to make room for"
    )


func _same_rows(count: int, capped: bool) -> SaChoicePopup:
    var host := _new_host()
    var popup := SaChoicePopup.new(true, capped)
    host.add_child(popup)
    for i in count:
        popup.add_row(StringName("row_%d" % i), "Same row", false, false, "", "Ctrl+Shift+S")
    return popup


## The review's third point: a list the `MAX_HEIGHT` cap stops scrolls without
## the room being short, and its bar lay over the shortcuts all the same. It is
## asked for in `wanted_size`, so the cap, `place` and a submenu all get it.
func test_a_list_the_cap_stops_asks_for_its_bar_in_what_it_wants() -> void:
    var long_list := _same_rows(40, true)
    var wide := long_list.wanted_size(0.0)
    assert_true(wide.y <= SaUI.px(SaChoicePopup.MAX_HEIGHT), "the cap holds the height")
    var short_list := _same_rows(3, true)
    var narrow := short_list.wanted_size(0.0)
    assert_eq(wide.x - narrow.x, SaPopupRect.bar_width(long_list), "the capped list is a bar wider than one that fits")
    assert_eq(SaPopupRect.with_bar(long_list, wide, wide.y - 10), wide, "and is not widened again for being placed short")


## A submenu opens through `beside`, which has no `place`, so the widening is a
## call of its own and the same rule: a bar's width when the list is placed
## shorter than it asked, nothing when it fits.
func test_a_list_placed_short_is_widened_by_its_bar_and_one_placed_whole_is_not() -> void:
    var popup := _same_rows(60, false)
    var asked := Vector2i(300, 900)
    var bar := roundi(float(SaPopupRect.bar_width(popup)) * popup.content_scale_factor)
    assert_true(bar > 0, "the bar has a width")
    assert_eq(SaPopupRect.with_bar(popup, asked, 400).x, asked.x + bar, "placed short, it is a bar wider")
    assert_eq(SaPopupRect.with_bar(popup, asked, 900), asked, "placed whole, it is as asked")
