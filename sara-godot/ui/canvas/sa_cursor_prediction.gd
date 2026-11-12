## Where the ring is drawn against where the pointer is, so the frame the
## compositor is holding is paid for in advance.
##
## With the queue at one frame and no motion event dropped, what is left is the
## one frame nobody can remove: the ring is drawn, the compositor keeps it, and
## the hand has moved on by the time it is on glass. Prediction covers that
## frame: velocity times latency is where the pointer is going to be. It is pure,
## taking points and clocks and answering a point, so a suite can feed it a known
## speed and read the lead back, the only way the lead can be checked, because
## Wayland will not let a capture move the pointer.
##
## Three ways this goes wrong, and what stops each:
##
## - A jittering reading, because the device writes the position at a rate the
##   frame loop does not divide, so a velocity between the last two readings
##   alternates by a third of itself. The velocity is a least-squares fit over
##   [constant WINDOW_SECONDS] of readings instead.
## - A pointer at rest, whose readings a pixel apart multiplied by a latency put
##   the ring where the pointer is not. Below [constant REST_SPEED] the lead is
##   nothing, and it fades in to [constant GLIDE_SPEED] rather than switching on.
## - A pointer that teleports (a warp, a window move, a scenario stepping the
##   pointer) is not a hand. The lead is capped at [constant MAX_LEAD].
##
## The learned lead: a hand slows before it turns and a line through the
## readings throws that away. `SaCursorLeadWeights` is one matrix per horizon,
## fitted by `scripts/train_cursor_lead.py` on recorded strokes over the last
## [constant SaCursorLeadWeights.TAPS] displacements, and [method learned_lead]
## applies it under the same three guards. Whether the ring leads at all is
## `SaSettings.cursor_lead`. Auto, the default, is on only where the drawn
## pointer has real lag, a pen moving a pointer Sara draws itself (under
## Wayland, where the driver gives the pen no cursor), because under X11 the
## hardware cursor is the pointer and the ring sits on it.
##
## A row of the weights may carry more inputs after the displacements, and the
## weights file says which in `INPUTS`, a row that names none reading only the
## displacements: the distance from the newest reading to each edge of the canvas
## view in logical pixels clipped at [constant EDGE_HORIZON] and scaled to one (a
## distance, so the right edge reads the same on every screen shape), the pen's
## pressure followed by it times each displacement, and the tilt across and down.
## They are the plain numbers the event carries and `SaStrokeRecorder` writes,
## through no curve, because the fit was made on those.
class_name SaCursorPrediction
extends RefCounted

## How long a run of readings the velocity is fitted over, in seconds.
##
## Six or seven readings at sixty hertz. The whole range was measured: what the
## fit leaves of the beat falls with the window and the corner it rounds grows
## with it, and a tenth of a second is where the two cross. Against the low pass
## it replaced, the lead moves 0.77 pixels between two frames at 900 pixels a
## second rather than 2.51, and 1.54 rather than 5.03 at 1800, while a reversal
## settles in 5 frames rather than 8 and a step from rest reaches nine tenths of
## its lead in the same 5. What it costs is the sharp corner: a right-angle turn
## at 900 pixels a second lands 18 percent further from the pointer than the low
## pass did, 10.60 pixels rms against 8.96, and a smooth arc 7 percent.
const WINDOW_SECONDS: float = 0.10

## Below this speed, in logical pixels a second, the pointer is at rest and the
## ring is drawn on it exactly.
##
## Thirty is about a pixel per frame at sixty hertz, which is the scale of the
## noise a hand resting on a tablet produces.
const REST_SPEED: float = 30.0

## At this speed, in logical pixels a second, the lead is the full one. Between
## here and [constant REST_SPEED] it is faded in by a smoothstep.
##
## A fade rather than a threshold, because a hand crossing a threshold would
## move the ring by the whole lead the threshold's speed earns, which is
## `REST_SPEED` times the latency: half a pixel at one refresh interval and a
## pixel at the 32 milliseconds the settings file will take. Small, but it is a
## step in a place where the ring is meant to be sitting still. Two pixels a frame is a hand that has decided to move, so the
## fade is over by then and nothing at painting speed is touched.
const GLIDE_SPEED: float = 120.0

## The furthest the ring may lead, in logical pixels. A cap rather than a
## clamp on the velocity, because what has to be bounded is what a painter
## sees.
##
## At one refresh interval this is a pointer crossing 3840 pixels a second, which
## no hand does: a fast stroke measured at 1800 and it leads by 30. The cap is
## for the warp and the window move, and it stays where it is because the
## measurement says it never meets a hand.
const MAX_LEAD: float = 64.0

