## The grid over the canvas: a hairline every so many document pixels, switched
## from View > Toggle Grid and surviving a launch.
##
## A sibling of `selection_overlay.gd` rather than a painter on
## `canvas_overlay.gd`, for the same reason the selection is one: it watches
## something of its own, the setting, and a painter has no place to keep that
## subscription. A child of the canvas view like both of them, so it draws in
## document pixels and follows the zoom, the pan and the rotation without
## computing any of them.
##
## **One screen pixel at every zoom** comes from `draw_line`'s negative width,
## which is Godot's hairline: the line is rasterised a pixel wide whatever the
## transform above it says. `canvas_overlay.gd` draws the symmetry axes the same
## way. What a hairline cannot fix is spacing: 64 document pixels is 0.64 screen
## pixels at one per cent zoom, and a grid whose lines are closer together than
## they are wide is a grey fill. So the step doubles until it is worth drawing,
## which is what keeps the grid a grid rather than a wash.
##
## **The spacing the doubling starts from is a setting**, `SaSettings.grid_size`,
## because a pixel painter wants a line on every document pixel and this file's
## constant gave them a cell 64 across. The doubling is untouched by that: it is
## the readability floor, so a one-pixel grid zoomed out draws a coarser grid
## rather than a grey field, and at one per cent zoom, the lowest Sara allows,
## one document pixel doubles ten times to 1024 and still has its eight screen
## pixels.
class_name SaGridOverlay
extends Control

## The grid's step in document pixels at a zoom where it needs no doubling, for
## a caller that names no size of its own. `SaSettings.grid_size` is what the
## overlay itself asks, and this is its default.
const BASE_STEP: int = SaSettings.DEFAULT_GRID_SIZE

## The least a step may be on screen before it is doubled, in screen pixels.
## Below eight the lines start to read as a texture rather than as a grid, and
## a hairline is one pixel of the eight.
const MIN_SCREEN_STEP: float = 8.0

## How many doublings are allowed before the grid gives up and draws nothing.
## Twelve takes the step from 64 to 262144 document pixels, past any document
## Sara can hold, so the loop cannot run away on a zoom of zero.
const MAX_DOUBLINGS: int = 12

var _canvas: SaCanvas = null
## What the last redraw was drawn for, so `_process` asks two cheap questions a
## frame rather than redrawing every one of them. Nothing announces a zoom, and
## the setting announces only when it is written.
var _shown_step: float = 0.0
var _shown_on: bool = false


## The canvas is a constructor argument rather than an assignment, because a
## class writes its own members only. Defaulted so that `.new()` still works the
## way Godot expects of a Control.
func _init(canvas: SaCanvas = null) -> void:
    _canvas = canvas


static func attach_to(canvas: SaCanvas) -> SaGridOverlay:
    var overlay := SaGridOverlay.new(canvas)
    overlay.name = "GridOverlay"
    overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(overlay)
    return overlay


func _process(_delta: float) -> void:
    var on := SaSettings.show_grid
    var step := _step_for(_zoom())
    if on == _shown_on and is_equal_approx(step, _shown_step):
        return
    _shown_on = on
    _shown_step = step
    queue_redraw()


func _draw() -> void:
    if not SaSettings.show_grid or _canvas == null or _canvas.document == null:
        return
    var document_size := Vector2(_canvas.document.canvas_size)
    if document_size.x <= 0.0 or document_size.y <= 0.0:
        return
    var step := _step_for(_zoom())
    if step <= 0.0:
        return
    # Drawn over the document rectangle and no further. A grid that ran to the
    # viewport edges would be drawing over the background beyond the document,
    # where there is nothing for it to measure.
    var color := Color(1.0, 1.0, 1.0, 0.18)
    var at := step
    while at < document_size.x:
        draw_line(Vector2(at, 0.0), Vector2(at, document_size.y), color, -1.0)
        at += step
    at = step
    while at < document_size.y:
        draw_line(Vector2(0.0, at), Vector2(document_size.x, at), color, -1.0)
        at += step


## The step in document pixels the grid draws at *zoom*: *grid_size*, doubled
## until it is at least `MIN_SCREEN_STEP` on screen. Static and taking both so a
## test can ask it at any size without a canvas or a settings write.
##
## Named `grid_size` rather than `size` because `Control` already has a `size`
## and the editor warns over the shadow.
static func step_for_zoom(zoom: float, grid_size: int = BASE_STEP) -> float:
    if zoom <= 0.0:
        return 0.0
    var step := float(maxi(grid_size, SaSettings.MIN_GRID_SIZE))
    var doublings := 0
    while step * zoom < MIN_SCREEN_STEP and doublings < MAX_DOUBLINGS:
        step *= 2.0
        doublings += 1
    return step if step * zoom >= MIN_SCREEN_STEP else 0.0


func _step_for(zoom: float) -> float:
    return step_for_zoom(zoom, SaSettings.grid_size)


func _zoom() -> float:
    if _canvas == null or not is_instance_valid(_canvas):
        return 0.0
    return SaCanvasView.for_canvas(_canvas).get_zoom()


## What the grid is drawing, for a capture: whether it is on, the size it was
## asked for, the step it chose and the zoom it chose at. A screenshot says the
## grid is there and cannot say it did not thicken, which is the half worth
## measuring, nor which size it started from.
static func capture_state(root: Window) -> Dictionary:
    var overlay: SaGridOverlay = null
    for node in root.find_children("GridOverlay", "Control", true, false):
        var found := node as SaGridOverlay
        if found != null and found._canvas != null and found._canvas.get_window() == root:
            overlay = found
            break
    if overlay == null:
        return {}
    var zoom := overlay._zoom()
    var grid_size := SaSettings.grid_size
    return {
        "on": SaSettings.show_grid,
        "zoom": zoom,
        # What was asked for, beside what the doubling made of it. The two differ
        # wherever the zoom is too far out for the size, and a shot of a grid
        # cannot say which of the two it is looking at.
        "size_document": grid_size,
        "step_document": step_for_zoom(zoom, grid_size),
        "step_screen": step_for_zoom(zoom, grid_size) * zoom,
    }
