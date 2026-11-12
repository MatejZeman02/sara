## The share of a frame a stroke's walk may take, and the samples and the dabs a
## frame could not take, carried into the next one.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A frame ends whatever the pen sends.** A dab costs about 0.2 ms of
## GDScript, and a fast scribble with a 2 px Pencil asks for four or five
## thousand a second. The tool machine hands the brush every raw motion, and a
## tablet driver can bring well over a hundred of them in one frame, so a frame
## that walked every motion queued for it would leave more queued for the next
## and the canvas would freeze for whole seconds until the pen slowed. So the
## brush walks until the frame's share is spent, keeps the rest in order and
## walks it in the frames after, and the canvas shows the stroke growing while
## the pen is still moving. Nothing is merged or dropped, so the stroke lands
## whole and along the same path as a slow one.
##
## **The share is counted in dabs, not in samples.** Windows Ink folds several
## of the pen's reports into one motion when a frame is late, so one motion of a
## fast scribble carries hundreds of dabs and tens of milliseconds on its own. A
## span stops at the dab where the frame's share ran out, [Walk] keeps where it
## stood, and the next frame lays the dab after it.
##
## **A sample is taken where it arrived.** The brush feeds the stabiliser and
## reads the pointer's place and the pressure when the motion comes, because
## the pointer has moved on by the time a carried sample is walked. What waits
## here is only the walk.
##
## **The pen's lift waits for the walk.** A release with a walk still carried
## is kept, and the brush lifts once the last dab is laid, so the stroke is
## committed whole. A press, a tool switch and a reset walk whatever is left at
## once, because each of them starts something the open stroke must not run
## into.
##
## **Only a brush that frames tick carries.** The tool machine ticks the active
## tool once a frame, and [method frame] is that tick. A suite runs every test
## inside one frame of the runner and ticks no tool, so a brush that has never
## been ticked walks everything when it comes, and so does one whose last tick
## is longer ago than [constant STALE_USEC], because no frame is coming to walk
## what it would carry.
class_name SaWalkBudget
extends RefCounted

## The time a frame may spend walking, in microseconds. Half of a 60 Hz frame,
## leaving the other half for the composite, the redraw and the post draw, which
## take most of it under a stroke.
const FRAME_USEC: int = 8000
## How long after the last tick a walk may still be carried, in microseconds.
## A frame lasts a few tens of milliseconds while the budget holds, so a
## quarter of a second without one means none is coming.
const STALE_USEC: int = 250000


## One span's walk, painting a dab wherever the accumulator says one goes, which
## can stop before any dab and go on from there later.
##
## **One dab at a time, and the segment start moves to each one**, which is
## Krita's `KisPaintOp::paintLine` and is what lets the spacing change inside a
## segment: the brush's dispatch registers the spacing it painted with, and the
## next question is asked against that. The old loop divided the whole segment
## by one step size and painted that many dabs, so the entire segment was walked
## at the step its *end* asked for, which is exactly the case the size option
## makes common: a stroke that thickens under pressure dropped dabs at its thin
## end.
##
## **Chord by chord along the span's path.** The accumulator carries what is
## left of a step from one chord into the next, so the dabs are spaced along the
## curve as they were along a straight segment, and a straight span is one chord
## and the walk it always was. Pressure and tilt follow the curve's parameter.
##
## The bound is not Krita's, which has none. Nothing in the accumulator can
## return a non-negative parameter twice without resetting itself, so the loop
## terminates on its own, and a per-event hot path that could freeze the window
## on a division nobody predicted gets a ceiling anyway.
class Walk:
    extends RefCounted

    var _span: SaStrokeCurve.Span = null
    var _chord: int = 1
    var _start := Vector2.ZERO
    var _parameter: float = 0.0
    var _steps: int = 0
    ## The chord's bound, -1 until the chord is begun.
    var _ceiling: int = -1

    func _init(span: SaStrokeCurve.Span) -> void:
        _span = span
        _start = span.path[0]

    ## Lays the span's dabs through *stamp*, which takes a place, a pressure and
    ## a tilt, and answers true once the span is walked, or false when the clock
    ## passed *deadline* first. The clock is read before the accumulator is
    ## asked, so a stop leaves no step taken without its dab. A deadline of
    ## nought never passes.
    func run(distance: SaStrokeDistance, stamp: Callable, deadline: int) -> bool:
        var path := _span.path
        while _chord < path.size():
            var goal := path[_chord]
            var goal_parameter := _span.parameter_at(_chord)
            if _ceiling < 0:
                _ceiling = 2 + int(_start.distance_to(goal) / SaStrokeDistance.MIN_DISTANCE_SPACING)
            while _steps < _ceiling:
                if deadline > 0 and Time.get_ticks_usec() >= deadline:
                    return false
                var t := distance.next_point_position(_start, goal)
                if t < 0.0:
                    break
                _steps += 1
                _start = _start.lerp(goal, t)
                _parameter = lerpf(_parameter, goal_parameter, t)
                # Raw pressure, so one space rather than two.
                stamp.call(_start, _span.pressure_at(_parameter), _span.tilt_at(_parameter))
            _start = goal
            _parameter = goal_parameter
            _chord += 1
            _steps = 0
            _ceiling = -1
        return true


