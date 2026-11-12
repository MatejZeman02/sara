## One line in the log for every frame of a perf window, naming what the frame
## spent its time on, so a long frame in any run says what it was.
##
## The perf window keeps the longest frame and no list of frames, which is
## right for a table and no help with a frame of half a second that comes back
## one run in ten. One such frame was met once and four runs with timers did
## not catch it again. So a window a scenario opens with `"trace": true` prints a
## `Sara frame:` line at every drawn frame, and the frame is cut where the
## engine cuts it:
##
## - **before the tick**, from where the frame's wait starts to the process
##   tick, which is the input the window handled, the physics step and the
##   pacer's sleep,
## - **process**, from the tick to the start of the drawing, which is every
##   node's `_process` and whatever the frame's deferred calls ran,
## - **draw**, from there to the post draw, which is the engine's drawing and
##   its wait on the device, with the card's own time beside it.
##
## Inside those, the places Sara's own work is known to grow with the stack
## hand their time to [method spent] under a name: the fold's pay, the easel's
## composite, the layers docker's rows and its follow of the document, the eye,
## the idle clock's stop and the search's warming of a settings page.
## A part that took more than [constant PART_USEC] is named with its time, and
## what the three phases spent outside every named part is named as well, so a
## frame whose time went somewhere nothing names still says in which phase.
##
## **Whether Sara had a core.** A frame whose every part took ten times its
## usual time is not ten slow parts, and only the scheduler knows. On Linux the
## main thread's `/proc/thread-self/schedstat` says how long it ran and how
## long it waited for a core, so each line ends with the frame's time on a core
## and waiting for one, and what is left of the frame is time the thread slept:
## the pacer, the wait on the device or the compositor, a page brought in.
## Beside them is the whole process's time on a core, its every thread, from
## `/proc/self/stat` to the hundredth of a second it counts in, so a wait for a
## core Sara's own threads took is told from one another process took.
## Elsewhere the three are left off the line.
##
## The wait starts where the stroke ledger's does, at the last drawn frame, or
## at the start of an iteration that drew nothing, so a line's total is the
## frame gap the window reads as `frame_gap_usec_max`.
##
## **Off, it costs a compare.** [method now] answers nought while the trace is
## off and [method spent] returns on it, and the trace connects to the engine's
## signals only while it is on. Nothing is read back and nothing is dispatched
## (hard rules 1 and 2): every figure is a clock read on the main thread, and
## the card's time is the engine's own render measure.
class_name SaFrameTrace
extends RefCounted

## What every line opens with, beside the trail's `Sara stall:`.
const LINE := "Sara frame:"
## A part, or a phase's unnamed rest, under this is left out of the line.
const PART_USEC: int = 5000

## Whether a window traces its frames. Written by [method start] and
## [method stop] only, read by the hooks.
static var enabled: bool = false
## The lines printed since [method start], one a drawn frame.
static var lines: int = 0
## The last line printed, which a suite reads.
static var last_line: String = ""

## Where a line goes, `print` when nothing was handed to [method start].
static var _sink: Callable = Callable()
## Where the frame's wait started, and the tick of the iteration under way.
static var _from_usec: int = 0
static var _tick_usec: int = 0
static var _pre_draw_usec: int = 0
static var _drawn_since_tick: bool = false
## The main thread's time on a core and waiting for one, in nanoseconds, where
## the frame's wait started and at the tick of the iteration under way, empty
## where the system says neither.
static var _sched_from := PackedInt64Array()
static var _sched_tick := PackedInt64Array()
## The named parts since the frame's wait started, and those since the tick of
## the iteration under way, which an iteration that draws nothing keeps. Each
## is a span, its name, its start and its end, so a part that ran inside
## another is told from one beside it. A frame holds a span a row at most, and
## the list goes with the frame.
static var _parts: Array[Span] = []
static var _since_tick: Array[Span] = []
## The most each named part took in one drawn frame since [method start], which
## the perf window's end reports, so a part under [constant PART_USEC] that no
## line names is read all the same.
static var peaks: Dictionary[String, int] = {}


## Turns the trace on, with the frame's wait starting now. *sink* takes each
## line in place of `print`, for a suite.
static func start(sink: Callable = Callable()) -> void:
    _sink = sink
    lines = 0
    last_line = ""
    _from_usec = Time.get_ticks_usec()
    _tick_usec = 0
    _pre_draw_usec = 0
    _drawn_since_tick = false
    _parts = []
    _since_tick = []
    peaks = {}
    _sched_from = schedule()
    _sched_tick = _sched_from
    enabled = true
    var loop := Engine.get_main_loop() as SceneTree
    if loop != null and not loop.process_frame.is_connected(_ticked):
        loop.process_frame.connect(_ticked)
    if not RenderingServer.frame_pre_draw.is_connected(_drawing):
        RenderingServer.frame_pre_draw.connect(_drawing)
    if not RenderingServer.frame_post_draw.is_connected(_drawn):
        RenderingServer.frame_post_draw.connect(_drawn)


