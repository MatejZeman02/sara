## The CPU half of stroke latency: from an event's arrival to the dab's dispatch,
## and from a frame's first arrival to its composite, its redraw and its post draw.
##
## Godot 4.7's InputEvent carries no timestamp, so the first clock Sara has is the
## window's input signal, and everything here is measured from that. Past the post
## draw the frame is the compositor's and no clock in the process can see it.
##
## Integers only, and never a list of samples. A 2000-dab stroke would otherwise
## make the dump grow with the stroke, and a minimum, a sum, a maximum and a count
## are what a table shows. Always on, like the four counters of SaCompute, because
## a ledger behind a flag is a ledger nobody reads. The cost per event is a clock
## read and a handful of integer compares.
##
## Every hook takes the process frame as a defaulted last argument. The app never
## passes it. A test does, because a test function cannot wait for a frame and a
## stroke injected in one lands in a single process frame.
##
## Every figure below is static and one for every document, because the window
## has one main loop and draws one frame at a time whichever document is shown,
## and a stroke is laid in one document at a time.
##
## A frame's arrival stamp waits for its composite. A pen's dab is composited in
## the frame it arrived in, so the three frame figures close inside that frame. A
## capture scenario's dab is made in SaCapture's `_process`, after the easel's, so
## its composite is the next frame's and its figures read one frame long. That
## skew is constant, stated in the perf block's page, and not corrected here.
##
## **A stroke leaves one line in the log.** A window is a scenario's, and a
## painter runs none, so without the line a stroke that lags would leave only
## stall lines, which say a frame was long and not what it was long with. So
## the ledger also keeps the figures of the stroke
## under way, from the left button's press to the first frame drawn after its
## release, and prints them as one `Sara stroke:` line when a stroke that laid a
## dab ends: every frame's time, the longest frame split into its input, its
## drawing, the card's time and the wait for the display, the motions and the
## dabs, the compute lists, and input to dispatch. A frame's input is from its
## first event's arrival to the last event or dab after it, which is the event
## handling in the app and the step in a capture, and its drawing is from there
## or from its tick, whichever is later, to its post draw.
##
## **The frame beyond the drawing.** The drawing is only the CPU's share of a
## frame, so a line that stopped there would leave a stroke whose frames sit at
## 20 ms with a drawing of 8 ms a mystery. Two figures fill it. The
## card's own time for the frame comes from the engine's per-viewport render
## measure, which costs no capture from the query pool and reads no texel back,
## and the wait for the display is the frame's own period beyond the iteration
## that drew it and the events it handled before its tick, which is the pacer's
## sleep and the wait for the next refresh. The line adds every frame's wait up
## beside the input and the drawing, so a stroke's wait reads as one figure.
## Both are read on every drawn frame, so the line says where a slow frame went
## without a window open to ask for it.
class_name SaStrokeLedger
extends RefCounted

const NO_FRAME := -1
## What a figure nothing measured reads as, for a card with no measure and for a
## suite that feeds the frame itself.
const NO_MEASURE := -1
## What a stroke's line opens with, beside the trail's `Sara stall:`.
const STROKE := "Sara stroke:"

static var events: int = 0
static var motions: int = 0
static var motions_per_frame_max: int = 0
static var dabs: int = 0
static var targets: int = 0
static var dabs_per_frame_max: int = 0
static var frames_with_dabs: int = 0
static var frames_drawn: int = 0

static var dispatch_n: int = 0
static var dispatch_min: int = 0
static var dispatch_sum: int = 0
static var dispatch_max: int = 0

static var composite_n: int = 0
static var composite_min: int = 0
static var composite_sum: int = 0
static var composite_max: int = 0

static var redraw_n: int = 0
static var redraw_min: int = 0
static var redraw_sum: int = 0
static var redraw_max: int = 0

static var post_draw_n: int = 0
static var post_draw_min: int = 0
static var post_draw_sum: int = 0
static var post_draw_max: int = 0

static var interval_n: int = 0
static var interval_min: int = 0
static var interval_sum: int = 0
static var interval_max: int = 0

