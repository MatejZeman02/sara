## The row slot's own height.
##
## A row of the top bar that holds only a slot was zero tall, because a plain
## Control asks for no size, so the bar's panel stopped at the first row and
## the second row's controls hung below it over the canvas. The slot has to
## ask for its content's height, and for no width, because scrolling sideways
## is what it is for.
extends "res://tests/test_framework.gd"


func test_a_slot_is_as_tall_as_its_content_and_no_wider() -> void:
    var slot := SaRowSlot.new()
    var content := Control.new()
    content.custom_minimum_size = Vector2(900, 30)
    slot.add_content(content)
    var minimum := slot.get_combined_minimum_size()
    assert_eq(minimum.y, 30.0, "The slot asks for its content's height")
    assert_eq(minimum.x, 0.0, "and for no width, because the content scrolls")
    slot.free()


func test_an_empty_slot_asks_for_nothing() -> void:
    var slot := SaRowSlot.new()
    assert_eq(slot.get_combined_minimum_size(), Vector2.ZERO, "Nothing inside, nothing asked for")
    slot.free()