## The carried samples, three entries each: the place, the raw pressure and the
## tilt, oldest first from [member _head].
var _samples: Array = []
var _head: int = 0
## The span a frame stopped inside, or null.
var _walk: Walk = null
## When the last tick ended, or -1 before the first.
var _ticked_usec: int = -1
## The walking this frame has done so far.
var _spent_usec: int = 0
## Whether the pen has lifted while a walk was carried and the stroke waits
## for it, when a new motion is the pen's hover and no part of the stroke.
var lifting: bool = false


## Walks *span* whole through *stamp*, with no share to keep to. Null walks
## nothing.
static func walk(span: SaStrokeCurve.Span, distance: SaStrokeDistance, stamp: Callable) -> void:
    if span != null:
        Walk.new(span).run(distance, stamp, 0)


## One sample of the stroke, walked by the next [method take].
func push(at: Vector2, pressure: float, tilt: Vector2) -> void:
    _samples.append(at)
    _samples.append(pressure)
    _samples.append(tilt)


## Walks the carried span and samples until the frame's share is spent, or all
## of them when *all*, and answers whether none is left. *sample* takes a
## place, a pressure and a tilt and answers the span it completes or null, and
## *stamp* lays one dab.
func take(sample: Callable, distance: SaStrokeDistance, stamp: Callable, all: bool = false) -> bool:
    var started := Time.get_ticks_usec()
    var carrying := not all and _ticked_usec >= 0 and started - _ticked_usec < STALE_USEC
    var deadline := started + maxi(1, FRAME_USEC - _spent_usec) if carrying else 0
    var done := _take(sample, distance, stamp, deadline)
    _spent_usec += Time.get_ticks_usec() - started
    return done


func _take(sample: Callable, distance: SaStrokeDistance, stamp: Callable, deadline: int) -> bool:
    while true:
        if _walk != null:
            if not _walk.run(distance, stamp, deadline):
                return false
            _walk = null
        if _head >= _samples.size():
            break
        if deadline > 0 and Time.get_ticks_usec() >= deadline:
            return false
        var span: SaStrokeCurve.Span = sample.call(_samples[_head], _samples[_head + 1], _samples[_head + 2])
        _head += 3
        if span != null:
            _walk = Walk.new(span)
    _samples.clear()
    _head = 0
    return true


## The frame's tick, after its last share of walking: a new frame begins.
func frame() -> void:
    _spent_usec = 0
    _ticked_usec = Time.get_ticks_usec()


## Answers true and keeps the lift for later when a walk is still carried, or
## false when the pen may lift now.
func lift_later() -> bool:
    lifting = _walk != null or _head < _samples.size()
    return lifting


## Answers whether a kept lift is due, once, after a [method take] that left
## nothing.
func lifted() -> bool:
    var due := lifting
    lifting = false
    return due
