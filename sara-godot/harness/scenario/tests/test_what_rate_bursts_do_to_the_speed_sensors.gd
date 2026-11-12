## What a stroke's `rate` bursts do to the speed sensors, measured.
##
## `rate` sends every report due since the frame before as one burst. These
## measure what that does to the speed sensors. They send one straight stroke of 750 document pixels, a pen
## moving at 1.5 pixels a millisecond, through the real brush, frame paced and
## at a pen's 240 reports a second, with frames of a sixtieth of a second and
## under a load that stretches each to 50 ms, and read the speed the brush's
## sample held at every dab through `SaSpeedTraceCapture.Recorder`. The running
## app's half is
## `scenarios/what-rate-bursts-do-to-the-speed-sensors-is-measured.json`.
##
## A test cannot await a frame, so a frame here is the pen's clock held at what
## a capture's pinned clock reads for it, [method SaPenClock.held], with the
## frame's wall time slept between two of them. The rate stroke's bursts are the
## stroke step's own pacing, which reads the wall clock as it does in the app.
##
## **The bursts bent speed twice over before the pen time was reported per report.** A pinned frame
## counted a sixtieth of a second whatever it took, so a burst of thirteen
## reports read as a pen three times as fast. And the brush fed its speed
## smoother once a dab at the clock's time for the frame, so every dab of a
## burst read one time and the smoother's trimmed mean dropped the frame's one
## long interval. The loaded stroke read eleven times its pen here and seven in
## the running app, and a fast one stood still from its first frames. Now the
## stroke step gives each report the time it was made and the brush feeds
## the smoother once a report, and the last three cases hold that a burst reads
## the pen.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const ScenarioStroke := preload("res://harness/scenario/sa_scenario_stroke.gd")
const SpeedTrace := preload("res://harness/captures/speed_trace_capture.gd")

## The canvas, whose short side the brush's radius is a fraction of.
const SIZE := Vector2i(1024, 512)
## The press, and the length of the straight stroke to the right of it.
const FROM := Vector2(100, 256)
const LENGTH: float = 750.0
## The default brush's 25 px radius on a 1080 px document, so its dabs are
## spaced as the scenario's are, nine pixels apart.
const RADIUS_PX: float = 25.0
## The pen's speed in document pixels a millisecond, a twentieth of what the
## sensor reads as full. Frame paced, that is thirty moves of 25 px.
const PEN: float = 1.5
## A pen's reports a second, the rate the scenarios paint at.
const RATE: float = 240.0
## A frame of a sixtieth of a second, and one the load stretches to 50 ms.
const FRAME_USEC: int = 16667
const LOAD_USEC: int = 50000

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _was_pinned: bool = false
## Whether a frame's events are timed by the capture's clock rather than the
## engine's.
var _pinned: bool = true


## The input driver handing each report of a burst to the brush, as the window
## would hand it a motion.
class BrushInput:
    extends "res://harness/drivers/sa_input_driver.gd"

    var bursts: Array[int] = []
    var _surface: SaSurface = null
    var _brush: Object = null

    func _init(run: CaptureRun, surface: SaSurface, brush: Object) -> void:
        super(run)
        _surface = surface
        _brush = brush

    ## Each report at the time it carries, as the driver's own burst sends it.
    func motion_burst(raw: Variant) -> void:
        bursts.append((raw as Array).size())
        for entry: Dictionary in raw as Array:
            var coords := entry["at"] as Array
            var motion := InputEventMouseMotion.new()
            motion.pressure = float(entry.get("pressure", 0.8))
            _surface.view.mouse_position = Vector2(float(coords[0]), float(coords[1]))
            SaPenClock.held(int(entry["made_usec"]), _brush.handle_input.bind(motion))


func before_each() -> void:
    _was_pinned = SaPenClock.is_pinned()
    SaPenClock.pin_to_frames()
    _pinned = true
    _surface = Fixtures.make_surface(SIZE)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _machine.active_tool.settings.radius = RADIUS_PX / float(mini(SIZE.x, SIZE.y))


func after_each() -> void:
    SaPenClock.unpin()
    if _was_pinned:
        # A suite has no frames of its own, so the pin taken here counts from
        # this frame, which is the one the run it interrupted was in.
        SaPenClock.pin_to_frames()
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


