## Where the boot's time actually went, kept as it happens rather than measured
## after the fact.
##
## A ready line of one number, "Ready in N ms", cannot say whether that number
## was kernels compiling, modules registering or something else entirely. This
## class is the seam every
## phase writes a mark into, timed from outside the phase rather than from
## within it: `ModuleLoader` times a module's `register()` call rather than
## asking the module to time itself, which is what lets a third-party module be
## measured the same way a built-in is (hard rule 6).
##
## Static and never reset between boots in the same process, because the one
## process that boots twice is a test, and `test_boot_marks.gd` wants to see
## the real boot's own marks, not a cleared table.
class_name SaBootMarks
extends RefCounted

static var _marks: Dictionary[StringName, int] = {}

## Bumped by `GlobalShaderCompiler` as each kernel's SPIR-V is served from the
## cache or compiled fresh. Every kernel takes exactly one path, so the two sum
## to the kernel count.
static var spirv_cache_hits: int = 0
static var spirv_compiles: int = 0

## How many entries `SaSpirvCache.prune()` dropped on the compiler's startup
## pass, written from its own return value. Zero on a cache under the cap, which
## is the ordinary case, so a reading of zero says the prune found nothing to do
## rather than that nobody measured it.
##
## It is the one number that says whether the boot gap the `spirv_cache_pruned`
## mark splits is the prune or the four autoloads after it, and it stays whole across a cold run
## that filled the directory and a warm one that did not.
static var spirv_cache_pruned_count: int = 0

## module id -> the microseconds its own `register()` call took, written by
## `ModuleLoader` from outside the call.
static var module_usec: Dictionary[StringName, int] = {}

## kind of work -> the microseconds the start spent on it, added by the code
## that did the work through [method add_work], timed from outside it as a
## module's `register()` is. The kinds a span of two marks already says are not
## kept here but read off the marks by [constant SPANS].
static var work_usec: Dictionary[StringName, int] = {}

## The kinds of work the start's marks measure on their own, each as
## `[kind, from mark, to mark]`, an empty from mark being the engine's start.
## The modules' own stage is left out, because the modules' own lines split it.
const SPANS: Array[Array] = [
    [&"engine", &"", &"run_log_init"],
    [&"script graph", &"run_log_init", &"compiler_init_begin"],
    [&"kernels", &"kernels_begin", &"kernels_end"],
    [&"interface", &"main_init", &"ui_built"],
    [&"waiting for module scripts", &"ui_built", &"module_scripts_loaded"],
    [&"tools and commands", &"modules_registered", &"ready"],
]

## The frames the boot drew while it went on, kept as the longest wait between
## two of them, which is how long the welcome window stood still at worst.
## `_last_frame_usec` is the frame before the one being waited on.
static var _last_frame_usec: int = 0
static var _longest_frame_usec: int = 0
static var _longest_frame_from_usec: int = 0

## A frame of the boot longer than this is kept in `_long_frames`, so the table
## names every stage that held the window rather than the worst one alone. A
## third of the 300 ms the boot holds each frame under.
const LONG_FRAME_USEC := 100000

## `[from_usec, usec]` of each frame of the boot over `LONG_FRAME_USEC`, in the
## order they came.
static var _long_frames: Array[PackedInt64Array] = []


## Keeps the first call of *name*. A mark says "we got here", not "we got here
## again", so a second call of the same name during one boot is silently kept
## rather than overwriting the first.
static func mark(name: StringName) -> void:
    if _marks.has(name):
        return
    _marks[name] = Time.get_ticks_usec()


## `mark` as an expression, for the one place a statement cannot stand: the
## first member of `Main`, whose initialiser runs the moment the main scene's
## load ends and before any other member is built. Always true.
static func marked(name: StringName) -> bool:
    mark(name)
    return true


static func has_mark(name: StringName) -> bool:
    return _marks.has(name)


## Adds the time since *since_usec* to *kind*'s share of the start. A kind
## measured twice, a catalogue for each language say, sums.
static func add_work(kind: StringName, since_usec: int) -> void:
    work_usec[kind] = work_usec.get(kind, 0) + Time.get_ticks_usec() - since_usec


## Every kind's time together, which the module loader reads on both sides of a
## module's `register()` so work a module asked for, its catalogue, is a kind's
## share and not counted again in the module's own.
static func work_total_usec() -> int:
    var total := 0
    for kind: StringName in work_usec:
        total += work_usec[kind]
    return total


