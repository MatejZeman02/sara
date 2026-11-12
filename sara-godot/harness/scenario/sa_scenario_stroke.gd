## One straight stroke, expanded into the frames it takes, and the verdict on
## whether any of it reached the GPU.
##
## The only step that makes the canvas itself change, and the only one that
## rewrites the scenario it is running: a stroke is not a thing that happens
## inside one frame, so it splices one move per frame into the runner's own step
## list and appends a report of itself behind them.
##
## **Its own class because a stroke is its own question.** What it costs to say
## whether a stroke painted is four functions of measurement, the windows over
## every point of the gesture, the press cover, the clause that names it and the
## clause that says a docker moved out from under it. None of that is input
## injection, and all of it is one concern: did the gesture land.
##
## Reached by path from the runner rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaScenarioStroke
extends RefCounted

## The run, by path like every other harness file this one names.
const CaptureRun := preload("res://harness/sa_capture_run.gd")
## The driver a stroke at a pen's own rate sends its bursts through.
const InputDriver := preload("res://harness/drivers/sa_input_driver.gd")
## The writer of the brush colour, the one the `colour` step goes through.
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")
## The frame a stroke's points are written in when it names none, and the frame
## the older scenarios in the tree were written in.
const SPACE_WINDOW := "window"
## Document pixels, mapped through the view as it stands when the step runs.
const SPACE_DOCUMENT := "document"
## The route past the window to the tool machine, by path for the reason the
## run is.
const ToolRoute := preload("res://harness/scenario/sa_scenario_tool_route.gd")
## The stabiliser held off for a stroke that asks for none, by path as well.
const Smoothing := preload("res://harness/scenario/smoothing/sa_stroke_smoothing.gd")
## The harness pen's own sample spacing in root logical units, how far apart a
## straight stroke's samples land when it names no `steps`. Twenty-five is the
## spacing at which a stroke of 400 units takes [constant MOST_STEPS] frames,
## so a long stroke takes the most and a dash of a few units takes one frame.
const SAMPLE_SPACING := 25.0
## The most frames a straight stroke with no `steps` takes.
const MOST_STEPS := 16

## The two shapes a stroke is written in, which a stroke of neither is refused with.
const SHAPES := '{"from": [x, y], "to": [x, y]}, or {"points": [{"at": [x, y]}, {"at": [x, y]}, ...]}'
## What the loud line says a docker's press has as a way round, the same words
## the stroke's own argument is written in, so a client can paste it.
const WAY_ROUND := '. A stroke with "route": "tool" goes under any docker and paints'

## The dabs a stroke laid and their texels, the end of its line, by path for
## the reason the run is.
const DabsLaid := preload("res://harness/scenario/sa_scenario_dabs_laid.gd")
## What the stroke left on its layer, the largest alpha it laid.
const AlphaLaid := preload("res://harness/scenario/sa_scenario_alpha_laid.gd")

## The run whose steps this splices into and whose tree it measures.
var _run: CaptureRun = null
## The step table's own input driver, null where a suite builds this alone, and
## then a stroke at a pen's rate says it cannot be sent.
var _input: InputDriver = null
## What hands a stroke on the tool route to the main canvas's tool machine.
var _route: ToolRoute = null


func _init(run: CaptureRun, input: InputDriver = null) -> void:
    _run = run
    _input = input
    _route = ToolRoute.new(run)


