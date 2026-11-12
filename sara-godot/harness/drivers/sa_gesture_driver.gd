## The three tool gestures a scenario could not write in the units the tool
## thinks in: the gradient's drag, the crop's box and the transform's handle.
##
## Every other pointer step is in root logical units, because that
## is what an injected event carries. These three tools are not. Each of them
## reads `get_document_mouse_position()` on the press and on every motion, so
## what a scenario means by "drag the crop box from (500, 500) to (900, 700)"
## is a pair of document pixels, and which root points reach them depends on
## the zoom, the pan and the rotation the view happens to be at. The gap was
## measured at sixteen units: a crop drag written as (500, 500) in root units
## left `crop.pending_rect` at y 516, and a scenario written in root units has
## to carry the offset in its head.
##
## So the step takes the tool's own units and this class converts, through the
## canvas's own transform rather than through arithmetic over the view's
## numbers, because that transform is the door `get_document_mouse_position`
## comes back out of. The verdict prints both points, so a run says what it
## aimed at in either frame rather than leaving a reader to work it out.
##
## **The gesture is spliced into the run rather than done here**, the way
## `sa_scenario_stroke.gd` splices a stroke and for the same reason: a press
## and a drag inside one frame are not a gesture. The gradient and the
## transform both do their work in `tick`, one dispatch per frame, so a drag
## with no frames in it previews nothing at all.
##
## Reached by path from the runner rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaGestureDriver
extends RefCounted

## The run, by path like every other harness file this one names.
const CaptureRun := preload("res://harness/sa_capture_run.gd")
## The harness's one lookup for the document the painter is working on.
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")
## The input driver's own answer to which window an event at a point goes to.
const PointerAim := preload("res://harness/drivers/aim/sa_pointer_aim.gd")

## How far, in root units, an end of the ramp the tool laid may stand from the
## point the step pressed or released at. The gradient keeps an end still under
## a hand that moved less than 1.5 screen pixels, and an injected point lands on
## a whole pixel, so the two can differ by a little and still be the same drag.
const LAID_REACH := 3.0

## What a refused gradient's line ends with: the way round the docker.
const WAY_ROUND := '. A gradient with "route": "tool" lays its ramp through the tool, under any docker'

## The run whose steps this splices into and whose tree it measures.
var _run: CaptureRun = null


func _init(run: CaptureRun) -> void:
    _run = run


## Drags the gradient tool: the gradient's drag, in document pixels.
##
## `{"gradient": {"from": [x, y], "to": [x, y], "steps": 10}}`
##
## Selects the gradient tool and drags, which is the whole of its gesture: the
## ramp previews from the press and is written into the layer on the release,
## inside the selection when there is one.
##
## **The step lays its ramp or says it failed.** A press a docker would take, or
## one off the canvas's view, is not sent, and a release onto a docker is not
## either, and the line names what was in the way. After the release the step
## asks the tool what it laid, and no ramp, a ramp of no length or a ramp that
## is not the drag asked for is a failed line, because a brush picked under the
## drag and a docker over the press each lose the ramp while a quiet line says
## nothing went wrong.
##
## **The ends are let go once the ramp is laid**, so a `ramp`, colour or option
## step after it leaves the ramp as it is, and the next drag over the same points
## starts a ramp rather than taking an end. `"hold": true` keeps them, for a
## scenario about the handles, and so do `commit` and `cancel`.
##
## `"route": "tool"` lays the ramp through the tool's own `draw_between`, with
## no pointer, so it lands under any docker and holds no ends.
func gradient(spec: Dictionary) -> void:
    _gesture(&"gradient", spec)


## Drags or ends a crop box: the crop box's drag, in document pixels.
##
## `{"crop": {"from": [x, y], "to": [x, y]}}` draws the box and
## `{"crop": {"commit": true}}` sends the Enter the tool takes as "do it".
## `{"crop": {"cancel": true}}` sends the Escape that drops it. The two are
## separate steps because the box between them is the thing a scenario asking
## about the crop's own arithmetic wants to dump and photograph.
func crop(spec: Dictionary) -> void:
    _gesture(&"crop", spec)


