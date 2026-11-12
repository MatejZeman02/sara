## The stamp brush engine, driven end to end, and what the drive found.
##
## Every `pending_` method here is a defect the drive measured on the running
## app and filed as a group F unit. A `pending_` method is not run: the framework
## calls what begins with `test_`, so the fixer renames one method and the suite
## starts asserting the thing that was wrong. That is the convention here,
## used so a filing arrives with the assertion already written rather than
## with a paragraph asking for one.
##
## The `test_` methods below are the arithmetic the drive checked against, and
## they pass today. They are here because a suite of nothing but pending methods
## runs nothing at all, and because the spacing law is the one number in this
## engine that a refactor can silently move.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## A texel harness, borrowed rather than copied: it dispatches the dab kernel
## over a real texture, which is the only way to assert one line of `dab.gmacs`.
const F72Suite = preload("res://modules/sara-base-modules/stamp-brush/tests/test_flow_builds.gd")

## Needs a RenderingDevice, since the harness reads a texel back. The three
## spacing methods below are arithmetic and would run without one, and this is
## what that costs: a machine with no GPU now skips them too.
const REQUIRES_GPU := true


## The fixed spacing walk, which the drive measured on seven drags and found
## exact on every one of them.
##
## `scenarios/stamp-engine-spacing.json` at spacing 0.1, 0.25, 0.5 and 1.0 over the same
## 960 pixel drag of a 43.2 pixel tip gave 223, 89, 45 and 23 dabs, and
## `floor(length / spacing) + 1` gives the same four. This is that arithmetic
## against `effective_spacing`, so a change to the walk that keeps the scenario
## green by accident does not keep this green.
func test_the_fixed_spacing_of_a_dab_is_the_fraction_of_its_own_diameter() -> void:
    var tip := SaBrushTipScript.new()
    tip.diameter = 43.2
    tip.ratio = 1.0
    for fraction: float in [0.1, 0.25, 0.5, 1.0]:
        tip.spacing = fraction
        var walk := SaStrokeDistance.effective_spacing(tip.half_extent().x * 2.0, tip.half_extent().y * 2.0, fraction)
        assert_almost_eq(
            walk.distance.x,
            43.2 * fraction,
            0.01,
            "Spacing %.2f walks %.2f pixels of a 43.2 pixel tip" % [fraction, walk.distance.x]
        )


## Automatic spacing goes as the square root of the diameter, which the drive
## measured rather than read.
##
## `scenarios/stamp-engine-spacing.json` at coefficient 0.5, 1.0 and 2.0 on a 43.2 pixel
## tip gave 3.29, 6.57 and 13.14, exactly linear in the coefficient, and the same
## coefficient of 1.0 on a 108 pixel tip gave 10.39. `6.57 / sqrt(43.2)` and
## `10.39 / sqrt(108)` are both 1.000 to three places, so the law is
## `coefficient * sqrt(diameter)` and neither the record nor the spec said so.
func test_automatic_spacing_goes_as_the_square_root_of_the_diameter() -> void:
    for pair: Array in [[43.2, 6.57], [108.0, 10.39]]:
        var diameter: float = pair[0]
        var walk := SaStrokeDistance.effective_spacing(diameter, diameter, 1.0, 1.0, false, 0.0, false, true, 1.0)
        assert_almost_eq(
            walk.distance.x / sqrt(diameter),
            1.0,
            0.02,
            (
                "A %.0f pixel tip walks %.2f, %.3f times the square root"
                % [diameter, walk.distance.x, walk.distance.x / sqrt(diameter)]
            )
        )
        assert_almost_eq(walk.distance.x, pair[1], 0.2, "and that is the %.2f the drive measured" % pair[1])