## The longest iteration the window held, on the ledger's own clock: from the
## iteration's tick to its post draw, or to the next tick for an iteration that
## drew nothing, whose figure then carries the pacer's sleep of about 10 ms.
##
## Timed here rather than read off the engine's `Performance.TIME_PROCESS`,
## which the engine sets once a second to the longest frame of the second
## before, so a window shorter than a second would read the frame before its
## `begin` and miss its own. The clock
## starts at the tick of the first iteration after `begin`, so the frame an open
## or an attach lands in is the window's own.
static var process_usec_max: int = 0

## The longest wait for a drawn frame, the stall a painter sees: from the reset
## to the first frame, then between neighbouring frames. A gesture's own work
## often runs in the frame that opens the window, so the first wait counts.
## Timed here rather than read off the engine's monitor, so it belongs to this
## window alone and a shot taken before `begin` is not in it.
##
## **A frame nothing asked for is not waited for.** Sara runs in low processor
## mode, where an iteration with nothing changed draws nothing and sleeps, so
## the time since the last drawn frame holds every idle iteration after it, and
## a scenario's wait would read as a stall of the step after it. So the clock
## starts again at an
## iteration that drew nothing, the start of it rather than its end, because a
## click is handled before the next iteration's tick and its work must stay
## inside the wait. An iteration that drew nothing still counts its own length,
## so a long one that never draws is not hidden.
static var frame_gap_usec_max: int = 0

## Every drawn frame's wait, the one `frame_gap_usec_max` is the longest of,
## folded so a window says its 95th percentile and how many missed the budget.
static var frame_times := SaFrameTimes.new()
## The line a slow frame is over: one refresh of the display the window is on,
## written by [method follow_display] from the rate the start-up block read, and
## the 60 Hz fallback while no rate is known.
static var budget_usec: int = SaFrameTimes.BUDGET_USEC
## The most compute lists and dispatches one drawn frame sent, read off
## `SaCompute`'s counters between two post draws, composites and all.
static var lists_per_frame_max: int = 0
static var dispatches_per_frame_max: int = 0
## The longest input and the longest drawing of one frame, as the header says.
static var input_usec_max: int = 0
static var draw_usec_max: int = 0
## The figures of the last stroke that ended, its line's, and empty before one.
static var last_stroke: Dictionary[String, Variant] = {}

static var _last_drawn_usec: int = 0
static var _last_tick_usec: int = 0
static var _drawn_since_tick: bool = false

## The frame the bucket below belongs to. It closes lazily, when a hook arrives
## carrying another index, so an idle frame costs nothing.
static var _frame: int = NO_FRAME
static var _motions_this_frame: int = 0
static var _dabs_this_frame: int = 0
static var _last_event_usec: int = 0
static var _last_event_frame: int = NO_FRAME
## Whether a composite has begun since the last arrival, after which a dab is no
## longer that arrival's. The brush sends a frame's dabs at `process_frame`,
## which can carry the next process frame index while the composite that shows
## them is still to come, so the index alone cannot say.
static var _composed_since_event: bool = false
## What came since the last post draw, the frame being drawn's, counted apart
## from the bucket above because an event's process frame index need not be its
## post draw's. Its input is its first arrival, nought before one, to the last
## arrival or dab after it.
static var _input_from_usec: int = 0
static var _input_to_usec: int = 0
static var _motions_since_draw: int = 0
static var _dabs_since_draw: int = 0
## The time the frame being drawn spent loading a tip's picture on the main
## thread, and the file of the last load in it, which a stroke's longest frame
## names.
static var _tip_usec_since_draw: int = 0
static var _tip_since_draw: String = ""
## Where `SaCompute`'s two counters stood at the last post draw.
static var _lists_at_draw: int = 0
static var _dispatches_at_draw: int = 0
## The stroke under way, null between strokes.
static var _stroke: Stroke = null

## Whether the engine's render measure was asked for on the root viewport, so
## the frame's GPU figure costs one call the first time and a read after it.
static var _measure_on: bool = false