## Paints one stroke: smoothed as a hand's is, or through its points as given
## with `"smoothing": false`. The only step that makes the canvas itself change.
##
## **Arguments.**
## - `from` array, `[x, y]`.
## - `to` array, `[x, y]`.
## - `points` array, `{"at": [x, y], "pressure": p}` each.
## - `pressure` number, 0 to 1.
## - `space` string, `document`.
## - `route` string, `tool` goes under dockers.
## - `colour` string or array, set at the press.
##
## `{"stroke": {"from": [x, y], "to": [x, y], "pressure": 0.8}}`
## is the straight line this step began as, one pressure and one tilt over the
## whole of it. With no `"steps"` it takes a frame for every
## [constant SAMPLE_SPACING] of its length in root units, at least one and at
## most [constant MOST_STEPS], so a dash of a few pixels takes one frame and a
## stroke of 400 units or more sixteen, because a scenario of thousands of
## dashes at sixteen frames each runs for longer than anyone waits. A
## `"steps": n` given still wins. And
## `{"stroke": {"points": [{"at": [x, y], "pressure": p, "tilt": [x, y]}, ...]}}`
## is the hand's own shape: every waypoint carries its own pressure and its own
## tilt. Either form in root logical units by default, or with
## `"space": "document"` in document pixels, mapped through the view by
## [method to_root]. The waypoints are how a scenario writes the bend of a
## stroke and the pen leaning through one, so a pressure ramp or a tilt sensor
## is painted rather than reasoned about. Both forms come out of
## [method _path_of] as one list of moves, and there is one expansion below.
##
## Three things have to be true at once before a scenario can paint, and every one
## of them looks like a working brush from the outside while it is missing:
##
## 1. The press has to land on the canvas. It takes its position from the step
##    rather than from the real pointer, which Wayland will not let a client
##    move, so a press read off the pointer lands wherever the hand is.
## 2. The motion has to reach the tool. An injected motion is never delivered to a
##    Control's `gui_input`, so a hover reaches nothing, whatever its coordinates.
##    It *is* delivered once the press opens a stroke, because MainCanvas._input
##    captures motion for the duration and hands it to the ToolMachine directly.
## 3. The motion has to carry pressure. StateBrush treats a pointer as a tablet
##    until eleven consecutive zero-pressure motions say otherwise, and a tablet
##    stroke at zero pressure paints a full-size dab at zero alpha. That is the
##    quiet one: the History count goes up, the canvas does not change, and nothing
##    anywhere reports a problem.
##
## Because of 2, the hover that would have primed the brush does not arrive,
## and the stroke does not fade in for it, because a pen's press dab waits for
## the first motion's pressure: the press end of a stroke reads the same alpha
## on this route as on the tool route below, which does send the hover.
##
## The step reports what the stroke did, not what it was asked for. It expands
## into one move per frame and then a verdict of its own, carrying the GPU
## dispatch count read here, so the line printed at the end is a before-and-after
## across the frames the stroke really took, rather than the request, which
## reads the same when an embedded docker sits over the point the press aimed
## at.
##
## The verdict is written as another `stroke` rather than as a step kind of its
## own, because a scenario that replays a run has to see the same vocabulary
## going in that came out, and a private kind the executor writes to itself
## would not be in the catalogue `scripts/sara_steps.py` reads.
##
## **`"rate"` sends the stroke at a pen's own rate** rather than one move a
## frame: `{"stroke": {"from": [x, y], "to": [x, y], "steps": 240, "rate": 240}}`
## is a pen reporting 240 times a second for one second. Each frame sends, as one
## burst, every report the pen would have sent since the frame before, so a slow
## frame is followed by a heap of motions and the work they ask for, which is the
## loop a painter's hand drives and a frame-paced stroke cannot. The verdict's
## frame count is then the frames it really took.
##
## **`"route": "tool"` goes straight to the brush**, under a docker and off the
## view: `{"stroke": {"route": "tool", "space": "document", "from": [700, 540],
## "to": [1800, 540]}}`. [SaScenarioToolRoute] hands each frame's event to the
## main canvas's tool machine rather than sending it through the window, so no
## docker can take the press, and a point off the view is painted where the
## document has it with the view left where it stands. The frames are this
## route's, a priming hover, the press, a motion per waypoint and the release,
## and `rate` paces them the same way. Its line opens "by the tool route" and
## names what the stroke went under as a fact, never as a failure.
## **`"colour"` is the stroke's own colour**, in the forms the `colour` step
## takes: `{"stroke": {"from": [x, y], "to": [x, y], "colour": "#4080c0"}}`. It is
## applied in the frame the step runs, before the press, so it costs no frame of
## its own and a stroke in a new colour is one step rather than two. The brush
## keeps it afterwards, as a painter's picked colour stays, and the verdict
## names it. An array of strokes each naming a colour is one request.
##
## A stroke on the input route whose press point is under a docker, of either
## kind, is not sent at all: the step prints the loud line and raises the error
## and nothing moves, because the docker would take the press as a hand's and a
## press on a Layers row's eye would hide a layer.
## `"route": "input"` is the default, because real input is what proves the
## painter's path. The other is there so that a client can paint and `look`
## without Tab, a pan or a zoom.
func stroke(spec: Dictionary) -> void:
    if spec.has("report"):
        _report_stroke(spec["report"] as Dictionary)
        return
    if spec.has("paced"):
        _pace(spec["paced"] as Dictionary)
        return
    if spec.has("tool_event"):
        _route.hand(spec["tool_event"] as Dictionary)
        return

    var space := String(spec.get("space", SPACE_WINDOW))
    var route := String(spec.get("route", ToolRoute.INPUT))
    # Asked before the path is filled in, because a straight stroke's frames
    # follow its length in root units, which a document stroke has only
    # through the view. Its refusal waits below, after the shape's.
    # The front surface's canvas whatever it holds, because a point in document
    # pixels is carried through the view's transform and a view has one before
    # a picture is loaded into it.
    var canvas: SaCanvas = null
    if space == SPACE_DOCUMENT:
        canvas = SaCanvasView.front_canvas()
        if route == ToolRoute.TOOL:
            canvas = ToolRoute.tool_canvas()
    var view := canvas.get_global_transform_with_canvas() if canvas != null else Transform2D.IDENTITY
    var path := _path_of(spec, view)
    if path.is_empty():
        return
    var written := _points_of(path)
    if route != ToolRoute.INPUT and route != ToolRoute.TOOL:
        push_warning("SaCapture: a stroke's 'route' is 'input' or 'tool', not '%s'" % route)
        return
    var as_written := path
    if space == SPACE_DOCUMENT:
        if canvas == null:
            push_warning("SaCapture: no canvas in the root window for a stroke in document pixels")
            return
        path = to_root(path, view)
    elif space != SPACE_WINDOW:
        push_warning("SaCapture: a stroke's 'space' is 'window' or 'document', not '%s'" % space)
        return
    if route == ToolRoute.TOOL and ToolRoute.tool_canvas() == null:
        push_warning("SaCapture: no canvas with a tool machine in the root window for a stroke on the tool route")
        return
    var button := String(spec.get("button", "left"))
    var colour: Variant = spec.get("colour", null)
    # Expanded into one step per frame rather than run inline, because a stroke
    # that happens inside a single frame is not a stroke. Sara composites once a
    # frame, so the whole thing landed in one composite, over chunks that
    # commit_stroke had already marked dirty whole. Anything measuring what a
    # stroke costs to draw was measuring the commit instead, and any per-frame
    # cost was invisible. A person's stroke is one small dab per frame.
    var rate := float(spec.get("rate", 0.0))
    var expanded: Array = [{"move": path[0]}, {"press": button}]
    if route == ToolRoute.TOOL:
        expanded = ToolRoute.frames(as_written, space, button, rate)
    elif rate <= 0.0:
        for i in range(1, path.size()):
            expanded.append({"move": path[i]})
        expanded.append({"release": button})

    var points := _points_of(path)
    var last := path[path.size() - 1] as Dictionary
    var pressures := path.map(func(entry: Dictionary) -> float: return float(entry.get("pressure", 0.0)))
    var verdict := {
        "from": [points[0].x, points[0].y],
        "to": [points[points.size() - 1].x, points[points.size() - 1].y],
        # Every waypoint's, so a pen that rose and fell reads as the turns it
        # took rather than as its two ends, which can hide a peak.
        "pressures": pressures,
        "tilt": last.get("tilt", [0.0, 0.0]),
        "steps": points.size() - 1,
        "dispatches": SaCompute.dispatches,
        "covers": _covers_over(points),
        # Measured with the covers and for their reason, before the gesture
        # can change what stands where.
        "window": _rect_array(_run.tree().root.get_visible_rect()),
        "view": _view_rect(),
        # The brush's dab before the press, so the line can tell the dabs
        # this stroke laid from the ones the last stroke left.
        "dab_before": DabsLaid.before(front_tool()),
        # The history and the layer before the press, so the line can say what
        # alpha the stroke's own step left there.
        "alpha_before": AlphaLaid.before(front_document()),
    }
    # A press under a docker is not sent. The input driver addresses it to the
    # window under the point, so the docker would take it as a hand's press, and
    # a press on a row's eye is a click and a run down the eye column a sweep:
    # a painting made through the door lost three layers' visibility that way
    #. The step answers with the loud line and sends nothing.
    if route == ToolRoute.INPUT and not press_cover(verdict["covers"] as Array).is_empty():
        _run.splice([{"stroke": {"report": verdict}}])
        return
    if colour != null:
        # Before the press, in this step's own frame, through the one writer the
        # `colour` step uses, so the brush is already that colour when it lands.
        # After the refusal above, so a stroke never sent leaves the brush as it was.
        CanvasDriver.colour(colour)
        verdict["colour"] = colour
    if route == ToolRoute.TOOL:
        verdict["route"] = route
        verdict["off_view"] = off_view_count(points, verdict["view"] as Array)
    if space == SPACE_DOCUMENT:
        verdict["document"] = [
            [written[0].x, written[0].y],
            [written[written.size() - 1].x, written[written.size() - 1].y],
        ]
    if rate > 0.0:
        if _input == null and route == ToolRoute.INPUT:
            push_warning("SaCapture: a stroke at a pen's rate needs the step table's input driver")
            return
        var paced := {"path": path, "rate": rate, "sent": 1, "button": button, "verdict": verdict}
        paced["spliced"] = Engine.get_process_frames()
        paced["untimed"] = bool(spec.get("untimed", false))
        if route == ToolRoute.TOOL:
            paced["path"] = as_written
            paced["route"] = route
            paced["space"] = space
        expanded.append({"stroke": {"paced": paced}})
    else:
        expanded.append({"stroke": {"report": verdict}})

    if not Smoothing.hold_for(spec, verdict, ToolRoute.tool_canvas()):
        return
    _hear_refusals(verdict)
    _run.splice(expanded)


