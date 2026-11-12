## The trail a run leaves in its log, so a run that froze says where it stopped.
##
## The quit prints one line per stage from the request to the hand-over to the
## engine, and each large teardown of Sara's own prints one while quitting.
## Everything else a freeze could sit inside, the tool, the command and the
## dialog, is noted without a line, so a stall can name it. `Watch` watches the
## frames and prints a line for a stall, a hitch, a run of slow frames or a pen
## held back, each once per freeze, with the thresholds on the constants below.
##
## A stall names where Sara is, not the last place it went. `note` writes a place
## Sara stays in until the next note, `enter` writes one that stands until its
## ticket is given back, and the latest written of those still standing is the
## one a stall names, with its age. A run of slow frames names what was noted or
## entered during it, by number rather than time because a suite hands the watch
## a clock of its own.
##
## Every line goes through `print`, so it reaches the console and the log file,
## and the debug export flushes the log after every line so a binary killed
## mid-run leaves every line printed before the kill. Time away is not a frame,
## so a gap a focus change fell in prints nothing and counts in no run of slow
## frames. The journal (`SARA_JOURNAL=1` or `--journal`) prints a timed line for
## every place and every slow frame and is off, and connects nothing, by default.
class_name SaTrail
extends RefCounted

## What every line of the quit's trail opens with.
const TRAIL := "Sara trail:"
## What a stall line opens with.
const STALL := "Sara stall:"
## What a hitch line opens with.
const HITCH := "Sara hitch:"
## What a line of the journal opens with.
const JOURNAL := "Sara journal:"
## The environment variable that starts the journal, beside the flag.
const JOURNAL_ENV := "SARA_JOURNAL"
## The flag after the `--` that starts the journal.
const JOURNAL_FLAG := "--journal"
## A frame gap longer than this prints a line once the frame comes, and a thread
## prints one while the main thread is still stuck past `STUCK_S`.
const STALL_S := 1.0
## A single frame longer than this and no stall is a hitch, a pause a painter
## feels.
const HITCH_S := 0.1
## A hitch this close to the one before it is the same burst and prints nothing.
const HITCH_BURST_S := 1.0
## A main thread stuck this long gets a line from the watcher while it is stuck.
const STUCK_S := 5.0
## A frame longer than this is slow, under ten frames a second. A frame under a
## twentieth of a second is never logged, since every frame after a stroke on a
## large painting is one.
const SLOW_S := 0.1
## Slow frames in one run adding up past this, not counting a stall, which has a
## line already, are a freeze. A run ends when its frames on time since its last
## slow one add up past `SLOW_S`.
const SLOW_RUN_S := 1.0
## Frames on time with no motion for longer than this ...
const QUIET_S := 0.25
## ... and then this many motions in one frame are a pen held back, the driver
## or the system sitting on the pen's events, known only by a heap arriving after
## a silence because Godot 4.7 stamps no event with its time. A pen at
## 200 reports a second held back for `QUIET_S` sends 50, and a mouse at
## 1000 a second resuming after a rest sends one per millisecond of the frame
## it resumes in, about ten at the resting cap of a hundred frames a second.
const BURST_MOTIONS := 24
## The ticket of the place `note` writes, which `enter` never answers, so a
## `give_back` of it, a dialog's hide before it ever showed, gives back nothing.
const NOTED := 0