## The first arrival of a frame, kept until a composite takes it when the frame
## had a dab, and dropped when it had none and a composite began or a whole
## frame passed since, or when a later frame's arrival comes.
static var _first_event_usec: int = 0
static var _first_event_frame: int = NO_FRAME
static var _first_event_has_dab: bool = false

## The stamp a composite took, which the redraw and the post draw then fold. A
## separate slot, because a capture scenario's next event arrives between the
## composite of its last dab and the post draw of the same frame.
static var _in_flight_usec: int = 0
static var _in_flight_redrawn: bool = false

## The last post draw that carried a dab, for the interval between two such
## frames in a row, which is the jank a painter feels across a stroke.
static var _last_dab_draw_usec: int = 0
static var _last_dab_draw_frame: int = NO_FRAME


## Called at the window's input signal, before the event is un-scaled or routed.
static func event_arrived(is_motion: bool, frame: int = NO_FRAME) -> void:
    var now := Time.get_ticks_usec()
    _roll(frame)
    events += 1
    _last_event_usec = now
    _last_event_frame = _frame
    _composed_since_event = false
    if _first_event_usec == 0 or (not _first_event_has_dab and _first_event_frame != _frame):
        _first_event_usec = now
        _first_event_frame = _frame
    if _input_from_usec == 0:
        _input_from_usec = now
    _input_to_usec = now
    if is_motion:
        motions += 1
        _motions_this_frame += 1
        _motions_since_draw += 1
        motions_per_frame_max = maxi(motions_per_frame_max, _motions_this_frame)
        if _stroke != null:
            _stroke.motions += 1


## Called at the window's input signal beside [method event_arrived] with the
## event as a button, null for any other. The left button's press opens a
## stroke and its release has the stroke close at the next drawn frame, so the
## dabs the release lays and the frame that shows them are the stroke's. A press
## while a stroke is still open closes that one first.
static func left_button(event: InputEventMouseButton, frame: int = NO_FRAME) -> void:
    if event == null or event.button_index != MOUSE_BUTTON_LEFT:
        return
    _roll(frame)
    if event.pressed:
        if _stroke != null:
            _close_stroke()
        _stroke = Stroke.new(Time.get_ticks_usec(), SaCompute.lists, SaCompute.dispatches)
    elif _stroke != null:
        _stroke.released = true


## Called when a dab's compute list has closed, with the chunks it touched.
##
## A dab no event of this frame caused, an airbrush tick for one, is counted and
## folds no latency: the last arrival is some other frame's and the difference
## would be the length of the hold. A dab sent at the next index's
## `process_frame`, before any composite, is still its arrival's.
static func dab_dispatched(target_count: int, frame: int = NO_FRAME) -> void:
    var now := Time.get_ticks_usec()
    _roll(frame)
    dabs += 1
    targets += target_count
    if _dabs_this_frame == 0:
        frames_with_dabs += 1
    _dabs_this_frame += 1
    _dabs_since_draw += 1
    dabs_per_frame_max = maxi(dabs_per_frame_max, _dabs_this_frame)
    if _stroke != null:
        _stroke.dabs += 1
    if _composed_since_event or _last_event_frame == NO_FRAME or _frame - _last_event_frame > 1:
        return
    _input_to_usec = now
    _first_event_has_dab = true
    var took := now - _last_event_usec
    dispatch_min = took if dispatch_n == 0 else mini(dispatch_min, took)
    dispatch_max = maxi(dispatch_max, took)
    dispatch_sum += took
    dispatch_n += 1
    if _stroke != null:
        _stroke.dispatched(took)


## Called as the easel starts a composite that has something to compose.
static func composite_issued(frame: int = NO_FRAME) -> void:
    var now := Time.get_ticks_usec()
    _roll(frame)
    _composed_since_event = true
    if not _first_event_has_dab:
        return
    var took := now - _first_event_usec
    composite_min = took if composite_n == 0 else mini(composite_min, took)
    composite_max = maxi(composite_max, took)
    composite_sum += took
    composite_n += 1
    _in_flight_usec = _first_event_usec
    _in_flight_redrawn = false
    _first_event_usec = 0
    _first_event_has_dab = false


