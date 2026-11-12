## A square graph the painter shapes by dragging points, for Curves.
##
## Its own control rather than part of the dialog, because the tablet sweep
## wants the same thing: a monotone curve through a handful of points, a picture
## behind it, and a lookup out of it.
##
## The curve is a monotone cubic through the points (Fritsch and Carlson), not
## a Catmull-Rom. A Catmull-Rom overshoots between two points that are close in
## x and far apart in y, which on a tone curve means a shadow that gets darker
## as the painter drags the point up, and a lookup that is not a function of
## input any more.
##
## Coordinates are 0 to 1 both ways with y up, so the identity is the diagonal
## from the bottom left. The screen flip lives in `_to_screen` alone.
@tool
class_name SaCurveEditor
extends Control

## A point moved, was added or was removed.
signal curve_changed

## How close, in logical pixels, a press has to be to grab a point rather than
## add one.
const GRAB := 10.0

## How far outside the graph a drag has to go before the point is dropped.
const DROP_MARGIN := 12.0

## Points drawn on the curve, in logical pixels.
const POINT_RADIUS := 4.0

## How far past the point's own radius the rim reaches, in logical pixels. A
## second, larger circle drawn behind the point rather than a stroke on it, the
## same halo `cursor_overlay.gd`'s `COLOR_SHADOW` draws behind the cursor arrow
## so it reads over a light panel as well as a dark one.
const POINT_RIM := 1.5

const COLOR_GRID := Color(1.0, 1.0, 1.0, 0.12)
const COLOR_IDENTITY := Color(1.0, 1.0, 1.0, 0.25)
const COLOR_CURVE := Color(1.0, 0.62, 0.2, 1.0)
const COLOR_POINT := Color(1.0, 1.0, 1.0, 0.9)

## How many segments the drawn curve is made of. The lookup is sampled at
## `SAMPLES` whatever this is.
const DRAWN_SEGMENTS := 64

## How many entries a lookup has, which is what a kernel that reads one is built for: the
## base module's `adjust.gmacs` takes 256 per channel. The widget's own number, so the Curves
## filter reads it here and the dependency points at the widget rather than at the engine
## behind it.
const SAMPLES := 256

## The picture behind the curve, usually the layer's histogram. Null draws none.
var histogram: Texture2D = null:
    set(value):
        histogram = value
        queue_redraw()

## The control points, x ascending, both axes 0 to 1. The two ends move in x
## as well as y like any other point, each kept short of its neighbour
## so the curve stays a function of input, and neither can be removed. Below
## the first point's x and above the last's the sampled curve holds that end's
## y, which `SaMonotoneCurve.sample` already does by clamping its segment.
var points: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 1.0)])

var _dragging: int = -1

## The point last pressed, which Delete removes. Minus one when none is, as
## after a release over nothing, a removal, or a reset.
var _picked: int = -1


func _init() -> void:
    custom_minimum_size = Vector2(float(SaUI.px(220)), float(SaUI.px(220)))
    mouse_filter = Control.MOUSE_FILTER_STOP
    # A press takes the focus, so Delete reaches the graph before the key that
    # clears the layer does.
    focus_mode = Control.FOCUS_CLICK
    # Said to the shortcut router, which a docker's window lets see a key before
    # the graph does: Delete is the graph's while it has the focus.
    set_meta(&"keeps_delete", true)


func _ready() -> void:
    # The rim is read from the palette at draw time, so a theme switch has to
    # ask for a redraw the way `_draw` is not otherwise asked for one.
    if not EventBus.theme_changed.is_connected(_on_theme_changed):
        EventBus.theme_changed.connect(_on_theme_changed)


func _on_theme_changed(_theme_id: String) -> void:
    queue_redraw()


## Back to the identity, which is what Reset and a fresh open want.
func reset() -> void:
    points = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 1.0)])
    _dragging = -1
    _picked = -1
    queue_redraw()
    curve_changed.emit()