## Samples further apart than this are a new gesture rather than a continuation,
## in seconds. A pointer that left the window and came back has no velocity
## worth carrying across the gap.
const GAP_SECONDS: float = 0.25

## The shortest interval a velocity is taken over, in seconds. Two samples in
## the same tick divide by nothing.
const MIN_INTERVAL: float = 0.0005

## What `cursor_prediction_ms` holds when the latency is the display's own
## refresh interval rather than a number somebody wrote. `SaSettingsCursorLead`
## owns the real value, because the preference's clamp needed it and `core` may
## not name a class under `ui`.
const FOLLOW_DISPLAY: float = SaSettingsCursorLead.FOLLOW_DISPLAY

## What `SaSettings.cursor_lead` may hold and what the Tablet page calls each
## one. `SaSettingsCursorLead` owns the real list, for the same reason
## `FOLLOW_DISPLAY` moved.
##
## Auto by default, on only where there is actual delay, which is where the
## pointer is one Sara draws and can therefore be a frame behind the hand. A
## tablet under Wayland is that case, because no OS cursor is drawn for the pen
## and Sara's ring is the only pointer there is. A mouse has the system's
## pointer beside the ring, and so does a pen on X11 in the default mode, and a
## ring leading a hardware pointer with nothing drawn beside it is a ring
## somewhere the pointer is not. The Both mode, where the ring is drawn beside
## the system's pointer on purpose, shows the same lag, and there the lead is
## what puts the ring back on it.
const LEAD_MODES: Array[Dictionary] = SaSettingsCursorLead.LEAD_MODES

## The refresh rate assumed when the display server will not answer, in hertz.
## `screen_get_refresh_rate` answers -1 on a headless run and on some drivers.
const ASSUMED_REFRESH_HZ: float = 60.0

## How far from an edge of the canvas view a reading still counts as near it,
## in logical pixels. The same number as `EDGE_HORIZON` in
## `scripts/train_cursor_lead.py`, which fits the rows that read it.
const EDGE_HORIZON: float = 300.0

## How many edge distances a row reads when it reads any, left, top, right and
## bottom.
const EDGE_COUNT: int = 4

## The fitted velocity, in logical pixels a second.
var velocity: Vector2 = Vector2.ZERO

## The learned rows this predictor applies, `SaCursorLeadWeights.WEIGHTS` unless
## a suite hands it others.
var _rows: Array = []

## The inputs the rows read, in the order their weights stand, as the weights
## file's `INPUTS` names them. Empty for rows whose file names none, which read
## as their width says.
var _inputs: Array = []

## The newest reading's pressure and tilt, as the pen's motion event gave them.
## Nothing and upright until a pen has moved.
var _pressure: float = 0.0
var _tilt: Vector2 = Vector2.ZERO

var _points: PackedVector2Array = PackedVector2Array()
var _usecs: PackedInt64Array = PackedInt64Array()


## A predictor applying *rows* as its learned lead, laid out as
## `SaCursorLeadWeights.WEIGHTS` is and reading the *inputs* their file names.
## Given neither, it applies the shipped rows and the inputs their file names,
## and rows given without inputs read as their width says.
func _init(rows: Array = SaCursorLeadWeights.WEIGHTS, inputs: Array = []) -> void:
    _rows = rows
    _inputs = SaCursorLeadWeights.INPUTS if inputs.is_empty() and rows == SaCursorLeadWeights.WEIGHTS else inputs


## Feeds one pointer reading at *usec*, which is `Time.get_ticks_usec`.
##
## Every frame, from the overlay's own `_process`, rather than from motion
## events: the ring is drawn per frame and the velocity it is drawn with has to
## be measured over the same clock.
func sample(at: Vector2, usec: int) -> void:
    if not _points.is_empty():
        var since := float(usec - _usecs[_usecs.size() - 1]) / 1_000_000.0
        if since > GAP_SECONDS:
            # A gap is a new gesture. The window goes rather than decaying, or a
            # pointer that left the window and came back leads towards where it
            # was going when it left.
            reset()
        elif since < MIN_INTERVAL:
            # A pointer read twice in one tick. Keeping it would put two
            # readings at the same instant into the fit, which is a vertical
            # line through the times and no slope at all.
            return
    _points.append(at)
    _usecs.append(usec)
    _drop_what_left_the_window()
    velocity = _fitted()