## Called when a tip's picture was loaded on the main thread, *what* being its
## file and *usec* how long it took: the whole of a load a press had to finish
## or make, or one frame's share of a load off the stroke. `SaTipCache` calls it,
## so a frame a load fell in says so in the stroke's line.
static func tip_loaded(what: String, usec: int) -> void:
    _tip_usec_since_draw += usec
    _tip_since_draw = what


## Called when the view sees the composite count move and queues its redraw.
static func redraw_queued(frame: int = NO_FRAME) -> void:
    var now := Time.get_ticks_usec()
    _roll(frame)
    if _in_flight_usec == 0 or _in_flight_redrawn:
        return
    _in_flight_redrawn = true
    var took := now - _in_flight_usec
    redraw_min = took if redraw_n == 0 else mini(redraw_min, took)
    redraw_max = maxi(redraw_max, took)
    redraw_sum += took
    redraw_n += 1


## Connected to `SceneTree.process_frame` by the main canvas, once an iteration
## before any node's process. When the iteration before drew nothing, its length
## is folded, as a wait and as an iteration, and the wait for a frame starts
## again at its start.
static func frame_ticked() -> void:
    var now := Time.get_ticks_usec()
    if not _drawn_since_tick and _last_tick_usec > 0:
        process_usec_max = maxi(process_usec_max, now - _last_tick_usec)
        frame_gap_usec_max = maxi(frame_gap_usec_max, now - maxi(_last_tick_usec, _last_drawn_usec))
        _last_drawn_usec = maxi(_last_drawn_usec, _last_tick_usec)
    _drawn_since_tick = false
    _last_tick_usec = now


## Connected to `RenderingServer.frame_post_draw` by the main canvas. Every drawn
## frame is counted and its iteration timed from its tick, and one that carries a
## composited dab folds the whole answer of the process, up to submission, and its
## distance from the dab frame before it when the two are neighbours.
##
## *gpu* and *wait* are the card's time for the frame and the wait for the
## display, both [constant NO_MEASURE] for the reading taken here: the engine's
## per-viewport render measure for the card, and the frame's own period beyond
## the iteration that drew it for the wait. A suite passes both to fold a frame
## whose clocks it cannot wait for.
static func frame_drawn(frame: int = NO_FRAME, gpu_usec: int = NO_MEASURE, wait_usec: int = NO_MEASURE) -> void:
    var now := Time.get_ticks_usec()
    _roll(frame)
    frames_drawn += 1
    var gap := now - _last_drawn_usec
    frame_gap_usec_max = maxi(frame_gap_usec_max, gap)
    _last_drawn_usec = now
    _drawn_since_tick = true
    var process := now - _last_tick_usec if _last_tick_usec > 0 else 0
    process_usec_max = maxi(process_usec_max, process)
    var input := _input_to_usec - _input_from_usec if _input_from_usec > 0 else 0
    var drawn_from := maxi(_last_tick_usec, _input_to_usec)
    var drawn := now - drawn_from if drawn_from > 0 else 0
    var gpu := gpu_usec if gpu_usec >= 0 else measured_gpu_usec()
    var wait := wait_usec
    if wait < 0:
        wait = maxi(gap - (now - busy_from(_last_tick_usec, _input_from_usec, now - gap)), 0) if _last_tick_usec > 0 else 0
    fold_frame(gap, input, drawn, gpu, wait)
    if _in_flight_usec == 0:
        return
    var took := now - _in_flight_usec
    post_draw_min = took if post_draw_n == 0 else mini(post_draw_min, took)
    post_draw_max = maxi(post_draw_max, took)
    post_draw_sum += took
    post_draw_n += 1
    _in_flight_usec = 0
    if _last_dab_draw_frame != NO_FRAME and _last_dab_draw_frame == _frame - 1:
        var interval := now - _last_dab_draw_usec
        interval_min = interval if interval_n == 0 else mini(interval_min, interval)
        interval_max = maxi(interval_max, interval)
        interval_sum += interval
        interval_n += 1
    _last_dab_draw_usec = now
    _last_dab_draw_frame = _frame