## Guards `_places` and `_tickets`, which the watcher's thread reads.
static var _mutex := Mutex.new()
## The places standing, oldest first, each a ticket, what it says and when it
## was written, in microseconds. The one `note` writes has ticket `NOTED` and
## is always there, so a stall always has a place to name. Every place is
## timed, not only while the journal is on, because a stall line says how old
## the place it names is.
static var _places: Array[Array] = [[NOTED, "the boot", 0]]
## The place given back last, what it said, when it was entered and when it was
## given back, in microseconds, and empty before the first give back. Work that
## enters a place and gives it back inside one frame has left no place standing
## by the time the watch measures the gap that work held, an export being such
## work, so a line for a gap the give back fell in names this one.
static var _left: Array = []
## The last ticket `enter` answered.
static var _tickets: int = NOTED
## How many notes and enters a run's line can name, the newest kept. A run past
## it names the latest of its work, which is the work still under way.
const EVENTS_KEPT := 1024
## How many pieces of work a run's line names at most, the rest counted.
const EVENTS_NAMED := 3
## The notes and enters, oldest first, each its number and what it said.
static var _events: Array[Array] = []
## The number of the last note or enter, zero before the first.
static var _event_number: int = 0
## Whether the quit has been handed to the engine, after which a teardown of
## Sara's own prints a line. Before it a teardown is a suite freeing a canvas.
static var _quitting: bool = false
## Whether the journal prints, read once from the flag and the environment.
## Public as the docker's drag trail is, so a suite turns it on and off.
static var journal: bool = (
    OS.get_environment(JOURNAL_ENV) == "1"
    or OS.get_cmdline_user_args().has(JOURNAL_FLAG)
    or OS.get_cmdline_args().has(JOURNAL_FLAG)
)


## Notes where Sara went, for the stall lines, without a line of its own. It
## stands until the next note, over every place entered before it.
static func note(what: String) -> void:
    _mutex.lock()
    _drop(NOTED)
    _places.append([NOTED, what, Time.get_ticks_usec()])
    _count(what)
    _mutex.unlock()
    if journal:
        mark("went to %s" % what)


## Enters a place that stands only until the ticket answered is handed to
## `give_back`, a dialog while it shows or a command while it runs.
static func enter(what: String) -> int:
    _mutex.lock()
    _tickets += 1
    var ticket := _tickets
    _places.append([ticket, what, Time.get_ticks_usec()])
    _count(what)
    _mutex.unlock()
    if journal:
        mark("entered %s" % what)
    return ticket


## Puts *what* on the numbered list a run's line reads. The caller holds the
## mutex.
static func _count(what: String) -> void:
    _event_number += 1
    _events.append([_event_number, what])
    if _events.size() > EVENTS_KEPT:
        _events.pop_front()


## The number of the last note or enter, which the watch keeps at each beat.
static func events_so_far() -> int:
    _mutex.lock()
    var number := _event_number
    _mutex.unlock()
    return number


## What a run's line names for the notes and enters numbered past *after* up to
## *upto*: each told once, the most frequent first with how many times, an
## earlier one first among equals, and past `EVENTS_NAMED` a count of the rest.
## With none in it, the place standing, as before the run and with its age.
static func ran_in(after: int, upto: int) -> String:
    _mutex.lock()
    var counts: Dictionary[String, int] = {}
    for event: Array in _events:
        var number: int = event[0]
        if number > after and number <= upto:
            counts[event[1]] = counts.get(event[1], 0) + 1
    var place: Array = _places[-1]
    _mutex.unlock()
    if counts.is_empty():
        return "nothing noted in it, before it at %s" % _aged(place, Time.get_ticks_usec(), -1)
    var named: Array = counts.keys()
    # A sort that keeps the order of equals is not promised, so the first seen
    # is compared by its place in the keys, which a Dictionary keeps.
    var seen := {}
    for index in named.size():
        seen[named[index]] = index
    named.sort_custom(
        func(a: String, b: String) -> bool: return counts[a] > counts[b] or (counts[a] == counts[b] and seen[a] < seen[b])
    )
    var told := PackedStringArray()
    for what: String in named.slice(0, EVENTS_NAMED):
        told.append(what if counts[what] == 1 else "%s (%d times)" % [what, counts[what]])
    if named.size() > EVENTS_NAMED:
        told.append("%d more" % (named.size() - EVENTS_NAMED))
    return "at " + ", ".join(told)


## Gives back the place *ticket* entered, wherever it stands, so the place a
## stall names is the latest of those left. A ticket given back already gives
## back nothing.
static func give_back(ticket: int) -> void:
    if ticket == NOTED:
        return
    _mutex.lock()
    var place := _drop(ticket)
    _mutex.unlock()
    if journal and not place.is_empty():
        var entered: int = place[2]
        mark("left %s after %d ms" % [place[1], int((Time.get_ticks_usec() - entered) / 1000.0)])


