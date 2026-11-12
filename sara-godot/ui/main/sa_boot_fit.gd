## The boot's fit, taken again once the window and the top bar have their sizes.
##
## The main canvas fits its document in its own `_ready`, which runs before `ui/`
## has built the top bar and before the compositor has handed the window its real
## size. So the boot measured a window at the 1920 by 1080 of `project.godot` with
## nothing over it, where a zoom of one fits the default document exactly, the
## window then settled at 1048, and the canvas's resize handler moved the pan by
## half the difference. The top 110 rows of the document were under a bar ending
## at 94, at every interface scale.
##
## The fit is held rather than delayed, because nothing says when the boot is
## over. Every change to the viewport's size, to a cover's size or to a docker's
## size or visibility fits the document again into what the covers leave and
## between the dockers, until the view has been moved by
## anything else or a mouse button has been pressed in the window. Either means
## the painter has started, and from then on a resize keeps the view where they
## left it, which is what `SaCanvas._on_viewport_resized` is for. A time limit,
## the way the docker layout tells a settled window from a settling one, was the
## other way to end it and is not used: a boot on a loaded machine can settle
## after any limit short enough to stay out of a painter's way.
##
## The dockers are the view's side covers, found in their group when this joins
## the tree rather than handed in, because the boot has built every one of them
## by then and `Main` names only the two covers it built itself. A docker the
## layout moves without a resize moves with the viewport's own size change,
## which this already answers, and the fit that answers it runs at the end of
## the frame, after the layout has placed them all.
class_name SaBootFit
extends Node

## How far the canvas may be from where the hold expects it and still count as
## untouched, in logical units. The resize handler adds half of every change one
## at a time in float32, and the sum of those drifts from half the whole change
## by far less than this, while no pan a hand makes is this small.
const SLACK: float = 0.01

var _canvas: SaCanvas
var _view: SaView
var _covers: Array[Control] = []
## The dockers, the side covers in the view's group when this joined the tree.
var _sides: Array[Window] = []
var _window: Window

## Whether a size change still fits the document again. False for good once the
## view has moved under something else or a button was pressed.
var _held: bool = true
## A fit is already waiting for the end of the frame, so a burst of size changes
## costs one.
var _queued: bool = false

## Where the last fit left the canvas and the viewport it measured, which is how
## a view nobody else has touched is told from one that moved.
var _fitted_scale: Vector2 = Vector2.ZERO
var _fitted_position: Vector2 = Vector2.ZERO
var _fitted_viewport: Vector2 = Vector2.ZERO


## *view* is the one the canvas's tools move, so a fit announces itself to them.
## *covers* are the controls whose size decides what the fit leaves room for, and
## *window* is where a press ends the hold, null when nothing should.
func _init(canvas: SaCanvas, view: SaView, covers: Array[Control], window: Window) -> void:
    name = "BootFit"
    _canvas = canvas
    _view = view
    _covers = covers
    _window = window


func _ready() -> void:
    if _canvas == null or _view == null or not _canvas.is_inside_tree():
        _held = false
        return
    _remember()
    _canvas.get_viewport().size_changed.connect(_queue_fit)
    for cover in _covers:
        cover.resized.connect(_queue_fit)
    for node in get_tree().get_nodes_in_group(SaCanvasView.SIDE_COVER_GROUP):
        var side := node as Window
        if side != null:
            _sides.append(side)
            side.size_changed.connect(_queue_fit)
            side.visibility_changed.connect(_queue_fit)
    if _window != null:
        _window.window_input.connect(_on_window_input)
    # The bar may have had its size before this node joined the tree.
    _queue_fit()


## Shows the document again the way it opens, `SaView.reset`, in what the
## covers leave between the dockers, unless the hold has ended or the view is not
## where the last fit left it. Public so a test can run the fit a size
## change queues without awaiting a frame.
func fit_again() -> void:
    _queued = false
    if not _held or not is_instance_valid(_canvas) or not _canvas.is_inside_tree():
        return
    if not _untouched():
        release()
        return
    _view.reset(_canvas.canvas_size)
    _remember()


## Ends the hold. A size change after this is the resize handler's alone.
func release() -> void:
    if not _held:
        return
    _held = false
    if is_instance_valid(_canvas) and _canvas.is_inside_tree():
        var viewport := _canvas.get_viewport()
        if viewport.size_changed.is_connected(_queue_fit):
            viewport.size_changed.disconnect(_queue_fit)
    for cover in _covers:
        if is_instance_valid(cover) and cover.resized.is_connected(_queue_fit):
            cover.resized.disconnect(_queue_fit)
    for side in _sides:
        if is_instance_valid(side) and side.size_changed.is_connected(_queue_fit):
            side.size_changed.disconnect(_queue_fit)
            side.visibility_changed.disconnect(_queue_fit)
    if is_instance_valid(_window) and _window.window_input.is_connected(_on_window_input):
        _window.window_input.disconnect(_on_window_input)


func _queue_fit() -> void:
    if not _held or _queued:
        return
    _queued = true
    fit_again.call_deferred()


func _remember() -> void:
    _fitted_scale = _canvas.scale
    _fitted_position = _canvas.position
    _fitted_viewport = _canvas.get_viewport().get_visible_rect().size


## The canvas is where the last fit put it, moved only by the resize handler's
## half of every change in the viewport's size since.
func _untouched() -> bool:
    var viewport := _canvas.get_viewport().get_visible_rect().size
    var expected := _fitted_position + (viewport - _fitted_viewport) * 0.5
    return _canvas.scale.is_equal_approx(_fitted_scale) and _canvas.position.distance_to(expected) < SLACK


func _on_window_input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    if button != null and button.pressed:
        release()
