## A space typed into a list's search is a letter of the search, and never
## a choice.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `SaChoicePopup._input` once sent space with enter to
## `choose_highlighted()`, and `_input` runs before the focused field's
## `gui_input`, so "colour d" typed into the blend list chose Colour Dodge at the
## space and closed the list. A visible field had already been given a visible field the letters
## for the same reason, and space stayed behind with the keys that choose.
##
## Driven through `push_input` on the popup's own window, which is the one path
## that reaches both the popup's `_input` and the focused field after it, so a
## test that reads the needle reads what the painter's key did. Embedded on
## purpose, the way `test_choice_popup.gd` opens a popup: without embedding a
## Window added to the tree maps a real OS window.
extends "res://tests/test_framework.gd"

## Over `SaChoiceSearch.MIN_ROWS`, so the list carries a field.
const LONG_LIST := 25
## Under it, so the list carries none and keeps the keyboard itself.
const SHORT_LIST := 3

var _host: Node = null
var _was_embedding := false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "D77SpaceHost"
    EventBus.add_child(_host)


func after_each() -> void:
    _host.free()
    _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


## A list of *rows* opened under an anchor, with the field focused the way
## `open_under` focuses it, only now rather than deferred.
func _open_list(rows: int, chosen: Array[StringName]) -> SaChoicePopup:
    var anchor := Control.new()
    anchor.size = Vector2(120.0, 24.0)
    _host.add_child(anchor)
    var popup := SaChoicePopup.new()
    popup.one_of = false
    popup.clear()
    popup.add_row(&"colour_dodge", "Colour Dodge")
    popup.add_row(&"colour_burn", "Colour Burn")
    for i in rows - 2:
        popup.add_row(StringName("row_%d" % i), "Row %d" % i)
    popup.chosen.connect(func(id: StringName) -> void: chosen.append(id))
    _host.add_child(popup)
    popup.open_under(anchor)
    if popup.search.visible:
        popup.search.grab_focus()
    return popup


## A real key press: the keycode `_input` matches on and the unicode a `LineEdit`
## inserts, both, because a key from the keyboard carries both.
func _press(popup: SaChoicePopup, keycode: Key, unicode: int = 0) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.unicode = unicode
    event.pressed = true
    popup.push_input(event)


## Letters typed into the field, and then the field's `text_changed`, which a
## `LineEdit` in the tree emits deferred and a test that cannot wait a frame
## sends itself. The text is the field's own, whatever the keys put there.
func _type(popup: SaChoicePopup, text: String) -> void:
    for i in text.length():
        _press(popup, OS.find_keycode_from_string(text[i].to_upper()), text.unicode_at(i))
    popup.search.text_changed.emit(popup.search.text)


func test_a_space_in_the_field_is_a_letter_and_chooses_nothing() -> void:
    var chosen: Array[StringName] = []
    var popup := _open_list(LONG_LIST, chosen)
    assert_true(popup.search.visible, "Twenty-five rows carry a field")
    assert_true(popup.search.has_focus(), "and the field holds the keyboard")

    _type(popup, "colour")
    assert_eq(popup.search.text, "colour", "The letters reach the field")
    assert_eq(popup.highlighted(), &"colour_dodge", "and the keyboard is on the first row left")

    _press(popup, KEY_SPACE, 32)

    assert_true(popup.visible, "A space leaves the list open")
    assert_true(chosen.is_empty(), "and chooses nothing")
    assert_eq(popup.search.text, "colour ", "because the needle took it and ends in the space")

    _type(popup, "b")
    assert_eq(popup.search.text, "colour b", "The painter types on past the space")
    assert_false(popup.is_row_shown(&"colour_dodge"), "and the two words narrow the list")
    assert_eq(popup.highlighted(), &"colour_burn", "to the row that holds both")


func test_enter_in_the_field_still_chooses() -> void:
    var chosen: Array[StringName] = []
    var popup := _open_list(LONG_LIST, chosen)
    _type(popup, "dodge")

    _press(popup, KEY_ENTER)

    assert_eq(chosen, [&"colour_dodge"] as Array[StringName], "Enter chooses the row the field left the keyboard on")
    assert_false(popup.visible, "and closes the list")


func test_a_space_on_a_list_with_no_field_still_chooses() -> void:
    var chosen: Array[StringName] = []
    var popup := _open_list(SHORT_LIST, chosen)
    assert_false(popup.search.visible, "Three rows carry no field")
    popup.move_highlight(1)

    _press(popup, KEY_SPACE, 32)

    assert_eq(chosen, [&"colour_dodge"] as Array[StringName], "A space chooses the highlighted row, the way it always did")
    assert_false(popup.visible, "and closes the list")
