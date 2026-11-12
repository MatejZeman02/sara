## What the speed sensor read at each dab of a stroke, with a load that slows
## the frames when one is asked for.
##
## A stroke's `rate` sends every report due since the frame before as one
## burst, and the brush times each report off `SaPenClock`, which a capture pins
## to its frames. Whether a burst bends the speed the brush reads is a question
## of the times its reports read, and a picture cannot answer it, because the speed is
## a number the dynamics read and nothing draws. So the trace puts a [Recorder]
## in the active brush's place of its `stroke_info`, which writes down each
## dab's place, time and speed as the brush counts it, and puts the brush's own
## back at the end.
@tool
class_name SaSpeedTraceCapture
extends RefCounted

## The name the running trace's node is found by at its end.
const NODE_NAME := "SaSpeedTrace"


## The stroke's sample as the brush keeps it, and every dab it counts written
## down: its place, the time it read in milliseconds, the smoother's speed in
## document pixels a millisecond and the sensor's 0 to 1.
class Recorder:
    extends SaStrokeInfo

    var dabs: Array[PackedFloat64Array] = []

    func next_dab() -> void:
        super()
        dabs.append(PackedFloat64Array([position.x, position.y, elapsed_ms, _last_speed, drawing_speed()]))


## The trace while it runs: the tool, its own sample to put back, the recorder
## in its place and the wall time of each frame. A node, so the load is spent in
## its `_process` once a frame and the trace is found again by name at its end.
class Trace:
    extends Node

    var label: String = ""
    var tool: Object = null
    var recorder: Recorder = null
    var load_usec: int = 0
    var wall: bool = false
    var frame_ms: Array[float] = []
    var _own: SaStrokeInfo = null
    var _was_pinned: bool = false
    var _last_usec: int = 0

    func _init(named: String, held: Object, load_ms: float, wall_clock: bool) -> void:
        name = NODE_NAME
        label = named
        tool = held
        load_usec = roundi(maxf(load_ms, 0.0) * 1000.0)
        wall = wall_clock
        recorder = Recorder.new()
        _own = held.get("stroke_info")
        held.set("stroke_info", recorder)
        _was_pinned = SaPenClock.is_pinned()
        if wall and _was_pinned:
            SaPenClock.unpin()

    func _process(_delta: float) -> void:
        var now := Time.get_ticks_usec()
        if _last_usec > 0:
            frame_ms.append(float(now - _last_usec) / 1000.0)
        _last_usec = now
        if load_usec > 0:
            OS.delay_usec(load_usec)

    ## The brush's own sample back and the clock as the trace found it.
    func close() -> void:
        tool.set("stroke_info", _own)
        if wall and _was_pinned:
            SaPenClock.pin_to_frames()


## Writes down the speed each dab read: `{"speed_trace": {"begin": "name"}}`
## before a stroke and `{"speed_trace": {"end": true}}` after it.
##
## **Arguments.**
## - `begin` string, the trace's name, which its file is named after.
## - `load_ms` number, a busy wait added to every frame until the end.
## - `clock` string, `wall` for the engine's clock rather than the frames'.
## - `end` boolean, puts the brush's sample back and writes the trace.
##
## The load is the slow machine a `rate` stroke's bursts are for: a frame that
## takes three times as long is followed by three times the reports. `"clock":
## "wall"` reads the engine's clock for the length of the trace in place of the
## capture's pinned frames, which is the clock a painter's brush reads.
##
## The end writes `speed-<name>.json` beside the shots, a row a dab of `x`, `y`,
## the time in milliseconds, the speed in document pixels a millisecond and the
## sensor's reading, and answers one line with their spread and the frames'
## mean wall time. The first dab is left out of the spread, because it has no
## pair to measure between and reads nought.
static func run(tree: SceneTree, spec: Dictionary, out_dir: String = "") -> String:
    var running := tree.root.get_node_or_null(NODE_NAME) as Trace
    if spec.has("begin"):
        if running != null:
            return "SaCapture: speed trace %s is still running" % running.label
        var tool := _active_tool()
        if tool == null or not "stroke_info" in tool:
            return "SaCapture: speed trace found no brush with a stroke sample"
        var wall := String(spec.get("clock", "frames")) == "wall"
        tree.root.add_child(Trace.new(String(spec["begin"]), tool, float(spec.get("load_ms", 0.0)), wall))
        return "SaCapture: speed trace %s begun, load %.1f ms a frame" % [spec["begin"], float(spec.get("load_ms", 0.0))]
    if not spec.has("end"):
        return "SaCapture: a speed trace step is 'begin' or 'end'"
    if running == null:
        return "SaCapture: no speed trace to end"
    running.close()
    tree.root.remove_child(running)
    var line := _write(running, out_dir)
    running.queue_free()
    return line


