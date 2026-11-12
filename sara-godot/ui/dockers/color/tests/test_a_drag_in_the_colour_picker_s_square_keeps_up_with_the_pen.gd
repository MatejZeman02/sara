## A drag in the Colour Picker's square keeps up with the pen.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Accumulated input is off, so a tablet's every motion reaches the square, and
## each one ran the picker's controls, the store and every listener of
## the foreground. The square now sends the colour the motions of one frame
## reached once, at the frame's end, and a press and a release send theirs at
## once. The picker here is a view, wired to `SaColors` as every picker on
## screen is, and out of the tree, as the other picker suites' are.
extends "res://tests/test_framework.gd"

## How many motions one frame carries here, the row's fifty.
const MOTIONS := 50

var _view: SaColorPickerView
var _was_foreground: Color
var _was_recent: Array[Color] = []
## The process frame of every `foreground_changed` the store sent.
var _heard: Array[int] = []


func before_each() -> void:
    _was_foreground = SaColors.foreground
    _was_recent = SaColors.recent.duplicate()
    _heard.clear()
    _view = SaColorPickerView.new()
    _view.shape.kind = SaPickerShape.Kind.WHEEL
    _view.shape._apply_layout()
    # The side every picker edits is shared, and a suite before this one may
    # have left the background edited.
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    _view.foreground_swatch.gui_input.emit(press)
    SaColors.foreground_changed.connect(_on_foreground_changed)


func after_each() -> void:
    SaColors.foreground_changed.disconnect(_on_foreground_changed)
    _view.free()
    _view = null
    SaColors.foreground = _was_foreground
    SaColors.recent.assign(_was_recent)
    SaColors.save()


func _on_foreground_changed() -> void:
    _heard.append(Engine.get_process_frames())


## A point *across* and *up* of the way over the square, in the frame's pixels.
func _in_square(across: float, up: float) -> Vector2:
    var area := _view.shape.area_rect
    return area.position + Vector2(across * area.size.x, (1.0 - up) * area.size.y)


func _button(at: Vector2, down: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = down
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
    event.position = at
    return event


func _motion(at: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    event.position = at
    return event


## The colour the store's foreground holds, as the square sent it.
func _store_colour() -> String:
    return SaColors.foreground_base.to_html(false)


func test_fifty_motions_in_one_frame_send_one_colour_the_last() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree, for the frame a drag is folded into")
    if tree == null:
        return
    var area := _view.shape.area_rect.size
    assert_true(area.x > 10.0 and area.y > 10.0, "The square is laid out, %s" % area)
    var shape := _view.shape
    shape._on_frame_gui_input(_button(_in_square(0.1, 0.9), true))
    assert_eq(_heard.size(), 1, "A press sets the colour at once, a click with no drag included, %s" % _view.view_report())
    assert_eq(_store_colour(), shape.color().to_html(false), "with the colour under the press")
    await tree.process_frame
    _heard.clear()

    var last := ""
    for i in MOTIONS:
        var t := float(i + 1) / float(MOTIONS)
        shape._on_frame_gui_input(_motion(_in_square(0.1 + 0.8 * t, 0.9 - 0.7 * t)))
        if i == MOTIONS - 1:
            last = shape.color().to_html(false)
    assert_eq(_heard.size(), 0, "No motion sends its colour while the frame's events are read")
    var sent_in := Engine.get_process_frames()
    await tree.process_frame
    assert_eq(_heard.size(), 1, "Fifty motions in one frame send one colour, %s" % [_heard])
    if _heard.size() == 1:
        assert_true(_heard[0] - sent_in <= 1, "in the frame the motions came in, not later")
    assert_eq(_store_colour(), last, "and it is the last motion's colour")

    var release_at := _in_square(0.3, 0.4)
    shape._on_frame_gui_input(_motion(_in_square(0.6, 0.5)))
    shape._on_frame_gui_input(_button(release_at, false))
    var released := shape.color().to_html(false)
    assert_eq(_store_colour(), released, "A release sets the colour at once, what was held back included")
    # A shape of its own, pressed where the release was, says what colour is
    # under that point.
    var probe := SaPickerShape.new()
    probe.kind = SaPickerShape.Kind.WHEEL
    probe._apply_layout()
    probe.hue = shape.hue
    probe._on_frame_gui_input(_button(release_at, true))
    assert_eq(released, probe.color().to_html(false), "and the colour is the one under the release point")
    probe.free()
    _heard.clear()
    await tree.process_frame
    assert_eq(_heard.size(), 0, "Nothing is left to send at the frame's end after a release")


## The profile's costly part: a hidden slider row painted its tracks for every
## colour. It now keeps the colour and draws it when it is shown, so what it
## shows is the same.
func test_a_hidden_slider_row_draws_the_colour_it_was_shown_when_it_is_shown() -> void:
    var hidden := SaPickerSliders.make(SaPickerSliders.Model.OKHSV)
    var shown := SaPickerSliders.make(SaPickerSliders.Model.OKHSV)
    var colour := Color(0.8, 0.3, 0.1)
    hidden.visible = false
    hidden.show_color(colour)
    shown.show_color(colour)
    var before := hidden.sliders[1].track_gradient.colors.duplicate()
    hidden.visible = true
    for i in 3:
        assert_almost_eq(hidden.sliders[i].value, shown.sliders[i].value, 1e-6, "Channel %d reads the colour once shown" % i)
    assert_eq(hidden.sliders[1].track_gradient.colors, shown.sliders[1].track_gradient.colors, "and its track is the colour's")
    assert_true(before != shown.sliders[1].track_gradient.colors, "which it had not painted while hidden")
    hidden.free()
    shown.free()
