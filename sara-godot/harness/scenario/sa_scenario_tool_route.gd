## The `"route": "tool"` of a `stroke`: each frame's event handed straight to
## the main canvas's tool machine, under any docker and off the view.
##
## A stroke on the default route is real input. It is placed in the window,
## the window's GUI hit-tests it, and an embedded docker over the point takes
## the press, so the step could say that a docker had swallowed the stroke and
## a client could answer only by moving the docker or the view. A point off
## the view has no window point to press at all. This route skips the window,
## the hit test and `MainCanvas._owns_point`, and hands every event to
## `ToolMachine.handle_input` in the canvas control's own coordinates, which
## is where every route into the brush ends. The view is never moved, so a
## point off screen is painted where the document has it.
##
## **The event's position is not what the brush paints at.** `StateBrush`
## reads its point from `SaCursorPolicy.pointer_in`, which answers from the
## pen's last place while a pen moves the pointer and from the display server
## otherwise. So each event is noted with the cursor package first, the way
## `CursorOverlay._input` notes every event the window receives. A motion is
## then noted again as a press at the same place, because the package keeps a
## press's place whatever device it thinks made it, and it takes a motion that
## opens at exactly 1.0 with no tilt for a mouse's made-up pressure and would
## hand the brush the display server's pointer, which a point off the window
## cannot be.
##
## Reached by path from the stroke rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaScenarioToolRoute
extends RefCounted

## The run, by path like every other harness file this one names.
const CaptureRun := preload("res://harness/sa_capture_run.gd")
## The driver whose button events a `press` step sends, so a route's press is
## the same event the default route's is before it is placed.
const InputDriver := preload("res://harness/drivers/sa_input_driver.gd")

## Real input through the window, the default, because
## real input is what proves the painter's path.
const INPUT := "input"
## Straight to the main canvas's tool machine.
const TOOL := "tool"

## The four events a frame of this route hands over.
const HOVER := "hover"
const PRESS := "press"
const MOTION := "motion"
const RELEASE := "release"
## How many steps of its last bit [method exact_root] moves a root point each
## way. One left a point of the 200 at zoom 0.61 a texel off, two left none.
const EXACT_STEPS := 3

## The run whose tree holds the canvas this paints on.
var _run: CaptureRun = null
## The last point handed over in root units, for a motion's `relative`.
var _last: Vector2 = Vector2.ZERO
## The button the stroke holds between its press and its release, as a mask a
## motion reports.
var _held_mask: int = 0


func _init(run: CaptureRun) -> void:
    _run = run


## The steps a stroke on this route runs, one a frame as the default route's:
## the hover that primes the brush, the press, one motion per waypoint after
## the first and the release, each a `{"stroke": {"tool_event": ...}}`. *path*
## is the waypoints in *space* as written, so each frame maps its point through
## the view as it stands then. With *rate* the motions are left to the paced
## step and only the hover and the press are returned.
static func frames(path: Array, space: String, button: String, rate: float) -> Array:
    var first := path[0] as Dictionary
    var out: Array = [_frame(HOVER, first, space, button), _frame(PRESS, first, space, button)]
    if rate > 0.0:
        return out
    for i in range(1, path.size()):
        out.append(_frame(MOTION, path[i] as Dictionary, space, button))
    out.append(_frame(RELEASE, path[path.size() - 1] as Dictionary, space, button))
    return out


## The release a paced stroke on this route ends with.
static func release_frame(path: Array, space: String, button: String) -> Dictionary:
    return _frame(RELEASE, path[path.size() - 1] as Dictionary, space, button)


## One frame's step, the event [method event_spec] describes.
static func _frame(event: String, waypoint: Dictionary, space: String, button: String) -> Dictionary:
    return {"stroke": {"tool_event": event_spec(event, waypoint, space, button)}}


## The waypoint with what this route needs to hand it over as *event*, which is
## what [method hand] takes.
static func event_spec(event: String, waypoint: Dictionary, space: String, button: String) -> Dictionary:
    var spec := waypoint.duplicate()
    spec["event"] = event
    spec["space"] = space
    spec["button"] = button
    return spec


## Hands one event of a stroke to the main canvas's tool machine: `{"stroke":
## {"tool_event": {"event": "press", "at": [x, y], "space": "document",
## "pressure": 0.8, "tilt": [0, 0], "button": "left"}}}`. The `stroke` step
## writes these itself for `"route": "tool"`, and a scenario never needs to.
func hand(spec: Dictionary) -> void:
    var canvas := tool_canvas()
    if canvas == null:
        push_warning("SaCapture: no canvas with a tool machine in the root window for a stroke on the tool route")
        return
    var control := canvas.get_parent() as Control
    var at := root_point(spec, canvas)
    var event := event_of(spec, at, _last, _held_mask)
    if event == null:
        push_warning("SaCapture: a tool route event is 'hover', 'press', 'motion' or 'release', not '%s'" % spec.get("event"))
        return
    var kind := String(spec.get("event", ""))
    if kind == PRESS:
        _held_mask = (event as InputEventMouseButton).button_mask
    elif kind == RELEASE:
        _held_mask = 0
    _last = at

    var window := canvas.get_window()
    SaCursorPolicy.note_pointer_device(event, window)
    if event is InputEventMouseMotion:
        SaCursorPolicy.note_pointer_device(place_of(at), window)
    canvas.tool_machine().handle_input(event.xformed_by(control.get_global_transform().affine_inverse()))