## Turns the trace off and lets go of the engine's signals.
static func stop() -> void:
    enabled = false
    _sink = Callable()
    var loop := Engine.get_main_loop() as SceneTree
    if loop != null and loop.process_frame.is_connected(_ticked):
        loop.process_frame.disconnect(_ticked)
    if RenderingServer.frame_pre_draw.is_connected(_drawing):
        RenderingServer.frame_pre_draw.disconnect(_drawing)
    if RenderingServer.frame_post_draw.is_connected(_drawn):
        RenderingServer.frame_post_draw.disconnect(_drawn)


## The clock a part starts from, nought while the trace is off.
static func now() -> int:
    return Time.get_ticks_usec() if enabled else 0


## Adds the time since *began*, from [method now], to the part *what* of the
## frame under way. A part spent twice in one frame, a row each, adds up, and a
## part spent inside another is named inside it.
static func spent(what: String, began: int) -> void:
    if not enabled or began <= 0:
        return
    var at := Time.get_ticks_usec()
    _since_tick.append(Span.new(what, began, at, _phase_at(at)))


## The phase a clock read at *at* falls in.
static func _phase_at(at: int) -> String:
    if _tick_usec <= 0 or at < _tick_usec:
        return "before the tick"
    if _pre_draw_usec >= _tick_usec and at >= _pre_draw_usec:
        return "draw"
    return "process"


static func _ticked() -> void:
    var at := Time.get_ticks_usec()
    if _tick_usec > 0 and not _drawn_since_tick:
        # The iteration before drew nothing, so the wait starts again at its
        # tick, as the ledger's does, and only what it spent is kept.
        _from_usec = maxi(_from_usec, _tick_usec)
        _sched_from = _sched_tick
        _parts = _since_tick
    else:
        _parts.append_array(_since_tick)
    _since_tick = []
    _drawn_since_tick = false
    _tick_usec = at
    _sched_tick = schedule()
    _pre_draw_usec = 0


static func _drawing() -> void:
    _pre_draw_usec = Time.get_ticks_usec()


static func _drawn() -> void:
    var at := Time.get_ticks_usec()
    _parts.append_array(_since_tick)
    _since_tick = []
    var sched := schedule()
    var line := line_of(at - _from_usec, _phases(at), _parts, SaStrokeLedger.measured_gpu_usec())
    _keep_peaks(_parts)
    line += scheduled(_sched_from, sched)
    _sched_from = sched
    lines += 1
    last_line = line
    if _sink.is_valid():
        _sink.call(line)
    else:
        print(line)
    _from_usec = at
    _drawn_since_tick = true
    _parts = []


## A thread's time on a core and waiting for one since it started, in
## nanoseconds, from its `schedstat` under `/proc`, and the whole process's time
## on cores beside them, empty where the system has no such file. The calling
## thread's by default, and *thread* names another as `self/task/<id>`, which is
## how the trail's watcher reads the main thread from its own.
static func schedule(thread: String = "thread-self") -> PackedInt64Array:
    var file := FileAccess.open("/proc/%s/schedstat" % thread, FileAccess.READ)
    if file == null:
        return PackedInt64Array()
    var fields := file.get_line().split(" ", false)
    if fields.size() < 2:
        return PackedInt64Array()
    var process := FileAccess.open("/proc/self/stat", FileAccess.READ)
    var whole := -1
    if process != null:
        # The name in brackets may hold spaces, so the fields are counted from
        # after it: utime and stime are the 14th and 15th, in hundredths.
        var line := process.get_line()
        var after := line.substr(line.rfind(")") + 2).split(" ", false)
        if after.size() > 12:
            whole = (after[11].to_int() + after[12].to_int()) * 10_000_000
    return PackedInt64Array([fields[0].to_int(), fields[1].to_int(), whole])


## The clause the schedule adds to a line, from *before* to *after*, nothing
## when either is empty.
static func scheduled(before: PackedInt64Array, after: PackedInt64Array) -> String:
    if before.size() < 2 or after.size() < 2:
        return ""
    @warning_ignore("integer_division")
    var ran := (after[0] - before[0]) / 1000
    @warning_ignore("integer_division")
    var waited := (after[1] - before[1]) / 1000
    var said := ", on a core %s, waiting for one %s" % [_ms(ran), _ms(waited)]
    if before.size() > 2 and before[2] >= 0 and after[2] >= 0:
        @warning_ignore("integer_division")
        said += ", the process on cores %s" % _ms((after[2] - before[2]) / 1000)
    return said