## Where a frame's own work began, for the wait beyond it: its tick, or its
## first event's arrival where that came first and after the frame before was
## drawn, *last_drawn*.
##
## **An event handled before the tick is the frame's work and not a wait.** On
## Android, Godot hands each pen event to its render thread's queue, which runs
## between two iterations, and Sara reads every motion as it comes, so the
## whole of a frame's event handling, its dabs with it, falls between the last
## frame's post draw and this one's tick. Measured from the tick alone it read
## as wait, and the tablet's lines named a wait of 1.26 s for a frame whose
## input took 1.26 s. A desktop pen's events come before the tick as well,
## from the display server's poll.
static func busy_from(tick: int, first_event: int, last_drawn: int) -> int:
    if first_event > last_drawn and first_event < tick:
        return first_event
    return tick


## The card's time for the frame just drawn, from the engine's own render
## measure on the root viewport, in microseconds. The measure is asked for the
## first time this runs, because it costs a timestamp pair a frame in the engine
## and no capture from the query pool a stroke exhausts, and nought comes back
## where there is no viewport to ask, as a suite with no window has.
##
## The root viewport rather than a canvas's own, because a window's frames are
## the ones a painter waits for, and the measure is the engine's own rather than
## a pair this file opens, which is what keeps it on for every frame.
static func measured_gpu_usec() -> int:
    var loop := Engine.get_main_loop() as SceneTree
    if loop == null or loop.root == null:
        return 0
    var viewport := loop.root.get_viewport_rid()
    if not _measure_on:
        _measure_on = true
        RenderingServer.viewport_set_measure_render_time(viewport, true)
    return maxi(roundi(RenderingServer.viewport_get_measured_render_time_gpu(viewport) * 1000.0), 0)


## The display the window is on refreshes at *hz* Hz, so one refresh of it is
## the line a slow frame is over and every frame folded from here counts against
## it. The start-up block calls it with the screen's rate, and a rate of nought
## or less leaves the sixty hertz fallback, which is what a driver that answers
## -1 gives.
static func follow_display(hz: float) -> void:
    budget_usec = SaFrameTimes.budget_for_hz(hz)
    frame_times = SaFrameTimes.new(budget_usec)


## Clears every figure. Only the perf window calls this, at its begin, because a
## minimum and a maximum cannot be differenced the way a counter can.
static func reset() -> void:
    events = 0
    motions = 0
    motions_per_frame_max = 0
    dabs = 0
    targets = 0
    dabs_per_frame_max = 0
    frames_with_dabs = 0
    frames_drawn = 0
    dispatch_n = 0
    dispatch_min = 0
    dispatch_sum = 0
    dispatch_max = 0
    composite_n = 0
    composite_min = 0
    composite_sum = 0
    composite_max = 0
    redraw_n = 0
    redraw_min = 0
    redraw_sum = 0
    redraw_max = 0
    post_draw_n = 0
    post_draw_min = 0
    post_draw_sum = 0
    post_draw_max = 0
    interval_n = 0
    interval_min = 0
    interval_sum = 0
    interval_max = 0
    process_usec_max = 0
    frame_gap_usec_max = 0
    frame_times = SaFrameTimes.new(budget_usec)
    lists_per_frame_max = 0
    dispatches_per_frame_max = 0
    input_usec_max = 0
    draw_usec_max = 0
    last_stroke = {}
    _input_from_usec = 0
    _input_to_usec = 0
    _motions_since_draw = 0
    _dabs_since_draw = 0
    _tip_usec_since_draw = 0
    _tip_since_draw = ""
    _lists_at_draw = SaCompute.lists
    _dispatches_at_draw = SaCompute.dispatches
    _stroke = null
    _last_drawn_usec = Time.get_ticks_usec()
    _last_tick_usec = 0
    _drawn_since_tick = false
    _frame = NO_FRAME
    _motions_this_frame = 0
    _dabs_this_frame = 0
    _last_event_usec = 0
    _last_event_frame = NO_FRAME
    _composed_since_event = false
    _first_event_usec = 0
    _first_event_frame = NO_FRAME
    _first_event_has_dab = false
    _in_flight_usec = 0
    _in_flight_redrawn = false
    _last_dab_draw_usec = 0
    _last_dab_draw_frame = NO_FRAME


