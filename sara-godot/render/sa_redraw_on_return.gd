## Draws the window again when it comes back, so a change made while it was
## hidden is on screen the moment it is shown.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Why this exists --------------- Sara runs in `low_processor_mode`, so a frame
## is drawn only when something marks the window changed. Without this a change
## sent from the notebook while Sara's window stands behind the browser shows
## only once the pointer moves over the canvas, and never when Alt+Tab brings
## the window back.
##
## What eats the frame is the engine. GNOME marks a covered window suspended,
## and while it is Godot presents nothing. The canvas's redraw is still asked
## for, but Godot 4.7 renders a frame without presenting it while the device
## has uploads pending, which a write of pixels leaves behind, and that frame
## takes the request as met. When the window is shown again nothing is left
## marked, so nothing is drawn. A redraw asked for once the window is back is
## drawn at once, which is what this does.
##
## Three things ask for it:
## - **The focus coming in**, which is what Alt+Tab or a click on the taskbar
##   gives the window.
## - **A change the window could not show.** When the document composites while
##   the window may not draw, the redraw is asked for again on every frame until
##   the window draws one. The engine says whether it may through
##   `DisplayServer.window_can_draw`, which is false while the window is
##   suspended and also once a second has passed with no frame drawn, so it is
##   read only when the document has changed: read alone, a window resting for
##   a second would draw a frame a second for nothing. Asking while the window
##   is hidden costs nothing, since a frame that cannot be presented and has no
##   upload behind it is not rendered.
## - **A door step that changed the document**, through `SaCanvas.after_door_step`,
##   so a Sara beside the notebook shows what the step did with no motion over
##   it and no command in Python to ask.
##
## Godot draws the whole window on every frame it draws, so one redraw of the
## canvas puts the dockers that show the document, Layers' thumbnails and the
## Navigator, on screen with it.
class_name SaRedrawOnReturn
extends Node

const NODE_NAME: String = "SaRedrawOnReturn"

## Asks for the window to be drawn again, the canvas's `queue_redraw`.
var _redraw: Callable
## Whether the window may draw now, `DisplayServer.window_can_draw` for the
## canvas's window. A suite hands in its own.
var _can_draw: Callable
## How many composites the document has had, `SaEasel.composite_count`.
var _composites: Callable
## The composites the last frame saw.
var _composites_seen: int = 0
## The composites the last answered door step saw, so the next tells whether
## the document changed in between.
var _composites_answered: int = 0
## The document changed while the window could not show it, so the redraw is
## asked for on every frame until it can.
var _owed: bool = false


func _init(redraw: Callable, can_draw: Callable, composites: Callable) -> void:
    _redraw = redraw
    _can_draw = can_draw
    _composites = composites
    name = NODE_NAME


func _ready() -> void:
    _composites_seen = _composites.call()
    _composites_answered = _composites_seen


## Called at the end of every step the door answers. The document has changed
## since the step before when it has composited since, and only then is the
## window drawn again, so a step that only read it draws nothing.
func step_answered() -> void:
    var count: int = _composites.call()
    var changed := count != _composites_answered
    _composites_answered = count
    if changed:
        _redraw.call()


func _process(_delta: float) -> void:
    var count: int = _composites.call()
    if count != _composites_seen:
        _composites_seen = count
        _owed = true
    if not _owed:
        return
    if _can_draw.call():
        _owed = false
    else:
        _redraw.call()


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
        _redraw.call()