## Replaces the points, sorted, which is what a test or a scenario hands in.
## The ends keep the x they were given, since a painter may have moved them.
func set_points(wanted: PackedVector2Array) -> void:
    var sorted: Array = []
    for point in wanted:
        sorted.append(Vector2(clampf(point.x, 0.0, 1.0), clampf(point.y, 0.0, 1.0)))
    sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
    points = PackedVector2Array(sorted)
    _picked = -1
    if points.size() < 2:
        reset()
        return
    queue_redraw()
    curve_changed.emit()


## Whether the curve is the diagonal, which is what says the kernel can skip a
## channel's round trip.
func is_identity() -> bool:
    for point in points:
        if absf(point.x - point.y) > 1e-4:
            return false
    return points.size() == 2


## The lookup the kernel reads, *count* entries from x 0 to x 1.
func samples(count: int = SAMPLES) -> PackedFloat32Array:
    return sample_curve(points, count)


## The monotone cubic through *control*, sampled evenly. Static so the maths
## can be checked without a control in a tree. The maths is `SaMonotoneCurve`'s
## in `utils`, since the sensor in the door reads the same curve and `core`
## names nothing under `ui`.
static func sample_curve(control: PackedVector2Array, count: int) -> PackedFloat32Array:
    return SaMonotoneCurve.sample(control, count)


func _to_screen(point: Vector2) -> Vector2:
    return Vector2(point.x * size.x, (1.0 - point.y) * size.y)


func _to_curve(at: Vector2) -> Vector2:
    if size.x <= 0.0 or size.y <= 0.0:
        return Vector2.ZERO
    return Vector2(clampf(at.x / size.x, 0.0, 1.0), clampf(1.0 - at.y / size.y, 0.0, 1.0))


func _draw() -> void:
    if size.x <= 1.0 or size.y <= 1.0:
        return
    if histogram != null:
        draw_texture_rect(histogram, Rect2(Vector2.ZERO, size), false)
    for i in range(1, 4):
        var t := float(i) / 4.0
        draw_line(Vector2(t * size.x, 0.0), Vector2(t * size.x, size.y), COLOR_GRID, 1.0)
        draw_line(Vector2(0.0, t * size.y), Vector2(size.x, t * size.y), COLOR_GRID, 1.0)
    draw_line(Vector2(0.0, size.y), Vector2(size.x, 0.0), COLOR_IDENTITY, 1.0)

    var drawn := sample_curve(points, DRAWN_SEGMENTS)
    var line := PackedVector2Array()
    for i in range(drawn.size()):
        line.append(_to_screen(Vector2(float(i) / float(drawn.size() - 1), drawn[i])))
    draw_polyline(line, COLOR_CURVE, 2.0, true)

    # The rim first and the point over it, so a point at either corner reads
    # against the histogram behind it, white on white and white on black alike.
    # One rim colour from the palette rather than the point's own colour
    # darkened, so the rim answers a theme switch.
    for point in points:
        var at := _to_screen(point)
        draw_circle(at, SaUI.pxf(POINT_RADIUS + POINT_RIM), SaTheme.palette.shadow)
        draw_circle(at, SaUI.pxf(POINT_RADIUS), COLOR_POINT)
    if _picked >= 0 and _picked < points.size():
        var ring := _to_screen(points[_picked])
        draw_arc(ring, SaUI.pxf(POINT_RADIUS + POINT_RIM + 1.0), 0.0, TAU, 24, COLOR_CURVE, 1.5, true)


func _gui_input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            _press(button.position)
        else:
            _dragging = -1
        accept_event()
        return
    if button != null and button.button_index == MOUSE_BUTTON_RIGHT:
        if button.pressed:
            _remove(_point_at(button.position))
        accept_event()
        return
    var key := event as InputEventKey
    if key != null and key.keycode == KEY_DELETE and not key.is_command_or_control_pressed():
        # Accepted whether or not a point is picked, so a Delete the graph
        # was given never falls through to the key that clears the layer.
        if key.pressed and not key.echo:
            _remove(_picked)
        accept_event()
        return
    var motion := event as InputEventMouseMotion
    if motion != null and _dragging >= 0:
        _drag(motion.position)
        accept_event()