## Drags the transform's handle: in document pixels.
##
## `{"transform": {"from": [x, y], "to": [x, y], "shift": true}}` and then
## `{"transform": {"commit": true}}`.
##
## What the press lands on decides what the drag means, exactly as it does
## under a hand: a handle scales, Ctrl on an edge shears, the middle moves. Lifting the
## pixels is the selection's business and stays the scenario's, so the step
## before the first of these is a `select`.
func transform(spec: Dictionary) -> void:
    _gesture(&"transform", spec)


## One gesture of *tool_name*, expanded into the frames it takes.
##
## The tool is selected here rather than left to the scenario because the step
## is named after it, and a gesture that reached whatever tool happened to be
## active fails far from its cause and reads backwards.
func _gesture(tool_name: StringName, spec: Dictionary) -> void:
    if spec.has("report"):
        _report(tool_name, spec["report"] as Dictionary)
        return
    if spec.has("laid"):
        _check_laid(spec["laid"] as Dictionary)
        return
    if spec.has("between"):
        _lay_between(spec["between"] as Dictionary)
        return

    var canvas := CanvasDriver.main_canvas()
    if canvas == null:
        push_warning("SaCapture: no document in front for a %s gesture" % tool_name)
        return

    var commit := bool(spec.get("commit", false))
    var cancel := bool(spec.get("cancel", false))
    if not spec.has("from") and not commit and not cancel:
        push_warning("SaCapture: a %s gesture needs 'from' and 'to' in document pixels, or a commit or a cancel" % tool_name)
        return

    var expanded: Array = [{"tool": String(tool_name)}]
    var verdict := {"steps": 0, "dispatches": SaCompute.dispatches}
    if spec.has("from"):
        var drag := _drag_of(canvas, tool_name, spec)
        if drag.is_empty():
            return
        verdict.merge(drag["verdict"] as Dictionary, true)
        if tool_name == &"gradient" and String(spec.get("route", "")) == "tool":
            verdict["steps"] = 0
            verdict["route"] = "tool"
            _run.splice([expanded[0], {"gradient": {"between": verdict}}, {"gradient": {"report": verdict}}])
            return
        if tool_name == &"gradient" and not _refused(canvas, verdict).is_empty():
            return
        expanded.append_array(drag["steps"] as Array)
        if tool_name == &"gradient":
            var before := tool_report(tool_name).get("gradient", {}) as Dictionary
            verdict["held_before"] = bool(before.get("held", false))
            verdict["keep"] = bool(spec.get("hold", false)) or commit or cancel
            expanded.append({"gradient": {"laid": verdict}})
    if commit:
        expanded.append({"key": "enter"})
    if cancel:
        expanded.append({"key": "escape"})
    expanded.append({String(tool_name): {"report": verdict}})

    _run.splice(expanded)


## The press, the moves and the release one drag is, and what the verdict has
## to remember about it. Empty when the step named no pair of points.
##
## A `move` before the press and not a `press` carrying an `at`, because these
## three tools read the pointer rather than the event: the press has to meet a
## pointer that a motion has already put where the gesture starts, and a motion
## injected in the same frame as the press has not been delivered yet.
func _drag_of(canvas: SaCanvas, tool_name: StringName, spec: Dictionary) -> Dictionary:
    var from_raw := spec.get("from", []) as Array
    var to_raw := spec.get("to", from_raw) as Array
    if from_raw == null or from_raw.size() < 2 or to_raw == null or to_raw.size() < 2:
        push_warning("SaCapture: a %s gesture needs 'from' and 'to' as [x, y] in document pixels" % tool_name)
        return {}

    var from := Vector2(float(from_raw[0]), float(from_raw[1]))
    var to := Vector2(float(to_raw[0]), float(to_raw[1]))
    var frames: int = maxi(int(spec.get("steps", 8)), 1)
    var press_at := root_point(canvas, from)
    var release_at := root_point(canvas, to)

    var steps: Array = [{"move": {"at": [press_at.x, press_at.y]}}]
    steps.append({"press": {"button": "left", "shift": bool(spec.get("shift", false)), "ctrl": bool(spec.get("ctrl", false))}})
    for i in range(1, frames + 1):
        var at := root_point(canvas, from.lerp(to, float(i) / float(frames)))
        steps.append({"move": {"at": [at.x, at.y]}})
    steps.append({"release": "left"})

    var verdict := {
        "from": [from.x, from.y],
        "to": [to.x, to.y],
        "root_from": [press_at.x, press_at.y],
        "root_to": [release_at.x, release_at.y],
        "steps": frames,
    }
    return {"steps": steps, "verdict": verdict}