## Keeps the pen's pressure and tilt off *motion*, the newest reading, beside the
## positions [method sample] keeps. From the overlay's `_input`, because the frame
## loop reads the pointer's position on its own and the pen's other numbers
## arrive only on its events. A gesture's [method reset] leaves them, since they
## are the pen's and not the gesture's.
func note_pen(motion: InputEventMouseMotion) -> void:
    _pressure = motion.pressure
    _tilt = motion.tilt


## Forgets the gesture, so the next sample starts a new one.
func reset() -> void:
    velocity = Vector2.ZERO
    _points = PackedVector2Array()
    _usecs = PackedInt64Array()


## How fast the pointer is moving, in logical pixels a second.
func speed() -> float:
    return velocity.length()


## Whether the pointer is moving enough for the lead to mean anything.
func is_moving() -> bool:
    return speed() >= REST_SPEED


## How much of the full lead a pointer at *of_speed* is given, from nothing at
## [constant REST_SPEED] to all of it at [constant GLIDE_SPEED].
##
## The argument is not called `speed`, because a parameter that shadows
## [method speed] is a warning `check_lsp.sh` fails a run on.
static func lead_fraction(of_speed: float) -> float:
    return smoothstep(REST_SPEED, GLIDE_SPEED, of_speed)


## How far ahead the ring goes over *seconds*, in logical pixels.
##
## The argument is `seconds` rather than the latency's own name, because a
## parameter that shadows [method latency_seconds] is a warning `check_lsp.sh`
## fails a run on.
##
## Zero while the pointer rests, so a still ring is drawn on the pointer
## exactly, which is half of what the lead has to prove.
func lead(seconds: float) -> Vector2:
    if seconds <= 0.0:
        return Vector2.ZERO
    var fraction := lead_fraction(speed())
    if fraction <= 0.0:
        return Vector2.ZERO
    return (velocity * seconds * fraction).limit_length(MAX_LEAD)


## Where the ring goes for a pointer at *at*.
func predicted(at: Vector2, seconds: float) -> Vector2:
    return at + lead(seconds)


## How far ahead the ring goes over *seconds* by the learned matrices, in
## logical pixels, under the same guards as [method lead]: nothing at rest,
## faded in to [constant GLIDE_SPEED], capped at [constant MAX_LEAD].
##
## The matrices read the last [constant SaCursorLeadWeights.TAPS]
## displacements on an even grid, so the window has to reach that far back:
## while it does not, the first frames of a gesture, the answer is the fit's.
## Rows that read the edges of the canvas view are handed *view*, the view's
## rectangle in the same space as the readings, and an empty one reads as the
## middle of a view, every edge beyond the horizon. Rows that read the pressure
## or the tilt are handed the newest reading's, as [method note_pen] kept them.
func learned_lead(seconds: float, view: Rect2 = Rect2()) -> Vector2:
    if seconds <= 0.0:
        return Vector2.ZERO
    var fraction := lead_fraction(speed())
    if fraction <= 0.0:
        return Vector2.ZERO
    var steps := grid_displacements()
    if steps.is_empty():
        return lead(seconds)
    var names := row_inputs(_rows, _inputs)
    var inputs := row_values(names, steps, _points[_points.size() - 1], view, _pressure, _tilt)
    if inputs.is_empty() or _rows.is_empty() or (_rows[0] as Array).size() != 2 * (inputs.size() + 1):
        # A table this code cannot read is the fit's answer rather than a ring
        # thrown by weights applied to the wrong inputs.
        return lead(seconds)
    return (weighted_lead(inputs, seconds * 1000.0, _rows) * fraction).limit_length(MAX_LEAD)


## Where the ring goes for a pointer at *at* by the learned lead, *view* being
## the canvas view's rectangle as [method learned_lead] reads it.
func predicted_learned(at: Vector2, seconds: float, view: Rect2 = Rect2()) -> Vector2:
    return at + learned_lead(seconds, view)


## How many edge distances each of *rows* reads after the displacements, none
## for the rows fitted before the recorder carried the view.
static func row_edges(rows: Array) -> int:
    if rows.is_empty():
        return 0
    var width := int((rows[0] as Array).size() / 2.0) - 1 - 2 * SaCursorLeadWeights.TAPS
    return EDGE_COUNT if width == EDGE_COUNT else 0


## The inputs each of *rows* reads, in the order their weights stand: the ones
## *declared* when the weights file names them, and otherwise what the rows'
## width says, the displacements with the edges or without, which is all a file
## from before the files named their inputs could hold.
static func row_inputs(rows: Array, declared: Array = []) -> Array:
    if not declared.is_empty():
        return declared
    if row_edges(rows) > 0:
        return ["displacements", "edges"]
    return ["displacements"]


