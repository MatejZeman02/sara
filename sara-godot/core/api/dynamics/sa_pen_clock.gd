## When a pen sample was made, the one clock every brush reads its times and
## its clock-drawn seeds from.
##
## **The wall clock in the app, the frame count in a capture.** A painter's
## stroke is timed by the hand, and the engine's clock is the nearest reading of
## that. A scenario's stroke is timed by nothing but its frames: it lays one move
## a frame, and how many microseconds a frame took on this run is how busy the
## machine was. Read off the engine's clock, that jitter would reach the speed
## sensor, and a scenario's noise strokes would land a texel or two apart
## between runs of one tree, by up to nine at the thin end where the smoother
## has the fewest samples. Pinned, a
## scenario's pen moves one frame of [constant FRAME_MS] per move, whatever the
## frame cost.
##
## **A sixtieth stays right under a load, and a report at a rate brings its own
## time.** A frame-paced stroke is written as one move a frame, so a frame is
## its pen's interval by definition, and counted at its real length a load of
## 33 ms read that pen at two fifths of its speed and the stroke's picture moved
## with the machine. A stroke's `rate` sends several reports a frame, and each
## is sent with the clock [method held] at the time it was due, so the pin
## times the frame and never the reports inside it.
##
## **The app's reports in one frame are one moment.** Godot's events carry no
## time, and the reports a frame delivers were made over the frame before it
## and reach the brush microseconds apart. [method report_ms] reads them all at
## the time the frame's first one read, and the speed smoother spreads one
## moment's reports evenly over the frame's interval once the next begins.
##
## **A preset's picture is timed by its own events.** It drives a whole stroke
## through a tool with nobody's hand on it, and read off either clock above its
## speed was the pace the chooser drew it at: the Bristle Flat's picture, whose
## Drift follows speed, came out a different file on every cold boot and moved
## 387 texels once the chooser drew a frame between its shares. So the picture
## holds the clock at its own event's time for the length of that event's call,
## [method held], and that time wins over the pin and the wall.
##
## **A replayed recording is timed by the recording.** A lesson's player
## [method follow]s the times the recorded stroke was laid at and hands each
## frame the airbrush's interval the recorded frame had, [method hand_frame],
## so the same recording lays the same paint at any pace and on any machine,
## and hands the stroke the seed the recording drew, [method seed_next].
## The airbrush asks [method frame_elapsed_ms] for its interval, which is the
## engine's frame delta whenever nothing follows a recording.
##
## Static, because the clock is the process's, and every brush in the door and
## every module asks it without holding one.
class_name SaPenClock
extends RefCounted

## What one drawn frame counts for while the clock is pinned, a display at
## sixty hertz, the rate the speed curves of the shipped presets were drawn at.
const FRAME_MS: float = 1000.0 / 60.0

## Where a pinned clock starts, so the first frame after the pin reads a
## second rather than nought: a seed of nought means "draw one from the clock"
## to [method SaStrokeInfo.begin], and a clock that answered nought would hand
## the question back to itself.
const PINNED_ORIGIN_USEC: int = 1_000_000

## The process frame the pin was taken at, or -1 while the clock is the wall's.
static var _pinned_at: int = -1

## The time [method held] holds the clock at for the length of its call, or -1
## while nothing holds it.
static var _held_usec: int = -1

## The time a replay holds the clock at from frame to frame, [method follow],
## or -1 while no replay does.
static var _followed_usec: int = -1

## The process frame the replay's handed interval belongs to, and the
## interval in milliseconds, [method hand_frame].
static var _handed_frame: int = -1
static var _handed_ms: float = 0.0

## The process frame the airbrush last asked [method frame_elapsed_ms] in.
static var _ticked_frame: int = -1

## The seed the last stroke drew, [method stroke_seed], which a recording
## keeps beside its stroke.
static var last_seed: int = 0

## How many seeds strokes have drawn since Sara started, so a recording tells
## whether a press drew one.
static var seeds_drawn: int = 0

## The seed a replay handed the next stroke, or -1 while none is handed.
static var _next_seed: int = -1

## The process frame whose first report [member _report_usec] is the time of,
## or -1 before any report.
static var _report_frame: int = -1

## What the engine's clock read at the first report of [member _report_frame].
static var _report_usec: int = 0


