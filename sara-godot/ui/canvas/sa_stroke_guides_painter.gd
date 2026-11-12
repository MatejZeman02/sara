## Draws the guides a module holds strokes to, a drawing assistant's rulers,
## over the canvas through `SaStrokeHold`, which knows each holder and its
## geometry. This file knows neither, so a module's guide is drawn without the
## overlay naming it.
##
## A child of the overlay, attached with it by `SaCanvasOverlay.attach_to`. It
## looks once a frame at what the guides are made of and at the zoom, since a
## ruler moved, an undo and a switch of the View menu are signals the overlay
## does not watch, and asks the overlay to redraw when either moved.
class_name SaStrokeGuidesPainter
extends Node

var _canvas: SaCanvas = null
var _overlay: Control = null
var _drawn: Array = []


func _init(canvas: SaCanvas = null, overlay: Control = null) -> void:
    _canvas = canvas
    _overlay = overlay


## Gives *overlay*, over *canvas*, a guides painter.
static func attach_to(canvas: SaCanvas, overlay: SaCanvasOverlay) -> void:
    var painter := SaStrokeGuidesPainter.new(canvas, overlay)
    painter.name = "StrokeGuidesPainter"
    overlay.add_child(painter)
    overlay.add_painter(painter.draw)


func _process(_delta: float) -> void:
    var seen := [_per_pixel(), SaStrokeHold.signature(_canvas.document if _canvas != null else null)]
    if seen != _drawn:
        _drawn = seen
        _overlay.queue_redraw()


func draw(overlay: Control) -> void:
    if _canvas == null or _canvas.document == null:
        return
    SaStrokeHold.draw(_canvas.document, overlay, _per_pixel())


## Document pixels to one on screen.
func _per_pixel() -> float:
    return 1.0 / maxf(absf(_canvas.scale.x), 0.01) if _canvas != null else 1.0
