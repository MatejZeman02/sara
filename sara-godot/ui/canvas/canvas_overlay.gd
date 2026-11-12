## What is drawn over the canvas and is not paint: the symmetry axes and their
## handles today, marching ants when a selection needs them.
##
## A child of the canvas view, so it inherits the view's zoom, pan and
## rotation and draws in document pixels. Painters register a Callable that
## takes this control and draws with it, so a later feature adds its own
## without editing this file, and the overlay redraws when the document it
## watches announces a change.
class_name SaCanvasOverlay
extends Control

## The axes' colour, an orange that reads over paint of most colours.
const AXIS_COLOR := Color(1.0, 0.55, 0.1, 0.8)
## How large a symmetry handle is drawn, in screen pixels at every zoom. The
## press `MainCanvas` takes for one reaches a little further.
const HANDLE_RADIUS: float = 5.0

var _canvas: SaCanvas = null
var _painters: Array[Callable] = []
var _watched: SaSymmetry = null
## The zoom the handles were last drawn at, since a zoom moves no setter.
var _drawn_zoom: float = 0.0


## The canvas is a constructor argument rather than an assignment, because a
## class writes its own members only. Defaulted so that `.new()` still works the
## way Godot expects of a Control.
func _init(canvas: SaCanvas = null) -> void:
    _canvas = canvas


## Makes an overlay over *canvas*, with the symmetry axes as its first painter.
static func attach_to(canvas: SaCanvas) -> SaCanvasOverlay:
    var overlay := SaCanvasOverlay.new(canvas)
    overlay.name = "CanvasOverlay"
    overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(overlay)
    overlay.add_painter(overlay.draw_symmetry_axes)
    SaStrokeGuidesPainter.attach_to(canvas, overlay)
    # The selection's ants and the quick mask, a sibling with its own material.
    SaSelectionOverlay.attach_to(canvas)
    # The grid, a sibling for the same reason: it watches the setting.
    SaGridOverlay.attach_to(canvas)
    return overlay


## Adds a painter, called with this overlay on every redraw.
func add_painter(painter: Callable) -> void:
    if not _painters.has(painter):
        _painters.append(painter)
    queue_redraw()


func _process(_delta: float) -> void:
    # The document can change under the view (File > New, Open), and so can its
    # symmetry object. Cheap: one comparison a frame.
    var symmetry: SaSymmetry = _canvas.document.symmetry if _canvas != null and _canvas.document != null else null
    if symmetry != _watched:
        if _watched != null and _watched.changed.is_connected(queue_redraw):
            _watched.changed.disconnect(queue_redraw)
        _watched = symmetry
        if _watched != null:
            _watched.changed.connect(queue_redraw)
        queue_redraw()
    # The handles are drawn in screen pixels, so a zoom redraws them.
    var zoom := absf(_canvas.scale.x) if _canvas != null else 0.0
    if zoom != _drawn_zoom:
        _drawn_zoom = zoom
        queue_redraw()


func _draw() -> void:
    for painter in _painters:
        painter.call(self)


## The axes, as hairlines, so they stay one pixel at any zoom, and the two
## handles a drag moves them by, the same size on screen at every zoom.
func draw_symmetry_axes(overlay: Control) -> void:
    if _canvas == null or _canvas.document == null:
        return
    var symmetry := _canvas.document.symmetry
    if not symmetry.is_active():
        return
    var canvas_size := Vector2(_canvas.document.canvas_size)
    for line in symmetry.axes(canvas_size):
        overlay.draw_line(line[0], line[1], AXIS_COLOR, -1.0)
    var per_pixel := 1.0 / maxf(absf(_canvas.scale.x), 0.01)
    for handle in symmetry.handles():
        overlay.draw_circle(handle, HANDLE_RADIUS * per_pixel, Color(0.0, 0.0, 0.0, 0.6), true, -1.0, true)
        overlay.draw_circle(handle, (HANDLE_RADIUS - 1.5) * per_pixel, Color(AXIS_COLOR, 1.0), true, -1.0, true)
