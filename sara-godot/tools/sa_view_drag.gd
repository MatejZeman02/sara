## The drag that moves the view while a button holds it: a button bound to Pan
## pans, with Shift down at its press it turns the view, and with Ctrl down it
## zooms, as Blender and Krita have Ctrl and the middle button. A Shift left
## press under the pan tool turns the view too, and the left release ends that
## turn alone.
##
## **The turn** pivots on the press. The lever is the pointer's direction from
## the pivot, taken once it has moved [constant LEVER_PIXELS] from it, and the
## view turns by the angle the lever has swung since, snapping onto a right
## angle when it comes close.
##
## **The zoom** keeps the document point under the press where it is, and is
## an exponential of the travel, right and up adding and left and down taking
## away, so equal travel is an equal factor at every zoom:
## [constant PIXELS_PER_DOUBLING] pixels double it, and a drag of a thousand
## pixels across the canvas makes it four times. It is measured from the zoom
## the press found, so a drag past a limit holds there until the pointer comes
## back to where it reached it, as the zoom tool's drag does.
##
## The modifier is read at the press and kept for the drag, so Shift or Ctrl let
## go midway goes on turning or zooming. Shift wins over Ctrl at a press holding
## both, which is the turn the page always named.
##
## Private to the tools package, beside the machine as `SaShiftPress` is. The
## machine hands it each press, release and motion with the view, and it holds
## no reference to either.
class_name SaViewDrag
extends RefCounted

## What the drag under way does.
enum Kind { NONE, PAN, TURN, ZOOM }

## How far the pointer must leave the pivot before its direction means anything.
const LEVER_PIXELS: float = 12.0

## Screen pixels of travel that double the zoom, so a long drag across the
## canvas, a thousand of them, is a factor of four.
const PIXELS_PER_DOUBLING: float = 500.0

## What the drag under way does, read by the machine.
var kind: Kind = Kind.NONE

## The turn began on a left press, so the left release is the one that ends it.
var with_left: bool = false

## Where the press landed, the turn's pivot and the zoom's anchor.
var _pivot: Vector2 = Vector2.ZERO
var _start_rotation: float = 0.0
var _lever: float = 0.0
## Whether the lever has been taken since the press. A flag of its own rather
## than a NaN in the lever, which the language server warns about at every start.
var _lever_taken: bool = false
var _start_zoom: float = 1.0


## A press or release of a button bound to Pan, on *view*.
func button(press: InputEventMouseButton, view: SaView) -> void:
    with_left = false
    kind = Kind.NONE
    if not press.pressed:
        return
    if press.shift_pressed:
        _turn_from(press.position, view)
    elif press.ctrl_pressed:
        kind = Kind.ZOOM
        _pivot = press.position
        _start_zoom = view.get_zoom()
    else:
        kind = Kind.PAN


## A left press that turns the view, which the machine starts under a tool
## that turns it on a Shift drag.
func turn_with_left(at: Vector2, view: SaView) -> void:
    _turn_from(at, view)
    with_left = true


## The left release. True when it ended a turn the left press began.
func left_released() -> bool:
    var was_turning := with_left
    with_left = false
    if was_turning:
        kind = Kind.NONE
    return was_turning


## A swap of the tool in hand ends any drag but a zoom, because the Ctrl that
## began a zoom can be a held tool's key, the eyedropper's under Krita's keys,
## and letting it go swaps the tool back while the button still zooms.
func drop() -> void:
    with_left = false
    if kind != Kind.ZOOM:
        kind = Kind.NONE


## Follows *motion* on *view*. True when the drag took it.
func follow(motion: InputEventMouseMotion, view: SaView) -> bool:
    match kind:
        Kind.PAN:
            view.set_pan(view.get_pan() + motion.relative)
        Kind.TURN:
            _turn_towards(motion.position, view)
        Kind.ZOOM:
            var travel := (motion.position.x - _pivot.x) + (_pivot.y - motion.position.y)
            view.zoom_at(_start_zoom * pow(2.0, travel / PIXELS_PER_DOUBLING), _pivot)
        _:
            return false
    return true


func _turn_from(at: Vector2, view: SaView) -> void:
    kind = Kind.TURN
    _pivot = at
    _start_rotation = view.get_rotation()
    _lever_taken = false


func _turn_towards(pointer: Vector2, view: SaView) -> void:
    var arm := pointer - _pivot
    if arm.length() < LEVER_PIXELS:
        return
    if not _lever_taken:
        _lever = arm.angle()
        _lever_taken = true
        return
    view.rotate_at(SaView.snap_rotation(_start_rotation + arm.angle() - _lever), _pivot)