## Now, in microseconds: the time a call is held at, or else the engine's clock,
## or the frames since the pin at [constant FRAME_MS] each.
static func now_usec() -> int:
    if _held_usec >= 0:
        return _held_usec
    if _followed_usec >= 0:
        return _followed_usec
    if _pinned_at < 0:
        return Time.get_ticks_usec()
    return after_frames(Engine.get_process_frames() - _pinned_at)


## What the clock reads *frames* frames of [constant FRAME_MS] after
## [constant PINNED_ORIGIN_USEC], the time a pinned clock reads that many frames
## after its pin, and the time a picture's event that many events into its
## stroke is held at.
static func after_frames(frames: int) -> int:
    return PINNED_ORIGIN_USEC + roundi(float(frames) * FRAME_MS * 1000.0)


## Calls *work* with the clock reading *usec* for the whole of the call, and
## gives the clock back as it was once the call returns, so a hold inside a
## hold is the inner one's time and then the outer one's again.
##
## A preset's picture sends each event of its stroke through this, so every
## sample its brush stamps reads the event's own time whatever the pace the
## picture is drawn at, on every boot and in a capture.
static func held(usec: int, work: Callable) -> void:
    var outer := _held_usec
    _held_usec = usec
    work.call()
    _held_usec = outer


## Now, in milliseconds, which is what the speed smoother is fed.
static func now_ms() -> float:
    return float(now_usec()) / 1000.0


## Holds the clock at *usec* from now until the next call or [method let_go],
## across frames, the time a replayed recording's event or frame was made at.
## A call's [method held] still wins inside it.
static func follow(usec: int) -> void:
    _followed_usec = usec


## Back to the pin or the engine's clock after a replay.
static func let_go() -> void:
    _followed_usec = -1
    _handed_frame = -1
    _next_seed = -1


## Whether a replay holds the clock.
static func is_followed() -> bool:
    return _followed_usec >= 0


## Hands the next process frame *ms*, the airbrush's interval the recording's
## own frame had. The frames of a slowed replay between two of the
## recording's are handed none.
static func hand_frame(ms: float) -> void:
    _handed_frame = Engine.get_process_frames() + 1
    _handed_ms = ms


## The milliseconds the airbrush's clock moves this frame: *delta*, the
## engine's frame in seconds, or while a replay holds the clock, what it handed
## this frame and nought on a frame it handed nothing.
static func frame_elapsed_ms(delta: float) -> float:
    _ticked_frame = Engine.get_process_frames()
    if _followed_usec < 0:
        return delta * 1000.0
    return _handed_ms if Engine.get_process_frames() == _handed_frame else 0.0


## A stroke's seed, which places its grain: the one a replay handed, [method
## seed_next], or the clock's time now.
static func stroke_seed() -> int:
    last_seed = _next_seed if _next_seed >= 0 else now_usec()
    _next_seed = -1
    seeds_drawn += 1
    return last_seed


## Hands the next stroke *usec* for its seed, the one the recorded stroke drew.
static func seed_next(usec: int) -> void:
    _next_seed = usec


## The process frame whose airbrush tick is the first to see an event made
## now: this one when its tick has not come yet, the next once it has. What a
## recording keeps beside each point, so a replay hands the point to the same
## tick the recording reached.
static func tick_frame() -> int:
    var frame := Engine.get_process_frames()
    return frame + 1 if _ticked_frame == frame else frame


## When a pen report was made, in milliseconds, which the speed smoother is fed
## once a report: the held time of a report that brings its own, the frame's on
## a pinned clock, and on the engine's the time the frame's first report read,
## so every report one frame delivers reads one moment.
static func report_ms() -> float:
    return float(report_usec()) / 1000.0


## [method report_ms] in microseconds, which a recording keeps beside each
## point of a stroke, so a replay reports the times the recorded pen did.
static func report_usec() -> int:
    if _held_usec >= 0 or _followed_usec >= 0 or _pinned_at >= 0:
        return now_usec()
    var frame := Engine.get_process_frames()
    if frame != _report_frame:
        _report_frame = frame
        _report_usec = Time.get_ticks_usec()
    return _report_usec


## Whether the clock counts frames, which a suite and a state dump read.
static func is_pinned() -> bool:
    return _pinned_at >= 0


## Counts frames from this one on, so every run of a scenario times its strokes
## the same. The capture node calls it once, and nothing in the app does.
static func pin_to_frames() -> void:
    _pinned_at = Engine.get_process_frames()


## Back to the engine's clock, for a suite that pinned it.
static func unpin() -> void:
    _pinned_at = -1
