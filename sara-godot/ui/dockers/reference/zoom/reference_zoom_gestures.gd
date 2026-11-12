## Every way the reference board zooms: the wheel and a touchpad's scroll, the
## quick zoom chord held with a left drag, the zoom in and out chords, and a
## pinch, on a touchpad or with two fingers on a screen.
##
## The note was "there is no way to zoom without scroll wheel while in
## reference docker", so a painter with a pen and no mouse could fit the board
## and nothing else. Each gesture here is the one the canvas zooms with, read
## from the shortcut profile in force, so a painter's own chord works on the
## board too: Ctrl+Space and a drag right or up zooms in about the press, left
## or down out, Ctrl+Equal and Ctrl+Minus step by `STEP`
## about the board's middle, and a pinch zooms about its centre.
##
## A folder of its own beside the view because the docker's folder stood at
## its 2500 lines. The view hands this every event first with its board and its
## size, and builds it with two questions, whether the pointer is on the view
## and what to say when the board moved, which is the view's `changed`, so the
## docker hears of a zoom from here as it hears of the wheel. It names the
## board and never the view, which is the docker's own.
##
## **The zoom chords reach the board through the shortcut command**, because a
## key goes to the window with the focus, which is often the main one while the
## pen hovers a docker. The command asks `step_hovered` before it zooms the
## canvas, and the board under the pointer answers it alone. The maximise asks
## `shares_the_quick_zoom`, because by default it is on Ctrl+Space too, and the
## press of the board's quick zoom must not fill the window with the docker.
class_name ReferenceZoomGestures
extends RefCounted

## The shortcut profile's quick zoom, the canvas's Ctrl+Space by default.
const QUICK_ZOOM: StringName = &"tool_zoom_quick"

## The shortcut profile's docker maximise, which shares the quick zoom's chord.
const MAXIMISE: StringName = &"docker_maximise"

## How fast the drag zooms: a drag as long as the board's shorter side
## multiplies the zoom by e to this power, the canvas zoom tool's sensitivity.
const DRAG_SENSITIVITY: float = 4.0

## What a notch of the wheel and a zoom chord multiply the zoom by, the
## view's `ZOOM_STEP`, which reads it from here.
const STEP: float = 1.15

## The gestures of the board the pointer moved over last, held weakly, which
## `step_hovered` asks whether the pointer is still on it.
static var _over: WeakRef = null

## Whether the pointer is on the view, the view's `inside`.
var _inside: Callable

## Said once the board moved, the view's `changed` with false.
var _moved: Callable

## Whether a key, by its keycode, is down: `Input.is_key_pressed` in Sara, and
## a suite's own answer, which no headless run can hold a key for.
var _key_down: Callable

## The board and the view's size the last event came with, which a chord,
## arriving with neither, zooms.
var _board: SaReferenceBoard = null
var _size: Vector2 = Vector2.ZERO

## The quick zoom drag in flight: where it was pressed, in the view's own
## coordinates, and the zoom the press found.
var dragging: bool = false
var _press_at: Vector2 = Vector2.ZERO
var _start_zoom: float = 1.0

## The touches down on the board, by index, where each is now, and the
## distance between the two when the second landed with the zoom then.
var _touches: Dictionary[int, Vector2] = {}
var _pinch_from: float = 0.0
var _pinch_zoom: float = 1.0


func _init(inside: Callable, moved: Callable, key_down: Callable = Input.is_key_pressed) -> void:
    _inside = inside
    _moved = moved
    _key_down = key_down


## Whether *event* over a view of *size* showing *board* was a zoom, which then
## has moved the board. The view asks this before anything else, so a left
## press with the quick zoom held never reaches the selection box or a
## picture's move.
func input(event: InputEvent, board: SaReferenceBoard, size: Vector2) -> bool:
    _board = board
    _size = size
    if board == null:
        return false
    if event is InputEventMouseMotion:
        _over = weakref(self)
    var moved := SaStep.notches(event).y
    if moved != 0.0:
        _zoom_about(SaStep.where(event, size / 2.0), pow(STEP, -moved))
        return true
    var magnify := event as InputEventMagnifyGesture
    if magnify != null:
        _zoom_about(magnify.position, magnify.factor)
        return true
    if event is InputEventScreenTouch or event is InputEventScreenDrag:
        return _touch(event)
    return _drag(event)