## Takes *ticket*'s place off the list and answers it, the ticket, what it said
## and when it was written, or an empty array when it was given back already.
## The caller holds the mutex.
static func _drop(ticket: int) -> Array:
    for index in _places.size():
        if _places[index][0] == ticket:
            var place: Array = _places[index]
            _places.remove_at(index)
            if ticket != NOTED:
                _left = [place[1], place[2], Time.get_ticks_usec()]
            return place
    return []


## A line of the journal, with the milliseconds since start, and nothing while
## the journal is off. For what Sara did that is no place of its own, a preset
## applied or a window shown.
static func mark(what: String) -> void:
    if journal:
        print("%s %d ms, %s" % [JOURNAL, Time.get_ticks_msec(), what])


## Prints a journal line each time a window in *tree* is shown or hidden, a
## menu, a popup and a docker included, those there now and those added after.
## The watch asks for it while the journal is on.
static func follow_windows(tree: SceneTree) -> void:
    if not tree.node_added.is_connected(_window_added):
        tree.node_added.connect(_window_added)
    var stack: Array[Node] = [tree.root]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        _follow_window(node)
        stack.append_array(node.get_children(true))


## A window that joins the tree showing told its visibility as it entered,
## before the tree said it was added, so its showing is told here.
static func _window_added(node: Node) -> void:
    if _follow_window(node) and journal and (node as Window).visible:
        _window_moved(node as Window)


## Follows *node* when it is a window not followed yet, and answers whether it
## is a window at all.
static func _follow_window(node: Node) -> bool:
    var window := node as Window
    if window == null:
        return false
    if not window.visibility_changed.is_connected(_window_moved):
        window.visibility_changed.connect(_window_moved.bind(window))
    return true


static func _window_moved(window: Window) -> void:
    mark("%s %s" % [window_name(window), "shown" if window.visible else "hidden"])


## What the journal calls *window*: a menu, a popup or a window, by its title or
## its node's name, and the class it is, the nearest named one of its scripts, so
## a docker reads as its own class.
static func window_name(window: Window) -> String:
    var kind := "the menu" if window is PopupMenu else "the popup" if window is Popup else "the window"
    var label := window.title if not window.title.is_empty() else String(window.name)
    var type := window.get_class()
    var script: Script = window.get_script()
    while script != null:
        if not String(script.get_global_name()).is_empty():
            type = String(script.get_global_name())
            break
        script = script.get_base_script()
    return "%s %s (%s)" % [kind, label, type]


## A stage of the quit, noted and printed as a line.
static func stage(what: String) -> void:
    note(what)
    print("%s %s" % [TRAIL, what])


## The quit is handed to the engine, and from here a teardown prints a line.
## `what` ends with the quit called, and a suite's Main passes `engine` false to
## stop short of the engine's quit, which would end the whole run.
static func hand_over(tree: SceneTree, what: String, engine := true) -> void:
    if not engine:
        stage("%s, and a suite stops short of the engine's quit" % what)
        return
    _quitting = true
    stage("%s, Sara's own teardown follows" % what)
    tree.quit()


## A large teardown of Sara's own, a line while quitting and a note otherwise.
static func teardown(what: String) -> void:
    if _quitting:
        stage(what)
    else:
        note(what)


## Where Sara is, the latest place noted or entered and not given back, from
## either thread.
static func last() -> String:
    _mutex.lock()
    var what: String = _places[-1][1]
    _mutex.unlock()
    return what


## Where Sara is and how long its place has stood, which is what a stall line,
## a slow run's line and the stuck watcher name.
##
## A place written in the last `SLOW_S` is this frame's own work and reads as
## it is. An older one says how long ago it was written, because the work that
## holds a frame does not always write a place: every stall of the structure
## painter's night read `at SaSadFile: opened ...-start.sad in 2530 ms` for a
## load minutes past, and nothing in the line said so. An age about as
## long as the frame is a place that was written inside it.
static func last_aged() -> String:
    _mutex.lock()
    var place: Array = _places[-1]
    _mutex.unlock()
    return _aged(place, Time.get_ticks_usec(), int(SLOW_S * 1e6))


