## The scene the copy's timing suite runs: a paper that moves every frame and
## declares, every time it is asked, that the whole of it changed. So a frame's
## copy is the largest a scene can ask for, every chunk of the canvas.
##
## A band of a second colour steps across the ground at each ask, so the pixels
## the copy carries are new each frame and not a picture copied again. It draws
## through the rendering server at once rather than in `_draw`, for the reason
## the two tone scene beside it gives: `_draw` runs from a deferred call at the
## end of a frame, and a suite runs inside one frame.
extends Node2D

## How far the band steps at each ask, in pixels.
const STEP := 37

## The ground.
@export var color: Color = Color(0.3, 0.5, 0.9, 1.0)
## The band that moves.
@export var band_color: Color = Color(1.0, 0.6, 0.1, 1.0)
## The side of the square, from the top left corner, the scene declares
## changed, and 0 for the whole viewport. The suite narrows it to find the
## rectangle a frame holds.
@export var declared_side: int = 0

## Where the band's left edge is, in pixels.
var _band_x: int = 0


func _ready() -> void:
    _paint()


## The rectangle changed since the layer last asked, which it asks once a
## frame. Asking is what moves the band, so the next drawn frame differs.
func sara_dirty_rect() -> Rect2i:
    var whole := Rect2i(Vector2i.ZERO, Vector2i(get_viewport_rect().size))
    _band_x = (_band_x + STEP) % maxi(whole.size.x, 1)
    _paint()
    if declared_side <= 0:
        return whole
    return whole.intersection(Rect2i(0, 0, declared_side, declared_side))


func _paint() -> void:
    if not is_inside_tree():
        return
    var item := get_canvas_item()
    var area := get_viewport_rect()
    RenderingServer.canvas_item_clear(item)
    RenderingServer.canvas_item_add_rect(item, area, color)
    RenderingServer.canvas_item_add_rect(item, Rect2(float(_band_x), 0.0, area.size.x / 8.0, area.size.y), band_color)