## What the perf window reads. Times are microseconds, and a mean is the sum over
## the count, whole microseconds, zero when nothing was folded.
static func block() -> Dictionary[String, Variant]:
    return {
        "events": events,
        "motions": motions,
        "motions_per_frame_max": motions_per_frame_max,
        "dabs": dabs,
        "targets": targets,
        "dabs_per_frame_max": dabs_per_frame_max,
        "frames_with_dabs": frames_with_dabs,
        "frames_drawn": frames_drawn,
        "input_to_dispatch": _fold(dispatch_n, dispatch_min, dispatch_sum, dispatch_max),
        "input_to_composite": _fold(composite_n, composite_min, composite_sum, composite_max),
        "input_to_redraw": _fold(redraw_n, redraw_min, redraw_sum, redraw_max),
        "input_to_post_draw": _fold(post_draw_n, post_draw_min, post_draw_sum, post_draw_max),
        "dab_frame_interval": _fold(interval_n, interval_min, interval_sum, interval_max),
        "process_usec_max": process_usec_max,
        "frame_gap_usec_max": frame_gap_usec_max,
        "frame_usec": frame_times.block(),
        "lists_per_frame_max": lists_per_frame_max,
        "dispatches_per_frame_max": dispatches_per_frame_max,
        "input_usec_max": input_usec_max,
        "draw_usec_max": draw_usec_max,
    }


## Folds one frame's figures into the window and into the stroke under way, and
## closes a stroke whose release this frame shows. *gap* is the frame's time,
## the wait since the frame drawn before it, *input* and *draw* the CPU's share
## of it, and *gpu* and *wait* what the frame spent beyond that, the card's time
## for it and the wait for the display. [method frame_drawn] measures the frame
## and calls here, and a suite that cannot wait for a frame calls here with the
## four times it names, so a test's frame and a painter's take one path.
static func fold_frame(gap: int, input: int, draw: int, gpu: int, wait: int) -> void:
    frame_times.fold(gap)
    var lists := SaCompute.lists - _lists_at_draw
    var dispatched := SaCompute.dispatches - _dispatches_at_draw
    _lists_at_draw = SaCompute.lists
    _dispatches_at_draw = SaCompute.dispatches
    lists_per_frame_max = maxi(lists_per_frame_max, lists)
    dispatches_per_frame_max = maxi(dispatches_per_frame_max, dispatched)
    input_usec_max = maxi(input_usec_max, input)
    draw_usec_max = maxi(draw_usec_max, draw)
    if _stroke != null:
        _stroke.frame(gap, input, draw, _motions_since_draw, _dabs_since_draw, lists, gpu, wait)
        _stroke.tip(gap, _tip_usec_since_draw, _tip_since_draw)
    _input_from_usec = 0
    _input_to_usec = 0
    _motions_since_draw = 0
    _dabs_since_draw = 0
    _tip_usec_since_draw = 0
    _tip_since_draw = ""
    if _stroke != null and _stroke.released:
        _close_stroke()


## Ends the stroke under way, keeps its figures as `last_stroke` and prints its
## line when it laid a dab. A press on a docker or a menu is a left button too,
## and lays none.
static func _close_stroke() -> void:
    last_stroke = _stroke.block(Time.get_ticks_usec(), SaCompute.lists, SaCompute.dispatches)
    _stroke = null
    var laid: int = last_stroke["dabs"]
    if laid > 0:
        print(line_of(last_stroke))