## Listens on `EventBus.paint_refused` from the press to the report, so a stroke
## the tool turned away says so and why, a hidden or locked layer, rather than
## only that the tool drew nothing.
static func _hear_refusals(verdict: Dictionary) -> void:
    var heard: Array[String] = []
    var listener := func(line: String) -> void: heard.append(line)
    verdict["heard"] = heard
    verdict["listener"] = listener
    EventBus.paint_refused.connect(listener)


## What the tool said turning the stroke of *verdict* away, and the listener let
## go, empty when nothing was said or nobody listened.
static func _refusals_heard(verdict: Dictionary) -> Array[String]:
    var heard: Array[String] = []
    var listener: Variant = verdict.get("listener", null)
    if listener is Callable and EventBus.paint_refused.is_connected(listener):
        EventBus.paint_refused.disconnect(listener)
    if verdict.get("heard") is Array:
        heard.assign(verdict["heard"])
    return heard


## One frame of a stroke at a pen's own rate: every report due since the
## first of these frames and not yet sent, as one burst, then this step again
## until the last report is out, and the release and the verdict after it.
##
## The clock starts at the first frame rather than at the press, so the first
## burst is the reports of one frame and not of the two the press took.
##
## **Each report reads the time it was made**, the press's and the report's
## place over the rate after it, carried as the entry's `made_usec` and held
## while it goes in, so the reports of one burst are as far apart as a pen sends
## them and the brush reads the speed the pen moved at. Sent at the frame's
## time, a burst read as one instant, and a pen at 1.5 px/ms read 10.7 under a
## load in `scenarios/what-rate-bursts-do-to-the-speed-sensors-is-measured.json`.
## A capture's pinned clock still counts a frame as a sixtieth, which times a
## frame-paced stroke as its scenario wrote it, one move a sixtieth whatever the
## frame cost. The interval here is the pen's own and no frame's, so a pinned
## clock gives the reports the same times on every run however the frames group
## them.
##
## **`"untimed": true` sends the reports as the app's pen does**, with no time
## of their own, so the brush times them as it times a painter's:
## `{"stroke": {"from": [x, y], "to": [x, y], "steps": 120, "rate": 240,
## "untimed": true}}`. Godot's events carry no time, and this is the burst a
## painter's frame delivers. Its reports fall due from the press, as a pen's
## do, since with no times to say otherwise the frame a timed stroke waits
## after its press would read as a pen that stood still.
func _pace(state: Dictionary) -> void:
    var now := Time.get_ticks_usec()
    if int(state.get("began", 0)) == 0:
        var since := _since_press(state)
        state["began"] = now - (since if bool(state.get("untimed", false)) else 0)
        state["pen_began"] = SaPenClock.now_usec() - since
    var path := state["path"] as Array
    var rate := float(state["rate"])
    var elapsed := float(now - int(state["began"])) / 1e6
    var due := mini(path.size(), 1 + int(elapsed * rate))
    var sent := int(state["sent"])
    var by_tool := String(state.get("route", ToolRoute.INPUT)) == ToolRoute.TOOL
    var space := String(state.get("space", SPACE_WINDOW))
    if due > sent:
        var burst: Array = []
        for k in range(sent, due):
            var entry := (path[k] as Dictionary).duplicate()
            if not bool(state.get("untimed", false)):
                entry["made_usec"] = int(state["pen_began"]) + roundi(float(k) * 1e6 / rate)
            burst.append(entry)
        if by_tool:
            for entry: Dictionary in burst:
                var spec := ToolRoute.event_spec(ToolRoute.MOTION, entry, space, String(state["button"]))
                if entry.has("made_usec"):
                    SaPenClock.held(int(entry["made_usec"]), _route.hand.bind(spec))
                else:
                    _route.hand.call(spec)
        else:
            _input.motion_burst(burst)
        state["sent"] = due
    state["frames"] = int(state.get("frames", 0)) + 1
    if due < path.size():
        _run.splice([{"stroke": {"paced": state}}])
        return
    var verdict := state["verdict"] as Dictionary
    verdict["steps"] = state["frames"]
    var release: Dictionary = {"release": state["button"]}
    if by_tool:
        release = ToolRoute.release_frame(path, space, String(state["button"]))
    _run.splice([release, {"stroke": {"report": verdict}}])