## The numbers a row reads for the inputs *names*, in their order, as
## `scripts/train_cursor_lead.py` lays them out: the displacements *steps*, the
## edge distances of *at* in *view*, the *pressure* followed by it times each
## displacement number, and the *tilt* across, then down. Empty when a name is
## one this code cannot build, so a table naming it is never applied at all.
static func row_values(
    names: Array, steps: PackedFloat32Array, at: Vector2, view: Rect2, pressure: float, tilt: Vector2
) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    for name: Variant in names:
        match String(name):
            "displacements":
                out.append_array(steps)
            "edges":
                out.append_array(edge_distances(at, view))
            "pressure":
                out.append(pressure)
                for step: float in steps:
                    out.append(pressure * step)
            "tilt":
                out.append(tilt.x)
                out.append(tilt.y)
            _:
                return PackedFloat32Array()
    return out


## The distances from *at* to the left, top, right and bottom edges of *view*,
## each clipped to nothing and to [constant EDGE_HORIZON] and scaled to one, as
## `scripts/train_cursor_lead.py` computes them from a recording. An empty
## *view* is no view known, and reads as its middle.
static func edge_distances(at: Vector2, view: Rect2) -> PackedFloat32Array:
    var out := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
    if view.size.x <= 0.0 or view.size.y <= 0.0:
        return out
    var gaps := [at.x - view.position.x, at.y - view.position.y, view.end.x - at.x, view.end.y - at.y]
    for i in EDGE_COUNT:
        out[i] = clampf(float(gaps[i]) / EDGE_HORIZON, 0.0, 1.0)
    return out


## The rectangle of the canvas view under *pointer* in *window*, in the
## window's space, or an empty one when no view is there. The view is the
## control a canvas sits in rather than the canvas, which is the document's own
## rectangle, and it is the rectangle `SaStrokeRecorder` writes as `v`: a docker
## beside the view is a wall the hand meets before the monitor's edge.
static func view_at(window: Window, pointer: Vector2) -> Rect2:
    for sa_canvas: SaCanvas in SaCanvas.live_canvases():
        if sa_canvas.get_window() != window or not sa_canvas.is_visible_in_tree():
            continue
        var holder := sa_canvas.get_parent() as Control
        if holder != null and holder.get_global_rect().has_point(pointer):
            return holder.get_global_rect()
    return Rect2()


## The last [constant SaCursorLeadWeights.TAPS] displacements of the pointer on
## the weights' own grid, ending at the newest reading, as x then y per step,
## or empty while the window does not reach back far enough.
##
## The readings are interpolated onto the grid rather than fed raw, because the
## events arrive in bursts per frame and the matrices were fitted on a grid.
func grid_displacements() -> PackedFloat32Array:
    var taps: int = SaCursorLeadWeights.TAPS
    var count := _points.size()
    if count < 2:
        return PackedFloat32Array()
    var step_usec := int(1_000_000.0 / SaCursorLeadWeights.GRID_HZ)
    var newest := _usecs[count - 1]
    if newest - _usecs[0] < step_usec * taps:
        return PackedFloat32Array()
    var out := PackedFloat32Array()
    var previous := _at_usec(newest - step_usec * taps)
    for i in range(taps - 1, -1, -1):
        var here := _at_usec(newest - step_usec * i)
        out.append(here.x - previous.x)
        out.append(here.y - previous.y)
        previous = here
    return out


## What *rows* add for *inputs* at *horizon_ms*, interpolated between the two
## fitted horizons around it and scaled beyond the last, so a 144 hertz screen
## and a 60 millisecond setting both get an answer.
static func weighted_lead(inputs: PackedFloat32Array, horizon_ms: float, rows: Array = SaCursorLeadWeights.WEIGHTS) -> Vector2:
    var horizons: Array = SaCursorLeadWeights.HORIZONS_MS
    var last := horizons.size() - 1
    if horizon_ms <= float(horizons[0]):
        return _apply_row(rows[0], inputs) * (horizon_ms / float(horizons[0]))
    if horizon_ms >= float(horizons[last]):
        return _apply_row(rows[last], inputs) * (horizon_ms / float(horizons[last]))
    var upper := 1
    while float(horizons[upper]) < horizon_ms:
        upper += 1
    var below := float(horizons[upper - 1])
    var above := float(horizons[upper])
    var t := (horizon_ms - below) / (above - below)
    return _apply_row(rows[upper - 1], inputs).lerp(_apply_row(rows[upper], inputs), t)