## The board zoomed by *factor* about *at*, a point of the view, and the view
## told when it moved.
func _zoom_about(at: Vector2, factor: float) -> void:
    if _board != null and _board.zoom_about(at, factor):
        _moved.call()


## The quick zoom's left drag: pressed with the chord held, then every motion
## until the lift sets the zoom from the press's, about the press.
func _drag(event: InputEvent) -> bool:
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed and quick_zoom_held(button):
            dragging = true
            _press_at = button.position
            _start_zoom = _board.zoom
            return true
        if not button.pressed and dragging:
            dragging = false
            return true
        return false
    var motion := event as InputEventMouseMotion
    if motion == null or not dragging:
        return false
    _zoom_about(_press_at, drag_zoom(motion.position - _press_at, _size) * _start_zoom / _board.zoom)
    return true


## What a drag of *moved* multiplies the press's zoom by on a board of *size*:
## right and up are in, left and down out, and the two add.
static func drag_zoom(moved: Vector2, size: Vector2) -> float:
    var side := maxf(minf(size.x, size.y), 1.0)
    return exp((moved.x - moved.y) / side * DRAG_SENSITIVITY)


## Whether the quick zoom's chord is held at *button*'s press: its key down
## and every modifier it names on the press, for any chord the profile gives it.
func quick_zoom_held(button: InputEventMouseButton) -> bool:
    for chord in SaShortcutStore.chords_for(QUICK_ZOOM):
        var key := SaShortcutStore.parse_chord(chord)
        if key == null or not _key_down.call(key.keycode):
            continue
        if key.ctrl_pressed and not button.ctrl_pressed:
            continue
        if key.shift_pressed and not button.shift_pressed:
            continue
        if key.alt_pressed and not button.alt_pressed:
            continue
        if key.meta_pressed and not button.meta_pressed:
            continue
        return true
    return false


## Two fingers on the board: the ratio of their distance to the one they
## landed at zooms from the zoom then, about their midpoint. One finger is the
## mouse's, which the engine makes of it, so this leaves it alone.
func _touch(event: InputEvent) -> bool:
    var touch := event as InputEventScreenTouch
    if touch != null:
        if touch.pressed:
            _touches[touch.index] = touch.position
        else:
            _touches.erase(touch.index)
        _pinch_from = _distance()
        _pinch_zoom = _board.zoom
        return _touches.size() >= 2
    var drag := event as InputEventScreenDrag
    if not _touches.has(drag.index):
        return false
    _touches[drag.index] = drag.position
    if _touches.size() < 2 or _pinch_from <= 0.0:
        return false
    var points := _touches.values()
    var middle: Vector2 = (points[0] + points[1]) / 2.0
    _zoom_about(middle, _distance() / _pinch_from * _pinch_zoom / _board.zoom)
    return true


## How far apart the first two touches down are, zero with fewer.
func _distance() -> float:
    if _touches.size() < 2:
        return 0.0
    var points := _touches.values()
    return (points[0] as Vector2).distance_to(points[1])


## The board under the pointer, when there is one, zoomed one step about its
## middle, in for *inward*, which the zoom in and zoom out commands ask before
## they zoom the canvas. True when a board took the chord.
static func step_hovered(inward: bool) -> bool:
    var gestures := hovered()
    if gestures == null:
        return false
    gestures._zoom_about(gestures._size / 2.0, STEP if inward else 1.0 / STEP)
    return true


## The gestures of the reference board the pointer is over now, or null.
static func hovered() -> ReferenceZoomGestures:
    var gestures := _over.get_ref() as ReferenceZoomGestures if _over != null else null
    if gestures == null or gestures._board == null or not gestures._inside.call():
        return null
    return gestures


## Whether the pointer is over a board while the maximise shares a chord with
## the quick zoom, so the maximise stands down and the press is the board's.
static func shares_the_quick_zoom() -> bool:
    if hovered() == null:
        return false
    var quick := SaShortcutStore.chords_for(QUICK_ZOOM)
    for chord in SaShortcutStore.chords_for(MAXIMISE):
        if quick.has(chord):
            return true
    return false