## How long before the first paced frame the press was, on the pen's clock:
## the frame before it, a sixtieth on a pinned clock and that frame's own length
## on the engine's. Counted from the first frame instead, the first report of
## a loaded stroke on the engine's clock would read a frame late and its first
## dabs would read the pen slower. Nought when no frame has passed since the step
## spliced the stroke, which is a suite pressing and pacing by hand.
func _since_press(state: Dictionary) -> int:
    if SaPenClock.is_pinned():
        return roundi(SaPenClock.FRAME_MS * 1000.0)
    if Engine.get_process_frames() == int(state.get("spliced", -1)):
        return 0
    return roundi(_run.tree().root.get_process_delta_time() * 1e6)


## The moves a stroke is, whichever of its two shapes it was written in, and an
## empty array when it was written as neither.
##
## A straight line is the waypoint form with the waypoints filled in, so the
## expansion above sees one thing. The pen telemetry a waypoint leaves out falls
## back to the stroke's own, which is what lets a scenario that cares about
## pressure alone write pressure alone and still get a tablet stroke: a motion
## at zero pressure paints a full-size dab at zero alpha, which is the quiet
## failure the head of this file is about.
##
## *view* carries a straight stroke's points to root units, the identity for
## one written in them, and only its length is read here: the samples a
## straight stroke with no `steps` is cut into are [method steps_for] its
## length in root units.
func _path_of(spec: Dictionary, view: Transform2D) -> Array:
    var pressure := float(spec.get("pressure", 0.8))
    var tilt: Variant = spec.get("tilt", [0.0, 0.0])
    var inverted := bool(spec.get("inverted", false))

    if spec.has("points"):
        var path: Array = []
        for entry: Variant in spec["points"] if spec["points"] is Array else []:
            path.append(_waypoint(entry, pressure, tilt, inverted))
        return path if path.size() >= 2 and not path.has({}) else _refused("points")

    var from_raw: Variant = spec.get("from", [])
    var to_raw: Variant = spec.get("to", from_raw)
    if not _is_xy(from_raw) or not _is_xy(to_raw):
        return _refused("from' and 'to")
    var from := Vector2(float(from_raw[0]), float(from_raw[1]))
    var to := Vector2(float(to_raw[0]), float(to_raw[1]))
    var steps := steps_for(view.basis_xform(to - from).length())
    if spec.has("steps"):
        steps = maxi(int(spec["steps"]), 1)
    var line: Array = [{"at": [from.x, from.y], "pressure": pressure, "tilt": tilt, "inverted": inverted}]
    for i in range(1, steps + 1):
        var at := from.lerp(to, float(i) / float(steps))
        line.append({"at": [at.x, at.y], "pressure": pressure, "tilt": tilt, "inverted": inverted})
    return line


## The frames a straight stroke *length* root units long takes when it names
## no `steps`: one a [constant SAMPLE_SPACING], at least one and at most
## [constant MOST_STEPS]. Static, so the suite grades the rule without a
## canvas.
static func steps_for(length: float) -> int:
    return clampi(ceili(length / SAMPLE_SPACING), 1, MOST_STEPS)


