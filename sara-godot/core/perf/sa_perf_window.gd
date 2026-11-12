## One measuring window over the five ledgers, and the block it leaves behind.
##
## `SaCompute` counts dispatches, `SaGpuTiming` times them on the GPU,
## `SaVramReport` weighs the memory, `SaBootMarks` kept the boot and
## `SaStrokeLedger` follows an event to its post draw. Each answers one question
## and none of them says "during this stroke". A window does: `begin` remembers
## where every cumulative counter stood, `end` subtracts, and what comes out is
## one dictionary the dump and the door both carry as `perf`.
##
## **Nothing shared is reset.** The four counters of `SaCompute`, its per-kernel
## tally and the copy statics of `SaTexture` are read from two places at once,
## the Info docker's delta for one, so the window snapshots them and leaves them
## alone. The stroke ledger and the GPU timing keep a minimum and a maximum,
## which cannot be differenced, and nothing but a window reads them, so those two
## are the window's to clear.
##
## **Nothing is read back and nothing is dispatched to measure** (hard rules 1
## and 2). `end` draws two frames, which is the main device's frame delay, so the
## timestamp pairs of the window's last frames have resolved before they are
## folded. A number comes back from the driver and no texel does.
##
## The GPU timing flag is on between `begin` and `end` and off everywhere else,
## which is the one measure behind a flag and `SaGpuTiming` says why.
class_name SaPerfWindow
extends RefCounted

## What every answer of the step starts with, the run log's own prefix first.
const LINE := "SaCapture: measure perf %s"

## How many frames `end` draws before it folds. The main device hands a frame's
## timestamps back this many frames later.
const FORCED_DRAWS: int = 2

## The block the last `end` folded, or the one a `read` folded when no window
## had closed yet. Read by the dump as `perf`. Replaced whole and never edited,
## so a reader holding the old one holds a finished block.
static var last_block: Dictionary[String, Variant] = {}

## The typed empty tally a kernel reads as its `begin` figures when it first ran
## inside the window, so the typed local it lands in takes it.
const _NO_TALLY: Dictionary[String, int] = {}

static var _is_open: bool = false
static var _has_closed: bool = false

## Where every cumulative figure stood at `begin`.
static var _at: Dictionary[String, Variant] = {}

## The steps the open window held, timed around each one by `hold_step`, so a
## step that costs a quarter of a millisecond shows as one rather than as the
## frame it waited for. Cleared by `begin`.
static var _steps: int = 0
static var _steps_usec: int = 0
static var _steps_usec_max: int = 0


## The perf form of the `measure` step: *form* is `begin`, `end` or `read`.
##
## The answer is one line. A refusal is a line too and changes nothing, so a
## scenario that begins twice reads the second as refused in its run log and the
## first window is still the one its `end` closes.
##
## Handed the document the window is measured over, null before one exists,
## rather than the harness's runner to ask for it, which would be a `core` file
## calling up by name into a node it cannot type.
##
## *trace* on a `begin` prints a `Sara frame:` line at every frame of the
## window, `SaFrameTrace`'s, and its `end` turns the trace off again.
static func capture(document: SaDocument, form: String, trace: bool = false) -> String:
    match form:
        "begin":
            if _is_open:
                return LINE % "refused, a window is already open"
            _begin(document)
            if trace:
                SaFrameTrace.start()
            return LINE % JSON.stringify({"window": {"open": true}})
        "end":
            if not _is_open:
                return LINE % "refused, no window is open"
            _end(document)
        "read":
            if not _has_closed:
                last_block = _resting_block(document)
        _:
            return LINE % ("refused, %s is not begin, end or read" % form)
    return LINE % JSON.stringify(last_block)


## Runs *step* through *runner* and, when a window is open and the step is not
## a `measure` of its own, adds the time it took to the window's steps. The
## window's `usec` is paced by frames, one step to a frame, so six tool switches
## read about 169 ms whatever a switch costs. This clock is around the call
## alone, and what the step defers to a later frame is not in it.
##
## *step* stays an untyped Dictionary: it is a scenario line the harness parsed
## from JSON and hands on whole, and this only asks it for a key.
static func hold_step(step: Dictionary, runner: Callable) -> void:
    var began := Time.get_ticks_usec()
    var traced := SaFrameTrace.now()
    runner.call(step)
    SaFrameTrace.spent("scenario step", traced)
    if not _is_open or step.has("measure"):
        return
    var took := Time.get_ticks_usec() - began
    _steps += 1
    _steps_usec += took
    _steps_usec_max = maxi(_steps_usec_max, took)


