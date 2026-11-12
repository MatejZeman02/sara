## The liquify engine of the Brush: a brush that pushes paint along with it,
## takes back what it pushed, straightens the strokes under it, turns it, or
## shrinks it towards its centre or grows it out.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Private to the liquify folder, registered by `sa_liquify.gd` as an engine of
## the Brush, so a painter reaches it by picking a liquify preset with the Brush
## in hand, and its four rows are `settings`, which a preset loads and saves.
##
## **A session, like the transform's.** A press on the active layer opens one
## when none is open, every drag after it adds to the same field, Enter or a
## switch to another tool or engine writes the whole session as one history
## step, and Escape puts everything back. A stamp preset picked while a session
## is open is such a switch. A press on another layer than the session's
## commits the old session first, because a field belongs to one layer.
##
## This file is the gesture: where the pointer is, and the motion since the
## last dab. The field, the originals and the history are
## `sa_liquify_session.gd`'s. Motions are gathered and dabbed once a frame, in
## `tick`, the way the transform draws once a frame whatever the pointer sent.
##
## **Push follows the hand, the other five follow the clock.** A push is the
## motion since the last dab. Reconstruct, smooth, twirl, shrink and grow
## change the field while the button is held, whether the brush moves or not,
## so each frame dabs once at the pointer by an amount the frame's length
## scales: a held brush twirls at the same speed on a slow machine as on a
## fast one. The twirl turns the
## way the Direction row says, clockwise to begin with, and Alt turns it the
## other way from that, and turns a shrink into a grow and a grow into a
## shrink.
extends ToolState

## The engine beside this file, reached by path the way the transform tool
## reaches its pass, so the tool builds it without waiting on the class cache.
const SaLiquifySessionScript = preload("res://modules/sara-base-modules/base/liquify/sa_liquify_session.gd")
const LiquifySettingsScript = preload("res://modules/sara-base-modules/base/liquify/liquify_settings.gd")
const LiquifyPictureScript = preload("res://modules/sara-base-modules/base/liquify/liquify_picture.gd")

## The range of the Size row, which the bracket keys keep to as well.
const SIZE_MIN: float = 4.0
const SIZE_MAX: float = 800.0
## The Mode row's values, the session's modes. Reconstruct keeps
## the 1 the mode had when it was called smooth, so a saved choice still means
## what it did, and the smooth that straightens strokes takes the next number
## free.
const PUSH: int = 0
const RECONSTRUCT: int = 1
const TWIRL: int = 2
const SHRINK: int = 3
const GROW: int = 4
const SMOOTH: int = 5
## The Direction row's values, the way a twirl turns on screen
## without Alt.
const CLOCKWISE: int = 0
const ANTICLOCKWISE: int = 1
## How far a held twirl at full strength turns the paint under its core, in
## radians a second: half a turn.
const TWIRL_RATE: float = PI
## How much of the way a held reconstruct at full strength goes in a second,
## as a rate: after a second a push keeps about a fiftieth of its offset.
const RECONSTRUCT_RATE: float = 4.0
## How long a held smooth at full strength runs the strokes' curvature flow in
## a second, in the sigma of its softening squared, `SMOOTH_SOFTEN` of the
## brush, so a brush twice as wide straightens a wobble twice as long in the
## same second. Measured on a model of the kernels under a 96 pixel brush, a
## second takes a wobble 40 to 60 pixels long to under a quarter of its swing,
## one 80 long to two fifths and one 30 long to three quarters, and leaves one
## 20 long, finer than the softening sees.
const SMOOTH_FLOW: float = 8.0
## How fast a held shrink or grow at full strength scales the paint under its
## core, as the logarithm of the factor a second: a second halves or doubles it.
const SCALE_RATE: float = log(2.0)
## How long each motion of a preset's picture holds the button, in seconds. A
## picture sends events and no frames, so each motion is a frame of its own,
## and a tenth of a second makes the forty of its S four seconds of a slow
## hand, which in a cell of 128 by 64 shows a held mode's work rather than a
## trace of it.
const PICTURE_FRAME: float = 0.1

## The mode, the direction, the size and the strength, the four rows, which a
## preset of the engine loads and saves. The descriptor hands every surface's
## tool the one shared resource, so a preset picked on the canvas is the
## liquify the scratchpad holds as well, and this one is for a tool built
## without a descriptor, a preset's picture above all.
var settings: Resource = LiquifySettingsScript.new()

var _session: SaLiquifySessionScript = null
var _pressed: bool = false
## Where the last dab left the brush, and where the pointer is now, in
## document pixels.
var _last: Vector2 = Vector2.ZERO
var _pending: Vector2 = Vector2.ZERO
## Whether Alt was down at the last event, which turns a twirl the other way
## from the Direction row and swaps shrink and grow.
var _alt: bool = false
## Whether this tool draws a preset's picture, where each motion is a frame.
var _picture: bool = false


## Enter commits, Escape cancels, and a press and drag pushes.
func handle_input(event: InputEvent) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return
    var modifiers := event as InputEventWithModifiers
    if modifiers != null:
        _alt = modifiers.alt_pressed
    var key := event as InputEventKey
    if key != null and key.keycode == KEY_ALT:
        _alt = key.pressed
    if key != null and key.pressed:
        if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
            commit_session()
        elif key.keycode == KEY_ESCAPE:
            cancel_session()
        return

    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            press(get_document_mouse_position())
        else:
            release()
        return

    if _pressed and event is InputEventMouseMotion:
        _pending = get_document_mouse_position()
        if _picture:
            tick(PICTURE_FRAME)