## The verdict on the gesture whose frames have just run.
##
## Both frames of reference are in the line, because the whole point of these
## three steps is that the two differ and a reader cannot tell by looking. The
## dispatch delta is read the way the stroke's verdict reads it, off the same
## cumulative counter the dump carries under `gpu`, so a gesture that reached
## no kernel says so instead of leaving a shot to be squinted at.
##
## What the tool holds afterwards comes from the tool's own `capture_report`,
## which is the tool's own door, so this file names no module class
## to read a box out of one. It is empty after a commit that hands back, the
## transform's Enter being exactly that, and the dump beside the line is where
## a committed move is read instead.
func _report(tool_name: StringName, spec: Dictionary) -> void:
    var dispatched: int = SaCompute.dispatches - int(spec.get("dispatches", 0))
    var held := JSON.stringify(tool_report(tool_name))
    var from_raw := spec.get("from", []) as Array
    if from_raw == null or from_raw.size() < 2:
        print("SaCapture: %s, no drag, %d GPU dispatches, %s" % [tool_name, dispatched, held])
        return
    print(
        (
            "SaCapture: %s %s -> %s in document pixels, root %s -> %s, %d frames%s, %d GPU dispatches, %s"
            % [
                tool_name,
                _point_text(from_raw),
                _point_text(spec.get("to", []) as Array),
                _point_text(spec.get("root_from", []) as Array),
                _point_text(spec.get("root_to", []) as Array),
                int(spec.get("steps", 0)),
                " by the tool's own door, with no pointer" if spec.get("route", "") == "tool" else "",
                dispatched,
                held,
            ]
        )
    )
    if spec.has("failed"):
        var failed := "SaCapture: %s failed: %s" % [tool_name, spec["failed"]]
        print(failed)
        push_error(failed)


## Why the gradient's drag in *verdict* would not reach the canvas, said loudly,
## or an empty string when the press and the release both would.
##
## The window under a point is the one the input driver hands the event to, so
## a docker standing there takes the press, embedded or a window of its own,
## and the press has to land on the canvas's view as well, the part the top bar
## leaves. The release may land past the view, where a hand carries a ramp past
## the canvas's edge, but not on a window, which would take it with the drag
## still open.
func _refused(canvas: SaCanvas, verdict: Dictionary) -> String:
    var root := _run.tree().root
    var press := _point_of(verdict["root_from"] as Array)
    var reason := ""
    for end: Array in [["press", press], ["release", _point_of(verdict["root_to"] as Array)]]:
        var window := PointerAim.window_under(root, end[1] as Vector2, true)
        if window != null and reason.is_empty():
            var title: String = window.title if window.title != "" else String(window.name)
            reason = "'%s' covers the %s at (%d, %d)" % [title, end[0], (end[1] as Vector2).x, (end[1] as Vector2).y]
    var view := SaCanvasView.for_canvas(canvas).get_visible_rect()
    if reason.is_empty() and not view.has_point(press):
        reason = (
            "the press at (%d, %d) is outside the canvas's view, which spans (%d, %d) to (%d, %d)"
            % [press.x, press.y, view.position.x, view.position.y, view.end.x, view.end.y]
        )
    if reason.is_empty():
        return ""
    var line := "SaCapture: gradient failed: no ramp was laid, %s, so the drag was not sent%s" % [reason, WAY_ROUND]
    print(line)
    push_error(line)
    return line


