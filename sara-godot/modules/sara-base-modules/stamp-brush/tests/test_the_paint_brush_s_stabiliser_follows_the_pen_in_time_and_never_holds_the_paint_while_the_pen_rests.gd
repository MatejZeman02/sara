## The shipped Paint preset's Average held its paint 60 ms behind the pen on a
## tablet, because it counted its window in samples and stood still while the pen rested.
##
## This feeds the stabiliser as the brush does, with each report's time, and
## reads the brush's lag in milliseconds at two report rates, then rests the pen
## after a corner and steps frames with no new report. Beside it runs today's
## average as it stood before the row, weighted by sample count, so the numbers
## before and after are printed from one run.
extends "res://tests/test_framework.gd"

const StabilizerScript = preload("res://modules/sara-base-modules/stamp-brush/walk/stroke_stabilizer.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The pen's speed along the line, in document pixels a millisecond.
const SPEED: float = 1.0
## How long the pen runs before the lag is read, well past any window.
const RUN_MS: float = 600.0
## A frame of a display at sixty hertz.
const FRAME_MS: float = 1000.0 / 60.0


## The average as it was when it counted samples: the last [method window] samples,
## weighted 1 to n oldest first, moving only when a sample arrives.
class SampleAverage:
    var samples: Array[Vector2] = []
    var size: int = 13

    func feed(raw: Vector2) -> Vector2:
        samples.append(raw)
        while samples.size() > size:
            samples.pop_front()
        var total := Vector2.ZERO
        var weight_sum := 0.0
        for i in samples.size():
            total += samples[i] * float(i + 1)
            weight_sum += float(i + 1)
        return total / weight_sum


func _average() -> RefCounted:
    var stabilizer := StabilizerScript.new()
    stabilizer.begin(StabilizerScript.Mode.AVERAGE, 0.5)
    return stabilizer


## The lag in milliseconds of a steady pen at *hz* reports a second, read at the
## last report: the new average's and today's.
func _lags(hz: float) -> Vector2:
    var stabilizer := _average()
    var today := SampleAverage.new()
    today.size = stabilizer.window()
    var interval := 1000.0 / hz
    var count := int(RUN_MS / interval)
    var now := Vector2.ZERO
    var then := Vector2.ZERO
    var pen := Vector2.ZERO
    for i in count + 1:
        var at := float(i) * interval
        pen = Vector2(SPEED * at, 200.0)
        now = stabilizer.feed(pen, 1000.0 + at)
        then = today.feed(pen)
    return Vector2((pen.x - now.x) / SPEED, (pen.x - then.x) / SPEED)


func test_one_amount_lags_the_same_time_at_88_and_at_240_reports_a_second() -> void:
    var at_88 := _lags(88.0)
    var at_240 := _lags(240.0)
    print(
        (
            "  lag at amount 0.5: before %.1f ms at 88 and %.1f ms at 240, after %.1f ms at 88 and %.1f ms at 240"
            % [at_88.y, at_240.y, at_88.x, at_240.x]
        )
    )
    assert_true(
        absf(at_88.x - at_240.x) <= 2.0, "The lag at 88, %.2f ms, is within 2 ms of the lag at 240, %.2f" % [at_88.x, at_240.x]
    )
    assert_true(at_88.x <= at_88.y + 0.01, "and at 88 no more than today's: %.2f against %.2f" % [at_88.x, at_88.y])
    assert_true(
        absf(at_88.y - at_240.y) > 20.0, "where today's counted samples and differed by %.1f ms" % absf(at_88.y - at_240.y)
    )
    assert_true(at_88.x > 1.0, "and the average still follows behind, so it still smooths: %.2f ms" % at_88.x)


## Right along a row, a corner, up a column, and the pen rests: frames at sixty
## hertz with no new report. Answers the distances from the pen's last place at
## each frame up to *until_ms* after the last report, the new average's, and
## today's, which waits for a report.
func _rest_after_a_corner(until_ms: float) -> Array[Vector2]:
    var stabilizer := _average()
    var today := SampleAverage.new()
    today.size = stabilizer.window()
    var interval := 1000.0 / 88.0
    var pen := Vector2.ZERO
    var then := Vector2.ZERO
    var at := 0.0
    for i in 40:
        at = 1000.0 + float(i) * interval
        pen = Vector2(SPEED * float(i) * interval, 300.0)
        stabilizer.feed(pen, at)
        then = today.feed(pen)
    var corner := pen
    for i in range(1, 9):
        at += interval
        pen = corner - Vector2(0.0, SPEED * float(i) * interval)
        stabilizer.feed(pen, at)
        then = today.feed(pen)
    var distances: Array[Vector2] = [Vector2(pen.distance_to(stabilizer.answer), pen.distance_to(then))]
    var frame := at
    while frame + FRAME_MS <= at + until_ms + 0.001:
        frame += FRAME_MS
        stabilizer.follow(frame)
        distances.append(Vector2(pen.distance_to(stabilizer.answer), pen.distance_to(then)))
    return distances


func test_a_resting_pen_is_caught_up_with_inside_50_ms() -> void:
    var distances := _rest_after_a_corner(50.0)
    var last: Vector2 = distances[-1]
    print(
        (
            "  rest after a corner: %.1f px short at the last report, %d frames and %.1f ms on %.1f px before, %.2f px after"
            % [distances[0].x, distances.size() - 1, (distances.size() - 1) * FRAME_MS, last.y, last.x]
        )
    )
    assert_true(distances[0].x > 10.0, "At the last report the brush stands well short of the pen: %.1f px" % distances[0].x)
    assert_true(last.x <= 1.0, "50 ms after the last report the brush is within a pixel of the pen: %.2f px" % last.x)
    assert_true(last.y > 10.0, "where today's stays put: %.1f px" % last.y)
    var nearer := true
    for i in range(1, distances.size()):
        nearer = nearer and distances[i].x <= distances[i - 1].x + 0.001
    assert_true(nearer, "and the brush only ever closes on the pen while it rests")


## The pen sets off again after a partial catch-up, and the brush never steps
## back along the line it came, because the average's clock only runs forward.
func test_the_brush_never_steps_back_when_the_pen_sets_off_again() -> void:
    var stabilizer := _average()
    var interval := 1000.0 / 88.0
    var at := 1000.0
    for i in 30:
        at = 1000.0 + float(i) * interval
        stabilizer.feed(Vector2(SPEED * float(i) * interval, 0.0), at)
    var x: float = stabilizer.answer.x
    var forward := true
    stabilizer.follow(at + 30.0)
    forward = forward and stabilizer.answer.x >= x
    x = stabilizer.answer.x
    for i in range(30, 50):
        stabilizer.feed(Vector2(SPEED * float(i) * interval, 0.0), at + 30.0 + float(i - 29) * interval)
        forward = forward and stabilizer.answer.x >= x - 0.001
        x = stabilizer.answer.x
    assert_true(forward, "Every answer stands at or past the one before it")


## The reports a frame delivers share one moment on the pen's clock, and the
## average spreads them over the frame rather than reading them as no time.
func test_reports_of_one_moment_are_spread_over_the_frame() -> void:
    var bunched := _average()
    var spread := _average()
    var interval := FRAME_MS / 2.0
    # Sixty-one, so the last moment holds its two reports as every other does.
    for i in 61:
        var pen := Vector2(SPEED * float(i) * interval, 0.0)
        bunched.feed(pen, 1000.0 + FRAME_MS * float((i + 1) >> 1))
        spread.feed(pen, 1000.0 + float(i) * interval)
    var x: float = bunched.answer.x
    var y: float = spread.answer.x
    assert_true(absf(x - y) <= 1.0, "Two reports a frame are followed as two at their own times: %.2f and %.2f" % [x, y])


## Paint ships with the Stabilizer off, and Inked Pen
## keeps its own.
func test_the_shipped_paint_preset_has_the_stabilizer_off() -> void:
    var named := {}
    for entry: Dictionary in SaShippedPresets.entries():
        named[String(entry["name"])] = SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry)
    assert_true(named.has("Paint"), "Paint is shipped")
    assert_eq(int(named["Paint"].stabilizer_mode), 0, "Paint's Stabilizer is off")
    assert_eq(int(named["Inked Pen"].stabilizer_mode), 1, "and Inked Pen keeps its Average")
