## A stroke follows a curve between its samples rather than a straight line.
##
## A walk that laid its dabs straight from one pen sample to the next would
## show corners on a quick curve, which arrives as samples far apart. It walks a centripetal Catmull-Rom
## through the samples either
## side, one sample late, and the last segment at pen up.
##
## These drive the real walk with only the dispatch replaced, as
## `test_fan_corners.gd` does, so what is asserted is where the walk asked
## for dabs. The picture is `scenarios/a-stroke-follows-a-curve-between-its-samples.json`.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The dab's radius the quarter circle is judged against, in document pixels,
## and the spacing, which is half of it as a soft round brush's is.
const DAB_RADIUS: float = 3.0
const STEP: float = 1.5

## The quarter circle: a radius of 400 pixels drawn as eight samples, which is
## a quick flick on a 240 Hz pen. Seven segments of about ninety pixels, each
## bowing two and a half pixels off its chord.
const ARC_RADIUS: float = 400.0
const ARC_SAMPLES: int = 8


## A brush whose dispatch is a note in an array, as in `test_fan_corners.gd`.
class RecordingBrush:
    extends StateBrushScript

    var dabs: Array[Vector2] = []
    var pressures: Array[float] = []
    var step: SaStrokeDistance.Spacing = SaStrokeDistance.Spacing.new(Vector2(STEP, STEP))

    func _stamp_brush(pos: Vector2, raw_pressure: float, _tilt: Vector2 = Vector2.ZERO) -> void:
        dabs.append(pos)
        pressures.append(raw_pressure)
        stroke_distance.register_dab(pos, step, raw_pressure)


func _brush() -> RecordingBrush:
    var brush := RecordingBrush.new()
    brush.stroke_distance.spacing = brush.step
    return brush


func _arc() -> Array[Vector2]:
    var samples: Array[Vector2] = []
    for i in ARC_SAMPLES:
        var angle := 0.5 * PI * float(i) / float(ARC_SAMPLES - 1)
        samples.append(ARC_RADIUS * Vector2(cos(angle), sin(angle)))
    return samples


## The whole stroke through the brush, pen up included.
func _paint(brush: RecordingBrush, samples: Array[Vector2], pressures: Array[float] = []) -> void:
    for i in samples.size():
        var pressure := pressures[i] if i < pressures.size() else 1.0
        brush._process_stroke_interpolation(samples[i], pressure, Vector2.ZERO)
    brush._finish_stroke_interpolation()


## The dabs the straight walk laid down before this row, from one sample to the
## next with the same accumulator, which is the baseline both suites compare to.
func _straight(samples: Array[Vector2]) -> Array[Vector2]:
    var walk := SaStrokeDistance.new()
    var step := SaStrokeDistance.Spacing.new(Vector2(STEP, STEP))
    walk.spacing = step
    var dabs: Array[Vector2] = []
    for i in range(1, samples.size()):
        var start := samples[i - 1]
        var goal := samples[i]
        for _guard in 10000:
            var t := walk.next_point_position(start, goal)
            if t < 0.0:
                break
            start = start.lerp(goal, t)
            dabs.append(start)
            walk.register_dab(start, step)
    return dabs


func _worst_miss(dabs: Array[Vector2]) -> float:
    var worst := 0.0
    for at in dabs:
        worst = maxf(worst, absf(at.length() - ARC_RADIUS))
    return worst


func test_a_quarter_circle_lies_within_half_a_dab_of_the_arc() -> void:
    var brush := _brush()
    _paint(brush, _arc())
    var curved := _worst_miss(brush.dabs)
    var straight := _worst_miss(_straight(_arc()))
    assert_true(brush.dabs.size() > 300, "The arc was painted, at %d dabs" % brush.dabs.size())
    assert_true(curved < 0.5 * DAB_RADIUS, "Every dab lies within half a dab's radius of the arc, the worst %.3f px off" % curved)
    assert_true(straight > 0.5 * DAB_RADIUS, "where the straight walk misses it by more, at %.3f px" % straight)
    assert_true(brush.dabs.back().distance_to(_arc().back()) < STEP, "and the stroke reaches the last sample at pen up")


## A straight line, sampled unevenly as a hand does, lands the same dabs in the
## same places as the straight walk did.
func test_a_straight_line_counts_the_same_dabs() -> void:
    var samples: Array[Vector2] = []
    var at := Vector2(20.0, 30.0)
    var along := Vector2(3.0, 1.0).normalized()
    for gap: float in [0.0, 7.0, 31.0, 2.5, 60.0, 13.0, 90.0, 4.0]:
        at += along * gap
        samples.append(at)
    var brush := _brush()
    _paint(brush, samples)
    var before := _straight(samples)
    assert_eq(brush.dabs.size(), before.size(), "The same dab count as the straight walk")
    for i in mini(brush.dabs.size(), before.size()):
        assert_true(
            brush.dabs[i].distance_to(before[i]) < 1e-3, "and dab %d where it was, %s against %s" % [i, brush.dabs[i], before[i]]
        )


## The segment is drawn one sample late: the curve needs the sample after it.
func test_a_segment_waits_for_the_sample_after_it() -> void:
    var brush := _brush()
    var arc := _arc()
    brush._process_stroke_interpolation(arc[0], 1.0, Vector2.ZERO)
    brush._process_stroke_interpolation(arc[1], 1.0, Vector2.ZERO)
    assert_eq(brush.dabs.size(), 0, "Nothing is painted while the first segment waits")
    brush._process_stroke_interpolation(arc[2], 1.0, Vector2.ZERO)
    var first := brush.dabs.size()
    assert_true(first > 0, "The third sample draws the first segment")
    for dab in brush.dabs:
        assert_true(dab.distance_to(arc[0]) <= arc[0].distance_to(arc[1]) + STEP, "and only the first")
    brush._finish_stroke_interpolation()
    assert_true(brush.dabs.size() > first, "Pen up draws the one that was waiting")


## A stroke of two samples has nothing to bend towards, so it walks straight.
func test_two_samples_walk_straight() -> void:
    var brush := _brush()
    _paint(brush, [Vector2.ZERO, Vector2(50.0, 20.0)] as Array[Vector2])
    assert_true(brush.dabs.size() > 10, "It painted, at %d dabs" % brush.dabs.size())
    for dab in brush.dabs:
        assert_almost_eq(dab.cross(Vector2(50.0, 20.0).normalized()), 0.0, 1e-3, "and every dab is on the line")


## Pressure follows the same parameter the position does.
func test_pressure_follows_the_curve() -> void:
    var brush := _brush()
    var pressures: Array[float] = []
    for i in ARC_SAMPLES:
        pressures.append(float(i) / float(ARC_SAMPLES - 1))
    _paint(brush, _arc(), pressures)
    var drops := 0
    for i in range(1, brush.pressures.size()):
        if brush.pressures[i] < brush.pressures[i - 1] - 1e-6:
            drops += 1
    assert_eq(drops, 0, "Pressure rises all along the arc")
    var middle := int(brush.dabs.size() * 0.5)
    var angle := brush.dabs[middle].angle()
    assert_almost_eq(
        brush.pressures[middle], angle / (0.5 * PI), 0.02, "and the middle dab carries the pressure of its place on the arc"
    )


## Collinear samples are one chord, so a straight segment costs nothing extra.
func test_collinear_samples_make_one_chord() -> void:
    var path := SaStrokeCurve.chords(Vector2.ZERO, Vector2(10.0, 0.0), Vector2(40.0, 0.0), Vector2(45.0, 0.0))
    assert_eq(path.size(), 2, "One chord from start to end")
