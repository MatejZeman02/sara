## How often Sara presents, and how deep the queue in front of the glass is.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A brush ring that trails the real pointer is fixed here and not by a cap on
## the brush's size. The overlay samples the pointer at draw time, so the ring
## is not drawn late, it is presented late. Godot renders behind vsync into a
## three-image swapchain, so a frame reaches the glass two or three refreshes
## after it was drawn, and a Wayland compositor adds one more. The target is
## one frame, not zero.
##
## Mailbox replaces the oldest queued frame rather than waiting for a slot. The
## driver answers on the next frame drawn, so the pacer reads the answer then,
## and `fallback_mode` says what stands where it was refused. The fallback is no
## vsync where a compositor stands behind the window (it flips whole frames, so
## nothing tears), and vsync stays enabled where that is not known, a bare X11
## session or Windows.
##
## The swapchain holds two images, set by
## `rendering/rendering_device/vsync/swapchain_image_count` in `project.godot`,
## and an `override.cfg` beside the program can change it. The resting cap
## (`run/max_fps` is 100) comes off while motion events arrive and goes back on
## when they stop, so an idle program does not spin the GPU, and the cap that
## replaces it is the painter's `painting_frame_rate`. On Android that is read
## again on every frame the hand moves, because the panel goes from 60 to 120 Hz
## a moment after a touch, and [method request_unbuffered_pen] asks the window
## for every pen event, since a view hands them over once a frame.
##
## Whether it works is judged by `scripts/ring_lag.py` on a real desktop. This
## file reports what it did, in `capture_state`, so a scenario can say the
## settings took effect offscreen, where lag cannot be measured.
class_name SaFramePacer
extends Node

## Frames without a motion event before the cap and the low-processor mode come
## back.
##
## Twelve, which is a fifth of a second at 60 Hz. Long enough that the gap
## between two strokes, or the pause at the top of a stroke while the hand
## changes direction, does not drop the cap back on and lose a frame to it.
## Short enough that a program left alone is not spinning a second later.
const IDLE_FRAMES: int = 12

## Frames drawn after asking for mailbox before the answer is read. The first
## rebuilds the swapchain and is where the driver refuses, and the second is a
## margin for a frame the engine skipped.
const VSYNC_SETTLE_FRAMES: int = 2

## The name of the node the bootstrap adds, so anything looking for one asks the
## tree by name rather than keeping a reference.
const NODE_NAME: String = "SaFramePacer"

## The name Godot's Android display server answers to.
const ANDROID_DRIVER: String = "Android"

## `InputDevice.SOURCE_CLASS_POINTER`, the class of input a pen, a finger and a
## mouse all belong to, which is the argument `View.requestUnbufferedDispatch`
## takes.
const ANDROID_SOURCE_CLASS_POINTER: int = 2

## The cap and the low-processor mode as they were before this node touched
## either, read at `_ready` rather than assumed, so a profile or a command line
## that set one is what gets restored.
var resting_max_fps: int = 0
var resting_low_processor: bool = false

## Whether `settle_vsync` has read the driver's answer and put in the fallback
## where one was needed, which a dump reports so a mode read before it is not
## taken for the answer.
var vsync_settled: bool = false

## Whether the window took the request for unbatched pen events, which only an
## Android build makes. A dump reports it, because a request the bridge refused
## says nothing on screen.
var unbuffered_pen: bool = false

## `Engine.get_frames_drawn` when mailbox was asked for, which the settling
## counts from.
var _asked_at_frame: int = 0

## Frames since the last motion event, counted up to `IDLE_FRAMES` and no
## further. `IDLE_FRAMES` or more is resting.
var _idle_frames: int = IDLE_FRAMES

## Where the OS pointer was on the previous frame, which is the reading that
## actually answers "is the hand moving".
##
## **`_input` alone did not work and the first capture said so.** The pacer sits
## under Main in the root viewport, and by the time an event reaches a node there
## the canvas or a docker has often called `set_input_as_handled()`, which stops
## the event travelling any further. Six pacer dumps into a scenario that had
## just injected three motions, every one of them read `moving: false`. Sampling
## the pointer costs one call a frame, sees a warp a scenario made as readily as a
## hand, and cannot be swallowed by whoever handled the event. `_input` is kept
## beside it for the case the sample cannot see: a tablet under a compositor that
## will not move the pointer at all.
var _last_pointer: Vector2i = Vector2i.ZERO


## Adds a pacer to *host* unless it already has one, and answers it.
##
## Static and by name for the reason `CursorOverlay.attach_to` is: the bootstrap
## calls it, nothing keeps a reference, and calling it twice is a no-op rather
## than a second node counting the same frames.
static func attach_to(host: Node) -> SaFramePacer:
    if host == null:
        return null
    var existing := host.get_node_or_null(NODE_NAME) as SaFramePacer
    if existing != null:
        return existing
    var pacer := SaFramePacer.new()
    pacer.name = NODE_NAME
    host.add_child(pacer)
    return pacer