## The start's shares in milliseconds, `{modules: {id: ms}, work: {kind: ms}}`:
## each module's own `register()`, and each kind of work that is no module's,
## the ones [method add_work] timed and the ones [constant SPANS] reads off
## *marks*, a kind whose marks are not both there left out. Read from the given
## tables rather than this start's, so a suite can set them.
static func shares_of(
    marks: Dictionary[StringName, int], modules: Dictionary[StringName, int], work: Dictionary[StringName, int]
) -> Dictionary[String, Dictionary]:
    var module_ms: Dictionary[StringName, float] = {}
    for module_id: StringName in modules:
        module_ms[module_id] = modules[module_id] / 1000.0
    var work_ms: Dictionary[StringName, float] = {}
    for kind: StringName in work:
        work_ms[kind] = work[kind] / 1000.0
    for span: Array in SPANS:
        var from: StringName = span[1]
        var to: StringName = span[2]
        if marks.has(to) and (from.is_empty() or marks.has(from)):
            var began: int = 0 if from.is_empty() else marks[from]
            work_ms[span[0]] = (marks[to] - began) / 1000.0
    return {"modules": module_ms, "work": work_ms}


## Called on every frame the boot processes, from its first frame until
## `boot_finished`, so the table can say how long the longest one waited.
static func boot_frame() -> void:
    var now := Time.get_ticks_usec()
    var waited := now - _last_frame_usec
    if _last_frame_usec > 0 and waited > _longest_frame_usec:
        _longest_frame_usec = waited
        _longest_frame_from_usec = _last_frame_usec
    if _last_frame_usec > 0 and waited > LONG_FRAME_USEC:
        _long_frames.append(PackedInt64Array([_last_frame_usec, waited]))
    _last_frame_usec = now


## `{marks: {name: msec}, cache_hits, compiles, spirv_cache_pruned_count,
## modules: {id: msec}, shares, kernels_ms, engine_to_main_init_ms,
## main_init_to_ready_ms, bootstrap_to_ready_ms, first_frame_ms,
## longest_boot_frame_ms, longest_boot_frame_from_ms, long_boot_frames}`.
##
## Every mark is milliseconds since the engine started, so `ready` itself is
## the whole wait before Sara answers and is what the ready line prints.
## `engine_to_main_init_ms` is the engine, every autoload's `_init` (the
## kernels among them) and the main scene's load. `main_init_to_ready_ms` is
## the rest. `bootstrap_to_ready_ms` is `Main._ready` alone, and `sara_perf.py`
## also reads it under the name `engine_to_ready_ms`.
##
## Each span is present only once both of its marks are, so a quiet process
## under low-processor mode that never queued a redraw omits `first_frame_ms`
## instead of reporting a zero that never happened. `longest_boot_frame_ms` is
## the longest wait between two frames of the boot and `_from_ms` when it began,
## present once `boot_frame` has seen two frames. `long_boot_frames` is every
## frame over `LONG_FRAME_USEC` as `{from_ms, ms}`, present once there is one.
## `shares` is [method shares_of] for this start.
static func table() -> Dictionary[String, Variant]:
    var marks_msec: Dictionary[StringName, float] = {}
    for name: StringName in _marks:
        marks_msec[name] = _marks[name] / 1000.0

    var modules_msec: Dictionary[StringName, float] = {}
    for module_id: StringName in module_usec:
        modules_msec[module_id] = module_usec[module_id] / 1000.0

    var out: Dictionary[String, Variant] = {
        "marks": marks_msec,
        "cache_hits": spirv_cache_hits,
        "compiles": spirv_compiles,
        "spirv_cache_pruned_count": spirv_cache_pruned_count,
        "modules": modules_msec,
        "shares": shares_of(_marks, module_usec, work_usec),
    }
    if _marks.has(&"kernels_begin") and _marks.has(&"kernels_end"):
        out["kernels_ms"] = (_marks[&"kernels_end"] - _marks[&"kernels_begin"]) / 1000.0
    if _marks.has(&"main_init"):
        out["engine_to_main_init_ms"] = _marks[&"main_init"] / 1000.0
    if _marks.has(&"main_init") and _marks.has(&"ready"):
        out["main_init_to_ready_ms"] = (_marks[&"ready"] - _marks[&"main_init"]) / 1000.0
    if _marks.has(&"bootstrap_begin") and _marks.has(&"ready"):
        out["bootstrap_to_ready_ms"] = (_marks[&"ready"] - _marks[&"bootstrap_begin"]) / 1000.0
    if _marks.has(&"ready") and _marks.has(&"first_frame_after_ready"):
        out["first_frame_ms"] = (_marks[&"first_frame_after_ready"] - _marks[&"ready"]) / 1000.0
    if _longest_frame_usec > 0:
        out["longest_boot_frame_ms"] = _longest_frame_usec / 1000.0
        out["longest_boot_frame_from_ms"] = _longest_frame_from_usec / 1000.0
    if not _long_frames.is_empty():
        var long_frames: Array[Dictionary] = []
        for frame: PackedInt64Array in _long_frames:
            long_frames.append({"from_ms": frame[0] / 1000.0, "ms": frame[1] / 1000.0})
        out["long_boot_frames"] = long_frames
    return out


