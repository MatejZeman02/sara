## The spacing accumulator, driven over synthetic paths.
##
## No GPU here. The walk is arithmetic, and the four cases are
## dab counts and positions rather than pixels. What a painter sees is the
## scenario, which counts dabs over three fixed drags.
extends "res://tests/test_framework.gd"

## How far the synthetic strokes run, in document pixels. Long enough that a
## spacing of ten leaves twenty dabs and short enough to read in a failure.
const PATH_LENGTH: float = 200.0

## What "the same to within a thousandth" means for the elliptical solution
## against a brute-force walk, which is the tolerance the elliptical solution is held to.
const ELLIPSE_TOLERANCE: float = 1e-3


## Every dab a walk paints along one straight segment, in order.
##
## The segment start moves to each dab, which is Krita's `paintLine` and is what
## the tool does, so a helper that walked from the original start would be
## testing something nothing runs.
func _walk(distance: SaStrokeDistance, start: Vector2, end: Vector2, spacing: SaStrokeDistance.Spacing) -> Array:
    var dabs: Array = []
    var here := start
    for _step in 4096:
        var t := distance.next_point_position(here, end)
        if t < 0.0:
            break
        var at := here.lerp(end, t)
        dabs.append(at)
        distance.register_dab(at, spacing)
        here = at
    return dabs


## The same walk fed one pixel at a time, which is the brute force the elliptical
## case is checked against: no closed form, just a very short segment repeated.
func _walk_in_steps(
    distance: SaStrokeDistance, start: Vector2, end: Vector2, spacing: SaStrokeDistance.Spacing, steps: int
) -> Array:
    var dabs: Array = []
    var previous := start
    for index in range(1, steps + 1):
        var next := start.lerp(end, float(index) / float(steps))
        dabs.append_array(_walk(distance, previous, next, spacing))
        previous = next
    return dabs


func _fresh(spacing: SaStrokeDistance.Spacing) -> SaStrokeDistance:
    var distance := SaStrokeDistance.new()
    distance.register_dab(Vector2.ZERO, spacing)
    return distance


## Case one: a constant isotropic spacing on a straight line. The dabs land
## every ten pixels and the first one is ten pixels in, not at the start, because
## the caller has already stamped the press dab before it asks for anything.
func test_a_constant_spacing_walks_a_straight_line_evenly() -> void:
    var spacing := SaStrokeDistance.Spacing.new(Vector2(10.0, 10.0))
    var distance := _fresh(spacing)
    var dabs := _walk(distance, Vector2.ZERO, Vector2(PATH_LENGTH, 0.0), spacing)

    assert_eq(dabs.size(), 20, "Two hundred pixels at ten apart is twenty dabs")
    for index in dabs.size():
        var expected := 10.0 * float(index + 1)
        assert_almost_eq(dabs[index].x, expected, 1e-4, "dab %d sits at %.3f" % [index, dabs[index].x])
        assert_almost_eq(dabs[index].y, 0.0, 1e-6, "and on the line")


## And the remainder is carried rather than dropped: two segments of a hundred
## and five leave the same dabs as one of two hundred and ten.
func test_the_remainder_carries_between_segments() -> void:
    var spacing := SaStrokeDistance.Spacing.new(Vector2(10.0, 10.0))
    var one_go := _fresh(spacing)
    var whole := _walk(one_go, Vector2.ZERO, Vector2(210.0, 0.0), spacing)

    var in_two := _fresh(spacing)
    var halves := _walk(in_two, Vector2.ZERO, Vector2(105.0, 0.0), spacing)
    halves.append_array(_walk(in_two, Vector2(105.0, 0.0), Vector2(210.0, 0.0), spacing))

    assert_eq(halves.size(), whole.size(), "The same count either way, %d and %d" % [halves.size(), whole.size()])
    for index in whole.size():
        assert_almost_eq(halves[index].x, whole[index].x, 1e-4, "and dab %d in the same place" % index)