## The SOFT generator paints a hard-edged disc at Softness 0, the bottom of
## its own slider, and no longer a three texel spike.
##
## `scenarios/stamp-engine-tips.json` shot 4 stroked the SOFT generator at softness 0.00,
## 0.25, 0.50 and 1.00 over a background of 128, and the first left the canvas at
## 128 texel for texel. `scenarios/soft-generator-empty-at-zero.json` shows
## what that reading missed: single dabs of the same ladder, where softness 0.00
## is 3 texels wide against the 55 of softness 0.25. The reshaping multiplied
## every interior sample by the softness, and the row is now a lerp towards full
## coverage, so its bottom is the hard edge that the same row already means on
## the two generators that read the fade instead.
##
## The reading here is deliberately not the table's peak. Sample zero is the held
## centre and the curve is 1.0 there, so a peak was 1.0 before the fix as well.
func test_the_soft_generator_paints_something_at_the_bottom_of_its_softness_row() -> void:
    var tip := SaBrushTipScript.new()
    tip.generator = SaDabGeometry.Generator.SOFT
    tip.softness = 0.0
    var table := tip.softness_table()
    var inside := table[int(table.size() / 2.0)]
    assert_almost_eq(inside, 1.0, 1e-4, "A softness of zero covers half way out, %.4f" % inside)
    tip.softness = 1.0
    var soft := tip.softness_table()
    assert_true(
        soft[int(soft.size() / 2.0)] < inside - 0.1,
        "and the top of the row is still the softer of the two, %.4f" % soft[int(soft.size() / 2.0)]
    )


## Flow below 1 under-builds in both painting modes. **Fixed.**
##
## `scenarios/stamp-engine-modes.json` shot 2, opacity 0.8 and flow 0.25 over one stroke of
## 110 dabs at spacing 0.1 on a background of 128 with a foreground of 16. The
## arithmetic asks for 38. Build-up reached 105 and wash 124, which is 20 and 4
## percent of the darkening that was asked for. The spec predicted this for wash
## and named Krita's running-average alpha darken as the fix. It did not predict
## it for build-up, and build-up turned out to be the simpler of the two: flow
## was going through a gamma of 2.4 on its way to the kernel, so a painter's 0.25
## arrived as 0.036.
##
## `scenarios/flow-under-builds.json` reads 37 on the stroke's own axis at
## flow 0.25, 0.5 and 1.0 alike, against the 38 the arithmetic asks for. The two
## numbers the drive read were 12 pixels off that axis, where a soft rim makes
## the answer a falloff rather than the rule.
func test_a_flow_below_one_still_reaches_the_opacity_it_was_set_to() -> void:
    var proof: Object = F72Suite.new()
    for flow: float in [0.25, 0.5, 1.0]:
        var alpha: PackedFloat32Array = proof._stamp(8, flow, SaDabGeometry.PaintMode.ALPHA_DARKEN)
        assert_almost_eq(
            alpha[32 * F72Suite.SIDE + 32], 1.0, 1e-4, "A wash stroke at flow %.2f reaches the opacity it was set to" % flow
        )


## A scenario can reach a curve option through the brush editor. The
## assertion for it is
## `test_a_capture_can_enable_a_curve_option_and_the_editor_is_the_door` in
## `ui/dockers/tests/test_a_curve_option_step_and_the_docker_left_edge.gd`,
## which reads the capture dispatcher's own step table, and there is no pending
## method here because there is nothing to fix.


## Size by pressure has no floor, so a light touch is a sub-pixel tip and
## thousands of dispatches.
##
## `scenarios/stamp-engine-dynamics.json` shot 2, size and opacity by pressure both on, one
## 960 pixel stroke at pressure 0.2: the dab is 0.13 pixels across and the stroke
## registered 1979 dabs, because the spacing follows the size and a spacing of
## 0.03 pixels walks the drag three thousand times. At pressure 0.5 it is 10.52
## pixels and 377 dabs, at 1.0 it is 64.8 and 62.
## Fixed by `pressure-size-has-no-floor`. The guard is a floor on the dab the
## kernel is asked to write rather than a floor on the ramp: the ramp is the
## migrated `pow(x, gamma * 2.4)` every existing preset was written against, and
## lifting it would change what every one of them paints.
##
## `MIN_DAB_DIAMETER` is measured rather than chosen, and the measurement is in
## its own doc comment. What this holds is the two halves the running app showed:
## a dab under the floor is not counted as painted, and one over it is.
func test_a_light_stroke_has_a_floor_on_its_dab_size() -> void:
    var walk := SaStrokeDistance.new()
    var spacing := SaStrokeDistance.effective_spacing(64.8, 64.8, 0.18)

    walk.register_dab(Vector2(10.0, 0.0), spacing, 1.0, -1.0, false)
    walk.register_dab(Vector2(20.0, 0.0), spacing, 1.0, -1.0, false)
    assert_eq(walk.dab_sequence, 0, "A sample the kernel could not write is not a dab the canvas received")
    assert_almost_eq(walk.total_distance, 10.0, 0.001, "and the walk still knows how far the stroke has come")
    assert_true(walk.has_last_position, "and where it got to, or the accumulator offers the same point for ever")

    walk.register_dab(Vector2(30.0, 0.0), spacing, 1.0)
    assert_eq(walk.dab_sequence, 1, "A dab over the floor is counted")

    assert_true(StateBrushScript.MIN_DAB_DIAMETER > 0.0, "The floor is a real number, not a disabled guard")
    assert_true(
        StateBrushScript.MIN_DAB_DIAMETER < 0.22,
        "and it sits under the smallest diameter any generator was measured to write at, 0.22"
    )