## The spread of *dabs*' speeds, every dab after the first: how many, the mean,
## the standard deviation, the least and the most, in document pixels a
## millisecond, the sensor's mean, and how many distinct times the dabs read,
## which is the frames they were laid in under a pinned clock.
static func spread(dabs: Array[PackedFloat64Array]) -> Dictionary:
    var speeds: Array[float] = []
    var times := {}
    var sensor := 0.0
    for row: PackedFloat64Array in dabs.slice(1):
        speeds.append(row[3])
        sensor += row[4]
        times[row[2]] = true
    if speeds.is_empty():
        return {"dabs": 0, "mean": 0.0, "sd": 0.0, "min": 0.0, "max": 0.0, "sensor": 0.0, "times": 0}
    var mean := 0.0
    for speed in speeds:
        mean += speed
    mean /= float(speeds.size())
    var square := 0.0
    for speed in speeds:
        square += (speed - mean) * (speed - mean)
    return {
        "dabs": speeds.size(),
        "mean": mean,
        "sd": sqrt(square / float(speeds.size())),
        "min": speeds.min(),
        "max": speeds.max(),
        "sensor": sensor / float(speeds.size()),
        "times": times.size(),
    }


## The tool in hand on the document the painter is working on, whose dabs the
## trace records.
static func _active_tool() -> Object:
    var canvas := SaCanvasView.front_canvas()
    var machine := canvas.tool_machine() if canvas != null else null
    return machine.active_tool if machine != null else null


static func _write(trace: Trace, out_dir: String) -> String:
    var dabs := trace.recorder.dabs
    var summary := spread(dabs)
    var frame := 0.0
    for ms in trace.frame_ms:
        frame += ms
    frame /= maxf(1.0, float(trace.frame_ms.size()))
    var rows: Array = []
    for row: PackedFloat64Array in dabs:
        rows.append(
            [
                snappedf(row[0], 0.01),
                snappedf(row[1], 0.01),
                snappedf(row[2], 0.001),
                snappedf(row[3], 0.0001),
                snappedf(row[4], 0.0001)
            ]
        )
    var record := {
        "name": trace.label,
        "clock": "wall" if trace.wall else "frames",
        "load_ms": float(trace.load_usec) / 1000.0,
        "frame_ms": frame,
        "frames": trace.frame_ms.size(),
        "spread": summary,
        "columns": ["x", "y", "time_ms", "speed_px_per_ms", "sensor"],
        "dabs": rows,
    }
    if out_dir != "":
        var file := FileAccess.open(out_dir.path_join("speed-%s.json" % trace.label), FileAccess.WRITE)
        if file != null:
            file.store_string(JSON.stringify(record, "  "))
    return (
        (
            "SaCapture: speed trace %s, %d dabs over %d times, frames %.1f ms, "
            + "speed %.3f px/ms mean, %.3f sd, %.3f to %.3f, sensor %.4f"
        )
        % [
            trace.label,
            summary["dabs"],
            summary["times"],
            frame,
            summary["mean"],
            summary["sd"],
            summary["min"],
            summary["max"],
            summary["sensor"],
        ]
    )