## Whether the ring leads at all under `SaSettings.cursor_lead`: on and off are
## the painter's word, and auto is [method auto_lead_on] read off this machine.
static func lead_enabled() -> bool:
    match SaSettings.cursor_lead:
        "on":
            return true
        "off":
            return false
    return auto_lead_on(SaCursorPolicy.pointer_is_tablet, SaCursorPolicy.sara_draws_the_pen())


## The Auto rule, pure so a suite can ask every case on one machine: the lead is
## on where a pen moves the pointer and Sara draws that pointer rather than
## leaving it to the system, which is *sara_draws_the_pointer*.
##
## The display driver is not a parameter because it was only ever one of the
## answers to the second question, and the answer is the policy's rather than
## this file's. Under Wayland with the default mode the second fact is true
## because the driver leaves the pen without a cursor. On Windows it is true
## where the painter chose Sara's own pointer, Always or Both, which is the mode
## the lag behind the system's pointer is read in at all.
static func auto_lead_on(tablet: bool, sara_draws_the_pointer: bool) -> bool:
    return tablet and sara_draws_the_pointer


## Whether *mode* is one of [constant LEAD_MODES].
static func is_lead_mode(mode: String) -> bool:
    for entry: Dictionary in LEAD_MODES:
        if String(entry["id"]) == mode:
            return true
    return false


## One *row* of the weights over *inputs*: the x weights, the x bias, the y
## weights, the y bias, laid out the way the training script writes them.
static func _apply_row(row: Array, inputs: PackedFloat32Array) -> Vector2:
    var width := inputs.size()
    var x := float(row[width])
    var y := float(row[2 * width + 1])
    for i in width:
        x += float(row[i]) * inputs[i]
        y += float(row[width + 1 + i]) * inputs[i]
    return Vector2(x, y)


## The pointer's position at *usec*, interpolated between the two readings
## around it, and the oldest reading's before the window starts.
func _at_usec(usec: int) -> Vector2:
    var count := _points.size()
    if usec <= _usecs[0]:
        return _points[0]
    for i in range(1, count):
        if _usecs[i] >= usec:
            var span := float(_usecs[i] - _usecs[i - 1])
            if span <= 0.0:
                return _points[i]
            return _points[i - 1].lerp(_points[i], float(usec - _usecs[i - 1]) / span)
    return _points[count - 1]


## The latency the ring is drawn against, in seconds.
##
## `SaSettings.cursor_prediction_ms` when a number is written there, and one
## refresh interval otherwise, which is what the compositor holds. It is a
## constant in the settings file rather than a row on the Display page,
## deliberately: the right number depends on a measurement nobody has taken
## yet, and a control offered without an answer is a control nobody can set
## well.
static func latency_seconds() -> float:
    var written: float = SaSettings.cursor_prediction_ms
    if written > 0.0:
        return written / 1000.0
    if written == 0.0:
        return 0.0
    return 1.0 / refresh_hz()


## The display's refresh rate, or [constant ASSUMED_REFRESH_HZ] where the
## server will not say. Headless answers -1, and so do some drivers.
static func refresh_hz() -> float:
    var reported := DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
    return reported if reported > 1.0 else ASSUMED_REFRESH_HZ


## Drops readings older than [constant WINDOW_SECONDS] behind the newest, always
## keeping the two a slope needs.
func _drop_what_left_the_window() -> void:
    var newest := _usecs[_usecs.size() - 1]
    var first := 0
    while first < _usecs.size() - 2 and float(newest - _usecs[first]) / 1_000_000.0 > WINDOW_SECONDS:
        first += 1
    if first == 0:
        return
    _points = _points.slice(first)
    _usecs = _usecs.slice(first)


## The least-squares slope of the readings in the window against their times.
##
## Every sample in the window carries, which is the whole point of it against
## the difference of the last pair: the device writes the position at its own
## rate and the frame loop reads it at another, so the last pair is whatever the
## two rates happened to line up as and the run of them is the hand.
func _fitted() -> Vector2:
    var count := _points.size()
    if count < 2:
        return Vector2.ZERO
    var base := _usecs[0]
    var mean_time := 0.0
    var mean_point := Vector2.ZERO
    for i in count:
        mean_time += float(_usecs[i] - base) / 1_000_000.0
        mean_point += _points[i]
    mean_time /= float(count)
    mean_point /= float(count)
    var spread := 0.0
    var covariance := Vector2.ZERO
    for i in count:
        var offset := float(_usecs[i] - base) / 1_000_000.0 - mean_time
        spread += offset * offset
        covariance += (_points[i] - mean_point) * offset
    if spread <= 0.0:
        return Vector2.ZERO
    return covariance / spread