## Where Sara was over the *gap_usec* just measured, which is what a line for
## one frame names.
##
## The place standing, unless the place given back last stood over half of
## that gap: then the gap is that work's, and the line says when it was
## entered and that it has ended. An export enters and gives back inside one
## frame, so by the time the watch measures the frame it held, nothing of it
## stands. Half the gap at least, rather than any part of it, because a dialog
## hidden as a frame began would otherwise take the frame after it, which is
## the work that followed the dialog and not the dialog.
##
## A line for one frame always says the age, where `last_aged` leaves it off a
## place of this frame's own. Against the gap beside it an age is the whole
## reading: as long as the frame is work that wrote its place when it began,
## and a fifth of a second against a frame of 1.2 s is work that wrote its
## place as the frame ended and held none of it. The door's request of thirty
## eyes leaves such a frame between every two steps, and the eye noted in its
## last tenth would read as the work that held it.
static func held(gap_usec: int) -> String:
    _mutex.lock()
    var place: Array = _places[-1]
    var left: Array = _left
    _mutex.unlock()
    var now := Time.get_ticks_usec()
    if not left.is_empty():
        var entered: int = left[1]
        var given_back: int = left[2]
        var stood := mini(given_back, now) - maxi(entered, now - gap_usec)
        @warning_ignore("integer_division")
        var half := gap_usec / 2
        if stood >= half:
            return "%s, entered %s ago and given back" % [left[0], how_long(now - entered)]
    return _aged(place, now, -1)


## *place* named as a line names it at *now*: by itself while its age is
## *floor_usec* or less, which is this frame's own work, and with its age and
## whether it was noted or entered when it is older than that.
static func _aged(place: Array, now: int, floor_usec: int) -> String:
    var written: int = place[2]
    var what: String = place[1]
    var ticket: int = place[0]
    var age := now - written
    if age <= floor_usec:
        return what
    return "%s, %s %s ago" % [what, "noted" if ticket == NOTED else "entered", how_long(age)]


## *usec* in the words a line of the log says it in: tenths of a second inside
## a minute, and minutes and seconds beyond one, since a label that stale is
## read by the minute.
static func how_long(usec: int) -> String:
    var seconds := usec / 1e6
    if seconds < 60.0:
        return "%.1f s" % seconds
    @warning_ignore("integer_division")
    var minutes := int(seconds) / 60
    return "%d min %d s" % [minutes, int(seconds) % 60]


## The file the engine is writing its log into: the launcher's `SARA_LOG_FILE`
## when it passed `--log-file`, and the project's setting otherwise. The flag
## tells a script nothing, so a launcher that passes it sets the variable too.
static func log_path() -> String:
    var asked := OS.get_environment("SARA_LOG_FILE")
    if not asked.is_empty():
        return asked
    var fallback := SaDataRoot.log_path()
    var configured: Variant = ProjectSettings.get_setting("debug/file_logging/log_path", fallback)
    if str(configured) == SaDataRoot.ENGINE_LOG:
        configured = SaDataRoot.default_log()
    return ProjectSettings.globalize_path(str(configured))


## Starts the watch under the root of *node*'s tree, watching until the root
## itself leaves it. A node outside any tree, a suite's Main, starts none.
##
## Not until the watch leaves: a node's children leave before it does, in the
## reverse of the order they were added in rather than of their index, so a
## watch added after the boot leaves before Main and the autoloads, and a
## freeze in their teardown would go unwatched. The root's own `tree_exiting`
## comes after every node of Sara's has left and before any is freed.
static func watch(node: Node) -> Watch:
    if not node.is_inside_tree():
        return null
    var root := node.get_tree().root
    var watcher := Watch.new()
    root.add_child(watcher)
    if journal:
        follow_windows(node.get_tree())
    root.tree_exiting.connect(watcher.finish)
    return watcher


