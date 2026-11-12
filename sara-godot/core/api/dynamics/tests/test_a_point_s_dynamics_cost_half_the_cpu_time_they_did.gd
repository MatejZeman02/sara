## The dynamics of a point of a Wet Into Wet stroke and of an Oil Smudge stroke
## over the same path cost at most half the CPU time they did.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **What a point's dynamics are.** For the noise brush, what `_answer` and
## `_drift` in `state_noise_brush.gd` ask of the door at a point: the dab the
## dynamics answer, the Strength, Thickness, Stretch and Lean options read by
## `noise_point.gd`, the Drift option, and the colour the colour dynamics shift.
## For the stamp, what `_stamp_brush` asks: the dab and its colour. Each holds
## the dynamics as its brush does, the noise brush a pen motion's points at a
## time and the stamp's walk a motion's dabs. The pen is
## fed into the stroke's reading outside the clock, since that is the sweep's
## and not the dynamics'.
##
## **The figures.** Each stroke is the S of `halv`'s timing for the tablet's
## lag, 98 points with the pressure up and back down and the pen leaning,
## played [constant STROKES] times, and the clock kept is the least of
## [constant RUNS] runs, since a run is only ever slowed by what else the
## machine does. [constant BEFORE_USEC] is that figure measured with the
## dynamics as they were, on the reference machine's CPU, and the half is
## asserted on that processor only, because a figure taken on one machine says
## nothing of another's. Elsewhere the suite prints its figures and skips the
## comparison.
extends "res://tests/test_framework.gd"

