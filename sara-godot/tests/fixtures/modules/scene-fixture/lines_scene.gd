## The scene of the scene fixture's Lines type: a ground in one colour and a
## line wherever a brush's stroke passed, in the brush's colour and as wide as
## the brush pressed, and the ground again wherever an eraser's passed.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It is the spec's second way of painting onto a scene layer at its smallest,
## a scene that asks for the strokes and decides itself what a stroke means.
## Sara hands it each stroke painted on its layer through [method sara_stroke],
## the press, each motion of the drag and the release, in document pixels with
## the pen's pressure, the brush's radius and its colour, and lays no paint on
## the layer itself. The scene says what it redrew through
## [method sara_dirty_rect], as the Marks scene does. It also defines
## [method sara_pointer], which draws nothing, so a suite can read a tool that
## is not a brush handed the pointer rather than a stroke. Every call is kept
## in [member heard], which is what a suite reads.
##
## It draws through the rendering server at once rather than in `_draw`, for
## the reason the Marks scene gives.
extends Node2D

## The narrowest line it draws, in document pixels, so a stroke at no pressure
## still shows where it went.
const MIN_WIDTH := 1.0

## The ground, set by the layer's parameters. The layer copies the whole
## viewport again after it sets one, so a new ground declares nothing.
@export var ground: Color = Color(0.0, 0.0, 0.0, 1.0):
    set(value):
        ground = value
        _paint()

## Every call Sara made, oldest first, each `{"method": ..., "phase": ...,
## "at": ..., "pressure": ...}`, and a stroke's with its `"radius"` and
## `"color"` as well.
var heard: Array[Dictionary] = []
## Each stroke handed so far, `{"points": Array[Vector3], "radius": float,
## "color": Color}`, a point being `Vector3(x, y, pressure)`.
var strokes: Array[Dictionary] = []
var _dirty: Rect2 = Rect2()


func _ready() -> void:
    _paint()


## What Sara calls for a brush's stroke over this scene's layer. *phase* is
## `&"press"`, `&"drag"` or `&"release"`, *at* the point in document pixels,
## *pressure* the pen's from 0 to 1, *radius* the brush's in document pixels
## and *color* the colour it paints, at alpha 0 for an eraser.
func sara_stroke(phase: StringName, at: Vector2, pressure: float, radius: float, color: Color) -> void:
    heard.append({"method": &"sara_stroke", "phase": phase, "at": at, "pressure": pressure, "radius": radius, "color": color})
    if phase == &"press":
        var points: Array[Vector3] = []
        strokes.append({"points": points, "radius": radius, "color": color})
    if strokes.is_empty():
        return
    var stroke: Dictionary = strokes.back()
    var along: Array[Vector3] = stroke["points"]
    along.append(Vector3(at.x, at.y, pressure))
    # The segment from the point before, grown by the widest half a line has.
    var before := along[maxi(along.size() - 2, 0)]
    var segment := Rect2(Vector2(before.x, before.y), Vector2.ZERO).expand(at).grow(radius + 2.0)
    _dirty = segment if not _dirty.has_area() else _dirty.merge(segment)
    _paint()


## What Sara calls for any other tool's press over this scene's layer. Kept and
## not drawn.
func sara_pointer(phase: StringName, at: Vector2, pressure: float) -> void:
    heard.append({"method": &"sara_pointer", "phase": phase, "at": at, "pressure": pressure})


## What changed since the layer last asked, which it asks once a frame.
func sara_dirty_rect() -> Rect2i:
    if not _dirty.has_area():
        return Rect2i()
    var dirty := Rect2i(Vector2i(_dirty.position.floor()), Vector2i(_dirty.size.ceil()) + Vector2i.ONE)
    _dirty = Rect2()
    return dirty


## How wide a stroke of *radius* draws at *pressure*: the brush's diameter
## scaled by the pressure, as a size curve that follows the pen would.
static func width_at(radius: float, pressure: float) -> float:
    return maxf(MIN_WIDTH, 2.0 * radius * pressure)


func _paint() -> void:
    if not is_inside_tree():
        return
    var item := get_canvas_item()
    RenderingServer.canvas_item_clear(item)
    RenderingServer.canvas_item_add_rect(item, get_viewport_rect(), ground)
    for stroke: Dictionary in strokes:
        var color: Color = stroke["color"]
        var ink := ground if color.a <= 0.0 else color
        var radius: float = stroke["radius"]
        var along: Array[Vector3] = stroke["points"]
        for index in along.size():
            var point := along[index]
            var width := width_at(radius, point.z)
            var at := Vector2(point.x, point.y)
            RenderingServer.canvas_item_add_circle(item, at, width * 0.5, ink)
            if index > 0:
                var before := Vector2(along[index - 1].x, along[index - 1].y)
                RenderingServer.canvas_item_add_line(item, before, at, ink, width)