## Back to a process that never measured: no window, no block, the flag off.
## A suite's `before_each`, because the statics outlive every test in the run.
static func forget() -> void:
    SaFrameTrace.stop()
    SaGpuTiming.enabled = false
    last_block = {}
    _at = {}
    _is_open = false
    _has_closed = false
    _clear_steps()


static func _clear_steps() -> void:
    _steps = 0
    _steps_usec = 0
    _steps_usec_max = 0


static func _begin(document: SaDocument) -> void:
    var easel := _easel_of(document)
    _at = {
        "counters": SaCompute.counters(),
        "kernels": SaCompute.kernel_counters(),
        "copies": SaTexture.copies,
        "copied_bytes": SaTexture.copied_bytes,
        "composite_count": easel.composite_count if easel != null else 0,
        "composite_usec": easel.composite_usec_total if easel != null else 0,
        "frames_drawn": Engine.get_frames_drawn(),
        "process_frames": Engine.get_process_frames(),
        "usec": Time.get_ticks_usec(),
    }
    SaStrokeLedger.reset()
    _clear_steps()
    SaGpuTiming.enabled = true
    SaGpuTiming.reset()
    _is_open = true


static func _end(document: SaDocument) -> void:
    # Before the draws below, which are the window's measuring and no frame of it.
    var traced := SaFrameTrace.lines if SaFrameTrace.enabled else 0
    SaFrameTrace.stop()
    # The draws come before anything else reads the window, a shot above all: a
    # frame that reads a texture back loses the captures taken before it. They
    # never present: the device's frame moves without one, and a present waits
    # on the compositor, which can hang a whole run.
    var forced := 0
    if RenderingServer.get_rendering_device() != null:
        for _i: int in FORCED_DRAWS:
            RenderingServer.force_draw(false)
            SaGpuTiming.collect()
            forced += 1
    var timing := SaGpuTiming.block()
    SaGpuTiming.enabled = false

    var easel := _easel_of(document)
    var counters := SaCompute.counters()
    var before: Dictionary[String, int] = _at["counters"]
    for key: String in counters:
        counters[key] -= before.get(key, 0)

    var ledger := SaStrokeLedger.block()
    var frames := {
        "drawn": ledger["frames_drawn"],
        "dab_frame_interval": ledger["dab_frame_interval"],
        "process_usec_max": ledger["process_usec_max"],
        "frame_gap_usec_max": ledger["frame_gap_usec_max"],
    }
    ledger.erase("frames_drawn")
    ledger.erase("dab_frame_interval")
    ledger.erase("process_usec_max")
    ledger.erase("frame_gap_usec_max")

    var block := _resting_block(document)
    block["window"] = {
        "open": false,
        # A forced draw moves the device on and not the engine's count, so the
        # two are told apart rather than added.
        "frames_drawn": Engine.get_frames_drawn() - _whole(_at, "frames_drawn"),
        "forced_draws": forced,
        "process_frames": Engine.get_process_frames() - _whole(_at, "process_frames"),
        "usec": Time.get_ticks_usec() - _whole(_at, "usec"),
        "steps": _steps,
        "steps_usec": _steps_usec,
        "steps_usec_max": _steps_usec_max,
        "traced_frames": traced,
        "traced_peaks_usec": SaFrameTrace.peaks.duplicate(),
    }
    block["counters"] = counters
    var timed: Dictionary[String, Dictionary] = timing["kernels"]
    block["kernels"] = _kernels(timed)
    block["gpu_time"] = _gpu_time(timing)
    block["reads"] = timing["reads"]
    block["composite"] = _category(timing, "composite")
    block["composite"]["count"] = (easel.composite_count if easel != null else 0) - _whole(_at, "composite_count")
    block["composite"]["issue_usec"] = (easel.composite_usec_total if easel != null else 0) - _whole(_at, "composite_usec")
    block["commit"] = _category(timing, "commit")
    block["stroke"] = ledger
    block["frames"] = frames
    block["copies"] = {
        "copies": SaTexture.copies - _whole(_at, "copies"),
        "bytes": SaTexture.copied_bytes - _whole(_at, "copied_bytes"),
    }
    last_block = block
    _at = {}
    _is_open = false
    _has_closed = true


## The part of a block that needs no window: the device, the memory and the
## boot. What a `read` answers before any window has closed, which is what a boot
## scenario dumps, and what every closed block starts from.
static func _resting_block(document: SaDocument) -> Dictionary[String, Variant]:
    return {
        "window": {"open": _is_open},
        "device": _device(),
        "vram": _vram(document),
        "startup": SaBootMarks.table(),
    }


