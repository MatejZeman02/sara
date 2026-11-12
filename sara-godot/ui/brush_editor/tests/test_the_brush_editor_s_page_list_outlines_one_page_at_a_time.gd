## The brush editor's page list outlines one page at a time.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A row that kept the focus beside the open one read as two pages picked.
## The open row is drawn unflat, its box and its border, and a flat row draws
## nothing but the focus box, so a row is outlined when it is the open one or
## when it holds a focus that is shown. That is what [method _outlined] reads,
## rather than a picture, because a headless run draws nothing.
##
## The list is built alone inside a viewport of its own under the `EventBus`
## autoload, so nothing another suite left in the root can take a press meant
## for it, and a click is a real press and release pushed into that viewport,
## so the focus moves the way a painter's hand moves it.
extends "res://tests/test_framework.gd"

const PAGES: Array = [
    {"title": "General"},
    {"title": "Texture"},
    {"title": "Look"},
    {"title": "Opacity", "dynamic": true, "switch": true, "on": false},
]
const GENERAL := 0
const TEXTURE := 1
const LOOK := 2

var _viewport: SubViewport = null
var _list: SaBrushEditorPageList = null


func before_each() -> void:
    _viewport = SubViewport.new()
    _viewport.size = Vector2i(320, 480)
    EventBus.add_child(_viewport)
    _list = SaBrushEditorPageList.new()
    _list.size = Vector2(320.0, 480.0)
    _viewport.add_child(_list)
    _list.build(PAGES)
    # The window's own wiring, which opens the page a row's press names.
    _list.page_selected.connect(_list.select)
    _list.select(GENERAL)
    _sort(_list)
    _sort(_list)


func after_each() -> void:
    if _viewport != null:
        _viewport.free()
    _viewport = null
    _list = null


static func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort(child)


func _button(index: int) -> Button:
    return _list._rows[index]["button"] as Button


## Whether the row at *index* is drawn with a box round it: unflat, which is
## the open row's, or holding a focus the viewport shows.
func _outlined(index: int) -> bool:
    var button := _button(index)
    return not button.flat or button.has_focus(true)


func _outlined_rows() -> Array:
    var out: Array = []
    for i in _list.page_count():
        if _outlined(i):
            out.append(_list.title_at(i))
    return out


## A real press and release at the middle of the row, after a motion over it.
func _click(index: int) -> void:
    var at := _button(index).get_global_rect().get_center()
    var over := InputEventMouseMotion.new()
    over.position = at
    over.global_position = at
    _viewport.push_input(over)
    for pressed: bool in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
        event.position = at
        event.global_position = at
        _viewport.push_input(event)


func _key(keycode: Key) -> void:
    for pressed: bool in [true, false]:
        var event := InputEventKey.new()
        event.keycode = keycode
        event.physical_keycode = keycode
        event.pressed = pressed
        _viewport.push_input(event)


## The row's Done line: General and then Look clicked, and Look alone drawn
## with an outline.
func test_general_then_look_clicked_outlines_look_alone() -> void:
    _click(GENERAL)
    assert_eq(_list.selected, GENERAL, "The press on General opens General")
    _click(LOOK)
    assert_eq(_list.selected, LOOK, "and the press on Look opens Look")
    assert_eq(_outlined_rows(), ["Look"], "and Look is the one row drawn with an outline")


## The case that matters most. General holds a focus that is shown, which is the
## keyboard's or a grab's, and Look is opened without a press on its row, the
## way the door's page step opens it. General must not keep its box.
func test_a_page_opened_while_another_row_shows_focus_outlines_the_open_one_alone() -> void:
    _button(GENERAL).grab_focus()
    assert_true(_button(GENERAL).has_focus(true), "General holds a focus that is drawn")
    _list.select(LOOK)
    assert_eq(_outlined_rows(), ["Look"], "Opening Look leaves Look the one row with an outline")
    assert_true(_button(LOOK).has_focus(true), "because the focus went with the page, shown as it was")


## A focus a press gave is hidden, and moving it keeps it hidden, so a click
## followed by a page the door opens never shows a box a click would not.
func test_a_hidden_focus_moves_hidden() -> void:
    _click(TEXTURE)
    assert_true(_button(TEXTURE).has_focus() and not _button(TEXTURE).has_focus(true), "A press gives Texture a hidden focus")
    _list.select(LOOK)
    assert_true(_button(LOOK).has_focus(), "Opening Look hands the focus to Look")
    assert_false(_button(LOOK).has_focus(true), "still hidden")
    assert_eq(_outlined_rows(), ["Look"], "and Look alone is outlined")


## The keyboard's focus is still reachable and shown: a key moves it to the
## next row, which is outlined because that is where the keyboard is, and
## Enter opens it, leaving one outline again.
func test_the_keyboard_still_reaches_a_row_and_shows_where_it_is() -> void:
    _click(GENERAL)
    _key(KEY_DOWN)
    assert_true(_button(TEXTURE).has_focus(true), "Down takes a shown focus to Texture")
    assert_eq(_outlined_rows(), ["General", "Texture"], "outlined beside the open page while the keyboard walks the list")
    _key(KEY_ENTER)
    assert_eq(_list.selected, TEXTURE, "Enter opens Texture")
    assert_eq(_outlined_rows(), ["Texture"], "and one row is outlined again")


## A focus on something that is not a row is the painter's and stays put.
func test_a_focus_outside_the_rows_is_left_where_it_is() -> void:
    var field := LineEdit.new()
    _viewport.add_child(field)
    field.grab_focus()
    _list.select(LOOK)
    assert_true(field.has_focus(), "A field that holds the focus keeps it when a page opens")
    assert_eq(_outlined_rows(), ["Look"], "and only the open row is outlined")
