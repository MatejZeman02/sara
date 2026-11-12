## The rule that decides when a brush editor preview draws again: the first ask
## at once, and every ask inside a short window after a draw as one draw when the
## window closes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Its own class so the stroke strip and the tip preview answer to one rule
## rather than to a copy each, and neither draws on every tick of a drag.
##
## **The rule follows from what a drag is**: a slider or a curve point dragged by
## hand emits an event per pixel, and a draw per event would be a draw per pixel
## of the drag. The first ask goes straight through, so a page switch or a
## checkbox draws at once and the painter never waits for a timer to say what
## they already did. An ask inside the window coalesces into one draw when it
## closes. An ask arriving while a draw is running is remembered rather than
## started, because two draws of the same settings racing to the same texture is
## one wasted draw and an order nobody chose.
##
## **The preview owns the drawing and this owns the when.** The draw is handed
## over as a `Callable` at construction, so nothing here knows a brush, an easel
## or a texture, and the preview adds this as a child so the wake-up is a real
## `Timer` in a running tree.
##
## **A hidden preview never draws.** An ask while the preview is in a running
## tree and not visible in it waits, and the draw happens when the preview is
## shown again, because a closed brush editor's strip would draw the ask that
## was waiting when it closed at whatever radius the canvas has moved to since,
## which at a tiny radius is thousands of smudge dabs in one frame, landing now
## and then inside the next stroke. A compressor outside the tree, or with no
## parent to ask, draws at once,
## because that is a suite asking and a suite has no screen to be hidden from.
class_name SaPreviewCompressor
extends Timer

## The shortest time after a draw that an ask waits to be folded into the next.
const WINDOW_SECONDS: float = 0.1

## How many times the last draw's own cost the window lasts, when that is longer
## than [constant WINDOW_SECONDS].
##
## **A fixed window is beaten by a draw that outlasts it.** The editor asks the
## strip and the tip preview together, one after the other, and each draw is a
## fresh easel painted and read back, about 110 ms against a window of 100. So
## the strip's window had closed by the time the tip preview finished, the tip
## preview's had closed by the time the strip finished, and fifty ticks of the
## Hardness slider drew fifty strips and fifty dabs with nothing coalesced. A
## window twice the draw outlasts a sibling of the same cost, and leaves the hand
## at least two thirds of the time however slow a draw gets.
const WINDOW_PER_DRAW: float = 2.0

## Asks folded into a later draw rather than drawn, for a dump. The compressor's
## whole claim is a number, and a picture cannot say how many times it was drawn.
var coalesced: int = 0

## A draw shorter than this many milliseconds opens no window and every ask
## draws at once, whatever [constant WINDOW_SECONDS] says. A reader whose draw
## is cheaper than a frame cannot have a drag outrun it, so holding an ask back
## would stall the picture for nothing, and a discrete change after the first
## would be silently folded into a draw that already happened. The filter
## dialog's preview is one such reader: Gaussian Blur runs in a few
## milliseconds where Local Contrast runs in tens. Negative, the default, is the
## brush editor's rule, where every draw is about a tenth of a second and every
## ask coalesces.
var coalesce_above_msec: int = -1

## The window this reader opens, as [constant WINDOW_SECONDS] and
## [constant WINDOW_PER_DRAW] by default. The filter dialog shortens both to
## zero and one: only one reader asks it and no sibling of the draw's cost can
## close its window, so a window the draw's own length is the fastest cadence
## that still never queues a run behind the last, and a drag that has stopped is
## redrawn within one draw rather than two.
var window_seconds: float = WINDOW_SECONDS
var window_per_draw: float = WINDOW_PER_DRAW

## Whether an ask is waiting for the window to close or the preview to show, for
## a test that wants to say the compressor swallowed one rather than dropped it.
var pending: bool = false

var _redraw: Callable
var _running: bool = false
## What the last draw took, in engine milliseconds, which sizes the window it opens.
var _last_draw_msec: int = 0

## When the window the last draw opened closes, in engine milliseconds.
##
## A deadline rather than `Timer.time_left`: a Timer outside the scene tree never
## counts down, so a strip a test built detached coalesced nothing and rendered
## twenty-one times. The Timer stays as the wake-up for a coalesced ask, which
## only a running tree can give, and the decision is arithmetic that works either
## way.
var _window_until_msec: int = 0


func _init(redraw: Callable) -> void:
    name = "Compressor"
    one_shot = true
    wait_time = WINDOW_SECONDS
    _redraw = redraw
    timeout.connect(_on_timeout)


## Asks for a draw. Cheap to call from every signal that can change what the
## preview shows.
func request() -> void:
    if _running or _hidden() or Time.get_ticks_msec() < _window_until_msec:
        pending = true
        coalesced += 1
        return
    draw_now()
    _open_window()


## Forgets the window and any ask waiting on it, so the next ask draws at once.
##
## A reader that opens on a new subject wants the first look at it now, not held
## back by the window the last subject's draw opened: a filter dialog opened on
## another filter draws its first preview on the spot.
func reset() -> void:
    stop()
    pending = false
    _window_until_msec = 0


## Draws now, whatever the window says. What a page build, a test and a scenario
## ask for.
##
## `_running` is up across the call rather than around an await: the draw is
## synchronous, and the flag is what makes an ask arriving from inside it, which
## a signal emitted by the paint path could send, coalesce instead of re-entering.
func draw_now() -> void:
    _running = true
    var started := Time.get_ticks_msec()
    _redraw.call()
    _last_draw_msec = Time.get_ticks_msec() - started
    _running = false


## How long the window the last draw opens stays open, in milliseconds.
func window_msec() -> int:
    return maxi(int(window_seconds * 1000.0), int(float(_last_draw_msec) * window_per_draw))


## The window closed, or the preview came back on screen or left it, because
## the visibility signal reaches this too: both ask the same question, whether
## an ask is waiting and the preview can be seen. An ask that waited while the
## preview was hidden is drawn when it is shown, so an editor opened again
## shows the settings as they are rather than as they were when it closed.
func _on_timeout() -> void:
    if not pending or _hidden():
        return
    pending = false
    draw_now()
    _open_window()


## Whether the preview this draws for is in a running tree and not visible in
## it, which is a closed brush editor above all. The parent is asked because it
## is the preview, and a `Timer` has no visibility of its own.
func _hidden() -> bool:
    var shown := get_parent() as CanvasItem
    return shown != null and shown.is_inside_tree() and not shown.is_visible_in_tree()


## Listens to the preview it was added to. Never undone by hand: the preview
## holds this for its whole life, and a freed compressor's connections go with
## it. A compressor parented a second time to the same preview is not connected
## twice, which Godot refuses with an error.
func _notification(what: int) -> void:
    if what != NOTIFICATION_PARENTED:
        return
    var shown := get_parent() as CanvasItem
    if shown != null and not shown.visibility_changed.is_connected(_on_timeout):
        shown.visibility_changed.connect(_on_timeout)


func _open_window() -> void:
    if coalesce_above_msec >= 0 and _last_draw_msec <= coalesce_above_msec:
        return
    var lasts := window_msec()
    _window_until_msec = Time.get_ticks_msec() + lasts
    if is_inside_tree():
        start(float(lasts) / 1000.0)