## Case two: the spacing changes half way along the segment. This is what the
## old accumulator could not do, because it divided the whole segment by one
## step size and painted that many dabs.
##
## The claim is arithmetic rather than a count: the first half is walked at ten
## and the second at twenty-five, so the gaps either side of the change differ
## and every gap matches the spacing in force when it was taken.
func test_a_spacing_that_changes_mid_stroke_is_walked_at_both() -> void:
    var narrow := SaStrokeDistance.Spacing.new(Vector2(10.0, 10.0))
    var wide := SaStrokeDistance.Spacing.new(Vector2(25.0, 25.0))
    var distance := _fresh(narrow)

    var dabs: Array = []
    var here := Vector2.ZERO
    var target := Vector2(PATH_LENGTH, 0.0)
    for _step in 4096:
        var t := distance.next_point_position(here, target)
        if t < 0.0:
            break
        var at := here.lerp(target, t)
        dabs.append(at)
        # The spacing widens once the walk is past a hundred, which is the
        # brush's own behaviour when a pressure sensor grows the tip.
        distance.register_dab(at, wide if at.x >= 100.0 else narrow)
        here = at

    # Ten dabs at ten apart to the hundred, then four at twenty-five to the two
    # hundred. **The old accumulator painted eight**: it divided the whole
    # segment by the step its end asked for, `int(200 / 25)`, so six dabs of the
    # thin half were never painted. That is the visible behaviour change this
    # unit is, said as two numbers.
    assert_eq(dabs.size(), 14, "Fourteen dabs where dividing by the final step gives eight")
    for index in range(1, dabs.size()):
        var gap: float = dabs[index].x - dabs[index - 1].x
        var expected := 25.0 if dabs[index - 1].x >= 100.0 else 10.0
        assert_almost_eq(gap, expected, 1e-3, "the gap after %.1f is %.3f" % [dabs[index - 1].x, gap])


## Case three: an elliptical spacing at thirty degrees, where the closed form has
## to agree with a walk that takes the same path a pixel at a time.
##
## A brute-force walk is the only honest check on a quadratic solution. The
## closed form solves for the crossing in one step and the stepped walk finds it
## by accumulating, so they agree only if the algebra is right.
func test_an_elliptical_spacing_agrees_with_a_brute_force_walk() -> void:
    var spacing := SaStrokeDistance.Spacing.new(Vector2(20.0, 6.0), deg_to_rad(30.0))
    var start := Vector2.ZERO
    var end := Vector2(PATH_LENGTH * cos(deg_to_rad(20.0)), PATH_LENGTH * sin(deg_to_rad(20.0)))

    var closed := _walk(_fresh(spacing), start, end, spacing)
    var stepped := _walk_in_steps(_fresh(spacing), start, end, spacing, 200)

    assert_true(closed.size() > 8, "The ellipse walk painted %d dabs" % closed.size())
    assert_eq(stepped.size(), closed.size(), "and the stepped walk painted the same %d" % stepped.size())
    var biggest := 0.0
    for index in closed.size():
        biggest = maxf(biggest, (closed[index] as Vector2).distance_to(stepped[index]))
    assert_true(biggest < ELLIPSE_TOLERANCE, "with the two never more than %.6f apart" % biggest)


## The point of the ellipse: a flat tip steps further along its long axis than
## across it. A walk along the tip's own major axis paints fewer dabs than the
## same distance across it, and a scalar accumulator paints the same either way.
func test_a_flat_tip_steps_further_along_its_length_than_across_it() -> void:
    var spacing := SaStrokeDistance.Spacing.new(Vector2(20.0, 5.0))
    var along := _walk(_fresh(spacing), Vector2.ZERO, Vector2(PATH_LENGTH, 0.0), spacing)
    var across := _walk(_fresh(spacing), Vector2.ZERO, Vector2(0.0, PATH_LENGTH), spacing)

    assert_eq(along.size(), 10, "Ten dabs along the long axis, at twenty apart")
    assert_eq(across.size(), 40, "and forty across it, at five")
    assert_almost_eq(along[0].x, 20.0, 1e-4, "with the first gap the major spacing")
    assert_almost_eq(across[0].y, 5.0, 1e-4, "and the minor one the other way")


