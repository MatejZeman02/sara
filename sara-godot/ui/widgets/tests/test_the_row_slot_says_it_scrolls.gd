## A row of the top bar that scrolls says so.
##
## With the menu titles back at the interface's font size, a 1280 window
## has 450 logical pixels of first row for 740 of controls, and Opacity, Flow and
## Edit Brush sit past the edge of the slot. The layout is kept
## and a sign is drawn: an arrow at the edge whenever the slot overflows, so
## the controls are hidden only to someone who does not look.
##
## **In the tree, not detached.** A `Range` emits `changed` and `value_changed`
## only while it is inside the tree, so a detached slot's scroll bar moves and its
## fades never hear of it: the first run of this file had the bar at 900 over a
## page of 200 and both arrows down. The slots go under a host on `EventBus`, the
## way `test_cursor_modes.gd` keeps its windows. A `ScrollContainer` still
## sizes its scroll bar only when it sorts its children, which is queued for a
## frame this suite never runs, so `_sort` sends the notification by hand.
extends "res://tests/test_framework.gd"

var _host: Node = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "RowSlotSignTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func _sort(slot: SaRowSlot, width: float) -> void:
    slot.size = Vector2(width, 30.0)
    slot.scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)


## A slot *width* wide over content *content_width* wide.
func _slot(width: float, content_width: float) -> SaRowSlot:
    var slot := SaRowSlot.new()
    var content := Control.new()
    content.custom_minimum_size = Vector2(content_width, 30.0)
    slot.add_content(content)
    _host.add_child(slot)
    _sort(slot, width)
    return slot


func _arrow(slot: SaRowSlot, on_left: bool) -> Control:
    return (slot._fade_left if on_left else slot._fade_right).get_node("Arrow") as Control


func _press(button: MouseButton, pressed: bool = true) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = button
    event.pressed = pressed
    event.factor = 1.0
    return event


func test_a_slot_that_fits_shows_no_arrow() -> void:
    var slot := _slot(200.0, 150.0)
    assert_false(slot._fade_left.visible, "Nothing is past the left edge of a slot that fits")
    assert_false(slot._fade_right.visible, "and nothing is past the right edge either")


func test_a_slot_with_more_to_the_right_shows_the_right_arrow_only() -> void:
    var slot := _slot(200.0, 900.0)
    var bar := slot.scroll.get_h_scroll_bar()
    assert_eq([bar.max_value, bar.page], [900.0, 200.0], "The sort gave the scroll bar the content and the slot's widths")
    assert_true(slot._fade_right.visible, "Controls past the right edge put the arrow there")
    assert_false(slot._fade_left.visible, "and a slot at its start has nothing past the left")
    var arrow := _arrow(slot, false)
    assert_true(arrow.visible, "The arrow is shown with its fade rather than beside it")
    assert_eq(arrow.mouse_filter, Control.MOUSE_FILTER_STOP, "and takes a press rather than handing it to the control beneath")


func test_scrolled_to_the_end_the_arrow_moves_to_the_left() -> void:
    var slot := _slot(200.0, 900.0)
    var bar := slot.scroll.get_h_scroll_bar()
    bar.value = bar.max_value
    assert_true(slot._fade_left.visible, "Scrolled to the end, the controls it passed are to the left")
    assert_false(slot._fade_right.visible, "and nothing is left past the right edge")


func test_a_press_on_an_arrow_scrolls_a_page_towards_it() -> void:
    var slot := _slot(200.0, 900.0)
    var bar := slot.scroll.get_h_scroll_bar()
    _arrow(slot, false).gui_input.emit(_press(MOUSE_BUTTON_LEFT))
    var page := 200.0 - float(SaUI.px(SaRowSlot.FADE_WIDTH))
    assert_almost_eq(bar.value, page, 0.5, "A press on the right arrow scrolls what the slot shows less the fade")
    assert_true(slot._fade_left.visible, "and the left arrow comes up for what it scrolled past")
    _arrow(slot, true).gui_input.emit(_press(MOUSE_BUTTON_LEFT))
    assert_almost_eq(bar.value, 0.0, 0.5, "A press on the left arrow scrolls back")
    _arrow(slot, false).gui_input.emit(_press(MOUSE_BUTTON_LEFT, false))
    assert_almost_eq(bar.value, 0.0, 0.5, "A release scrolls nothing, so one click is one page")


func test_the_wheel_over_an_arrow_still_scrolls_the_row() -> void:
    var slot := _slot(200.0, 900.0)
    var bar := slot.scroll.get_h_scroll_bar()
    _arrow(slot, false).gui_input.emit(_press(MOUSE_BUTTON_WHEEL_DOWN))
    assert_almost_eq(bar.value, bar.page / 8.0, 0.5, "A notch over the arrow moves the row as it does anywhere else on it")


func test_the_bars_row_report_carries_the_sign() -> void:
    var bar := TopMenuBar.new()
    _host.add_child(bar)
    var slot := bar.rows.brush_options_slot as SaRowSlot
    var content := Control.new()
    content.custom_minimum_size = Vector2(740.0, 30.0)
    slot.add_content(content)
    _sort(slot, 450.0)
    var narrow: Dictionary = bar.rows.row_report(1)["sign"]
    assert_eq(narrow, {"left": false, "right": true}, "A first row of 450 holding 740 reports its right arrow")
    _sort(slot, 1090.0)
    var wide: Dictionary = bar.rows.row_report(1)["sign"]
    assert_eq(wide, {"left": false, "right": false}, "and one of 1090 reports none")
