## The scene the scene layer's suite shows: the whole viewport in one colour,
## which is the parameter a layer sets, and a band in another that the suite
## moves to see the copy follow only the rectangle the scene declares.
##
## It draws through the rendering server at once rather than in `_draw`,
## because `_draw` runs from a deferred call at the end of a frame and a suite
## runs inside one frame, so a scene drawn there would stay blank.
extends Node2D

## The ground, set by the layer's parameters.
@export var color: Color = Color(0.0, 0.0, 0.0, 1.0):
    set(value):
        color = value
        _paint()

var _band: Rect2i = Rect2i()
var _band_color: Color = Color(1.0, 0.0, 0.0, 1.0)
var _dirty: Rect2i = Rect2i()


func _ready() -> void:
    _paint()


## Draws a band of *band_color* over *rect* and declares it changed.
func paint_band(rect: Rect2i, band_color: Color) -> void:
    _band = rect
    _band_color = band_color
    _dirty = rect
    _paint()


## What changed since the layer last asked, which it asks once a frame.
func sara_dirty_rect() -> Rect2i:
    var dirty := _dirty
    _dirty = Rect2i()
    return dirty


func _paint() -> void:
    if not is_inside_tree():
        return
    var item := get_canvas_item()
    RenderingServer.canvas_item_clear(item)
    RenderingServer.canvas_item_add_rect(item, get_viewport_rect(), color)
    if _band.has_area():
        RenderingServer.canvas_item_add_rect(item, Rect2(_band), _band_color)