## Case four: automatic spacing, where doubling the size less than doubles the
## step. That is the square root, and it is the whole reason the mode exists.
func test_automatic_spacing_grows_with_the_square_root_of_the_size() -> void:
    var small := SaStrokeDistance.effective_spacing(40.0, 40.0, 0.1, 1.0, false, 0.0, false, true, 1.0)
    var large := SaStrokeDistance.effective_spacing(80.0, 80.0, 0.1, 1.0, false, 0.0, false, true, 1.0)

    assert_almost_eq(small.distance.x, sqrt(40.0), 1e-4, "Forty pixels of tip steps by the root of forty")
    assert_almost_eq(large.distance.x, sqrt(80.0), 1e-4, "and eighty by the root of eighty")
    assert_true(
        large.distance.x < small.distance.x * 2.0,
        (
            "so doubling the size takes the step from %.3f to %.3f rather than to %.3f"
            % [small.distance.x, large.distance.x, small.distance.x * 2.0]
        )
    )
    assert_almost_eq(large.distance.x / small.distance.x, sqrt(2.0), 1e-4, "which is a factor of the square root of two")

    # Below a pixel the root would grow the step rather than shrink it, so Krita
    # uses the value itself there and this is that branch.
    var tiny := SaStrokeDistance.effective_spacing(0.25, 0.25, 0.1, 1.0, false, 0.0, false, true, 1.0)
    assert_almost_eq(tiny.distance.x, 0.25, 1e-6, "Under a pixel the step is the size itself")


## A plain spacing is the fraction of the tip's size a painter set, and the
## isotropic switch throws the rotation and the second axis away.
func test_effective_spacing_reads_the_fraction_and_the_isotropic_switch() -> void:
    var flat := SaStrokeDistance.effective_spacing(40.0, 10.0, 0.25, 1.0, false, deg_to_rad(30.0))
    assert_almost_eq(flat.distance.x, 10.0, 1e-6, "A quarter of forty on the long axis")
    assert_almost_eq(flat.distance.y, 2.5, 1e-6, "and of ten on the short one")
    assert_almost_eq(flat.rotation, deg_to_rad(30.0), 1e-6, "with the tip's rotation kept")
    assert_false(flat.is_isotropic(), "which is not a round spacing")

    var round_step := SaStrokeDistance.effective_spacing(40.0, 10.0, 0.25, 1.0, true, deg_to_rad(30.0))
    assert_almost_eq(round_step.distance.x, 10.0, 1e-6, "Isotropic takes the larger dimension")
    assert_almost_eq(round_step.distance.y, 10.0, 1e-6, "on both axes")
    assert_almost_eq(round_step.rotation, 0.0, 1e-6, "and drops the rotation, which then means nothing")
    assert_true(round_step.is_isotropic(), "so the cheap walk runs")

    var scaled := SaStrokeDistance.effective_spacing(40.0, 10.0, 0.25, 2.0)
    assert_almost_eq(scaled.distance.x, 20.0, 1e-6, "The extra scale multiplies the whole thing")


## A spacing under half a pixel is a dab per texel and then some, so both walks
## floor it. Without the floor a spacing of zero is a division by nothing and a
## loop that never advances.
func test_a_spacing_of_nothing_is_floored_rather_than_infinite() -> void:
    var spacing := SaStrokeDistance.Spacing.new(Vector2.ZERO)
    var dabs := _walk(_fresh(spacing), Vector2.ZERO, Vector2(10.0, 0.0), spacing)
    assert_eq(dabs.size(), 20, "Ten pixels at the half-pixel floor is twenty dabs")
    assert_almost_eq(dabs[0].x, 0.5, 1e-4, "the first at half a pixel")

    var thin := SaStrokeDistance.Spacing.new(Vector2(0.1, 4.0))
    var flat_dabs := _walk(_fresh(thin), Vector2.ZERO, Vector2(10.0, 0.0), thin)
    assert_eq(flat_dabs.size(), 20, "and the elliptical walk floors its axes the same way")


## A segment that goes nowhere paints nothing, which is the guard that stops a
## still pen from painting a dab per event through the distance walk. The timed
## walk is what paints on a still pen.
func test_a_segment_of_no_length_paints_nothing() -> void:
    var spacing := SaStrokeDistance.Spacing.new(Vector2(10.0, 10.0))
    var distance := _fresh(spacing)
    assert_eq(distance.next_point_position(Vector2(5.0, 5.0), Vector2(5.0, 5.0)), -1.0, "The isotropic walk says no")

    var flat := SaStrokeDistance.Spacing.new(Vector2(20.0, 5.0))
    var elliptical := _fresh(flat)
    assert_eq(elliptical.next_point_position(Vector2(5.0, 5.0), Vector2(5.0, 5.0)), -1.0, "and so does the ellipse")