const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePointScript = preload("res://modules/sara-noise-brush-engine/noise_point.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The points of a stroke, the strokes a run and the runs a figure.
const POINTS: int = 98
const STROKES: int = 20
const RUNS: int = 9
## A pen's report every 4 ms, and the length of the S.
const REPORT_MS: float = 4.0
## The points the noise brush sweeps under one hold of the dynamics, one pen
## motion's, about two and a half in `halv`'s timing of 98 points from 40 motions.
const FRAME_POINTS: int = 2
## The dabs the stamp's walk lays under one hold, one pen motion's, 909 dabs
## from 40 motions of Oil Smudge's S in the paint suite beside this one.
const WALK_DABS: int = 23
const SPAN := Vector2(1600.0, 700.0)
## The processor the figures before were taken on, and those figures, the
## microseconds of [constant STROKES] strokes.
const MEASURED_ON: String = "Intel(R) Core(TM) i7-10700K CPU @ 3.80GHz"
const BEFORE_USEC: Dictionary[String, int] = {"noise": 332918, "stamp": 57143}


## Where the S is at *t*, and the pen's pressure and lean there.
static func point_at(t: float) -> Vector2:
    return Vector2(200.0 + t * SPAN.x, 800.0 - sin(t * TAU) * SPAN.y * 0.5)


static func pressure_at(t: float) -> float:
    return 0.3 + 0.6 * sin(t * PI)


static func tilt_at(t: float) -> Vector2:
    return Vector2(20.0 + 15.0 * t, -10.0 + 25.0 * t)


## The settings of a shipped recipe called *wanted*, from *entries*, built by
## *build* onto *script*.
func _recipe(entries: Array[Dictionary], wanted: String, build: Callable, script: Script) -> Resource:
    for entry: Dictionary in entries:
        if String(entry["name"]) == wanted:
            return build.call(script, entry)
    assert_true(false, "%s ships" % wanted)
    return null


func _wet_into_wet() -> Resource:
    return _recipe(NoisePresetsScript.entries(), "Wet Into Wet", NoisePresetsScript.build, NoiseBrushSettingsScript)


func _oil_smudge() -> Resource:
    return _recipe(SaShippedPresets.entries(), "Oil Smudge", SaShippedPresets.build, StateBrushScript.BrushSettingsScript)


## The microseconds the noise brush's dynamics take over [constant STROKES]
## strokes, and a checksum of what they answered so the work cannot be skipped.
static func time_noise(settings: Resource) -> Vector2:
    var dynamics := SaDynamics.new(settings)
    var space := SaColorSpace.srgb()
    var spent := 0
    var sum := 0.0
    for stroke in STROKES:
        var info := SaStrokeInfo.new()
        info.begin(point_at(0.0), 1 + stroke)
        info.tip_diameter = 60.0
        dynamics.begin_stroke()
        dynamics.hold()
        for i in POINTS:
            var t := float(i) / float(POINTS - 1)
            info.hovering = false
            info.feed(point_at(t), pressure_at(t), tilt_at(t), 0.0, i * REPORT_MS)
            info.next_dab()
            info.texture = 0.5 + 0.4 * sin(t * 37.0)
            var started := Time.get_ticks_usec()
            if i % FRAME_POINTS == 0:
                dynamics.release()
                dynamics.hold()
            var dab := dynamics.evaluate(info, 60.0)
            var shift := NoisePointScript.shift_for(settings, info)
            var band := NoisePointScript.band_for(settings, dab)
            var lean := NoisePointScript.lean_for(settings, info)
            var thickness := NoisePointScript.thickness_for(settings, info)
            var stretch := NoisePointScript.stretch_for(settings, info)
            var drift: SaCurveOption = settings.drift_option
            var drifted := drift.size_like(info) if drift != null and drift.enabled else 1.0
            var color := SaColorDynamics.apply(settings.color, dab, settings.background_color, space)
            spent += Time.get_ticks_usec() - started
            sum += dab.size + dab.opacity + dab.hardness + shift + band + lean.x + thickness + stretch + drifted + color.r
        dynamics.release()
    return Vector2(spent, sum)


## The same for the stamp, its dab and its colour.
static func time_stamp(settings: Resource) -> Vector2:
    var dynamics := SaDynamics.new(settings)
    var space := SaColorSpace.srgb()
    var spent := 0
    var sum := 0.0
    for stroke in STROKES:
        var info := SaStrokeInfo.new()
        info.begin(point_at(0.0), 1 + stroke)
        dynamics.begin_stroke()
        dynamics.hold()
        for i in POINTS:
            var t := float(i) / float(POINTS - 1)
            info.hovering = false
            info.feed_dab(point_at(t), pressure_at(t), tilt_at(t), 0.0, i * REPORT_MS, settings.maker_pressure_curve)
            info.next_dab()
            var started := Time.get_ticks_usec()
            if i % WALK_DABS == 0:
                dynamics.release()
                dynamics.hold()
            var dab := dynamics.evaluate(info, 60.0)
            var color := SaColorDynamics.apply(
                settings.color, dab, settings.background_color, space, settings.color_source, settings.gradient_ramp
            )
            spent += Time.get_ticks_usec() - started
            sum += dab.size + dab.opacity + dab.rotation + dab.smudge_pickup + color.r
        dynamics.release()
    return Vector2(spent, sum)


## The least of [constant RUNS] runs of *timed* on *settings*.
static func least(timed: Callable, settings: Resource) -> Vector2:
    var best := Vector2(INF, 0.0)
    for run in RUNS:
        var figure: Vector2 = timed.call(settings)
        if figure.x < best.x:
            best = figure
    return best


func _compare(name: String, figure: Vector2) -> void:
    var before := int(BEFORE_USEC[name])
    print(
        (
            "Dynamics, %s: %d us for %d strokes of %d points, %.2f us a point, %d us before"
            % [name, int(figure.x), STROKES, POINTS, figure.x / float(STROKES * POINTS), before]
        )
    )
    if OS.get_processor_name() != MEASURED_ON or before <= 0:
        skip("the figures before were taken on %s" % MEASURED_ON)
        return
    assert_true(figure.x * 2.0 <= float(before), "%s: %d us is at most half of %d" % [name, int(figure.x), before])


func test_a_wet_into_wet_point_s_dynamics_cost_at_most_half() -> void:
    var figure := least(time_noise, _wet_into_wet())
    assert_true(is_finite(figure.y), "the dynamics answered numbers")
    _compare("noise", figure)


func test_an_oil_smudge_point_s_dynamics_cost_at_most_half() -> void:
    var figure := least(time_stamp, _oil_smudge())
    assert_true(is_finite(figure.y), "the dynamics answered numbers")
    _compare("stamp", figure)
