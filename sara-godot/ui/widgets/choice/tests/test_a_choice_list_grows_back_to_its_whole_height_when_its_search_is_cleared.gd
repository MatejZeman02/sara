## A choice list grows back to its whole height when its search
## is cleared.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The top bar's blend list stayed open under an empty field with no rows, the
## window as short as the field, after its search was cleared. A search hid rows
## and set no size, so the window kept whatever height it had been left at. Every
## search now asks `SaPopupRect.refit` for the height its rows want under the
## anchor the list opened under.
##
## The field is emptied three ways and nothing says which, so each is a
## test: backspace to empty, the field's clear button, and escape. The keys and
## the click are pushed into the list's own window, the way `test_space_in_a_search.gd`
## types, so each reaches the field through the path a hand's does.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A real `Window` goes in the tree.
const REQUIRES_GPU := true
## A needle no blend mode holds, in any language the list's second names carry.
const NO_MATCH := "qqx"

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
    EventBus.add_child(_host)


func after_each() -> void:
    _host.free()
    _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


## The top bar's blend list opened under its button, with the field holding the
## keyboard the way `open_under` hands it over, only now rather than deferred.
func _open_blend_list() -> SaChoicePopup:
    var button := BlendModeButton.new()
    button.registry = Fixtures.make_registries().blend_modes
    button.refresh()
    button.size = Vector2(160.0, 28.0)
    _host.add_child(button)
    button.toggle_list()
    var popup := button.popup
    if popup.search.visible:
        popup.search.grab_focus()
    return popup


func _press(popup: SaChoicePopup, keycode: Key, unicode: int = 0) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.unicode = unicode
    event.pressed = true
    popup.push_input(event)


## The field's `text_changed` follows the keys deferred in a tree, so the test,
## which cannot wait a frame, sends it the way the field would.
func _settle(popup: SaChoicePopup) -> void:
    popup.search.text_changed.emit(popup.search.text)


## Types *NO_MATCH* and reads that the list is down to its field, which says the
## window follows its rows on the way down as well as back up, and then leaves
## the window at the field's height, the photo's state.
func _search_for_nothing(popup: SaChoicePopup, opened: int) -> void:
    for i in NO_MATCH.length():
        _press(popup, OS.find_keycode_from_string(NO_MATCH[i].to_upper()), NO_MATCH.unicode_at(i))
    _settle(popup)
    assert_eq(popup.search.text, NO_MATCH, "The letters reach the field")
    assert_eq(popup.row_ids().filter(popup.is_row_shown).size(), 0, "and leave no row")
    assert_true(popup.size.y < opened, "so the window shrinks to the field")
    # Where a painter's screen left it, as short as the field, whatever the
    # engine did on the way. Without this a window that never moved would pass
    # the reads below on a build that does not fit anything.
    popup.size = Vector2i(popup.size.x, int(popup.search.size.y))


func test_the_list_opens_with_a_field_and_rows_to_hide() -> void:
    var popup := _open_blend_list()
    assert_true(popup.visible, "The blend list opens")
    assert_true(popup.search.visible, "with a field over it")
    assert_true(popup.search.has_focus(), "which holds the keyboard")
    assert_true(popup.size.y > popup.search.size.y * 3, "and opens at the height its rows want")


func test_backspace_to_empty_brings_back_the_whole_height() -> void:
    var popup := _open_blend_list()
    var opened := popup.size.y
    _search_for_nothing(popup, opened)

    for _i in NO_MATCH.length():
        _press(popup, KEY_BACKSPACE)
    _settle(popup)

    assert_eq(popup.search.text, "", "Backspace empties the field")
    assert_true(popup.visible, "and the list stays open")
    assert_eq(popup.size.y, opened, "at the height it opened at")


func test_the_clear_button_brings_back_the_whole_height() -> void:
    var popup := _open_blend_list()
    var opened := popup.size.y
    _search_for_nothing(popup, opened)

    # The clear button is drawn at the field's right end, inside its padding, so
    # a click just in from that edge and halfway down presses it.
    var field := popup.search.get_global_rect()
    var at := Vector2(field.end.x - 6.0, field.get_center().y)
    for pressed: bool in [true, false]:
        var click := InputEventMouseButton.new()
        click.button_index = MOUSE_BUTTON_LEFT
        click.position = at
        click.global_position = at
        click.pressed = pressed
        popup.push_input(click)
    _settle(popup)

    assert_eq(popup.search.text, "", "The clear button empties the field")
    assert_true(popup.visible, "and the list stays open")
    assert_eq(popup.size.y, opened, "at the height it opened at")


## Escape empties the field and the engine closes the popup on the same key,
## which `_on_popup_hidden` puts back a frame later at the rectangle the list had
## when the field was emptied. That rectangle is the window's own, so its height
## is read here, before the frame the suite cannot wait for.
func test_escape_brings_back_the_whole_height() -> void:
    var popup := _open_blend_list()
    var opened := popup.size.y
    _search_for_nothing(popup, opened)

    _press(popup, KEY_ESCAPE)

    assert_eq(popup.search.text, "", "Escape empties the field")
    assert_eq(popup.size.y, opened, "and the list is put back at the height it opened at")