## Frame paced, the speeds read do not move with the frames' cost, because a
## capture's clock counts frames: thirty moves under a 50 ms load read the
## same speed at every dab as thirty with no load at all, and near the pen's.
func test_a_frame_paced_stroke_reads_the_same_speeds_under_a_load() -> void:
    var moves := roundi(LENGTH / (PEN * SaPenClock.FRAME_MS))
    var free := _frame_paced(moves, 0)
    var loaded := _frame_paced(moves, LOAD_USEC)
    var spread := SpeedTrace.spread(loaded)
    _say("frame paced, %d frames under the load" % moves, spread, PEN)
    assert_eq(_speeds(loaded), _speeds(free), "Every dab reads the speed it read with no load")
    assert_true(int(spread["dabs"]) > 60, "The stroke laid its dabs, %d" % spread["dabs"])
    assert_almost_eq(float(spread["mean"]), PEN, PEN * 0.1, "and their mean is within a tenth of the pen's")


## At a rate, a frame the load stretches carries three times the reports, and
## each reads the time it was due rather than the frame's, so the brush reads
## the pen at every dab, the same speeds as with frames of a sixtieth. Before
## the fix the loaded stroke read 16.9 px/ms for this pen of 1.5.
func test_a_rate_stroke_under_a_load_reads_the_pen() -> void:
    var reports := roundi(LENGTH / PEN * RATE / 1000.0)
    var free := _rated(reports, FRAME_USEC)
    var loaded := _rated(reports, LOAD_USEC)
    var at_frames := SpeedTrace.spread(free["dabs"])
    var under_load := SpeedTrace.spread(loaded["dabs"])
    _say("rate 240, %s reports a frame" % _burst(free["bursts"]), at_frames, PEN)
    _say("rate 240 under the load, %s reports a frame" % _burst(loaded["bursts"]), under_load, PEN)
    var bigger := "The load makes the bursts bigger, %s reports a frame against %s"
    assert_true(
        _burst_mean(loaded["bursts"]) > 2.0 * _burst_mean(free["bursts"]),
        bigger % [_burst(loaded["bursts"]), _burst(free["bursts"])]
    )
    assert_almost_eq(
        float(under_load["mean"]),
        PEN,
        0.1,
        "Under the load the brush reads %.3f px/ms for a pen of %.2f" % [under_load["mean"], PEN]
    )
    assert_eq(_speeds(loaded["dabs"]), _speeds(free["dabs"]), "and every dab reads what it read with frames of a sixtieth")


## The engine's clock, a painter's brush's, reads the pen as well: the stroke
## step gives each report the time it was made on whichever clock runs. Before the fix
## it read 15.8 px/ms for this pen of 1.5.
func test_on_the_engines_clock_a_burst_reads_the_pen() -> void:
    SaPenClock.unpin()
    _pinned = false
    var reports := roundi(LENGTH / PEN * RATE / 1000.0)
    var loaded := _rated(reports, LOAD_USEC)
    var spread := SpeedTrace.spread(loaded["dabs"])
    _say("rate 240 under the load on the engine's clock", spread, PEN)
    assert_almost_eq(float(spread["mean"]), PEN, 0.1, "The brush reads %.3f px/ms for a pen of %.2f" % [spread["mean"], PEN])


## A fast stroke at a rate follows its speed to the lift, its second half
## within a tenth of the pen at every dab, and so does the same pen frame
## paced, whose eight moves of 94 pixels make it a pen of 5.63 px/ms.
## Before the fix the rate stroke read nought at all 83 dabs here, 3.24 px/ms from
## the eighth dab in the running app, and frame paced it read 17.7 for a pen
## of 6.
func test_a_fast_rate_stroke_follows_its_speed_to_the_lift() -> void:
    var fast := PEN * 4.0
    var rated := _rated(roundi(LENGTH / fast * RATE / 1000.0), FRAME_USEC)
    var spread := SpeedTrace.spread(rated["dabs"])
    _say("rate 240 at four times the speed", spread, fast)
    var late := _late(rated["dabs"])
    assert_true(int(spread["dabs"]) > 60, "The stroke laid its dabs, %d" % spread["dabs"])
    assert_almost_eq(late.min(), fast, fast * 0.1, "Its second half reads the pen's %.2f px/ms, from %.3f" % [fast, late.min()])
    assert_almost_eq(late.max(), fast, fast * 0.1, "to %.3f" % late.max())
    var moves := roundi(LENGTH / (fast * SaPenClock.FRAME_MS))
    var paced_pen := LENGTH / (float(moves) * SaPenClock.FRAME_MS)
    var paced := _frame_paced(moves, 0)
    var paced_spread := SpeedTrace.spread(paced)
    _say("frame paced at four times the speed", paced_spread, paced_pen)
    var paced_late := _late(paced)
    var reads := "Frame paced it reads its pen's %.3f px/ms, from %.3f" % [paced_pen, paced_late.min()]
    assert_almost_eq(paced_late.min(), paced_pen, 0.001, reads)
    assert_almost_eq(paced_late.max(), paced_pen, 0.001, "to %.3f" % paced_late.max())


