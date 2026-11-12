## The fan around a corner: the extra dabs a flat tip needs to turn one.
##
## Emitting extra dabs around a corner happens inside the walk along the
## stroke, which the dab pipeline owns. The hook is `SaStrokeInfo`'s angle
## override.
##
## `test_stroke_distance.gd` holds the arithmetic of `SaStrokeDistance.fan_angles`.
## This drives the walk itself: the real `_process_stroke_interpolation` over a
## real corner, with only the dispatch replaced, so what is asserted is which
## dabs the walk asked for and what angle each was handed.
##
## No GPU. A fan is a decision about angles and positions, and the picture it
## makes is `scenarios/the-fan-around-a-corner.json`.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The spacing every walk here steps by, in document pixels. Ten over a hundred
## leaves ten dabs a leg, which is enough to read a corner out of and few enough
## to print in a failure.
const STEP: float = 10.0
const LEG: float = 100.0


## A brush whose dispatch is a note in an array.
##
## `_stamp_brush` is replaced rather than extended, and deliberately: everything
## it does is GPU work this suite has no use for, and what it would have told
## the walk, `register_dab`, is done here instead so the accumulator advances
## exactly as it does in the app. Overriding without `super()` is the trap
## that breaks a walk silently, and this is the case where it is the point.
class RecordingBrush:
    extends StateBrushScript

    ## One entry per dab: where it landed, and the angle the fan pushed in, or
    ## `NAN` for a dab the walk laid down on its own.
    var dabs: Array = []
    var step: SaStrokeDistance.Spacing = SaStrokeDistance.Spacing.new(Vector2(STEP, STEP))

    func _stamp_brush(pos: Vector2, raw_pressure: float, _tilt: Vector2 = Vector2.ZERO) -> void:
        var pushed: float = stroke_info.angle_override if stroke_info.has_angle_override else NAN
        dabs.append({"at": pos, "angle": pushed})
        stroke_distance.register_dab(pos, step, raw_pressure)


## A brush whose rotation option carries a drawing angle sensor set up as asked.
func _brush(fan: bool, step_degrees: float = 30.0, locked: bool = false, active: bool = true) -> RecordingBrush:
    var brush := RecordingBrush.new()
    var sensor := SaSensor.create(SaSensor.Id.DRAWING_ANGLE, active)
    sensor.fan_corners = fan
    sensor.fan_step = step_degrees
    sensor.lock_angle = locked
    brush.settings.rotation_option.set_sensor(sensor)
    brush.stroke_distance.spacing = brush.step
    return brush


## Walks a right angle: east along the first leg, then south down the second.
func _paint_corner(brush: RecordingBrush) -> void:
    brush._process_stroke_interpolation(Vector2.ZERO, 1.0, Vector2.ZERO)
    brush._process_stroke_interpolation(Vector2(LEG, 0.0), 1.0, Vector2.ZERO)
    brush._process_stroke_interpolation(Vector2(LEG, LEG), 1.0, Vector2.ZERO)
    brush._finish_stroke_interpolation()


## Every dab the fan pushed an angle into, in order.
func _fanned(brush: RecordingBrush) -> Array:
    var out: Array = []
    for dab: Dictionary in brush.dabs:
        if not is_nan(float(dab["angle"])):
            out.append(dab)
    return out


## The corner, with the fan on. A right angle at thirty degrees is three
## divisions, so two dabs go in between, both at the corner itself.
func test_a_right_angle_fans_two_dabs_at_the_corner() -> void:
    var brush := _brush(true)
    _paint_corner(brush)
    var fanned := _fanned(brush)
    assert_eq(fanned.size(), 2, "Two dabs between the way in and the way out")
    for dab: Dictionary in fanned:
        assert_true(
            Vector2(dab["at"]).is_equal_approx(Vector2(LEG, 0.0)),
            "and both at the corner rather than along either leg, at %s" % dab["at"]
        )
    # East is zero and south is a quarter turn, Y growing downwards, so the two
    # intermediate angles are thirty and sixty degrees round from east.
    assert_almost_eq(float(fanned[0]["angle"]), deg_to_rad(30.0), 1e-4, "the first thirty degrees round")
    assert_almost_eq(float(fanned[1]["angle"]), deg_to_rad(60.0), 1e-4, "and the second sixty")