## The line a stroke's figures make in the log: seconds for a stroke and for
## a frame past a second, milliseconds under it, so a freeze reads as one.
static func line_of(figures: Dictionary[String, Variant]) -> String:
    var frames: Dictionary[String, int] = figures["frames"]
    var longest: Dictionary[String, int] = figures["longest"]
    var reached: Dictionary[String, int] = figures["input_to_dispatch"]
    var tip_usec: int = figures["longest_tip_usec"]
    var loading := ", %s of it loading the tip %s" % [_span(tip_usec), figures["longest_tip"]] if tip_usec > 0 else ""
    # The card's time and the wait for the display are one clause between them,
    # the pair a painter reads as what the frame spent outside the brush's own
    # work, so the line grows by one clause and takes one of the budget's rather
    # than two, as the row asked.
    var opening := (
        (
            "%s %.2f s, %d frames, the longest %s (input %s, drawing %s,"
            + " outside %s (gpu %s, wait %s), %d motions, %d dabs, %d lists%s),"
        )
        % [
            STROKE,
            figures["usec"] / 1e6,
            frames["count"],
            _span(frames["max"]),
            _span(longest["input"]),
            _span(longest["draw"]),
            _span(longest["gpu"] + longest["wait"]),
            _span(longest["gpu"]),
            _span(longest["wait"]),
            longest["motions"],
            longest["dabs"],
            longest["lists"],
            loading,
        ]
    )
    var slow := "the 95th percentile %s, %d over %.1f ms." % [_span(frames["p95"]), frames["slow"], frames["budget"] / 1e3]
    var input_usec: int = figures["input_usec"]
    var draw_usec: int = figures["draw_usec"]
    var wait_usec: int = figures.get("wait_usec", 0)
    var split := "Input %s, drawing %s and waiting %s in all." % [_span(input_usec), _span(draw_usec), _span(wait_usec)]
    var hand := "%d motions, at most %d in a frame." % [figures["motions"], figures["motions_per_frame_max"]]
    var laid := (
        "%d dabs at %.3f ms of input each, at most %d in a frame."
        % [figures["dabs"], figures["input_usec_per_dab"] / 1e3, figures["dabs_per_frame_max"]]
    )
    var sent := (
        "%d dispatches in %d compute lists, at most %d lists in a frame."
        % [figures["dispatches"], figures["lists"], figures["lists_per_frame_max"]]
    )
    var waited := "Input to dispatch %s on average, %s at most." % [_span(reached["mean"]), _span(reached["max"])]
    return " ".join([opening, slow, split, hand, laid, sent, waited])


## *usec* as a reader takes it in: seconds from one second up, milliseconds
## with one decimal below.
static func _span(usec: int) -> String:
    if usec >= 1000000:
        return "%.2f s" % (usec / 1e6)
    return "%.1f ms" % (usec / 1e3)


static func _fold(n: int, low: int, sum: int, high: int) -> Dictionary[String, int]:
    @warning_ignore("integer_division")
    var mean := sum / maxi(n, 1)
    return {"n": n, "min": low, "mean": mean, "max": high, "sum": sum}


## Closes the frame's bucket when the index has moved. A first arrival whose
## frame had a dab survives the close, because its composite is still owed, and
## so does one with no dab yet for one index while no composite has begun,
## because the brush sends a frame's dabs at `process_frame`.
static func _roll(frame: int) -> void:
    var index := frame if frame != NO_FRAME else Engine.get_process_frames()
    if index == _frame:
        return
    _frame = index
    _motions_this_frame = 0
    _dabs_this_frame = 0
    if not _first_event_has_dab and (_composed_since_event or index - _first_event_frame > 1):
        _first_event_usec = 0