## The spacing can shrink under the accumulator between one interpolation and
## the next, which leaves it already past the step. Both walks answer with a dab
## at the start of the segment rather than with nothing, which is Krita's
## behaviour and is not a defensive branch.
func test_a_spacing_that_shrank_paints_at_once_rather_than_never() -> void:
    var wide := SaStrokeDistance.Spacing.new(Vector2(50.0, 50.0))
    var distance := _fresh(wide)
    assert_eq(distance.next_point_position(Vector2.ZERO, Vector2(30.0, 0.0)), -1.0, "Thirty of fifty is not a dab yet")
    # The tip shrinks, so the accumulated thirty is now past the step.
    distance.spacing = SaStrokeDistance.Spacing.new(Vector2(10.0, 10.0))
    assert_almost_eq(
        distance.next_point_position(Vector2(30.0, 0.0), Vector2(40.0, 0.0)),
        0.0,
        1e-6,
        "and once the step is ten the dab is due at the start of the next segment"
    )

    var flat := _fresh(SaStrokeDistance.Spacing.new(Vector2(50.0, 50.0)))
    assert_eq(flat.next_point_position(Vector2.ZERO, Vector2(30.0, 0.0)), -1.0, "The ellipse accumulates the same")
    flat.spacing = SaStrokeDistance.Spacing.new(Vector2(10.0, 4.0))
    assert_almost_eq(flat.next_point_position(Vector2(30.0, 0.0), Vector2(40.0, 0.0)), 0.0, 1e-6, "and pays out the same way")


## The accumulator carries the numbers the sensors read: how far the stroke has
## gone, where it was going, how hard it was pressed and which dab this is. The
## last of those is the seed the kernel's density and randomness hash against.
func test_the_walk_records_what_the_sensors_read() -> void:
    var spacing := SaStrokeDistance.Spacing.new(Vector2(10.0, 10.0))
    var distance := SaStrokeDistance.new()
    assert_eq(distance.dab_sequence, 0, "A fresh walk has painted nothing")
    assert_false(distance.has_last_position, "and has been nowhere")

    distance.register_dab(Vector2.ZERO, spacing, 0.4)
    distance.register_dab(Vector2(30.0, 40.0), spacing, 0.9)
    distance.register_dab(Vector2(30.0, 90.0), spacing, 0.2)

    assert_eq(distance.dab_sequence, 3, "Three dabs")
    assert_almost_eq(distance.total_distance, 100.0, 1e-4, "a hundred pixels of travel")
    assert_almost_eq(distance.last_max_pressure, 0.9, 1e-6, "the hardest press kept rather than the last")
    assert_almost_eq(distance.last_angle, PI / 2.0, 1e-4, "and the last direction, straight down the y axis")

    distance.reset()
    assert_eq(distance.dab_sequence, 0, "A reset stroke starts over")
    assert_almost_eq(distance.total_distance, 0.0, 1e-6, "with no travel")
    assert_almost_eq(distance.last_max_pressure, 0.0, 1e-6, "and no press")


## The timed walk, with its clock and its control.
##
## A rate in dabs a second becomes an interval of `1000 / rate`, and the walk
## deposits one dab per interval of elapsed time over a segment of no length,
## which is exactly what a pointer held still is.
func test_the_timed_walk_deposits_on_a_still_pointer() -> void:
    var distance := SaStrokeDistance.new()
    distance.timed_interval = 50.0
    var still := Vector2(10.0, 10.0)
    var dabs := 0
    # One second of frames at sixty a second, 16.67 milliseconds each, with the
    # start time advancing to each dab exactly as `StateBrush.tick` advances it.
    for _frame in 60:
        var elapsed := 1000.0 / 60.0
        var consumed := 0.0
        for _step in 8:
            var t := distance.next_point_position(still, still, consumed, elapsed)
            if t < 0.0:
                break
            consumed = lerpf(consumed, elapsed, t)
            dabs += 1
    assert_eq(dabs, 20, "A rate of twenty a second deposits twenty in a second")