## Wakes the engine's Wayland events thread until the process has ended, so a
## quit never hangs in the engine's teardown (godot#123059).
##
## `WaylandThread::destroy` sets its flag, makes a roundtrip and joins the
## events thread, which reads the flag only once its `poll` on the display's
## socket returns. When the thread is scheduled late, the roundtrip has read
## the last reply off the socket already and the thread polls one nothing will
## write to again, so the process stays up with the main thread in the join.
## Under a nested weston that was one quit in forty, and more on a loaded
## machine, which is how a door quit with a 75 MB file open hung.
## A signal the thread catches ends that `poll` with `EINTR`, after which the
## thread reads the flag and leaves. The one signal a Godot process catches
## that does nothing is glibc's 33, `SIGSETXID`, whose handler returns at once
## for a signal another process sent. Nothing a script runs is left by then,
## so the waking is a small shell started here, which signals the thread by
## its name every half second while the process lives, for a minute at most,
## and only when the process catches 33.
class EngineWake:
    const _NAME := "sara-quit-wake"
    const _SHELL := """
exec </dev/null >/dev/null 2>&1
p=$1
caught=$(sed -n 's/^SigCgt:[[:space:]]*//p' /proc/$p/status)
[ -n "$caught" ] && [ $(( (0x$caught >> 32) & 1 )) -eq 1 ] || exit 0
n=0
while [ $n -lt 120 ] && [ -d /proc/$p/task ]; do
    sleep 0.5
    for t in /proc/$p/task/*; do
        [ "$(cat $t/comm 2>/dev/null)" = "Wayland Events" ] && kill -33 ${t##*/}
    done
    n=$((n + 1))
done
"""

    ## Starts the waking when the engine's display is Wayland on Linux, the
    ## only place the thread exists. A failed start leaves the quit as it was.
    static func start() -> void:
        if OS.get_name() != "Linux" or DisplayServer.get_name() != "Wayland":
            return
        OS.create_process("/bin/sh", ["-c", _SHELL, _NAME, str(OS.get_process_id())])


