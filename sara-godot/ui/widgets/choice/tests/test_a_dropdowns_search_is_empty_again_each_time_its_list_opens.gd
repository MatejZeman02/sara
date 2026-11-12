## A dropdown's search is empty again each time its list opens.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Searching for something and then clicking it should clear the typed letters, so
## the next click on the dropdown is not limited to the searched thing. The field emptied itself only on Escape and when the
## rows were rebuilt, so the blend list opened again on "dodge" and the dodge rows.
## `SaChoiceSearch` now hears its window's `popup_hide` and empties itself.
##
## The blend list of `BlendModeButton`, sections and all, because it is the list
## the rule is about and the one with headings a search hides. Two closes are
## tested, a chosen row and a click outside, the two a painter meets.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A real `Window` goes in the tree.
const REQUIRES_GPU := true

var _host: Control = null
var _was_embedding := false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    # Embedded for the reason `test_a_second_click_closes_the_list.gd` gives: a
    # Window added to a root that does not embed maps an OS window.
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Control.new()
    _host.name = "Host"
    _host.size = Vector2(800.0, 600.0)
    EventBus.add_child(_host)


func after_each() -> void:
    _host.free()
    _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


func _blend_button() -> BlendModeButton:
    var button := BlendModeButton.new()
    button.registry = Fixtures.make_registries().blend_modes
    button.refresh()
    button.size = Vector2(160.0, 28.0)
    _host.add_child(button)
    return button


## How many rows, headings and separators of the list show, so a list that came
## back whole reads the same as the list before any search.
func _shown(popup: SaChoicePopup) -> Dictionary:
    var column := popup.search.get_parent().get_node("ChoiceScroll/ChoiceColumn")
    var counts := {"rows": 0, "headings": 0, "lines": 0, "all": 0}
    for child in column.get_children():
        var key := "rows"
        if child is Label:
            key = "headings"
        elif child is HSeparator:
            key = "lines"
        elif not child is HBoxContainer:
            continue
        if (child as Control).visible:
            counts[key] += 1
        if key == "rows":
            counts["all"] += 1
    return counts


## The search typed, the way the field's own `text_changed` hands it to the list.
func _search(popup: SaChoicePopup, needle: String) -> void:
    popup.search.text = needle
    popup.search.text_changed.emit(needle)


func test_the_list_opens_whole_after_a_searched_row_was_chosen() -> void:
    var button := _blend_button()
    button.toggle_list()
    var popup := button.popup
    assert_true(popup.visible, "The blend list opens")
    assert_true(SaChoiceSearch.wanted_for(popup.row_ids().size()), "and is long enough to carry a field")
    var whole := _shown(popup)
    assert_eq(whole["rows"], whole["all"], "Before any search every row shows")

    _search(popup, "dodge")
    var narrowed := _shown(popup)
    assert_true(narrowed["rows"] > 0 and narrowed["rows"] < whole["rows"], "dodge leaves some rows and hides the rest")
    var dodge := popup.highlighted()
    assert_true(popup.label_button(dodge).text.to_lower().contains("dodge"), "and the keyboard is on a dodge row")

    var picked: Array[StringName] = []
    button.mode_selected.connect(func(mode: StringName) -> void: picked.append(mode))
    assert_true(popup.press_row(dodge), "The dodge row takes the click")
    assert_false(popup.visible, "and the list closes on it")
    assert_eq(picked.size(), 1, "with the mode chosen")
    assert_eq(popup.search.text, "", "The field is empty once the list closed")

    # Through `open_under` rather than `toggle_list`, whose frame guard reads a
    # press in the frame of the close as that close, and a suite holds one frame.
    popup.open_under(button)
    assert_true(popup.visible, "The list opens again")
    assert_eq(popup.search.text, "", "on an empty field")
    assert_eq(_shown(popup), whole, "and every row, heading and separator shows, as before the search")


func test_the_list_opens_whole_after_a_click_outside_closed_it() -> void:
    var button := _blend_button()
    button.toggle_list()
    var popup := button.popup
    var whole := _shown(popup)
    _search(popup, "dodge")
    assert_true(_shown(popup)["rows"] < whole["rows"], "dodge narrows the list")

    # A press on the main window well away from the list, which is what closes
    # an embedded popup in the engine. Hidden by hand if this engine's embedder
    # did not, so the field's own answer to `popup_hide` is still what is tested.
    var outside := InputEventMouseButton.new()
    outside.button_index = MOUSE_BUTTON_LEFT
    outside.pressed = true
    outside.position = Vector2(popup.position + popup.size) + Vector2(200.0, 200.0)
    outside.global_position = outside.position
    _host.get_viewport().push_input(outside)
    if popup.visible:
        popup.hide()
    assert_false(popup.visible, "The click outside closed the list")
    assert_eq(popup.search.text, "", "and emptied the field")

    # Through `open_under` rather than `toggle_list`, whose frame guard reads a
    # press in the frame of the close as that close, and a suite holds one frame.
    popup.open_under(button)
    assert_true(popup.visible, "The list opens again")
    assert_eq(popup.search.text, "", "on an empty field")
    assert_eq(_shown(popup), whole, "and every row, heading and separator shows")


## Escape keeps its two steps: the first empties a field with text and the list
## comes back, so the field's close handler must not take a second step for it.
func test_a_field_already_empty_is_left_alone_by_the_close() -> void:
    var button := _blend_button()
    button.toggle_list()
    var popup := button.popup
    var typed: Array[String] = []
    popup.search.text_changed.connect(func(needle: String) -> void: typed.append(needle))
    popup.hide()
    assert_eq(typed.size(), 0, "A list closed on an empty field sends no second emptying")