## The same corner with the fan off is no corner at all: the walk bends through
## it along the curve through the samples, where the fan keeps both legs straight
## so the corner it fills is where the pen turned.
##
## The walk is a curve, and the straight walk stays only where the fan
## takes over, so the two strokes differ by more than the fan.
func test_the_fan_off_rounds_the_corner_the_fan_turns() -> void:
    var with_fan := _brush(true)
    var without := _brush(false)
    _paint_corner(with_fan)
    _paint_corner(without)
    assert_eq(_fanned(without).size(), 0, "Nothing is fanned with the option off")
    for dab: Dictionary in with_fan.dabs:
        var at := Vector2(dab["at"])
        assert_true(
            is_zero_approx(at.y) or is_equal_approx(at.x, LEG), "With the fan every dab is on one of the two legs, at %s" % at
        )
    # Off both legs, and outside the corner rather than inside it, because a
    # curve through the corner arrives there along the way out.
    var off := 0
    for dab: Dictionary in without.dabs:
        var at := Vector2(dab["at"])
        if absf(at.y) > 1.0 and absf(at.x - LEG) > 1.0:
            off += 1
    assert_true(off > 0, "and without it the stroke bends through the corner, %d dabs off the legs" % off)


## A straight stroke has no corner, so it fans nothing however long it runs.
func test_a_straight_stroke_fans_nothing() -> void:
    var brush := _brush(true)
    brush._process_stroke_interpolation(Vector2.ZERO, 1.0, Vector2.ZERO)
    brush._process_stroke_interpolation(Vector2(LEG, 0.0), 1.0, Vector2.ZERO)
    brush._process_stroke_interpolation(Vector2(2.0 * LEG, 0.0), 1.0, Vector2.ZERO)
    brush._process_stroke_interpolation(Vector2(3.0 * LEG, 0.0), 1.0, Vector2.ZERO)
    brush._finish_stroke_interpolation()
    assert_eq(_fanned(brush).size(), 0, "A straight line turns no corner")
    assert_true(brush.dabs.size() > 20, "and it did paint, at %d dabs" % brush.dabs.size())


## A locked angle draws every dab at the angle the stroke started with, so a fan
## would be a stack of identical dabs at one point. The sensor refuses.
func test_a_locked_angle_fans_nothing() -> void:
    var brush := _brush(true, 30.0, true)
    _paint_corner(brush)
    assert_eq(_fanned(brush).size(), 0, "A locked angle turns nothing to fan")


## A sensor that is switched off is not following the stroke's direction at all,
## so the tip does not turn and there is no corner for it to cut.
func test_an_inactive_sensor_fans_nothing() -> void:
    var brush := _brush(true, 30.0, false, false)
    _paint_corner(brush)
    assert_eq(_fanned(brush).size(), 0, "An inactive drawing angle sensor fans nothing")


## A finer step fans more dabs through the same corner, which is the only thing
## the number is for.
func test_a_finer_step_fans_more_dabs() -> void:
    var coarse := _brush(true, 45.0)
    var fine := _brush(true, 10.0)
    _paint_corner(coarse)
    _paint_corner(fine)
    assert_eq(_fanned(coarse).size(), 1, "Ninety degrees at forty-five is two divisions and one dab")
    assert_eq(_fanned(fine).size(), 8, "and at ten degrees it is nine divisions and eight dabs")


## The override is put back after the fan, or every dab of the second leg would
## be drawn at the last fan angle rather than at the stroke's own direction.
func test_the_override_is_cleared_after_the_fan() -> void:
    var brush := _brush(true)
    _paint_corner(brush)
    assert_false(brush.stroke_info.has_angle_override, "The push is undone when the fan ends")
    assert_true(is_nan(float(brush.dabs[-1]["angle"])), "and the last dab of the stroke was the walk's own")