## The frame gaps, and the thread that speaks while the main thread cannot.
class Watch:
    extends Node

    const _SLOW_USEC := int(SaTrail.SLOW_S * 1e6)
    const _STALL_USEC := int(SaTrail.STALL_S * 1e6)
    const _HITCH_USEC := int(SaTrail.HITCH_S * 1e6)
    const _HITCH_BURST_USEC := int(SaTrail.HITCH_BURST_S * 1e6)
    const _RUN_LINE := (
        "%s the frames came slow for %.1f s, %d of them over %.1f s and the longest %.2f s," + " with %d pen motions, %s"
    )
    const _SLOW_LINE := "a frame took %d ms%s, at %s"
    const _PEN_LINE := "%s the pen went quiet for %.2f s while the frames came on time, then %d motions came in one frame, at %s"

    var _thread := Thread.new()
    ## Guards the five below, which both threads touch.
    var _lock := Mutex.new()
    ## When the main thread last ran a frame.
    var _beat_usec: int = Time.get_ticks_usec()
    ## The beat the watcher last spoke about, so one stall is one line.
    var _told_usec: int = 0
    var _stopping: bool = false
    ## Whether a window of Sara's holds the focus, as the last focus
    ## notification said. Away, a window the desktop hides may draw no frame at
    ## all, so the watcher says nothing while Sara is away.
    var _focused: bool = true
    ## Whether the focus left or came back since the last beat, so the gap the
    ## next frame closes may hold time Sara was away rather than a slow frame.
    var _focus_moved: bool = false

    ## The run of slow frames under way, none while `_run_frames` is zero. Its
    ## span holds the frames on time between its slow ones, and the untold time
    ## only the slow frames that were not stalls.
    var _run_frames: int = 0
    var _run_span_usec: int = 0
    var _run_untold_usec: int = 0
    var _run_longest_usec: int = 0
    ## Frames on time since the run's last slow one, which end it past `SLOW_S`.
    var _run_fast_usec: int = 0
    ## The pen's motions that came in the run, which tell a backlog of the pen
    ## from work of Sara's own that no hand asked for.
    var _run_motions: int = 0
    ## The trail's number of notes and enters at the last beat, and the span of
    ## them a run's line names: past the beat its first slow frame began at, up
    ## to its last slow frame.
    var _beat_events: int = SaTrail.events_so_far()
    var _run_after_event: int = 0
    var _run_upto_event: int = 0

    ## When the last hitch came, printed or folded into its burst, zero before
    ## any did.
    var _hitch_usec: int = 0

    ## The main thread's id under `/proc/self/task`, read on the main thread as
    ## the watch is made, and empty where the system has no `/proc`, which
    ## leaves every line as it was.
    var _main_task: String = _own_task()
    ## The latest schedule of the main thread the watcher read, and the one
    ## before the beat in hand, each with the clock it was read at, so a slow
    ## frame's line measures from a reading taken before the frame began. The
    ## watcher reads one a wake, and the main thread reads nothing while its
    ## frames come on time. Guarded by `_lock`.
    var _sched_newest := PackedInt64Array()
    var _sched_newest_usec: int = 0
    var _sched_before_beat := PackedInt64Array()
    var _sched_before_beat_usec: int = 0
    ## The reading the run of slow frames under way measures from, and its clock.
    var _run_sched := PackedInt64Array()
    var _run_sched_usec: int = 0

    ## The stroke ledger's motion count at the last beat, which moves at the
    ## canvas window's input signal, the first clock an event meets.
    var _seen_motions: int = SaStrokeLedger.motions
    ## The last beat that brought motions, zero before any did.
    var _moved_usec: int = 0
    ## The last beat since then that brought none, so the silence is measured
    ## without the frame the heap lands in, whose own gap holds its handling.
    var _silent_usec: int = 0
    ## The longest silent frame, so a silence that was a slow frame is left to
    ## the run of slow frames and the stall.
    var _quiet_longest_usec: int = 0

    func _init() -> void:
        name = "SaTrailWatch"
        process_mode = Node.PROCESS_MODE_ALWAYS

    func _enter_tree() -> void:
        if not _thread.is_started() and not _stopping:
            _thread.start(_watch)

    func _process(_delta: float) -> void:
        frame_came(Time.get_ticks_usec(), SaStrokeLedger.motions)

    ## A frame came at *now*, with the ledger's motion count at *motions*. A gap
    ## over `STALL_S` since the last one is a line, and it is folded into the
    ## run of slow frames and the pen's silence. Integers only, and a string
    ## read only on a slow frame, because this runs every frame.
    func frame_came(now: int, motions: int) -> void:
        _lock.lock()
        var gap := now - _beat_usec
        _beat_usec = now
        var came_back := _focus_moved
        _focus_moved = false
        _lock.unlock()
        var events_before := _beat_events
        _beat_events = SaTrail.events_so_far()
        if SaTrail.journal and gap > _SLOW_USEC:
            var fell := ", a focus change fell in it" if came_back else ""
            SaTrail.mark(_SLOW_LINE % [int(gap / 1000.0), fell, SaTrail.held(gap)])
        if came_back:
            _came_back(motions)
            return
        var from: Array = [PackedInt64Array(), 0]
        if gap > _HITCH_USEC:
            from = _reading_before(now - gap)
        if gap > _STALL_USEC:
            var said := "%s a frame took %.1f s, at %s" % [SaTrail.STALL, gap / 1e6, SaTrail.held(gap)]
            print(said + _on_a_core(from, "thread-self"))
        elif gap > _HITCH_USEC:
            _hitch(now, gap, from)
        # The perf window clears the ledger at its begin, and what came since is
        # what is there.
        var fresh := motions - _seen_motions if motions >= _seen_motions else motions
        _seen_motions = motions
        if gap > _SLOW_USEC and _run_frames == 0:
            _run_sched = from[0]
            _run_sched_usec = from[1]
        _fold_slow(gap, fresh, events_before)
        _fold_pen(now, gap, fresh)

    ## A frame of *gap* that ended at *now* was a hitch, and a line unless the
    ## one before it came a second or less ago. *from* is the reading of the
    ## main thread's schedule the line measures from.
    func _hitch(now: int, gap: int, from: Array) -> void:
        var burst := _hitch_usec > 0 and now - _hitch_usec <= _HITCH_BURST_USEC
        _hitch_usec = now
        if not burst:
            var said := "%s a frame took %d ms, at %s" % [SaTrail.HITCH, int(gap / 1000.0), SaTrail.held(gap)]
            print(said + _on_a_core(from, "thread-self"))

    ## The watcher's reading of the main thread's schedule at *now*, kept as
    ## the newest, and the newest before it kept as the one before the beat
    ## when it was read before the beat in hand. The watcher calls it each wake,
    ## and a suite whose watch has no thread calls it itself.
    func sample(now: int) -> void:
        if _main_task.is_empty():
            return
        var read := SaFrameTrace.schedule("self/task/" + _main_task)
        if read.is_empty():
            return
        _lock.lock()
        if _sched_newest_usec > 0 and _sched_newest_usec <= _beat_usec:
            _sched_before_beat = _sched_newest
            _sched_before_beat_usec = _sched_newest_usec
        _sched_newest = read
        _sched_newest_usec = now
        _lock.unlock()

    ## The latest reading taken at or before *began*, with its clock, or an
    ## empty one when the watcher has read none that early.
    func _reading_before(began: int) -> Array:
        _lock.lock()
        var out: Array = [PackedInt64Array(), 0]
        if _sched_newest_usec > 0 and _sched_newest_usec <= began:
            out = [_sched_newest, _sched_newest_usec]
        elif _sched_before_beat_usec > 0 and _sched_before_beat_usec <= began:
            out = [_sched_before_beat, _sched_before_beat_usec]
        _lock.unlock()
        return out

    ## The clause a slow frame's line ends with: how long since the reading
    ## *from*, which began at most one wake of the watcher before the frame did,
    ## and over that span the main thread's time on a core and waiting for one
    ## and the process's time on cores, in the frame trace's words. *thread* is
    ## where the main thread's schedule is read from by the calling thread.
    ## Nothing when there is no reading.
    func _on_a_core(from: Array, thread: String) -> String:
        var before: PackedInt64Array = from[0]
        if before.is_empty():
            return ""
        var now := Time.get_ticks_usec()
        var after := SaFrameTrace.schedule(thread)
        var clause := SaFrameTrace.scheduled(before, after)
        if clause.is_empty():
            return ""
        var read_at: int = from[1]
        return ", over the last %.1f ms%s" % [(now - read_at) / 1000.0, clause]

    ## The main thread's id, from the first field of its own `stat`, read on
    ## the thread that makes the watch, which is the main one.
    static func _own_task() -> String:
        var file := FileAccess.open("/proc/thread-self/stat", FileAccess.READ)
        if file == null:
            return ""
        var id := file.get_line().get_slice(" ", 0)
        return id if id.is_valid_int() else ""

    ## The gap just closed held a focus change, so it is the time Sara was away
    ## and no measure of a frame: it is neither a stall nor a slow frame, and the
    ## pen's silence starts again from here.
    func _came_back(motions: int) -> void:
        _seen_motions = motions
        _moved_usec = 0
        _silent_usec = 0
        _quiet_longest_usec = 0

    ## A frame of *gap* with *fresh* motions, the trail's count of notes and
    ## enters standing at *events_before* as it began, is folded into the run.
    func _fold_slow(gap: int, fresh: int, events_before: int) -> void:
        if gap > _SLOW_USEC:
            if _run_frames == 0:
                _run_after_event = events_before
            _run_upto_event = _beat_events
            _run_frames += 1
            _run_motions += fresh
            _run_span_usec += _run_fast_usec + gap
            _run_fast_usec = 0
            _run_longest_usec = maxi(_run_longest_usec, gap)
            if gap <= _STALL_USEC:
                _run_untold_usec += gap
            return
        if _run_frames == 0:
            return
        _run_fast_usec += gap
        if _run_fast_usec > _SLOW_USEC:
            _end_run()

    ## The run is over, and a line if it added up to a freeze. A stall alone
    ## never does, its line is told already.
    func _end_run() -> void:
        if _run_untold_usec > int(SaTrail.SLOW_RUN_S * 1e6):
            print(
                (
                    (
                        _RUN_LINE
                        % [
                            SaTrail.STALL,
                            _run_span_usec / 1e6,
                            _run_frames,
                            SaTrail.SLOW_S,
                            _run_longest_usec / 1e6,
                            _run_motions,
                            SaTrail.ran_in(_run_after_event, _run_upto_event),
                        ]
                    )
                    + _on_a_core([_run_sched, _run_sched_usec], "thread-self")
                )
            )
        _run_frames = 0
        _run_motions = 0
        _run_span_usec = 0
        _run_untold_usec = 0
        _run_longest_usec = 0
        _run_fast_usec = 0
        _run_sched = PackedInt64Array()
        _run_sched_usec = 0

    func _fold_pen(now: int, gap: int, fresh: int) -> void:
        if fresh == 0:
            if _moved_usec > 0:
                _silent_usec = now
                _quiet_longest_usec = maxi(_quiet_longest_usec, gap)
            return
        var quiet := _silent_usec - _moved_usec
        var held_back := (
            _moved_usec > 0
            and quiet > int(SaTrail.QUIET_S * 1e6)
            and fresh >= SaTrail.BURST_MOTIONS
            and _quiet_longest_usec <= _SLOW_USEC
        )
        if held_back:
            print(_PEN_LINE % [SaTrail.STALL, quiet / 1e6, fresh, SaTrail.last_aged()])
        _moved_usec = now
        _silent_usec = now
        _quiet_longest_usec = 0

    ## The root is leaving: the thread is joined here, before the engine's own
    ## teardown, so none outlives the tree and none is reported leaked. A run of
    ## slow frames the quit cut short is told.
    func finish() -> void:
        if _run_frames > 0:
            _end_run()
        stop()
        if SaTrail._quitting:
            SaTrail.EngineWake.start()
            SaTrail.stage("Sara's own teardown is done, the engine's follows")

    ## Freed without a `finish`, which is a suite's watch, the thread is joined
    ## all the same. The focus leaving every window of Sara's or coming back to
    ## one is noted, which the scene tree hands to every node and a suite's watch
    ## out of the tree takes by `notification`.
    func _notification(what: int) -> void:
        if what == NOTIFICATION_PREDELETE:
            stop()
        elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
            _lock.lock()
            _focused = what == NOTIFICATION_APPLICATION_FOCUS_IN
            _focus_moved = true
            _lock.unlock()
            SaTrail.mark("the focus came back to Sara" if what == NOTIFICATION_APPLICATION_FOCUS_IN else "the focus left Sara")

    func stop() -> void:
        _lock.lock()
        _stopping = true
        _lock.unlock()
        if _thread.is_started():
            _thread.wait_to_finish()

    func _watch() -> void:
        while true:
            OS.delay_msec(100)
            _lock.lock()
            var stopping := _stopping
            _lock.unlock()
            if stopping:
                return
            var now := Time.get_ticks_usec()
            sample(now)
            var stuck := stuck_for(now)
            if stuck > 0:
                var said := (
                    "%s the main thread has been stuck for %.1f s, at %s" % [SaTrail.STALL, stuck / 1e6, SaTrail.last_aged()]
                )
                print(said + _on_a_core(_reading_before(now - stuck), "self/task/" + _main_task))

    ## How long the main thread has been stuck at *now*, when that is a line
    ## the watcher owes, else zero. A stuck beat is told once, and never while
    ## Sara is away or the focus moved since the beat, since a hidden window
    ## may draw no frame at all.
    func stuck_for(now: int) -> int:
        _lock.lock()
        var stuck := now - _beat_usec
        var owed := stuck > int(SaTrail.STUCK_S * 1e6) and _told_usec != _beat_usec and _focused and not _focus_moved
        if owed:
            _told_usec = _beat_usec
        _lock.unlock()
        return stuck if owed else 0
