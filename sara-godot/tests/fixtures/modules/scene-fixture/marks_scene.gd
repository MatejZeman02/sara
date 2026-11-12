## The scene of the scene fixture's Marks type: a ground in one colour and a
## disc wherever the pen pressed, larger the harder it pressed.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It is what a student's playable canvas is at its smallest. Sara hands it a
## press, each motion of the drag after it and the release through
## [method sara_pointer], in document pixels with the pen's pressure, while its
## layer is the active one and the tool in hand is not a navigation tool, and
## it says what it redrew through [method sara_dirty_rect] so the layer copies
## that and nothing else. Every call is kept in [member heard], which is what a
## suite reads.
##
## It draws through the rendering server at once rather than in `_draw`, as the
## two tone scene of the scene layer's own suite does, because `_draw` runs from
## a deferred call at the end of a frame and a press handed in mid frame would
## show a frame late.
extends Node2D

## The disc's radius in document pixels at no pressure, and what full pressure
## adds to it.
const RADIUS := 6.0
const RADIUS_PER_PRESSURE := 14.0
## The mark's colour, bright against the ground.
const MARK := Color(1.0, 0.55, 0.1, 1.0)

## The ground, set by the layer's parameters. The layer copies the whole
## viewport again after it sets one, so a new ground declares nothing.
@export var ground: Color = Color(0.0, 0.0, 0.0, 1.0):
    set(value):
        ground = value
        _paint()

## Every call Sara made, oldest first, each `{"phase": ..., "at": ..., "pressure": ...}`.
var heard: Array[Dictionary] = []
## Where the last press landed and how hard, in document pixels.
var pressed_at: Vector2 = Vector2(-1.0, -1.0)
var pressed_with: float = 0.0
## Each press, `Vector3(x, y, pressure)`, which is what the discs are drawn from.
var _marks: Array[Vector3] = []
var _dirty: Rect2 = Rect2()


func _ready() -> void:
    _paint()


## What Sara calls for the pointer over this scene's layer. *phase* is
## `&"press"`, `&"drag"` or `&"release"`, *at* the point in document pixels and
## *pressure* the pen's, from 0 to 1, and a mouse's 1.
func sara_pointer(phase: StringName, at: Vector2, pressure: float) -> void:
    heard.append({"phase": phase, "at": at, "pressure": pressure})
    if phase != &"press":
        return
    pressed_at = at
    pressed_with = pressure
    _marks.append(Vector3(at.x, at.y, pressure))
    var reach := RADIUS + RADIUS_PER_PRESSURE * pressure + 1.0
    var disc := Rect2(at - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
    _dirty = disc if not _dirty.has_area() else _dirty.merge(disc)
    _paint()


## What changed since the layer last asked, which it asks once a frame.
func sara_dirty_rect() -> Rect2i:
    if not _dirty.has_area():
        return Rect2i()
    var dirty := Rect2i(Vector2i(_dirty.position.floor()), Vector2i(_dirty.size.ceil()) + Vector2i.ONE)
    _dirty = Rect2()
    return dirty


func _paint() -> void:
    if not is_inside_tree():
        return
    var item := get_canvas_item()
    RenderingServer.canvas_item_clear(item)
    RenderingServer.canvas_item_add_rect(item, get_viewport_rect(), ground)
    for mark: Vector3 in _marks:
        RenderingServer.canvas_item_add_circle(item, Vector2(mark.x, mark.y), RADIUS + RADIUS_PER_PRESSURE * mark.z, MARK)