## The index of the point nearest *at* within a grab's reach, or minus one.
##
## A press within reach of the graph's left or right edge grabs the end on that
## side while the end still stands on the edge, wherever its y is. An end on a
## corner has three quarters of its reach outside the control, where no press
## arrives, so the corner itself has to count, and a point added at x 0 beside
## an end already there would only sit on top of it.
func _point_at(at: Vector2) -> int:
    var grab := SaUI.pxf(GRAB)
    var nearest := -1
    var best := INF
    for i in range(points.size()):
        var distance := _to_screen(points[i]).distance_to(at)
        if distance <= grab and distance < best:
            nearest = i
            best = distance
    if nearest >= 0:
        return nearest
    var last := points.size() - 1
    if at.x <= grab and _to_screen(points[0]).x <= grab:
        return 0
    if at.x >= size.x - grab and _to_screen(points[last]).x >= size.x - grab:
        return last
    return -1


## Removes the point at *index* if it is an inner one. The two ends have
## nowhere to go, so they are kept.
func _remove(index: int) -> void:
    if index <= 0 or index >= points.size() - 1:
        return
    points.remove_at(index)
    _dragging = -1
    _picked = -1
    queue_redraw()
    curve_changed.emit()


## A press on a point grabs it, and a press anywhere else adds one there and
## grabs that, which is how a curve gets its shape in one gesture.
func _press(at: Vector2) -> void:
    var grabbed := _point_at(at)
    if grabbed >= 0:
        _dragging = grabbed
        _picked = grabbed
        queue_redraw()
        return
    var added := _to_curve(at)
    var index := points.size()
    for i in range(points.size()):
        if added.x < points[i].x:
            index = i
            break
    # Never on the x of a point already there, so the curve stays a function.
    var room := _room_between(index - 1, index)
    added.x = clampf(added.x, room.x, room.y)
    points.insert(index, added)
    _dragging = index
    _picked = index
    queue_redraw()
    curve_changed.emit()


## The press, the motion and the release a hand would give, from *from* to *to*
## in curve units, sent through `_gui_input` so a door step drags the way the
## pen does. A capture reaches a graph inside a window an injected click never
## reaches, and calling this rather than `set_points` is what keeps the step
## honest about what a press at *from* grabs.
func drag_through(from: Vector2, to: Vector2) -> void:
    for event: InputEvent in _drag_events(_to_screen(from), _to_screen(to)):
        _gui_input(event)


static func _drag_events(from: Vector2, to: Vector2) -> Array[InputEvent]:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = from
    var motion := InputEventMouseMotion.new()
    motion.position = to
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = to
    return [press, motion, release]


## A drag off the graph drops the point, unless it is one of the two ends,
## which have nowhere to go and stop at the graph's edge instead. Every point,
## the ends included, is kept short of its neighbours in x.
func _drag(at: Vector2) -> void:
    var last := points.size() - 1
    var outside := (
        at.x < -SaUI.pxf(DROP_MARGIN)
        or at.y < -SaUI.pxf(DROP_MARGIN)
        or at.x > size.x + SaUI.pxf(DROP_MARGIN)
        or at.y > size.y + SaUI.pxf(DROP_MARGIN)
    )
    if outside and _dragging > 0 and _dragging < last:
        _remove(_dragging)
        return

    var moved := _to_curve(at)
    # Kept between its neighbours, or between the edge and its one neighbour
    # for an end, so the points stay in x order and the curve stays a function
    # of input.
    var room := _room_between(_dragging - 1, _dragging + 1)
    moved.x = clampf(moved.x, room.x, room.y)
    points[_dragging] = moved
    queue_redraw()
    curve_changed.emit()


## The x a point may take between the points at *left* and *right*, either of
## which may be past the ends, where the graph's edge stands instead. A point
## stays short of a neighbour by 1e-3, or by a third of the gap when the
## neighbours are closer than that, so the two bounds never cross and a point
## squeezed between near neighbours still lands between them.
func _room_between(left: int, right: int) -> Vector2:
    var has_left := left >= 0
    var has_right := right < points.size()
    var low := points[left].x if has_left else 0.0
    var high := points[right].x if has_right else 1.0
    var margin := minf(1e-3, maxf(high - low, 0.0) / 3.0)
    return Vector2(low + margin if has_left else low, high - margin if has_right else high)