## *path* with every waypoint's `at` carried from document pixels to the root
## point that lands on it, through *view*, the canvas's global transform as it
## stands when the step runs.
##
## A client reading the zoom off a
## `fit` and the frame off a screenshot and computed every point by hand, and
## got it wrong when the layout moved. Pan, zoom, rotation and mirror are all in
## the one transform, which is the walk `SaGestureDriver.root_point` takes, so
## the same stroke lands on the same texels whatever the window's size. A point
## that maps outside the visible canvas is still sent, as a pen off the edge
## would be. Waypoints are mapped one by one after the straight form is filled
## in, which for an affine view is the same line either way.
##
## Static and handed the transform, so the suite grades it without a canvas.
static func to_root(path: Array, view: Transform2D) -> Array:
    var out: Array = []
    for entry: Variant in path:
        var point := (entry as Dictionary).duplicate()
        var coords := point["at"] as Array
        var at := view * Vector2(float(coords[0]), float(coords[1]))
        point["at"] = [at.x, at.y]
        out.append(point)
    return out


## Refuses a stroke whose *key* is not of its shape, naming both shapes, before
## any cast of it, since a cast of the wrong shape is a script error. Sends nothing.
static func _refused(key: String) -> Array:
    push_warning("SaCapture: stroke refused, its '%s' are not of its shape. A stroke takes %s" % [key, SHAPES])
    return []


