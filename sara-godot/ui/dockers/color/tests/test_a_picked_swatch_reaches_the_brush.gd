## A swatch, a recent colour or a typed hex reaches the brush.
##
## The Colour docker forwards the picker's `color_changed` to
## `EventBus.color_picked`, the one road to `SaColors.foreground`, and its
## `color_committed` to the recent row and nothing else. A left click on a kept
## swatch, a click on a recent chip and an Enter in the hex field announced the
## commit only, so the picker drew the new colour while the brush kept painting
## the old one. Each case here drives one of the three and reads what the docker
## listens to.
extends "res://tests/test_framework.gd"

## Whole steps of 255, so the hex field's two digits a channel carry it exactly.
const PICKED := Color8(51, 153, 230)

var _changed: Array[Color] = []
var _committed: Array[Color] = []


func _picker() -> SaColorPicker:
    _changed.clear()
    _committed.clear()
    var picker := SaColorPicker.new()
    picker.color_changed.connect(func(c: Color) -> void: _changed.append(c))
    picker.color_committed.connect(func(c: Color) -> void: _committed.append(c))
    return picker


func _left_press() -> InputEventMouseButton:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    return press


func _assert_reached(picker: SaColorPicker, what: String) -> void:
    assert_eq(_changed.size(), 1, "%s announces the new colour once, the signal the brush follows" % what)
    if not _changed.is_empty():
        assert_true(_changed[0].is_equal_approx(PICKED), "%s announces the colour picked" % what)
    assert_eq(_committed.size(), 1, "%s still joins the recent row once" % what)
    assert_true(picker.color.is_equal_approx(PICKED), "%s shows the colour picked" % what)


func test_a_kept_swatch_reaches_the_brush() -> void:
    var picker := _picker()
    picker.set_swatches([PICKED])
    var chip: Control = picker.palette_row.chips[0]
    chip.gui_input.emit(_left_press())
    _assert_reached(picker, "a swatch")
    picker.free()


func test_a_recent_chip_reaches_the_brush() -> void:
    var picker := _picker()
    picker.set_recent([PICKED])
    var chip := picker.recent_flow.get_child(0) as Control
    chip.gui_input.emit(_left_press())
    _assert_reached(picker, "a recent chip")
    picker.free()


func test_a_typed_hex_reaches_the_brush() -> void:
    var picker := _picker()
    picker.hex_input.text_submitted.emit("#" + PICKED.to_html(false))
    _assert_reached(picker, "a hex")
    picker.free()


func test_a_hex_that_is_not_a_colour_announces_nothing() -> void:
    var picker := _picker()
    picker.hex_input.text_submitted.emit("not a colour")
    assert_eq(_changed.size(), 0, "a hex that reads as no colour moves nothing")
    assert_eq(_committed.size(), 0, "and joins nothing to the recent row")
    picker.free()
