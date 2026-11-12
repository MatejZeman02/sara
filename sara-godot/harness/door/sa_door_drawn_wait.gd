## Holds a door step's answer back until the frame that shows it is drawn.
##
## Settle frames are process frames, so an answer sent after them, with the
## redraw asked for only once it had left, would let a client hear "done"
## before anything reached the screen, and a draw that never came would read as
## minutes of silence. Here the redraw is asked for first, the answer waits for
## `Engine.get_frames_drawn()` to move, and the number it moved to goes into the
## answer under `drawn`. A draw that does not come within `BOUND_MSEC` is an
## error that names the step.
##
## Whether the step changed the canvas is the same question `SaRedrawOnReturn`
## asks: has the easel composited since the request was taken. A step that only
## read the document owes no frame, and a request that settles for 0 frames is
## answered in the frame its step ran, before any composite, so it owes none
## either. A step that brought another painting forward owes one as well, which
## no composite says: the window shows another canvas, standing wherever its
## own compositing left it, so the front itself is read beside the count.
class_name SaDoorDrawnWait
extends RefCounted

## Milliseconds a draw may take after its redraw was asked for. Five seconds,
## because a window that is drawing at all draws within a few frames and the
## slowest frame Sara paints in a session is far under one, so five is not a
## slow frame but a draw that is not coming, and it is well under the client's
## 120 seconds.
const BOUND_MSEC: int = 5000

## The harness's one lookup for the document the painter is working on.
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")

enum Verdict {
    ## The step changed nothing, so it is answered as it always was.
    NOT_OWED,
    ## The redraw is asked for and no frame has been drawn since.
    WAITING,
    ## A frame was drawn after the redraw was asked for.
    DRAWN,
    ## No frame was drawn within the bound.
    OVERDUE,
}

## The composites the document in front has had, a `Callable` of nothing. A
## suite hands in its own.
var composites: Callable = _composites_in
## Which document is in front, a `Callable` of nothing answering a number that
## changes when another one comes forward. A suite hands in its own.
var front: Callable = _front_in
## Asks for the window to be drawn again, a `Callable` of the root.
var ask: Callable = _redraw_front
## The frames drawn so far, `Engine.get_frames_drawn`.
var frames: Callable = Engine.get_frames_drawn
## The clock in milliseconds, `Time.get_ticks_msec`.
var clock: Callable = Time.get_ticks_msec
## The bound this wait holds a draw to.
var bound_msec: int = BOUND_MSEC

var _root: Window = null
var _composites_at_request: int = 0
var _front_at_request: int = 0
var _waiting: bool = false
var _frames_at_ask: int = 0
var _deadline: int = 0
var _drawn_frame: int = 0
var _overdue: bool = false


## Notes where the document stands as a request is taken.
func begin(root: Window) -> void:
    _root = root
    _composites_at_request = composites.call()
    _front_at_request = front.call()
    _waiting = false
    _drawn_frame = 0
    _overdue = false


## Asked once the step's settle frames are over and in every frame after, until
## it is anything but WAITING. The first call asks for the redraw when the
## document changed.
func after_settle() -> Verdict:
    if not _waiting:
        if int(composites.call()) == _composites_at_request and int(front.call()) == _front_at_request:
            return Verdict.NOT_OWED
        _waiting = true
        _frames_at_ask = frames.call()
        _deadline = int(clock.call()) + bound_msec
        ask.call(_root)
    var drawn: int = frames.call()
    if drawn > _frames_at_ask:
        _drawn_frame = drawn
        _waiting = false
        return Verdict.DRAWN
    if int(clock.call()) >= _deadline:
        _waiting = false
        return Verdict.OVERDUE
    return Verdict.WAITING


## Whether the step can be answered now, which is when its frame is drawn, when
## it owes none, and when the bound has passed, the last of which `stamp` turns
## into the error. False while the wait goes on.
func arrived() -> bool:
    var verdict := after_settle()
    _overdue = verdict == Verdict.OVERDUE
    return verdict != Verdict.WAITING


## Puts what the wait found into *answer*, the answer to *step*: the frame the
## draw came in, under `drawn`, or for a step that owed no frame nothing, or for
## a draw that did not come the error that names the step and the bound, which
## turns `ok` false and leaves the rest of the answer as it was.
func stamp(answer: Dictionary, step: Dictionary) -> void:
    if _drawn_frame > 0:
        answer["drawn"] = _drawn_frame
    if _overdue:
        answer["ok"] = false
        answer["step"] = step
        answer["bound_ms"] = bound_msec
        var said := "no frame was drawn within %d ms after the step %s changed the canvas, " % [bound_msec, JSON.stringify(step)]
        answer["error"] = said + "so the window is not drawing (covered, suspended or stalled)"


## The composites the front surface's easel has run, which is what says the
## step changed what the window shows. The window itself is the wait's own
## *root*, asked to be drawn again, and a second open document composites on
## an easel of its own that this step did not touch.
static func _composites_in() -> int:
    var shown := CanvasDriver.main_canvas()
    return shown.easel.composite_count if shown != null and shown.easel != null else 0


## Which document is in front, as its canvas's instance id, 0 while there is
## none. A number only: nothing here reads the canvas, and two of these are
## only ever compared.
static func _front_in() -> int:
    var shown := CanvasDriver.main_canvas()
    return int(shown.get_instance_id()) if shown != null else 0


## Draws the window the front document stands in again, whatever that document
## last composited, when it is *root*.
##
## `SaCanvas.after_door_step`, which the door calls at the end of every reply,
## redraws only a canvas that has composited since the step before, and a step
## that brought another painting forward composited nothing of its own, so it
## declines the very redraw this wait is waiting for. Sara draws only what it
## is asked to draw, so the frame would never come.
static func _redraw_front(root: Window) -> void:
    var shown := CanvasDriver.main_canvas()
    if shown != null and shown.get_window() == root:
        shown.queue_redraw()