## The front surface's canvas when it can take a tool event, or null: a
## machine of its own to hand it to and a Control parent whose transform the
## event is carried through. A canvas that has neither has no tool to paint
## with, as `active_tool_name` says of the same pair.
##
## The first canvas in the root window with a machine would not do: once a
## second document opens, every tab stands in the root window too, so only the
## front surface picks one out.
static func tool_canvas() -> SaCanvas:
    var canvas := SaCanvasView.front_canvas()
    var takes_events := canvas != null and canvas.tool_machine() != null and canvas.get_parent() is Control
    return canvas if takes_events else null


## Where *spec*'s point lands in root units: carried through *canvas*'s
## transform as it stands for a document point, and as written otherwise.
static func root_point(spec: Dictionary, canvas: CanvasItem) -> Vector2:
    var coords := spec.get("at", [0.0, 0.0]) as Array
    var at := Vector2(float(coords[0]), float(coords[1]))
    if String(spec.get("space", "window")) == "document":
        return exact_root(at, canvas.get_global_transform_with_canvas())
    return at


## The root point *view* carries back to exactly *at*, a point in document
## pixels, so the brush paints at the point as given.
##
## **The brush reads its point back through the view.** `SaPointerDevice`
## carries the pen's place in the window into the canvas through the inverse of
## *view*, and in float32 the way there and back lost a hair: 99 of 200 integer
## points came back as 284.9999 or 543.9999 at zoom 0.61 and 28 at zoom 1, and
## a dab under 3 px across, which takes the texel under its point by `floor`,
## landed one texel left or up. So the nearest root point is moved a few
## steps of its last bit until the inverse gives *at* back. Where no step does,
## the one that comes back closest in *at*'s own texel is kept, and the nearest
## point when none is in it, which is the answer this route always gave.
static func exact_root(at: Vector2, view: Transform2D) -> Vector2:
    var nearest := view * at
    var back := view.affine_inverse()
    var step := Vector2(_last_bit(nearest.x), _last_bit(nearest.y))
    var best := nearest
    var best_miss := INF
    for i in range(-EXACT_STEPS, EXACT_STEPS + 1):
        for j in range(-EXACT_STEPS, EXACT_STEPS + 1):
            var root := Vector2(nearest.x + i * step.x, nearest.y + j * step.y)
            var lands := back * root
            if lands == at:
                return root
            var miss := lands.distance_to(at)
            if lands.floor() == at.floor() and miss < best_miss:
                best = root
                best_miss = miss
    return best


## One step of the last bit of a float32 near *value*, which is how far apart
## the root points a Vector2 can hold stand there.
static func _last_bit(value: float) -> float:
    var size := absf(value)
    if size < 1e-30:
        return 1e-38
    return pow(2.0, floorf(log(size) / log(2.0)) - 23.0)


## The event *spec* describes at *at* in root units, as the window would have
## received it, or null for a kind this route does not know. *last* is the
## point before it and *held* the buttons down, both for a motion.
static func event_of(spec: Dictionary, at: Vector2, last: Vector2, held: int) -> InputEventMouse:
    var kind := String(spec.get("event", ""))
    var which := String(spec.get("button", "left"))
    if kind == PRESS or kind == RELEASE:
        var button := InputDriver.button_event({}, which, kind == PRESS)
        if kind == PRESS:
            button.button_mask = (1 << (button.button_index - 1)) as MouseButtonMask
        button.position = at
        button.global_position = at
        return button
    if kind != HOVER and kind != MOTION:
        return null
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.global_position = at
    motion.relative = at - last if kind == MOTION else Vector2.ZERO
    motion.pressure = float(spec.get("pressure", 0.0))
    var tilt := spec.get("tilt", [0.0, 0.0]) as Array
    motion.tilt = Vector2(float(tilt[0]), float(tilt[1])) if tilt != null and tilt.size() >= 2 else Vector2.ZERO
    motion.pen_inverted = bool(spec.get("inverted", false))
    if kind == MOTION:
        motion.button_mask = held as MouseButtonMask
    return motion


## A left press at *at*, which is how the cursor package is told where the
## pointer is whatever device it takes a motion for. Noted only, never sent.
static func place_of(at: Vector2) -> InputEventMouseButton:
    var place := InputEventMouseButton.new()
    place.button_index = MOUSE_BUTTON_LEFT
    place.pressed = true
    place.position = at
    place.global_position = at
    return place