## Asks for mailbox, unless the project asked for a mode of its own, and
## answers what the window reports, as the `DisplayServer` enum.
##
## **Which is the mode asked for and not yet the driver's answer.** The driver
## looks at the modes its surface offers when it next rebuilds the swapchain,
## on the next frame drawn, and only then falls back to enabled with "The
## requested V-Sync mode Mailbox is not available". Read on the same line,
## mailbox is what the window says either way, so a read-back there never sees
## a refusal and no fallback would run. `settle_vsync` reads
## the answer once the driver has given it.
static func request_mailbox() -> int:
    if DisplayServer.get_name() == "headless":
        return DisplayServer.VSYNC_DISABLED
    if project_vsync_mode() == DisplayServer.VSYNC_ENABLED:
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)
    return DisplayServer.window_get_vsync_mode()


## Reads what the driver gave once it has drawn with it, puts the fallback in
## where that was not mailbox, and answers the mode that stands.
##
## Read back rather than taken from the setter, which returns nothing, because
## a report saying "mailbox" because mailbox was asked for is the kind of claim
## this report exists to stop.
static func settle_vsync() -> int:
    if DisplayServer.get_name() == "headless":
        return DisplayServer.VSYNC_DISABLED
    var got := DisplayServer.window_get_vsync_mode()
    var then := settled_mode(project_vsync_mode(), got, DisplayServer.get_name(), OS.has_environment("WAYLAND_DISPLAY"))
    if then >= 0:
        DisplayServer.window_set_vsync_mode(then)
    return DisplayServer.window_get_vsync_mode()


## The mode to put in once the driver answered *got* for a window whose project
## asked for *project_mode*, or -1 to leave it as it is: left where the project
## chose a mode or the driver gave mailbox, and otherwise `fallback_mode` unless
## that is what already stands.
static func settled_mode(project_mode: int, got: int, display_server: String, under_wayland: bool) -> int:
    if project_mode != DisplayServer.VSYNC_ENABLED or got == DisplayServer.VSYNC_MAILBOX:
        return -1
    var fallback := fallback_mode(display_server, under_wayland)
    return -1 if fallback == got else fallback


## The mode to stand where mailbox is refused, for a window under the display
## server named *display_server*, with *under_wayland* whether a Wayland
## compositor is running.
##
## No vsync where a compositor is known to take the window's frames whole,
## which is X11 under a Wayland compositor, because there the vsync queues
## frames in front of a compositor that has its own. Enabled everywhere else,
## rather than whatever was there: a bare X11 session may have no compositor
## at all and disabled would tear, and adaptive is enabled with a tear under the
## refresh rate. Wayland itself is in the second list only because mailbox has
## never been refused there.
static func fallback_mode(display_server: String, under_wayland: bool) -> int:
    if display_server == "X11" and under_wayland:
        return DisplayServer.VSYNC_DISABLED
    return DisplayServer.VSYNC_ENABLED


## The vsync mode the project settings ask for, enabled unless an
## `override.cfg` says otherwise.
static func project_vsync_mode() -> int:
    var mode: int = ProjectSettings.get_setting("display/window/vsync/vsync_mode", DisplayServer.VSYNC_ENABLED)
    return mode


## What the swapchain was told to hold, from the project setting, or 3 where the
## setting has never been written, which is the engine's own default.
static func swapchain_image_count() -> int:
    var count: int = ProjectSettings.get_setting("rendering/rendering_device/vsync/swapchain_image_count", 3)
    return count


func _ready() -> void:
    name = NODE_NAME
    resting_max_fps = Engine.max_fps
    resting_low_processor = OS.low_processor_usage_mode
    _last_pointer = _pointer_now()
    request_mailbox()
    unbuffered_pen = request_unbuffered_pen()
    _asked_at_frame = Engine.get_frames_drawn()
    # Every motion in this window, whether or not it is over a canvas, and
    # nothing is marked handled: this only counts.
    set_process_input(true)
    set_process(true)


func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        note_motion()


## One motion event arrived, which puts the painter's frame rate while painting
## in place of the resting cap if the hand was at rest. Public because a capture
## drives the pacer without a real pointer, and because the meaning is "the hand
## is moving" rather than "an InputEventMouseMotion was constructed".
func note_motion() -> void:
    if _idle_frames >= IDLE_FRAMES:
        Engine.max_fps = painting_max_fps()
        OS.low_processor_usage_mode = false
    _idle_frames = 0


## Puts the painting cap in again where the display's rate has moved since the
## hand started, on Android alone, whose panel changes its rate under the hand.
## Answers whether the cap changed.
func follow_the_panel(display_server: String = DisplayServer.get_name()) -> bool:
    if display_server != ANDROID_DRIVER or not is_moving():
        return false
    var cap := painting_max_fps()
    if cap == Engine.max_fps:
        return false
    Engine.max_fps = cap
    return true