## And with no interval it deposits nothing at all, however long the pointer is
## held. That is the control the assertion above needs and it is also the whole
## of what the airbrush switch does.
func test_a_still_pointer_deposits_nothing_without_a_clock() -> void:
    var distance := SaStrokeDistance.new()
    var still := Vector2(10.0, 10.0)
    for _frame in 60:
        assert_eq(distance.next_point_position(still, still, 0.0, 1000.0 / 60.0), -1.0, "Nothing on a still pointer")


## A caller that asks once a frame gets one dab a frame, whatever the rate.
##
## **This is not what the airbrush does.** `StateBrush.airbrush_dabs_for_frame`
## asks until the walk says no, so a rate of 120 at sixty frames a second
## deposits 120 and not 60, which `core/api/dab/tests/test_airbrush_rate.gd`
## holds from the other side. What is asserted here is the property of the
## *caller* rather than of the walk, and it is worth keeping because it is the
## shape every other caller in the tool has: ask once, stamp once.
func test_a_caller_that_asks_once_a_frame_gets_one_dab_a_frame() -> void:
    var distance := SaStrokeDistance.new()
    distance.timed_interval = 1000.0 / 120.0
    var still := Vector2.ZERO
    var dabs := 0
    for _frame in 60:
        if distance.next_point_position(still, still, 0.0, 1000.0 / 60.0) >= 0.0:
            dabs += 1
    assert_eq(dabs, 60, "One answer a frame is one dab a frame, however fast the clock is set")


## Ignore Spacing turns the distance gate off, so time is the only clock and a
## fast drag deposits what a slow one does over the same elapsed time.
func test_ignoring_spacing_makes_a_fast_drag_deposit_what_a_slow_one_does() -> void:
    var counts: Array = []
    for length: float in [20.0, 400.0]:
        var distance := SaStrokeDistance.new()
        distance.timed_interval = 50.0
        distance.register_dab(Vector2.ZERO, SaStrokeDistance.Spacing.new(Vector2(10.0, 10.0), 0.0, false, false), 0.0, 50.0)
        var dabs := 0
        var here := Vector2.ZERO
        var target := Vector2(length, 0.0)
        var consumed := 0.0
        for _step in 64:
            var t := distance.next_point_position(here, target, consumed, 200.0)
            if t < 0.0:
                break
            here = here.lerp(target, t)
            consumed = lerpf(consumed, 200.0, t)
            dabs += 1
            distance.register_dab(here, SaStrokeDistance.Spacing.new(Vector2(10.0, 10.0), 0.0, false, false), 0.0, 50.0)
        counts.append(dabs)
    assert_eq(counts[0], counts[1], "Twenty pixels and four hundred deposit the same %d" % counts[0])
    assert_eq(counts[0], 4, "which is the elapsed time over the interval")


## With the distance gate on, the smaller of the two factors wins, so a fast drag
## is gated by travel and a still pointer by time. That is Krita's rule and it is
## what makes an airbrush usable while the hand is moving.
func test_the_smaller_of_the_two_gates_wins() -> void:
    var distance := SaStrokeDistance.new()
    var spacing := SaStrokeDistance.Spacing.new(Vector2(10.0, 10.0))
    distance.register_dab(Vector2.ZERO, spacing, 0.0, 1000.0)
    # A hundred pixels in ten milliseconds: travel says ten dabs, the clock says
    # none, and travel is the smaller factor.
    var dabs := 0
    var here := Vector2.ZERO
    var target := Vector2(100.0, 0.0)
    for _step in 64:
        var t := distance.next_point_position(here, target, 0.0, 10.0)  # far under the interval
        if t < 0.0:
            break
        here = here.lerp(target, t)
        dabs += 1
        distance.register_dab(here, spacing, 0.0, 1000.0)
    assert_eq(dabs, 10, "Travel gates a fast drag, at %d dabs" % dabs)


## The fan's arithmetic. Both ends are excluded on purpose, so a corner that
## turns by exactly one step fans nothing: the dab already drawn and the dab
## about to be drawn are the two ends, and there is nothing between them.
func test_a_turn_within_one_step_fans_nothing() -> void:
    for turn: float in [0.0, 10.0, 29.9, 30.0]:
        var angles := SaStrokeDistance.fan_angles(0.0, deg_to_rad(turn), 30.0)
        assert_eq(angles.size(), 0, "A turn of %.1f degrees at a step of 30 fans nothing" % turn)


