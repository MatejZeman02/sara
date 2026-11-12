## Whether the pointer the stamp brush draws with is a pen or a mouse, as far
## as its motions have shown, and the motions a stroke holds back while they
## have shown neither.
##
## **Nothing names the device.** Under Wayland every pointer is device 0, and a
## pen pressed from no pressure reports what a mouse does, no pressure and no
## tilt, until its pressure rises. So a motion with a pressure, a tilt or the
## flipped end is a pen's, a run of plain ones past [constant MOUSE_STREAK] is a
## mouse's, and the brush's `is_tablet` follows what [method read] answers.
##
## **A pointer that has shown neither waits.** Taking the first pressed plain
## motion of such a pointer for a mouse's lays a stroke pressed from no pressure
## with its press and that motion at a mouse's full pressure, and Fill with its
## size on the pressure opens with a pale lobe at full width, 52 px longer than
## the same stroke laid once a pen has been seen. So such a motion is held,
## where it came and when, until a pen's reading lays it at the none it
## reported, or the streak running out or the lift lays it as a mouse's. A real
## pen gives its reading at its first pressed motions and a mouse has hovered
## past the streak before it presses, so neither waits in practice.
##
## The class owns that evidence and the motions it settles, and nothing of the
## stroke, which is what `state_brush.gd` keeps.
class_name SaPenOrMouse
extends RefCounted

## What [method read] made of a motion.
enum Shown { NEITHER, PEN, MOUSE }

## Plain motions in a row past which the pointer is a mouse.
const MOUSE_STREAK: int = 10

## Whether the last word on the pointer came from a motion that reported a
## pen, not the guess a fresh brush starts on.
var pen_seen: bool = false
## A pen has touched with this brush, which outlasts a tiltless pen's hovers.
var pen_touched: bool = false

## Plain motions in a row, which say a mouse once there are enough of them.
var _streak: int = 0
## The pressed plain motions held back, where each came and when it was
## reported, in the order they came.
var _held_at: PackedVector2Array = PackedVector2Array()
var _held_ms: PackedFloat64Array = PackedFloat64Array()


## What *motion* shows of the pointer: a pen when it reports a pressure, a tilt
## or the flipped end, a mouse when it is the plain one past the streak, and
## neither otherwise.
func read(motion: InputEventMouseMotion) -> Shown:
    if motion.pressure > 0.0 or motion.tilt != Vector2.ZERO or motion.pen_inverted:
        pen_seen = true
        _streak = 0
        return Shown.PEN
    _streak += 1
    if _streak > MOUSE_STREAK:
        pen_seen = false
        return Shown.MOUSE
    return Shown.NEITHER


## Whether *pressure*, laid while the brush reads a pen when *is_tablet*, is a
## pen's touch, between none and full, which it notes. A mouse's 1 under
## Windows Ink is made up and no pen's touch.
func touched(pressure: float, is_tablet: bool) -> bool:
    var touch := is_tablet and pressure > 0.0 and pressure < 1.0
    pen_touched = pen_touched or touch
    return touch


## Holds back a pressed plain motion at *at*, reported at *reported_ms*, of a
## pointer that has shown neither a pen nor a mouse.
func hold(at: Vector2, reported_ms: float) -> void:
    _held_at.append(at)
    _held_ms.append(reported_ms)


## Hands each motion held back to *lay*, as `lay(at, reported_ms, pressure,
## tilt)` at *pressure* and upright, in the order they came, and lets them go.
## A motion was held only when it reported neither a pressure nor a tilt, so a
## pen lays it at none and a mouse at full.
func lay_held(lay: Callable, pressure: float) -> void:
    var at := _held_at
    var reported := _held_ms
    clear()
    for i in at.size():
        lay.call(at[i], reported[i], pressure, Vector2.ZERO)


## Lets the held motions go unlaid, as a stroke that is reset does.
func clear() -> void:
    _held_at = PackedVector2Array()
    _held_ms = PackedFloat64Array()