## Asks Android for every pointer event as it arrives rather than one batch a
## frame, through the window's decor view, and answers whether it was asked.
## Elsewhere, or where the bridge gives no activity, it answers false and asks
## nothing.
##
## Called on Godot's own thread rather than Android's interface thread, which
## the bridge cannot reach without running a script there.
## `requestUnbufferedDispatch` stores the class in a field of the view and of
## its root, read by the interface thread at the next event, and checks no
## thread, so the call is safe from here.
static func request_unbuffered_pen() -> bool:
    if DisplayServer.get_name() != ANDROID_DRIVER or not Engine.has_singleton("AndroidRuntime"):
        return false
    var activity: Object = Engine.get_singleton("AndroidRuntime").call("getActivity")
    if activity == null:
        return false
    var window: Object = activity.call("getWindow")
    if window == null:
        return false
    var decor: Object = window.call("getDecorView")
    if decor == null:
        return false
    decor.call("requestUnbufferedDispatch", ANDROID_SOURCE_CLASS_POINTER)
    return true


## The cap while the hand moves, 0 for uncapped, from the painter's setting.
static func painting_max_fps() -> int:
    return SaSettingsPerformance.painting_max_fps(SaSettings.painting_frame_rate)


func _process(_delta: float) -> void:
    if not vsync_settled and Engine.get_frames_drawn() >= _asked_at_frame + VSYNC_SETTLE_FRAMES:
        settle_vsync()
        vsync_settled = true
    var at := _pointer_now()
    if at != _last_pointer:
        _last_pointer = at
        note_motion()
        follow_the_panel()
        return
    if _idle_frames >= IDLE_FRAMES:
        return
    _idle_frames += 1
    if _idle_frames >= IDLE_FRAMES:
        rest()


## The pointer, pen or mouse, or the origin where there is no display server to ask, which
## is the headless test run.
static func _pointer_now() -> Vector2i:
    return Vector2i.ZERO if DisplayServer.get_name() == "headless" else Vector2i(SaCursorPolicy.pointer_in(null))


## Puts the cap and the low-processor mode back, whatever they were at boot.
##
## Called from `_process` when the hand stops, and from `_exit_tree`, because a
## pacer freed while the hand was moving would otherwise leave the engine
## uncapped for the rest of the session.
func rest() -> void:
    Engine.max_fps = resting_max_fps
    OS.low_processor_usage_mode = resting_low_processor
    _idle_frames = IDLE_FRAMES


func _exit_tree() -> void:
    rest()


## Whether the cap is off because the hand is moving.
func is_moving() -> bool:
    return _idle_frames < IDLE_FRAMES


## Reports the frame pacer: for a scenario, the mode the driver gave, the
## swapchain count the project asked for, the cap now and at rest, and whether
## the hand is moving.
##
## The whole of the pacer's proof offscreen. The lag itself cannot be measured
## under a nested compositor, which is why `scripts/ring_lag.py` is a desktop
## script, so what a run here can say is that mailbox took, that the swapchain
## is two, and that the cap comes off under motion and goes back on after it.
## `project_vsync_mode` is there so a tester who wrote an `override.cfg` sees
## it was read.
static func capture_state(tree: SceneTree) -> String:
    var pacer := tree.root.find_child(NODE_NAME, true, false) as SaFramePacer
    var headless := DisplayServer.get_name() == "headless"
    var report := {
        "present": pacer != null,
        "display_server": DisplayServer.get_name(),
        "vsync_mode": vsync_name(-1 if headless else DisplayServer.window_get_vsync_mode()),
        "project_vsync_mode": vsync_name(project_vsync_mode()),
        "vsync_settled": pacer != null and pacer.vsync_settled,
        "unbuffered_pen": pacer != null and pacer.unbuffered_pen,
        "swapchain_image_count": swapchain_image_count(),
        "max_fps": Engine.max_fps,
        "low_processor_usage_mode": OS.low_processor_usage_mode,
        "resting_max_fps": pacer.resting_max_fps if pacer != null else 0,
        "resting_low_processor": pacer.resting_low_processor if pacer != null else false,
        "moving": pacer != null and pacer.is_moving(),
        "painting_frame_rate": SaSettings.painting_frame_rate,
        "painting_max_fps": painting_max_fps(),
        "frames_drawn": Engine.get_frames_drawn(),
        "idle_frames_before_resting": IDLE_FRAMES,
        "frame_msec": 1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
    }
    return "SaCapture: pacer %s" % JSON.stringify(report)


## The `DisplayServer` vsync enum as the word a person reads, because a dump
## holding `3` says nothing and the whole point of the block is which of the four
## the driver settled on.
static func vsync_name(mode: int) -> String:
    match mode:
        DisplayServer.VSYNC_DISABLED:
            return "disabled"
        DisplayServer.VSYNC_ENABLED:
            return "enabled"
        DisplayServer.VSYNC_ADAPTIVE:
            return "adaptive"
        DisplayServer.VSYNC_MAILBOX:
            return "mailbox"
        _:
            return "none, headless"