## The ready line's figure, the `ready` mark in whole milliseconds since the
## engine started, or -1 before the boot reached it. The time since
## `Main._ready` began would leave out the engine, the autoloads and the scene
## load, more than half of the wait.
static func ready_line_ms() -> int:
    if not _marks.has(&"ready"):
        return -1
    return roundi(_marks[&"ready"] / 1000.0)


## A span of the boot before `Main` begins that took longer than this is
## named on the ready line by its two marks. Half a second, which a warm boot
## stays under in every span but the engine's own and the kernels, so a fast
## boot prints the bare line.
const NAMED_SPAN_USEC := 500000

## The mark the first autoload writes as Sara's code begins. Everything before
## it is the engine's own: the device, Godot's renderer shaders and their
## cache.
const SARA_BEGINS := &"run_log_init"


## The ready line's note, the figure split where `Main` begins: `engine and
## autoloads 4064 ms (kernels 467 ms, 90 cached, 0 compiled), main to ready
## 2025 ms (modules 7 ms)`. Empty where a figure has nothing to show, so a
## test boot that never reaches the kernel loop prints no empty parenthesis.
## Inside the first half, beside the kernels, it names the engine's own part
## and every span over `NAMED_SPAN_USEC`, as `summary_of` says.
static func summary() -> String:
    return summary_of(_marks, module_usec, spirv_cache_hits, spirv_compiles)


## `summary` read from the given marks rather than this boot's, so a suite can
## set them at known times. *marks* is mark name to microseconds since the
## engine started, *modules* module id to microseconds.
##
## The engine's own part is the `SARA_BEGINS` mark itself, printed as `engine
## N ms` once it is over the threshold. Every other span is the time between
## two marks next to each other in time, both at or before `main_init`,
## printed as `from to to N ms`. The kernels' own span is left out, and so is
## every mark inside it, because the kernels are already named with their
## counts and a frame drawn between two slices of them is not a span of its
## own.
static func summary_of(
    marks: Dictionary[StringName, int], modules: Dictionary[StringName, int], hits: int, compiles: int
) -> String:
    var inside: PackedStringArray = []
    if marks.has(&"kernels_begin") and marks.has(&"kernels_end"):
        var kernels_msec := (marks[&"kernels_end"] - marks[&"kernels_begin"]) / 1000.0
        inside.append("kernels %d ms, %d cached, %d compiled" % [kernels_msec, hits, compiles])
    if marks.has(&"main_init"):
        inside.append_array(_named_spans(marks))
    var modules_text := ""
    if not modules.is_empty():
        var modules_total_usec := 0
        for module_id: StringName in modules:
            modules_total_usec += int(modules[module_id])
        modules_text = "modules %d ms" % (modules_total_usec / 1000.0)

    var parts: PackedStringArray = []
    if marks.has(&"main_init"):
        parts.append(_span("engine and autoloads", marks[&"main_init"] / 1000.0, ", ".join(inside)))
    elif not inside.is_empty():
        parts.append(", ".join(inside))
    if marks.has(&"main_init") and marks.has(&"ready"):
        parts.append(_span("main to ready", (marks[&"ready"] - marks[&"main_init"]) / 1000.0, modules_text))
    elif modules_text != "":
        parts.append(modules_text)
    return ", ".join(parts)


## The engine's own part and the spans over the threshold before `main_init`,
## in the order the boot reached them.
static func _named_spans(marks: Dictionary[StringName, int]) -> PackedStringArray:
    var end_usec: int = marks[&"main_init"]
    var has_kernels := marks.has(&"kernels_begin") and marks.has(&"kernels_end")
    var order: Array[StringName] = []
    for name: StringName in marks:
        var at: int = marks[name]
        if at > end_usec:
            continue
        if has_kernels and at > marks[&"kernels_begin"] and at < marks[&"kernels_end"]:
            continue
        order.append(name)
    order.sort_custom(func(a: StringName, b: StringName) -> bool: return marks[a] < marks[b])

    var named: PackedStringArray = []
    if marks.has(SARA_BEGINS) and marks[SARA_BEGINS] > NAMED_SPAN_USEC:
        named.append("engine %d ms" % (marks[SARA_BEGINS] / 1000.0))
    for i in range(1, order.size()):
        var from := order[i - 1]
        var to := order[i]
        if from == &"kernels_begin" and to == &"kernels_end":
            continue
        var usec: int = marks[to] - marks[from]
        if usec > NAMED_SPAN_USEC:
            named.append("%s to %s %d ms" % [from, to, usec / 1000.0])
    return named


static func _span(label: String, msec: float, inside: String) -> String:
    var text := "%s %d ms" % [label, msec]
    if inside != "":
        text += " (%s)" % inside
    return text