## Readies the tool to draw a preset's picture, called by the presets chooser
## on the throwaway tool it paints one with, once the preset's settings are on
## it. Lays the grid the stroke shows its work on, and for Reconstruct twirls
## it first, so the stroke has something to put back.
func begin_picture() -> void:
    var doc: SaDocument = document()
    if not LiquifyPictureScript.lay(doc):
        return
    _picture = true
    if settings.mode != RECONSTRUCT:
        return
    _session = SaLiquifySessionScript.new(doc)
    if _session.begin(doc.active_layer):
        LiquifyPictureScript.unsettle(_session, doc.canvas_size)


## The frame's one dab: a push when the pointer moved since the last, and a
## reconstruct, a smooth, a twirl, a shrink or a grow while the button is held,
## for as long as [method SaPenClock.frame_elapsed_ms] says the frame was, the
## engine's delta live and the recording's own frame in a lesson's replay.
func tick(delta: float) -> void:
    if _pressed:
        _flush()
        hold(SaPenClock.frame_elapsed_ms(delta) / 1000.0)


## Reconstructs, smooths, twirls, shrinks or grows at the pointer for
## *seconds* of a held button. Public so a suite and a scenario run the same
## frame a held button does.
func hold(seconds: float) -> void:
    if not _pressed or _session == null or seconds <= 0.0:
        return
    if settings.mode == RECONSTRUCT:
        _session.reconstruct(_pending, settings.size, 1.0 - exp(-RECONSTRUCT_RATE * settings.strength * seconds))
    elif settings.mode == SMOOTH:
        _session.smooth(_pending, settings.size, settings.strength, SMOOTH_FLOW * seconds)
    elif settings.mode == TWIRL:
        var turn := TWIRL_RATE * seconds * (-1.0 if (settings.direction == ANTICLOCKWISE) != _alt else 1.0)
        _session.twirl(_pending, settings.size, settings.strength, turn)
    elif settings.mode == SHRINK or settings.mode == GROW:
        var amount := SCALE_RATE * seconds
        if (settings.mode == GROW) != _alt:
            _session.grow(_pending, settings.size, settings.strength, amount)
        else:
            _session.shrink(_pending, settings.size, settings.strength, amount)


## Opens a session on the active layer if none is open, and starts a drag at
## *at*. Public so a suite and a scenario drive the same path a click does.
func press(at: Vector2) -> void:
    var doc: SaDocument = document()
    var on := doc.active_layer if doc != null else null
    if on == null:
        return
    if _session == null or _session.document != doc:
        var script: Script = roles.script_for(&"liquify") if roles != null else SaLiquifySessionScript
        _session = script.new(doc)
    if _session.is_open() and _session.layer != on:
        _session.commit()
    if not _session.begin(on):
        return
    _pressed = true
    _last = at
    _pending = at


## Moves the drag to *at*, dabbing at once.
func drag_to(at: Vector2) -> void:
    if not _pressed:
        return
    _pending = at
    _flush()


## Ends the drag, dabbing what the last frame had not.
func release() -> void:
    if _pressed:
        _flush()
    _pressed = false


## Writes the session as one history step. True when there was one.
func commit_session() -> bool:
    release()
    return _session != null and _session.commit()


## Puts the session's chunks back as they were.
func cancel_session() -> void:
    release()
    if _session != null:
        _session.cancel()


## An undo or a redo commits first, so the session is the step it takes back.
## A session on a document rebuilt under it is left to [method reset].
func close_session() -> bool:
    var doc: SaDocument = document()
    return _session != null and _session.document == doc and commit_session()


## A session on this document that has moved paint. One opened by a press that
## dabbed nothing holds no originals, and its commit writes no step.
func holds_session() -> bool:
    var doc: SaDocument = document()
    return _session != null and _session.document == doc and _session.is_open() and not _session._before.is_empty()


## Leaving the tool commits, because a painter who pushed paint and reached for
## a brush meant the push. A
## session on a document rebuilt under it is let go untouched.
func reset() -> void:
    var doc: SaDocument = document()
    _pressed = false
    if _session == null:
        return
    if _session.document == doc:
        _session.commit()
    else:
        _session.close()
    _session = null


## The brush's ring.
func get_cursor_radius() -> float:
    return settings.size * 0.5


## The width the bracket keys and a shift-drag resize.
func own_size() -> float:
    return settings.size


func resize_own(size: float) -> void:
    settings.size = clampf(size, SIZE_MIN, SIZE_MAX)


func _flush() -> void:
    if _session == null or _pending == _last:
        return
    if settings.mode != PUSH:
        _last = _pending
        return
    _session.push(_last, _pending, settings.size, settings.strength)
    _last = _pending


## Whether a session is open and how many field chunks it holds, which a shot
## of pushed paint cannot say: pushed paint and paint painted there look alike.
func capture_report(tool_name: StringName, active: bool) -> Dictionary:
    if not active:
        return {}
    var open := _session != null and _session.is_open()
    return {
        "liquify":
        {
            "tool": String(tool_name),
            "open": open,
            "field_chunks": _session.fields.size() if open else 0,
            "size": settings.size,
            "strength": settings.strength,
            "mode": ["push", "reconstruct", "twirl", "shrink", "grow", "smooth"][clampi(settings.mode, PUSH, SMOOTH)],
            "direction": ["clockwise", "anticlockwise"][clampi(settings.direction, CLOCKWISE, ANTICLOCKWISE)],
        }
    }
