## A menu placed in a docker opens the same menu.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The bar's eleven menus are placeable, and a placed one is a second view of
## the same state. So the view here is built through the door,
## `SaSettings.build_element_view`, the way a composed docker builds one, and pressed where it stands. What it
## opens is read against what
## the bar's own title opens for the same document: the same rows, the same
## ticks and the same dimmed rows, and a press on a row runs its command.
##
## The bar hangs from a control in the real root with embedding forced, the way
## `test_an_open_menu_gives_way_to_the_title_the_pointer_moves_onto.gd` stands
## its bar, so the lists are real windows that open and close. Everything is
## asked in one frame, since a test that awaits drops every assertion after the
## await. The running app's proof is
## `scenarios/a-menu-placed-in-a-docker-opens-the-same-menu.json`.
extends "res://tests/test_framework.gd"

## Real windows go in the tree, and the Layer menu acts on a document.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const CATEGORY: String = "TopMenuBar"

## The keys of a row's report that say what a painter sees of it, without the
## hover and the keyboard, which follow the pointer and not the menu.
const SEEN: Array[String] = ["id", "label", "checkable", "checked", "disabled"]

var _was_embedding: bool = false
## The node the bar and the views hang from, in the root's tree.
var _host: Control = null
var _bar: TopMenuBar = null
var _surface: SaSurface = null
var _doc: SaDocument = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _surface = Fixtures.make_surface()
    _doc = _surface.easel.document
    _host = Control.new()
    _host.name = "T3Host"
    _host.size = Vector2(tree.root.size)
    EventBus.add_child(_host)
    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(Fixtures.make_registries(_surface).commands)
    # A bar with no Main draws the Layer menu for the document it is handed,
    # the way `test_a_layer_row_that_cannot_act_is_dimmed.gd` hands it one.
    (_bar.menu("Layer") as SaLayerMenu).document = _doc


func after_each() -> void:
    if _host != null:
        _host.free()
    _host = null
    _bar = null
    _doc = null
    Fixtures.teardown(_surface)
    _surface = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


## A fresh view of the menu *m_name*, built through the door and stood in the
## host clear of the bar, where a docker's column would hold it.
func _place(m_name: String) -> SaMenuViews.MenuView:
    var built := SaSettings.build_element_view(CATEGORY, m_name)
    if built == null:
        return null
    _host.add_child(built)
    built.position = Vector2(400, 160)
    built.size = Vector2(180, built.get_combined_minimum_size().y)
    return built as SaMenuViews.MenuView


## What a painter sees of each row of *popup* and its submenus, in order.
func _seen(popup: SaChoicePopup) -> Array:
    var out: Array = []
    var rows: Array = []
    for list: SaChoicePopup in SaMenu.lists_of(popup):
        rows.append_array(list.row_report())
    for row: Dictionary in rows:
        var kept := {}
        for field: String in SEEN:
            kept[field] = row[field]
        out.append(kept)
    return out


## The Layer menu's row key for the command *command_id*.
func _key(command_id: StringName) -> StringName:
    return SaMenu.key(SaLayerMenuRows.number_of(command_id))


func test_every_menu_is_placeable_and_the_second_row_is_not() -> void:
    for m_name: String in TopMenuBar.MENU_NAMES:
        assert_true(SaSettings.is_placeable(CATEGORY, m_name), "'%s' has a view the bar registered" % m_name)
    assert_false(SaSettings.is_placeable(CATEGORY, SaSettings.ROW_SENTINEL), "while the Second Row is where things go")


## The case that matters: the Layer menu's view built, opened, read against the
## bar's own Layer menu, and a row pressed in it running its command.
func test_the_layer_view_opens_the_bars_layer_menu_beside_it_and_a_row_runs() -> void:
    var ops := SaLayerOps.new(_doc)
    var bottom: SaLayer = ops.layers()[0]
    _doc.set_active_layer(bottom)
    bottom.alpha_locked = true
    var view := _place("Layer")
    assert_not_null(view, "The door builds a view of the Layer menu")
    if view == null:
        return
    assert_eq(view.text, "Layer", "with the menu's title on it")
    assert_false(view.disabled, "and live, the bar being there to open the list")

    var list: SaChoicePopup = _bar.menus["Layer"]
    view.pressed.emit()
    assert_true(list.visible, "A press on the view opens the bar's own Layer list")
    var anchor := SaPopupRect.of_anchor(view)
    assert_eq(list.position.x, int(anchor.position.x), "beside the view, at its left edge")
    assert_eq(list.position.y, ceili(anchor.end.y), "and under it, rather than under the bar's title")
    var from_view := _seen(list)
    view.pressed.emit()
    assert_false(list.visible, "A second press on the view closes it")

    _bar.menu_buttons["Layer"].pressed.emit()
    assert_true(list.visible, "The bar's own title opens the same list")
    var from_bar := _seen(list)
    _bar.menu_buttons["Layer"].pressed.emit()
    assert_false(from_view.is_empty(), "The view's list holds rows")
    assert_eq(from_view, from_bar, "and they are the bar's rows, ticks and dims, row for row")
    var by_id := {}
    for row: Dictionary in from_view:
        by_id[row["id"]] = row
    assert_true(by_id[_key(&"layer_merge_down")]["disabled"], "Merge Down is dimmed with the bottom layer active")
    assert_true(by_id[_key(&"layer_move_down")]["disabled"], "and so is Move Down")
    assert_false(by_id[_key(&"layer_move_up")]["disabled"], "while Move Up is live")
    assert_true(by_id[_key(&"layer_alpha_lock")]["checked"], "Alpha Lock is ticked for the alpha locked layer")

    view.pressed.emit()
    var holder := SaMenu.list_holding(list, _key(&"layer_move_up"))
    assert_true(holder.press_row(_key(&"layer_move_up")), "Move Up takes a press in the list the view opened")
    assert_eq(ops.layers()[1], bottom, "and runs its command: the bottom layer is now on top")
    assert_false(list.visible, "and the list goes, as it does from the bar")


func test_a_view_of_filter_opens_filter_and_not_another_menu() -> void:
    var view := _place("Filter")
    assert_not_null(view, "The door builds a view of the Filter menu")
    if view == null:
        return
    view.pressed.emit()
    for m_name: String in _bar.menus:
        var shown := (_bar.menus[m_name] as SaChoicePopup).visible
        assert_eq(shown, m_name == "Filter", "'%s' is %s" % [m_name, "open" if m_name == "Filter" else "closed"])
    _bar.menu_buttons["File"].pressed.emit()
    assert_false((_bar.menus["Filter"] as SaChoicePopup).visible, "A title pressed on the bar puts the view's list away")
    assert_true((_bar.menus["File"] as SaChoicePopup).visible, "and opens its own")


func test_a_view_whose_bar_is_gone_is_dimmed() -> void:
    _host.remove_child(_bar)
    _bar.free()
    _bar = null
    var view := _place("Help")
    assert_not_null(view, "The door still builds a view of Help")
    if view == null:
        return
    assert_true(view.disabled, "and it is dimmed, with no bar to open the list")