## One move a frame, the stroke step's default, each frame *frame_usec* of wall
## time after the last. Answers the dabs the brush counted.
func _frame_paced(moves: int, frame_usec: int) -> Array[PackedFloat64Array]:
    var recorder := SpeedTrace.Recorder.new()
    _machine.active_tool.stroke_info = recorder
    _surface.view.mouse_position = FROM
    _at_frame(0, _button.bind(true))
    for k in range(1, moves + 1):
        OS.delay_usec(frame_usec)
        _at_frame(k, _motion.bind(FROM + Vector2(LENGTH * float(k) / float(moves), 0.0)))
    _at_frame(moves + 1, _button.bind(false))
    return recorder.dabs


## *reports* at a pen's [constant RATE], through the stroke step's own pacing,
## each frame *frame_usec* of wall time after the last. Answers the dabs and the
## size of each burst.
func _rated(reports: int, frame_usec: int) -> Dictionary:
    var recorder := SpeedTrace.Recorder.new()
    _machine.active_tool.stroke_info = recorder
    var run := CaptureRun.new()
    var input := BrushInput.new(run, _surface, _machine.active_tool)
    var stroke := ScenarioStroke.new(run, input)
    var to := FROM + Vector2(LENGTH, 0.0)
    stroke.stroke({"from": [FROM.x, FROM.y], "to": [to.x, to.y], "steps": reports, "rate": RATE})
    _surface.view.mouse_position = FROM
    _at_frame(0, _button.bind(true))
    var frame := 1
    var paced := _next_paced(run)
    while not paced.is_empty():
        _at_frame(frame, stroke.stroke.bind({"paced": paced}))
        frame += 1
        OS.delay_usec(frame_usec)
        paced = _next_paced(run)
    _at_frame(frame, _button.bind(false))
    return {"dabs": recorder.dabs, "bursts": input.bursts}


## Runs *work* at the time a capture's clock reads *frame* frames after its pin,
## or at the engine's own time when the case unpinned it.
func _at_frame(frame: int, work: Callable) -> void:
    if _pinned:
        SaPenClock.held(SaPenClock.after_frames(frame), work)
    else:
        work.call()


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _machine.active_tool.handle_input(event)


func _motion(at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.pressure = 0.8
    _surface.view.mouse_position = at
    _machine.active_tool.handle_input(motion)


## The paced step the run holds next, taken out of the run as the runner would
## by stepping past it, or an empty dictionary once the release is all that is
## left.
func _next_paced(run: CaptureRun) -> Dictionary:
    for at: int in range(run.step_index, run.steps.size()):
        var step: Dictionary = run.steps[at]
        if step.has("stroke") and (step["stroke"] as Dictionary).has("paced"):
            run.step_index = at + 1
            return (step["stroke"] as Dictionary)["paced"]
    return {}


static func _speeds(dabs: Array[PackedFloat64Array]) -> Array[float]:
    var out: Array[float] = []
    for row: PackedFloat64Array in dabs:
        out.append(row[3])
    return out


## The speeds the later half of *dabs* read.
static func _late(dabs: Array[PackedFloat64Array]) -> Array[float]:
    var speeds := _speeds(dabs)
    return speeds.slice(floori(float(speeds.size()) * 0.5))


## The mean burst before the last, which is only what was left of the stroke.
static func _burst_mean(bursts: Array[int]) -> float:
    var middle := bursts.slice(0, maxi(1, bursts.size() - 1))
    var sum := 0
    for size: int in middle:
        sum += size
    return float(sum) / float(maxi(1, middle.size()))


static func _burst(bursts: Array[int]) -> String:
    return "%.1f" % _burst_mean(bursts)


## The spread a pacing read, printed so the run's log carries the figures.
static func _say(pacing: String, spread: Dictionary, pen: float) -> void:
    print(
        (
            "  rate burst: %s, pen %.2f px/ms: %d dabs over %d times, %.3f px/ms mean, %.3f sd, %.3f to %.3f, sensor %.4f"
            % [
                pacing,
                pen,
                spread["dabs"],
                spread["times"],
                spread["mean"],
                spread["sd"],
                spread["min"],
                spread["max"],
                spread["sensor"],
            ]
        )
    )