## Whether *value* is a point written as `[x, y]`, two numbers.
static func _is_xy(value: Variant) -> bool:
    var xy: Array = value if value is Array else []
    return xy.size() >= 2 and typeof(xy[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(xy[1]) in [TYPE_INT, TYPE_FLOAT]


## One waypoint as the `move` step it becomes, or an empty dictionary when it
## names no point.
static func _waypoint(entry: Variant, pressure: float, tilt: Variant, inverted: bool) -> Dictionary:
    var spec: Dictionary = entry if entry is Dictionary else {}
    var coords: Variant = spec.get("at")
    if not _is_xy(coords):
        return {}
    return {
        "at": [float(coords[0]), float(coords[1])],
        "pressure": float(spec.get("pressure", pressure)),
        "tilt": spec.get("tilt", tilt),
        "inverted": bool(spec.get("inverted", inverted)),
    }


## Where a path goes, without the telemetry, which is what the window scan and
## the verdict's two ends are measured from.
static func _points_of(path: Array) -> PackedVector2Array:
    var out := PackedVector2Array()
    for entry: Variant in path:
        var coords := (entry as Dictionary)["at"] as Array
        out.append(Vector2(float(coords[0]), float(coords[1])))
    return out


## Every window, embedded or of its own, covering any point the gesture will visit, measured
## before its first event goes out.
##
## Measured here rather than in the report, because a press that lands on a
## docker's title bar drags that docker. By the time the report runs the window
## has moved out from under the point it took the press at, so a scan done then
## answers about a layout the stroke itself destroyed, and the line that comes
## out blames the brush for drawing nothing.
##
## Every point rather than the press point, because a docker under the middle of
## a drag is something a reader has to be told about and one point cannot say it.
## Each entry carries where its window was, so the report can name the ones the
## gesture moved.
func _covers_over(points: PackedVector2Array) -> Array:
    var seen: Dictionary = {}
    var windows := _covering_windows()
    for i in points.size():
        var at := points[i]
        for entry: Dictionary in windows:
            var window := entry["window"] as Window
            var rect := entry["rect"] as Rect2
            if not rect.has_point(at):
                continue
            var title: String = window.title if window.title != "" else String(window.name)
            if seen.has(title):
                seen[title]["points"] = int(seen[title]["points"]) + 1
                continue
            seen[title] = {
                "title": title,
                "first": i,
                "at": [at.x, at.y],
                "points": 1,
                "was": [rect.position.x, rect.position.y],
            }
    return seen.values()


## Every window that can stand over the canvas and take a press, each with its
## rectangle in root units: the embedded ones where they sit, and the windows of
## their own, which every docker is once `SaSettings.embed_subwindows` is off.
##
## A let-out docker is as much a cover as an embedded one, because the input
## driver addresses the press to the window under the point
## (`SaPointerAim.window_under`) and the docker takes it, on any platform.
## Their rectangle is the one `SaCursorPolicy.rect_in` places in root units.
func _covering_windows() -> Array:
    var root := _run.tree().root
    var found: Array = []
    for window in SaCursorPolicy.embedded_subwindows(root, true):
        found.append({"window": window, "rect": Rect2(Vector2(window.position), Vector2(window.size))})
    for window in SaCursorPolicy.windows_of_their_own(root):
        found.append({"window": window, "rect": SaCursorPolicy.rect_in(root, window)})
    return found


## The verdict on the stroke whose frames have just run: did any dab reach the GPU.
##
## `SaCompute.dispatches` is cumulative and is what the state dump already carries
## under `gpu`, so a scenario and this step read one number. It moves when a dab is
## stamped and it does not move when the press was swallowed, which is the whole
## test: an embedded docker over the point leaves it where it was, and so does a
## tool that paints nothing.
##
## A window over the press point is the loud case, pushed as an error as well as
## printed: `sara_shot.py` shows a run's stdout only when something failed and
## collects any line beginning `ERROR:`, so that is what reaches a reader who did
## not go looking. Nothing over the point is the quiet case, named the same way
## but not raised, because a `stroke` is also how a scenario drags a marquee or a
## transform box and those tools are entitled to dispatch nothing. The tool is in
## the line either way, which is what tells the two apart at a glance.
##
## The quiet line names whatever covers any part of the drag rather than the
## press point alone, which would be a claim about a gesture made from a
## sixteenth of it, and stays quiet, because a marquee crossing a docker is not a
## failure.
##
## A press past the window is loud too, and so is a press off the canvas's view
## for a stroke written in document pixels, both measured by the step before its
## first event went out. A stroke in window units that presses the bar names the
## view it missed on the quiet line, because "nothing covers any of the 3
## points" for a press the canvas never heard sends a reader into the brush.
##
## A stroke on the tool route has none of these failures, because no window
## stands between it and the brush. Its line says what it went under and how
## many of its points were off the view, quietly, and "no GPU work" is as quiet
## as the default route's, since a marquee by the route dispatches nothing too.
func _report_stroke(spec: Dictionary) -> void:
    Smoothing.put_back(spec, ToolRoute.tool_canvas())
    var refused := _refusals_heard(spec)
    # A brush still walking the tail of a fast stroke commits it frames after
    # the lift, and what the stroke laid is read off that commit.
    var held := spec.get("alpha_before", {}) as Dictionary
    var waited := int(spec.get("alpha_waits", 0))
    if refused.is_empty() and waited < AlphaLaid.WAIT_FRAMES and AlphaLaid.pending(front_document(), held):
        spec["alpha_waits"] = waited + 1
        _run.splice([{"wait": 1}, {"stroke": {"report": spec}}])
        return
    if not _is_xy(spec.get("from")) or not _is_xy(spec.get("to")):
        return
    var from := Vector2(float(spec["from"][0]), float(spec["from"][1]))
    var to := Vector2(float(spec["to"][0]), float(spec["to"][1]))
    var dispatched: int = SaCompute.dispatches - int(spec.get("dispatches", 0))
    var steps: int = int(spec.get("steps", 0))
    var covers := spec.get("covers", []) as Array
    var moved := _moved_clause(covers)
    var laid := DabsLaid.after(front_tool(), int(spec.get("dab_before", 0)))
    var alpha := AlphaLaid.after(front_document(), held) if refused.is_empty() else ""
    laid += alpha
    var shape := (
        "stroke %s%s(%d, %d) -> (%d, %d)  %s%s  %d frames%s%s"
        % [
            route_clause(spec),
            document_clause(spec),
            from.x,
            from.y,
            to.x,
            to.y,
            pressure_clause(spec),
            _tilt_clause(spec),
            steps,
            colour_clause(spec),
            Smoothing.clause(spec),
        ]
    )
    # A press the tool refused drew nothing, and the line it said is the reason,
    # so the answer's `errors` carry it as a failed export's do.
    if not refused.is_empty():
        var said := "SaCapture: %s  refused by the %s tool: %s" % [shape, _run.active_tool_name(), refused[0]]
        print(said)
        push_error(said)
        return
    # Nothing the window does stands in the tool route's way, so a docker over
    # a point and a point off the view are facts about the stroke rather than
    # why it failed, and no line of the route's is loud.
    if String(spec.get("route", "")) == ToolRoute.TOOL:
        var facts := tool_route_clause(covers, steps, int(spec.get("off_view", 0)))
        if dispatched > 0:
            print("SaCapture: %s  %d GPU dispatches%s%s" % [shape, dispatched, laid, facts])
            _warn_if_bare(shape, alpha)
        else:
            print("SaCapture: %s  no GPU work, so the %s tool drew nothing%s" % [shape, _run.active_tool_name(), facts])
        return
    # The press point first, and the dispatch count only after it. A press a
    # docker took opened no stroke, so nothing the tool does can follow it, and
    # a count of GPU dispatches across the stroke's frames is not a count of
    # dabs: the composite and the docker thumbnails dispatch too. A press on the
    # Brush Presets docker paints nothing and would still read "82 GPU
    # dispatches" if the count were asked before the cover.
    var press := press_cover(covers)
    if dispatched > 0 and press.is_empty():
        print("SaCapture: %s  %d GPU dispatches%s%s" % [shape, dispatched, laid, moved])
        _warn_if_bare(shape, alpha)
        return

    # A press no control of the canvas's could take is loud for the reason a
    # docker's is: the gesture never began, and no tool could have drawn.
    var missed := missed_press_clause(from, spec)
    if press.is_empty() and not missed.is_empty():
        var failed := "SaCapture: %s failed: no dab reached the GPU, %s%s" % [shape, missed, moved]
        print(failed)
        push_error(failed)
        return

    if press.is_empty():
        var off_view := off_view_clause(from, spec.get("view", []) as Array)
        print(
            (
                "SaCapture: %s  no GPU work, %s%s, so the %s tool drew nothing%s"
                % [
                    shape,
                    off_view + ", and " if not off_view.is_empty() else "",
                    cover_clause(covers, steps),
                    _run.active_tool_name(),
                    moved,
                ]
            )
        )
        return

    var line := (
        "SaCapture: %s failed: no dab reached the GPU, '%s' covers (%d, %d), so the press was not sent%s%s"
        % [shape, press["title"], from.x, from.y, moved, WAY_ROUND]
    )
    print(line)
    push_error(line)


## The tool in hand on the front surface's canvas, or null when it has no
## tool machine, which is whose dabs the line names.
static func front_tool() -> Object:
    var canvas := SaCanvasView.front_canvas()
    var machine: Object = canvas.tool_machine() if canvas != null else null
    return machine.get("active_tool") if machine != null else null


## Warns that the stroke of *shape* laid nothing when *alpha*, its clause, says
## so, so a script that reads only `warnings` hears of a dab too small or too
## faint to leave a texel, as Sparse Specks under its size is. A stroke that
## only recoloured opaque paint has a clause of its own and is not bare.
static func _warn_if_bare(shape: String, alpha: String) -> void:
    if alpha == AlphaLaid.clause(0.0, 0, 0, 0):
        push_warning("SaCapture: %s  laid nothing on the layer, though the brush ran" % shape)


## The document on the front surface's canvas, or null, which the stroke paints.
static func front_document() -> SaDocument:
    var canvas := SaCanvasView.front_canvas()
    return canvas.document if canvas != null else null


## The route a stroke went by, as the very opening of its line, or nothing for
## the default route, so a line on real input is the line it always was.
static func route_clause(spec: Dictionary) -> String:
    return "by the tool route, " if String(spec.get("route", "")) == ToolRoute.TOOL else ""


## What stood in a tool route stroke's way and was gone under, as the end of
## its line: each docker over its points and how many points were off the
## view, or nothing when there was neither.
##
## Said rather than left out, because a stroke the route took under a docker
## paints where the painter cannot see it, and a reader comparing a shot with
## the paint has to be told why the two differ.
static func tool_route_clause(covers: Array, steps: int, off_view: int) -> String:
    var points: int = maxi(steps, 1) + 1
    var parts: PackedStringArray = []
    for entry: Variant in covers:
        var cover := entry as Dictionary
        var at := cover["at"] as Array
        parts.append(
            (
                "under '%s' at %d of its %d points, from frame %d at (%d, %d)"
                % [cover["title"], int(cover["points"]), points, int(cover["first"]), float(at[0]), float(at[1])]
            )
        )
    if off_view > 0:
        parts.append("off the view at %d of its %d points, painted where the document has them" % [off_view, points])
    if parts.is_empty():
        return ""
    return ", the tool route went " + ", and ".join(parts)


## How many of *points* stand outside *view*, the canvas's view in root units as
## the verdict carries it, or none when the window has no view.
static func off_view_count(points: PackedVector2Array, view: Array) -> int:
    if view.size() < 4:
        return 0
    var rect := _rect_of(view)
    var count := 0
    for at in points:
        if not rect.has_point(at):
            count += 1
    return count


## The two ends of a stroke written in document pixels, as the opening of its
## line, or nothing for a stroke in window space, so a window stroke's line
## carries no clause it has no use for. The root points follow, which is
## what a reader matches against a docker's rectangle.
static func document_clause(spec: Dictionary) -> String:
    var ends := spec.get("document", []) as Array
    if ends == null or ends.size() < 2:
        return ""
    var from := ends[0] as Array
    var to := ends[1] as Array
    return "document (%d, %d) -> (%d, %d), root " % [float(from[0]), float(from[1]), float(to[0]), float(to[1])]


## The pressure a stroke was painted at, as one value, as the ramp it ran, or
## as the opening, each turn and the closing when it rose and fell.
##
## Two values when the ends differ, because a waypoint stroke exists to carry a
## ramp and a line printing its opening value alone would say the opposite of
## what the stroke did. A turn is where the pressure stops rising and falls or
## stops falling and rises, compared at two decimals, the precision the line
## prints, and a run of equal values counts as one, so a plateau is not a turn.
## A report that carries only `pressure` and `pressure_last` reads as the two
## ends it names.
static func pressure_clause(spec: Dictionary) -> String:
    var raw := spec.get("pressures", []) as Array
    if raw == null or raw.is_empty():
        var opening := float(spec.get("pressure", 0.0))
        raw = [opening, float(spec.get("pressure_last", opening))]
    var runs: Array[int] = []
    for value: Variant in raw:
        var hundredths := roundi(float(value) * 100.0)
        if runs.is_empty() or runs[runs.size() - 1] != hundredths:
            runs.append(hundredths)
    var named: Array[String] = ["%.2f" % (runs[0] / 100.0)]
    for i in range(1, runs.size() - 1):
        if (runs[i] > runs[i - 1]) != (runs[i + 1] > runs[i]):
            named.append("%.2f" % (runs[i] / 100.0))
    if runs.size() > 1:
        named.append("%.2f" % (runs[runs.size() - 1] / 100.0))
    return "pressure " + " to ".join(named)


## The colour a stroke named, as the end of the frames it took, or nothing for
## a stroke that named none and left the brush's colour as it stood.
static func colour_clause(spec: Dictionary) -> String:
    var raw: Variant = spec.get("colour", null)
    if raw == null:
        return ""
    if raw is Array:
        var parts: PackedStringArray = []
        for channel: Variant in raw as Array:
            parts.append(String.num(float(channel), 3))
        return ", colour [%s]" % ", ".join(parts)
    return ", colour %s" % String(raw)


## The pen's lean at the last waypoint, or nothing at all when it was upright.
##
## Absent rather than zero, so the line a scenario without tilt prints is the
## line it has always printed and a reader who sees the clause knows a scenario
## asked for tilt.
static func _tilt_clause(spec: Dictionary) -> String:
    var raw := spec.get("tilt", []) as Array
    if raw == null or raw.size() < 2:
        return ""
    var tilt := Vector2(float(raw[0]), float(raw[1]))
    if tilt.is_zero_approx():
        return ""
    return "  tilt (%.2f, %.2f)" % [tilt.x, tilt.y]


## The entry of *covers* whose window was under the press, or an empty dictionary
## when the press point was clear.
##
## Frame 0 of the walk is the press point itself, so "took the press" is a lookup
## rather than a second scan, and the loud case means the press alone however
## wide the scan is.
static func press_cover(covers: Array) -> Dictionary:
    for entry: Variant in covers:
        var cover := entry as Dictionary
        if int(cover.get("first", -1)) == 0:
            return cover
    return {}


## What covered the gesture, as the middle of the quiet line.
##
## The count of points is in it because that is the difference between "nothing
## was in the way" and "one point of seventeen was clear", and the old line could
## not tell a reader which it had checked.
static func cover_clause(covers: Array, steps: int) -> String:
    var points: int = maxi(steps, 1) + 1
    if covers.is_empty():
        return "nothing covers any of the %d points of the gesture" % points
    var parts: PackedStringArray = []
    for entry: Variant in covers:
        var cover := entry as Dictionary
        var at := cover["at"] as Array
        parts.append(
            (
                "'%s' covers %d of its %d points, from frame %d at (%d, %d)"
                % [cover["title"], int(cover["points"]), points, int(cover["first"]), float(at[0]), float(at[1])]
            )
        )
    return ", ".join(parts)


## Why the press opened no stroke when the reason is where the writer put it
## rather than anything the tool did, as the loud line's middle, or nothing.
##
## A press past the window always, and a press off the canvas's view when the
## stroke was written in document pixels, because its writer named a texel and
## the view put it somewhere else. A stroke in window units that presses the
## bar meant to, and keeps the quiet line.
##
## A stroke along the last row of a canvas at Fit is the case: Fit puts that row
## on the status line's top edge, and the press lands on the line. A `Rect2`
## holds its origin and not its far edge, the canvas never hears the press, and
## a quiet "nothing covers any of the 3 points" would send the reader into the
## brush.
static func missed_press_clause(press: Vector2, spec: Dictionary) -> String:
    var reason := off_window_clause(press, spec.get("window", []) as Array)
    if reason.is_empty() and spec.has("document"):
        reason = off_view_clause(press, spec.get("view", []) as Array)
    if reason.is_empty() or not spec.has("document"):
        return reason
    return reason + ". A view whose edge is the canvas's far edge, as at Fit, has no pixel there to press, so zoom out first"


## Where the press stood against the window, or nothing when *window* holds it
## or was never measured. No pen can press past the window, the last pixel it
## reaches ending on that edge, and no control takes a press there.
static func off_window_clause(press: Vector2, window: Array) -> String:
    if window.size() < 4:
        return ""
    var rect := _rect_of(window)
    if rect.has_point(press):
        return ""
    return (
        (
            "the press at (%d, %d) is outside the window, which spans (%d, %d) to (%d, %d)"
            + " without its far edges, so no control took it"
        )
        % [press.x, press.y, rect.position.x, rect.position.y, rect.end.x, rect.end.y]
    )


## Where the press stood against the canvas's view, the part of the window the
## bars leave to the canvas, or nothing when the view holds it or the window
## has no canvas.
static func off_view_clause(press: Vector2, view: Array) -> String:
    if view.size() < 4:
        return ""
    var rect := _rect_of(view)
    if rect.has_point(press):
        return ""
    return (
        "the press at (%d, %d) is outside the canvas's view, which spans (%d, %d) to (%d, %d)"
        % [press.x, press.y, rect.position.x, rect.position.y, rect.end.x, rect.end.y]
    )


## The canvas's view in root units, as the verdict carries it, or an empty
## array when the root window holds no canvas.
##
## The part the top bar leaves rather than the surface's control, which spans
## the whole window under the bar, so a press on the bar reads as outside it.
func _view_rect() -> Array:
    var canvas := SaCanvasView.front_canvas()
    return _rect_array(SaCanvasView.for_canvas(canvas).get_visible_rect()) if canvas != null else []


## *rect* as the four numbers a verdict carries, because the verdict is spliced
## back in as a step and a step is what a JSON file can hold.
static func _rect_array(rect: Rect2) -> Array:
    return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


## The rectangle four numbers of `_rect_array` stand for.
static func _rect_of(numbers: Array) -> Rect2:
    return Rect2(float(numbers[0]), float(numbers[1]), float(numbers[2]), float(numbers[3]))


## The windows the gesture carried off with it, as a clause to hang on any of the
## three lines above.
##
## A stroke that drags a docker looks from the counter exactly like a stroke the
## brush ignored, and the difference was 960 units of window movement nothing
## printed. Reported on the successful line too, because a stroke that paints and
## also rearranges the layout leaves the next scenario in the run somewhere it did
## not ask to be.
func _moved_clause(covers: Array) -> String:
    var moved: PackedStringArray = []
    for entry: Variant in covers:
        var cover := entry as Dictionary
        var was_raw := cover["was"] as Array
        var was := Vector2(float(was_raw[0]), float(was_raw[1]))
        var now: Variant = _window_place(String(cover["title"]))
        if now == null or (now as Vector2).is_equal_approx(was):
            continue
        var here := now as Vector2
        moved.append("'%s' from (%d, %d) to (%d, %d)" % [cover["title"], was.x, was.y, here.x, here.y])
    if moved.is_empty():
        return ""
    return ", and the gesture moved %s" % ", ".join(moved)


## Where the window titled *title* sits now, or null when nothing answers
## to that title any more.
func _window_place(title: String) -> Variant:
    for entry: Dictionary in _covering_windows():
        var window := entry["window"] as Window
        var found: String = window.title if window.title != "" else String(window.name)
        if found == title:
            return (entry["rect"] as Rect2).position
    return null
