## The turn of a tip that follows the stroke where the walk alone has no
## heading to give it: the press dab, which waits for the way the stroke
## leaves, and a corner, which the fan sweeps.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The press dab waits for a heading.** A dab's drawing angle is the way it
## moved from the dab before it, and the press dab has none, so with nothing to
## wait for it stands at the angle of a stroke going right: a flat tip would
## stand along every upright stroke and across every level one, and the fan
## would sweep from that angle to the stroke's own at the first point, a knob on
## one side and a notch on the other. So when the rotation option reads the
## drawing angle, the press dab is held until the first span the walk is handed
## and is laid at that span's start with the span's own heading pushed in
## through the stroke's override, so the first dab stands as the second will and
## there is no corner to fan. A pen's press already waited for its first
## motion's pressure, and the span starts at the press point with that pressure
## and that tilt, so the dab is the one it was in every way but its turn. A
## stroke that never leaves its point, a tap, has no heading to wait for and
## lays its dab at the lift, turned as a level stroke's would be.
##
## **The fan sweeps a corner.** A tip that follows the stroke turns by the
## whole corner between one dab and the next, and the outside of the corner is
## cut off between them. The dabs it pushes in stand at the corner itself, each
## at an angle a step further round than the last, through the same override.
## Nothing is fanned before the first dab, because `has_last_position` is what
## says the walk has an angle to fan from. The lock is never read under a fan,
## because `fan_degrees` refuses a locked sensor.
class_name SaStrokeTurn
extends RefCounted

## Whether the press dab is still owed, held for the stroke's heading. Set at
## the press, cleared once the dab is laid.
var waiting: bool = false


## Whether *settings*'s tip turns with the stroke's direction: the rotation
## option switched on and reading its drawing angle sensor, which is the one
## case the press dab's turn depends on where the stroke goes.
static func follows(settings: Resource) -> bool:
    var option: SaCurveOption = settings.rotation_option if "rotation_option" in settings else null
    if option == null or not option.enabled or not option.use_curve:
        return false
    var sensor := option.sensor_for(SaSensor.Id.DRAWING_ANGLE)
    return sensor != null and sensor.active


## The fan step *settings* asks for, in degrees, or 0.0 for none.
##
## Off the rotation option's own drawing angle sensor, because the fan exists to
## keep a tip that follows the stroke's direction from cutting a corner, and that
## sensor on that option is what makes a tip do it.
static func fan_degrees(settings: Resource) -> float:
    var option: SaCurveOption = settings.rotation_option if "rotation_option" in settings else null
    if option == null:
        return 0.0
    var sensor := option.sensor_for(SaSensor.Id.DRAWING_ANGLE)
    return sensor.fan_degrees() if sensor != null else 0.0


## The press: whether its dab waits is decided once a stroke, off *settings*.
func press(settings: Resource) -> void:
    waiting = follows(settings)


## Lays what the turn owes before *span* is walked, and answers *span*.
##
## The press dab when it still waits and *span* moves, or the fan at the
## corner *span* starts on. *stamp* lays one dab and takes a place, a raw
## pressure and a tilt, and *info* carries the angle pushed in for it.
func before_walk(
    span: SaStrokeCurve.Span, settings: Resource, distance: SaStrokeDistance, info: SaStrokeInfo, stamp: Callable
) -> SaStrokeCurve.Span:
    if span == null:
        return span
    if waiting:
        _lay_the_press(span, distance, info, stamp)
        return span
    var degrees := fan_degrees(settings)
    if not distance.has_last_position or degrees <= 0.0:
        return span
    var travel := span.path[1] - span.path[0]
    if travel.is_zero_approx():
        return span
    for angle in SaStrokeDistance.fan_angles(distance.last_angle, travel.angle(), degrees):
        _push(info, angle, stamp, span)
    return span


## The press dab still owed at the lift, a tap's or a stroke's that never left
## its point, laid at *at* with the angle a stroke going right would have.
func lay_unturned(stamp: Callable, at: Vector2, pressure: float, tilt: Vector2) -> void:
    if not waiting:
        return
    waiting = false
    stamp.call(at, pressure, tilt)


## The press dab at *span*'s start, turned to the first chord of it that moves.
## A span that does not move is walked to nothing and the dab waits on.
##
## The walk's own last angle is set to the same heading, which is the angle the
## dab was just drawn at: a span too short for a dab of its own would otherwise
## leave the next span's fan sweeping from the angle of a stroke going right.
func _lay_the_press(span: SaStrokeCurve.Span, distance: SaStrokeDistance, info: SaStrokeInfo, stamp: Callable) -> void:
    for i in range(1, span.path.size()):
        var travel := span.path[i] - span.path[0]
        if travel.is_zero_approx():
            continue
        waiting = false
        _push(info, travel.angle(), stamp, span)
        distance.last_angle = travel.angle()
        return


## One dab at *span*'s start drawn at *angle* through the stroke's override,
## which is put back after it so the walk's dabs read their own heading.
static func _push(info: SaStrokeInfo, angle: float, stamp: Callable, span: SaStrokeCurve.Span) -> void:
    info.angle_override = angle
    info.has_angle_override = true
    stamp.call(span.path[0], span.start.pressure, span.start.tilt)
    info.has_angle_override = false