static func _device() -> Dictionary[String, Variant]:
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        return {"name": "none", "api": "", "local": false}
    return {
        "name": rd.get_device_name(),
        "api": "%s %s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_api_version()],
        # A local device resolves no timestamp, so `gpu_time` is empty on one
        # and this is the line that says why.
        "local": rd != RenderingServer.get_rendering_device(),
    }


## The capture's block with the two figures it left to the fold: the
## storage buffers `SaCompute` counts and the bytes the undo history holds.
static func _vram(document: SaDocument) -> Dictionary[String, Variant]:
    var out: Dictionary[String, Variant] = {"sara_textures": SaTexture.allocated_bytes}
    if document != null:
        out = SaVramReport.block(document)
    out["sara_buffers"] = SaCompute.buffer_bytes
    out["history_bytes"] = document.history.total_bytes() if document != null and document.history != null else 0
    return out


## The tally less where it stood at `begin`, joined per key with the open and
## close pairs. A kernel that did nothing in the window is left out, so the sum
## of `dispatches` over the keys is the window's `counters.dispatches`.
static func _kernels(timed: Dictionary[String, Dictionary]) -> Dictionary[String, Dictionary]:
    var out: Dictionary[String, Dictionary] = {}
    var now := SaCompute.kernel_counters()
    var before: Dictionary[String, Dictionary] = _at["kernels"]
    for key: String in now:
        var entry: Dictionary[String, int] = now[key]
        var was: Dictionary[String, int] = before.get(key, _NO_TALLY)
        var moved := false
        for field: String in entry:
            entry[field] -= was.get(field, 0)
            moved = moved or entry[field] != 0
        if moved:
            out[key] = entry
    for key: String in timed:
        var pairs: Dictionary[String, Variant] = timed[key]
        var entry: Dictionary[String, int] = {"lists": 0, "dispatches": 0, "workgroups": 0}
        if out.has(key):
            entry = out[key]
        entry["gpu"] = _whole(pairs, "gpu_ticks")
        entry["gpu_max"] = _whole(pairs, "gpu_ticks_max")
        entry["pairs"] = _whole(pairs, "pairs")
        entry["skipped"] = _whole(pairs, "skipped")
        out[key] = entry
    return out


static func _gpu_time(timing: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
    var pairs := 0
    for table: String in ["kernels", "categories"]:
        var entries: Dictionary[String, Dictionary] = timing[table]
        for key: String in entries:
            pairs += _whole(entries[key], "pairs")
    # The reads a list recorded and read inside one step waited in, summed over
    # the lists they followed. The block's `reads` keeps them by list.
    var reads := 0
    var read_wait_usec := 0
    var by_list: Dictionary[String, Dictionary] = timing["reads"]
    for key: String in by_list:
        reads += _whole(by_list[key], "reads")
        read_wait_usec += _whole(by_list[key], "wait_usec")
    var main := RenderingServer.get_rendering_device()
    return {
        "ticks_per_usec": timing["ticks_per_usec"],
        "pairs": pairs,
        "reads": reads,
        "read_wait_usec": read_wait_usec,
        "skipped": timing["skipped"],
        "frame_delay": main.get_frame_delay() if main != null else 0,
        "frames_collected": timing["frames_collected"],
        "readable_after_min": timing["readable_after_min"],
        "readable_after_max": timing["readable_after_max"],
    }


## One of the two categories, with the zeros of an entry nothing opened.
static func _category(timing: Dictionary[String, Variant], category: String) -> Dictionary[String, Variant]:
    var categories: Dictionary[String, Dictionary] = timing["categories"]
    var entry: Dictionary[String, Variant] = {}
    if categories.has(category):
        entry = categories[category]
    var load_table: Dictionary = entry.get("load", {})
    return {
        "pairs": _whole(entry, "pairs"),
        "gpu": _whole(entry, "gpu_ticks"),
        "gpu_max": _whole(entry, "gpu_ticks_max"),
        "cpu_usec": _whole(entry, "cpu_usec"),
        "skipped": _whole(entry, "skipped"),
        "load": load_table.duplicate(),
    }


## The whole number *table* holds under *key*, nought when it holds none. Every
## figure of the capture is a count or a tally of ticks.
static func _whole(table: Dictionary, key: String) -> int:
    var value: int = table.get(key, 0)
    return value


## The easel holding *document*, which is its parent in every easel built.
static func _easel_of(document: SaDocument) -> SaEasel:
    return document.get_parent() as SaEasel if document != null else null