## Raising Sharpness changes the size the brush paints while the Size row
## does not move.
##
## `scenarios/stamp-engine-tips.json` shot 7, one dab of a 129.6 pixel tip at sharpness
## 0.00, 0.35, 0.70 and 1.00: the ink is 124, 90, 110 and 128 pixels across. The
## binarising is what the spec asks for. The 42 percent the disc grows between
## 0.35 and 1.00 is not, and at 0.35 a painter gets a brush 30 percent smaller
## than the number on the bar.
##
## **Fixed, and the method is `test_sharpness_binarises_the_dab_without_resizing_it`
## in [`test_sharpness_size.gd`](test_sharpness_size.gd)** rather than
## here, under the name it was filed with. It has to dispatch the dab kernel and
## read texels back, so its suite is `REQUIRES_GPU` and this one is not: putting
## it here would have made every assertion above skip on a machine with no
## rendering device, including three that are arithmetic. the
## note above is the precedent for a note in place of a method.


## The airbrush lays down the dabs its rate asks for, and this drive's own
## reading of it was frames counted as seconds.
##
## `scenarios/airbrush-tips.json` shot 1 held the pointer for "the same 60
## frames" at each rate and read 8 dabs at rate 10 and 48 at rate 50, which it
## called 80 and 96 percent. Two things are wrong with that reading and neither
## is in the walk. **The press deposits a dab of its own**, so the airbrush's
## share is 7 and 47. And **a frame is not a sixtieth of a second in an offscreen
## capture**: 7 at rate 10 is a run between 75 and 85 frames a second, 47 at rate
## 50 is a run between 62.5 and 64, and both are the rate exactly over the time
## those frames took. The scenario paints more before each later hold, so it
## slows down between them, which is the order it runs them in.
##
## Measured on the running app in `scenarios/airbrush-rate-short.json`, which
## carries the interval beside the count: four holds read 6, 12, 31 and 61
## airbrush dabs over 678.7, 1223.3, 620.0 and 1230.1 milliseconds, and every one
## is exactly the floor of `rate * seconds`. The whole measurement is in
## `core/api/dab/tests/test_airbrush_rate.gd`.
func test_the_airbrush_lays_down_the_dabs_its_rate_asks_for() -> void:
    for pair: Array in [[10.0, 70.0, 8], [50.0, 62.0, 48], [10.0, 60.0, 10], [50.0, 60.0, 50]]:
        var rate: float = pair[0]
        var fps: float = pair[1]
        var walk := SaStrokeDistance.new()
        walk.timed_interval = 1000.0 / rate
        var still := Vector2(10.0, 10.0)
        var dabs := 0
        for _frame in 60:
            var elapsed := 1000.0 / fps
            var consumed := 0.0
            for _step in 8:
                var t := walk.next_point_position(still, still, consumed, elapsed)
                if t < 0.0:
                    break
                consumed = lerpf(consumed, elapsed, t)
                dabs += 1
        assert_eq(
            dabs,
            int(pair[2]),
            "Rate %d over 60 frames at %.1f a second is %.2f s and %d dabs" % [int(rate), fps, 60.0 / fps, int(pair[2])]
        )