## The three phases of a frame drawn at *at*, in microseconds.
static func _phases(at: int) -> Dictionary[String, int]:
    var tick := _tick_usec if _tick_usec >= _from_usec else _from_usec
    var pre := _pre_draw_usec if _pre_draw_usec >= tick else at
    return {
        "before the tick": tick - _from_usec,
        "process": pre - tick,
        "draw": at - pre,
    }


## The line of one frame of *total* microseconds: each phase, with its parts
## over [constant PART_USEC] in brackets, longest first, and its rest outside
## them when that is over the line too, then the card's *gpu* time. A part that
## ran inside another is added to it by name in the other's own brackets, and
## the phase's rest counts the outer part alone.
static func line_of(total: int, phases: Dictionary[String, int], spans: Array[Span], gpu: int) -> String:
    var outer := _outermost(spans)
    var said: PackedStringArray = []
    for phase: String in ["before the tick", "process", "draw"]:
        var took: int = phases.get(phase, 0)
        var tops: Dictionary[String, int] = {}
        var inner: Dictionary[String, Dictionary] = {}
        var rest := took
        for at: int in spans.size():
            var span := spans[at]
            var holder := outer[at]
            if holder != at:
                var into: Dictionary = inner.get_or_add(spans[holder].what, {})
                var had: int = into.get(span.what, 0)
                into[span.what] = had + span.usec()
                continue
            if span.phase != phase:
                continue
            tops[span.what] = tops.get(span.what, 0) + span.usec()
            rest -= span.usec()
        var named: Array[String] = []
        for what: String in tops:
            if tops[what] > PART_USEC:
                named.append(what)
        named.sort_custom(func(a: String, b: String) -> bool: return tops[a] > tops[b])
        var inside: PackedStringArray = []
        for what: String in named:
            var parts: Dictionary = inner.get(what, {})
            inside.append("%s %s%s" % [what, _ms(tops[what]), _within(parts)])
        if rest > PART_USEC and not named.is_empty():
            inside.append("other %s" % _ms(rest))
        var clause := "%s %s" % [phase, _ms(took)]
        if not inside.is_empty():
            clause += " (%s)" % ", ".join(inside)
        said.append(clause)
    return "%s %s, %s, gpu %s" % [LINE, _ms(total), ", ".join(said), _ms(maxi(gpu, 0))]


## For each span, the index of the outermost span that holds it, its own index
## when none does. Read in the order the spans began, the longer first of two
## that began together, a span that begins before the outer one ends is inside
## it, since a part ends before the part it runs in.
static func _outermost(spans: Array[Span]) -> PackedInt32Array:
    var order: Array[int] = []
    for at: int in spans.size():
        order.append(at)
    order.sort_custom(
        func(a: int, b: int) -> bool:
            return spans[a].began < spans[b].began or (spans[a].began == spans[b].began and spans[a].ended > spans[b].ended)
    )
    var out := PackedInt32Array()
    out.resize(spans.size())
    var top := -1
    for at: int in order:
        if top >= 0 and spans[at].began < spans[top].ended:
            out[at] = top
        else:
            top = at
            out[at] = at
    return out


## Adds up each name's spans of one frame and keeps the most in [member peaks].
static func _keep_peaks(spans: Array[Span]) -> void:
    var frame: Dictionary[String, int] = {}
    for span: Span in spans:
        frame[span.what] = frame.get(span.what, 0) + span.usec()
    for what: String in frame:
        var most: int = peaks.get(what, 0)
        peaks[what] = maxi(most, frame[what])


## The parts inside one, over the line, longest first, as a bracket.
static func _within(inner: Dictionary) -> String:
    var long: Dictionary[String, int] = {}
    var named: Array[String] = []
    for key: Variant in inner:
        var what: String = key
        var usec: int = inner[key]
        if usec > PART_USEC:
            long[what] = usec
            named.append(what)
    if named.is_empty():
        return ""
    named.sort_custom(func(a: String, b: String) -> bool: return long[a] > long[b])
    var said: PackedStringArray = []
    for what: String in named:
        said.append("%s %s" % [what, _ms(long[what])])
    return " (%s)" % ", ".join(said)


static func _ms(usec: int) -> String:
    return "%.1f ms" % (usec / 1000.0)


## One part's time, where it began and ended, and the phase it ended in.
class Span:
    extends RefCounted

    var what: String
    var began: int
    var ended: int
    var phase: String

    func _init(name: String, from_usec: int, to_usec: int, in_phase: String) -> void:
        what = name
        began = from_usec
        ended = to_usec
        phase = in_phase

    func usec() -> int:
        return ended - began