## `steps - 1` dabs for `steps` equal divisions, at the angles those divisions
## fall on. A right angle at thirty degrees is three divisions and two dabs.
func test_a_right_angle_fans_the_intermediate_angles() -> void:
    var angles := SaStrokeDistance.fan_angles(0.0, deg_to_rad(90.0), 30.0)
    assert_eq(angles.size(), 2, "Three divisions of ninety degrees leave two dabs between them")
    assert_almost_eq(angles[0], deg_to_rad(30.0), 1e-5, "the first at thirty degrees")
    assert_almost_eq(angles[1], deg_to_rad(60.0), 1e-5, "and the second at sixty")


## A turn that does not divide by the step is split into equal parts rather than
## into whole steps and a remainder, so the last gap is never the odd one out.
func test_an_uneven_turn_is_split_into_equal_parts() -> void:
    var angles := SaStrokeDistance.fan_angles(0.0, deg_to_rad(100.0), 30.0)
    assert_eq(angles.size(), 3, "Four divisions of a hundred degrees leave three dabs")
    assert_almost_eq(angles[0], deg_to_rad(25.0), 1e-5, "at twenty-five")
    assert_almost_eq(angles[1], deg_to_rad(50.0), 1e-5, "fifty")
    assert_almost_eq(angles[2], deg_to_rad(75.0), 1e-5, "and seventy-five, none of them a remainder")


## The short way round, and the sign is the direction the stroke turned. A tip
## that fanned the long way would sweep three hundred degrees to cross ten.
func test_the_fan_takes_the_short_way_round() -> void:
    var angles := SaStrokeDistance.fan_angles(deg_to_rad(170.0), deg_to_rad(-160.0), 10.0)
    assert_eq(angles.size(), 2, "Thirty degrees the short way is three divisions and two dabs")
    for angle in angles:
        var from_start := absf(angle_difference(deg_to_rad(170.0), angle))
        assert_true(from_start <= deg_to_rad(30.0), "and every dab is inside the turn, not outside it")
    assert_almost_eq(angles[0], deg_to_rad(180.0), 1e-5, "the first at a hundred and eighty")


## A step under the floor is refused rather than clamped, because the number
## comes off a preset file and a fan of nine hundred dispatches at one point is a
## hang the painter cannot tell from a fan of ninety.
func test_a_step_under_the_floor_fans_nothing() -> void:
    for step: float in [0.0, -30.0, 0.5, SaStrokeDistance.MIN_FAN_STEP_DEGREES - 0.01]:
        var angles := SaStrokeDistance.fan_angles(0.0, PI, step)
        assert_eq(angles.size(), 0, "A step of %.2f degrees fans nothing" % step)


## At the floor the largest honest fan is a half turn, which is 179 dabs, so the
## ceiling is never the thing that answers for a step the editor can produce.
func test_the_ceiling_is_never_reached_from_the_floor() -> void:
    var angles := SaStrokeDistance.fan_angles(0.0, PI, SaStrokeDistance.MIN_FAN_STEP_DEGREES)
    assert_eq(angles.size(), 179, "A half turn at one degree is 180 divisions and 179 dabs")
    assert_true(angles.size() < SaStrokeDistance.MAX_FAN_DABS, "under the ceiling, which guards a smaller step")


## A turn that is an exact multiple of the step is counted as that multiple and
## not as one more. The angles a walk fans between are `atan2` of interpolated
## positions, so a leg that ran due east arrives a hair off it, and the first
## run of `test_fan_corners.gd` fanned three dabs through a right angle at a
## step of thirty because the ratio came out at 3.0000000000000004.
func test_an_exact_multiple_of_the_step_is_not_rounded_up() -> void:
    for hair: float in [0.0, 1e-9, -1e-9, 1e-7, -1e-7]:
        var angles := SaStrokeDistance.fan_angles(hair, deg_to_rad(90.0) + hair, 30.0)
        assert_eq(angles.size(), 2, "A right angle off by %s radians is still three divisions" % hair)