## Whether the drag just released laid the ramp it asked for, read off the
## tool's own report, and the ends let go when it did and the step did not ask
## to keep them.
##
## The report is empty when another tool was in hand at the release, as when
## the boot's first brush is picked under the drag and the brush takes it. A
## ramp of no length where the drag had one is the brush picked between the
## press and the first motion, which lays the ramp from the press to itself, one
## flat colour over the layer. With ends held before the press the press may
## have taken one of them, so either end standing at the release is the drag.
func _check_laid(verdict: Dictionary) -> void:
    var canvas := CanvasDriver.main_canvas()
    var machine := canvas.tool_machine() if canvas != null else null
    if machine == null:
        verdict["failed"] = "no canvas at the release"
        return
    var laid := tool_report(&"gradient").get("gradient", {}) as Dictionary
    if laid.is_empty():
        verdict["failed"] = "the %s tool was in hand at the release, so the drag laid no ramp" % machine.default_tool_name
        return
    if not bool(laid.get("held", false)):
        verdict["failed"] = "the gradient laid no ramp at the release"
        return
    var asked_from := _point_of(verdict["root_from"] as Array)
    var asked_to := _point_of(verdict["root_to"] as Array)
    var from := root_point(canvas, _point_of(laid["from"] as Array))
    var to := root_point(canvas, _point_of(laid["to"] as Array))
    var laid_text := (
        "the ramp was laid from %s to %s in document pixels"
        % [_point_text(laid["from"] as Array), _point_text(laid["to"] as Array)]
    )
    if from.distance_to(to) <= LAID_REACH and asked_from.distance_to(asked_to) > LAID_REACH:
        verdict["failed"] = laid_text + ", a ramp of no length, which is one flat colour over the layer"
    elif bool(verdict.get("held_before", false)):
        if to.distance_to(asked_to) > LAID_REACH and from.distance_to(asked_to) > LAID_REACH:
            verdict["failed"] = laid_text + ", and neither end stands where the drag was released"
    elif from.distance_to(asked_from) > LAID_REACH or to.distance_to(asked_to) > LAID_REACH:
        verdict["failed"] = laid_text + ", not where the drag was pressed and released"
    if not verdict.has("failed") and not bool(verdict.get("keep", false)):
        machine.close_session()


## Lays the ramp of *verdict* through the gradient's own `draw_between`, with
## no pointer, so no docker over the canvas can take it. The `tool` step before
## this one put the gradient in hand, and the method is asked for by name
## because this file names no module class.
func _lay_between(verdict: Dictionary) -> void:
    var canvas := CanvasDriver.main_canvas()
    var machine := canvas.tool_machine() if canvas != null else null
    var tool_state: ToolState = machine.registered_tools.get(&"gradient", null) if machine != null else null
    if tool_state == null or tool_state != machine.active_tool or not tool_state.has_method("draw_between"):
        verdict["failed"] = "the gradient was not in hand, so the tool laid no ramp"
        return
    if not bool(tool_state.call("draw_between", _point_of(verdict["from"] as Array), _point_of(verdict["to"] as Array))):
        verdict["failed"] = "the gradient's draw_between laid no ramp"


## A verdict's stored `[x, y]` as a point.
static func _point_of(coords: Array) -> Vector2:
    return Vector2(float(coords[0]), float(coords[1]))


## A verdict's stored point as `(x, y)`, or `(?, ?)` when it holds none.
static func _point_text(coords: Array) -> String:
    if coords == null or coords.size() < 2:
        return "(?, ?)"
    return "(%d, %d)" % [float(coords[0]), float(coords[1])]


## What the tool called *tool_name* says about itself, or an empty dictionary
## when it is not the active tool any more.
static func tool_report(tool_name: StringName) -> Dictionary:
    var canvas := CanvasDriver.main_canvas()
    var machine := canvas.tool_machine() if canvas != null else null
    if machine == null:
        return {}
    var tool_state: ToolState = machine.registered_tools.get(tool_name, null)
    if tool_state == null:
        return {}
    return tool_state.capture_report(tool_name, tool_state == machine.active_tool)


## The root logical point that puts the pointer over document pixel *at*.
##
## Through the canvas's own global transform, which is the walk
## `SaCanvasView.get_document_mouse_position` takes backwards: it asks the
## canvas Control for the local position of the viewport's pointer, so the
## pointer that lands on a document pixel is that pixel carried back out
## through the same transform. Rotation, mirroring and zoom are all in it, and
## none of them is arithmetic this file has to know about.
static func root_point(canvas: SaCanvas, at: Vector2) -> Vector2:
    return canvas.get_global_transform_with_canvas() * at