## One stroke's figures, from the left button's press to the first frame drawn
## after its release, as integers like the rest of the ledger.
class Stroke:
    extends RefCounted

    ## When the press arrived.
    var began_usec: int = 0
    ## Whether the release has arrived, so the next drawn frame ends the stroke.
    var released: bool = false
    var motions: int = 0
    var dabs: int = 0
    var frames := SaFrameTimes.new(SaStrokeLedger.budget_usec)

    var _motions_per_frame_max: int = 0
    var _dabs_per_frame_max: int = 0
    var _lists_per_frame_max: int = 0
    var _input_usec: int = 0
    var _draw_usec: int = 0
    var _wait_usec: int = 0
    var _dispatch_n: int = 0
    var _dispatch_sum: int = 0
    var _dispatch_max: int = 0
    ## The longest frame's own split and its share beyond the drawing, so a
    ## freeze names what it held and where the rest of it went.
    var _longest: Dictionary[String, int] = {"input": 0, "draw": 0, "gpu": 0, "wait": 0, "motions": 0, "dabs": 0, "lists": 0}
    ## The tip load the longest frame held, its time and its file, nought and
    ## empty when it held none.
    var _longest_tip_usec: int = 0
    var _longest_tip: String = ""
    ## Where `SaCompute`'s two counters stood at the press.
    var _lists_at: int = 0
    var _dispatches_at: int = 0

    func _init(now: int, lists: int, dispatches: int) -> void:
        began_usec = now
        _lists_at = lists
        _dispatches_at = dispatches

    ## A dab an event of its frame caused reached the card *took* after it.
    func dispatched(took: int) -> void:
        _dispatch_n += 1
        _dispatch_sum += took
        _dispatch_max = maxi(_dispatch_max, took)

    ## A frame was drawn *gap* after the one before it, its input and drawing
    ## taking *input* and *draw*, with these motions, dabs and lists in it, the
    ## card spending *gpu* and the wait for the display *wait*.
    func frame(gap: int, input: int, draw: int, motions_in: int, dabs_in: int, lists_in: int, gpu: int, wait: int) -> void:
        frames.fold(gap)
        _input_usec += input
        _draw_usec += draw
        _wait_usec += maxi(wait, 0)
        _motions_per_frame_max = maxi(_motions_per_frame_max, motions_in)
        _dabs_per_frame_max = maxi(_dabs_per_frame_max, dabs_in)
        _lists_per_frame_max = maxi(_lists_per_frame_max, lists_in)
        if gap >= frames.longest_usec:
            _longest = {
                "input": input,
                "draw": draw,
                "gpu": gpu,
                "wait": wait,
                "motions": motions_in,
                "dabs": dabs_in,
                "lists": lists_in,
            }

    ## The frame [method frame] just folded, *gap* long, spent *usec* loading
    ## the tip *what*. Kept when that frame is the longest, so the line names
    ## the load the freeze held and a load in a short frame says nothing.
    func tip(gap: int, usec: int, what: String) -> void:
        if gap < frames.longest_usec:
            return
        _longest_tip_usec = usec
        _longest_tip = what if usec > 0 else ""

    ## The stroke's figures as it ends *now*, with `SaCompute`'s counters there.
    func block(now: int, lists: int, dispatches: int) -> Dictionary[String, Variant]:
        @warning_ignore("integer_division")
        var per_dab := _input_usec / maxi(dabs, 1)
        @warning_ignore("integer_division")
        var reached: Dictionary[String, int] = {
            "n": _dispatch_n, "mean": _dispatch_sum / maxi(_dispatch_n, 1), "max": _dispatch_max
        }
        return {
            "usec": now - began_usec,
            "frames": frames.block(),
            "longest": _longest.duplicate(),
            "longest_tip_usec": _longest_tip_usec,
            "longest_tip": _longest_tip,
            "motions": motions,
            "motions_per_frame_max": _motions_per_frame_max,
            "dabs": dabs,
            "dabs_per_frame_max": _dabs_per_frame_max,
            "input_usec": _input_usec,
            "draw_usec": _draw_usec,
            "wait_usec": _wait_usec,
            "input_usec_per_dab": per_dab,
            "dispatches": dispatches - _dispatches_at,
            "lists": lists - _lists_at,
            "lists_per_frame_max": _lists_per_frame_max,
            "input_to_dispatch": reached,
        }
