## A ramp with handles under it: the black-to-white bar the input and
## output handles of Levels are dragged along.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Positions are 0 to 1 along the ramp, and the bar knows nothing about what a
## position means. The one handle it treats apart is the derived one, the grey,
## which is kept between its neighbours while the others may pass over where it
## stands, because the panel puts it back from the gamma after every move.
##
## A control of its own rather than an inner class of the Levels filter,
## which lives in this module.
class_name SaLevelsBar
extends Control

## The handle *key* is under the pointer at *position*.
signal handle_dragged(key: String, position: float)

## The ramp's height, the handle's height and half its width, in logical
## units, and how far a press may be from a handle and still take it.
const RAMP_HEIGHT := 14.0
const HANDLE_HEIGHT := 11.0
const HANDLE_HALF := 6.0
const GRAB := 10.0

## How far in from either edge the ramp starts, in logical units: half a
## handle and a little, so a handle at 0 or 1 is drawn whole.
const INSET := 8

## How close two handles may come. Not zero, or the input span is zero and
## the kernel divides by it.
const GAP := 0.004

## How many greys the ramp is sampled at.
const STOPS := 32

## The handle colours, black, mid grey and white, which is what each one
## stands for on the ramp.
const HANDLE_COLORS := {
    "in_black": Color(0.0, 0.0, 0.0, 1.0),
    "gamma": Color(0.5, 0.5, 0.5, 1.0),
    "in_white": Color(1.0, 1.0, 1.0, 1.0),
    "out_black": Color(0.0, 0.0, 0.0, 1.0),
    "out_white": Color(1.0, 1.0, 1.0, 1.0),
}

## The handle keys left to right.
var keys: Array = []
## Key -> 0 to 1 along the ramp.
var positions: Dictionary = {}

var _derived: String = ""
var _ramp: GradientTexture1D = null
var _dragging: String = ""


## *bar_name* is the node name, *handle_keys* the keys left to right, and
## *derived_key* the one the panel computes, or empty.
func _init(bar_name: String, handle_keys: Array, derived_key: String) -> void:
    name = bar_name
    keys = handle_keys
    _derived = derived_key
    for key: String in keys:
        positions[key] = 0.0
    custom_minimum_size = Vector2(0.0, SaUI.pxf(RAMP_HEIGHT + HANDLE_HEIGHT + 2.0))
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var gradient := Gradient.new()
    var offsets := PackedFloat32Array()
    var colors := PackedColorArray()
    for i in STOPS:
        var t := float(i) / float(STOPS - 1)
        offsets.append(t)
        colors.append(Color(t, t, t, 1.0))
    gradient.offsets = offsets
    gradient.colors = colors
    _ramp = GradientTexture1D.new()
    _ramp.gradient = gradient
    _ramp.width = 256


func has_handle(key: String) -> bool:
    return keys.has(key)


## Moves the handles to *wanted* without a signal, which is how the panel
## pushes its fields down.
func set_positions(wanted: Dictionary) -> void:
    for key: String in wanted:
        if keys.has(key):
            positions[key] = clampf(float(wanted[key]), 0.0, 1.0)
    queue_redraw()


## Takes *key* and moves it to *target* through the same motion and release
## a pointer makes, so a scenario's drag ends where a painter's would.
func drag_to(key: String, target: float) -> void:
    if not keys.has(key):
        return
    _dragging = key
    _drag(_x_of(clampf(target, 0.0, 1.0)))
    _dragging = ""


func _draw() -> void:
    if size.x <= 1.0:
        return
    var ramp := Rect2(_x_of(0.0), 0.0, _x_of(1.0) - _x_of(0.0), SaUI.pxf(RAMP_HEIGHT))
    draw_texture_rect(_ramp, ramp, false)
    draw_rect(ramp, SaTheme.palette.border_secondary, false, 1.0)
    for key: String in keys:
        _draw_handle(_x_of(float(positions[key])), HANDLE_COLORS.get(key, Color.GRAY))


## A triangle pointing up at the ramp, with a rim from the palette so a
## black handle reads on the ramp's black end and a white one on its
## white end.
func _draw_handle(x: float, fill: Color) -> void:
    var top := SaUI.pxf(RAMP_HEIGHT)
    var half := SaUI.pxf(HANDLE_HALF)
    var bottom := top + SaUI.pxf(HANDLE_HEIGHT)
    var rim := SaUI.pxf(1.5)
    var outer := PackedVector2Array(
        [Vector2(x, top - rim), Vector2(x + half + rim, bottom + rim), Vector2(x - half - rim, bottom + rim)]
    )
    draw_colored_polygon(outer, SaTheme.palette.border_selected)
    var inner := PackedVector2Array([Vector2(x, top), Vector2(x + half, bottom), Vector2(x - half, bottom)])
    draw_colored_polygon(inner, fill)


func _gui_input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            _dragging = _nearest(button.position.x)
            if _dragging != "":
                _drag(button.position.x)
        else:
            _dragging = ""
        accept_event()
        return
    var motion := event as InputEventMouseMotion
    if motion != null and _dragging != "":
        _drag(motion.position.x)
        accept_event()


## The handle within reach of *x*, the nearest when two are, and none
## when the press is on the ramp away from every handle.
func _nearest(x: float) -> String:
    var best := ""
    var best_distance := SaUI.pxf(GRAB)
    for key: String in keys:
        var distance := absf(_x_of(float(positions[key])) - x)
        if distance <= best_distance:
            best = key
            best_distance = distance
    return best


## Moves the dragged handle to *x*, held between the handles it may not
## pass: the derived one stays between its neighbours, and the others
## stay in order among themselves.
func _drag(x: float) -> void:
    var wanted := _position_of(x)
    var index := keys.find(_dragging)
    var lower := 0.0
    var upper := 1.0
    for i in range(index - 1, -1, -1):
        var key: String = keys[i]
        if _dragging == _derived or key != _derived:
            lower = float(positions[key]) + GAP
            break
    for i in range(index + 1, keys.size()):
        var key: String = keys[i]
        if _dragging == _derived or key != _derived:
            upper = float(positions[key]) - GAP
            break
    positions[_dragging] = clampf(wanted, lower, upper)
    queue_redraw()
    handle_dragged.emit(_dragging, float(positions[_dragging]))


func _x_of(at: float) -> float:
    var inset := SaUI.pxf(float(INSET))
    return inset + at * maxf(0.0, size.x - 2.0 * inset)


func _position_of(x: float) -> float:
    var inset := SaUI.pxf(float(INSET))
    var span := maxf(1.0, size.x - 2.0 * inset)
    return clampf((x - inset) / span, 0.0, 1.0)
