## Draws the line of the active effect layer over the canvas, with its two
## handles, in the symmetry axes' manner.
##
## It is a painter handed to `SaCanvasOverlay` from here, outside `ui/canvas`,
## so the overlay's file does not grow. The geometry is `SaEffectGuide`'s and
## the press that drags it is `MainCanvas`'s, which asks the same class. A
## child of the overlay's canvas, it looks once a frame at what the line is made
## of and asks the overlay to redraw when that moved, since neither an undo nor
## a change of the active layer is a signal the overlay watches.
class_name SaEffectGuidePainter
extends Node

## The line's colour, a cyan that tells it from the symmetry axes' orange.
const GUIDE_COLOR := Color(0.2, 0.8, 0.9, 0.85)
## A handle's radius in screen pixels at every zoom, as the axes' handles are.
const HANDLE_RADIUS: float = 5.0

var _canvas: SaCanvas = null
var _overlay: Control = null
var _drawn: Array = []


func _init(canvas: SaCanvas = null, overlay: Control = null) -> void:
    _canvas = canvas
    _overlay = overlay


## Gives *canvas*'s overlay a guide painter. Registered with the canvas through
## `SaCanvas.add_overlay_factory` after the overlay's own, which it finds by
## name.
static func attach_to(canvas: SaCanvas) -> void:
    var overlay := canvas.get_node_or_null("CanvasOverlay") as SaCanvasOverlay
    if overlay == null:
        return
    var painter := SaEffectGuidePainter.new(canvas, overlay)
    painter.name = "EffectGuidePainter"
    overlay.add_child(painter)
    overlay.add_painter(painter.draw)


func _process(_delta: float) -> void:
    var seen := _signature()
    if seen != _drawn:
        _drawn = seen
        _overlay.queue_redraw()


## The line and its handles, as hairlines and two discs the same size on screen
## at every zoom.
func draw(overlay: Control) -> void:
    var guide := _guide()
    if guide == null:
        return
    var drawn := guide.segment()
    if drawn.size() == 2:
        overlay.draw_line(drawn[0], drawn[1], GUIDE_COLOR, -1.0)
    var per_pixel := 1.0 / maxf(absf(_canvas.scale.x), 0.01)
    for handle in guide.handles():
        overlay.draw_circle(handle, HANDLE_RADIUS * per_pixel, Color(0.0, 0.0, 0.0, 0.6), true, -1.0, true)
        overlay.draw_circle(handle, (HANDLE_RADIUS - 1.5) * per_pixel, Color(GUIDE_COLOR, 1.0), true, -1.0, true)


func _guide() -> SaEffectGuide:
    if _canvas == null or _canvas.document == null or _canvas.compositor == null:
        return null
    return SaEffectGuide.of(_canvas.document, _canvas.compositor.filter_chain.registry)


## What the drawing depends on: the line's point and angle and the canvas's
## size, empty while no line is shown.
func _signature() -> Array:
    var guide := _guide()
    if guide == null:
        return []
    return [guide.point(), guide.angle(), _canvas.document.canvas_size]
