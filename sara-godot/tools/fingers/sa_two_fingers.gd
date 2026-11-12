## Two touches on the canvas, tracked by index, moving the view as one gesture.
##
## The midpoint carries the picture, the ratio of the distances zooms about it
## and the change of the angle between them turns it. Each is taken from where
## the gesture began rather than from the last drag, so a long pinch does not
## gather the rounding of a hundred small steps and the turn can snap onto a
## right angle the way a Shift middle drag does. The document point under the
## first midpoint is kept under the current one, which is what makes the pan,
## the zoom and the turn a single motion. The gesture ends when either finger
## lifts. One finger alone is `SaOneFinger`'s, which this hands every touch and
## drag, and which taps, picks and pans.
##
## **Two fingers that tap undo**, as Krita's do. Two fingers that land, stay
## within [constant SLOP] pixels of where each landed and are both up within
## [constant TAP_MSEC] of the second landing undo once, the way the Edit menu's
## Undo does: an open liquify or transform session becomes a step first, then
## the document steps back. The few pixels a tap's fingers wander have nudged the
## view by then, so the view goes back to where the tap found it. A third finger,
## or either finger moving past the slop, makes it a pinch, which never undoes.
##
## **Three fingers that tap redo**, as Procreate's do. Three fingers that
## land, stay within [constant SLOP] pixels of where each landed and are all
## up within [constant TAP_MSEC] of the third landing redo once,
## the way the Edit menu's Redo does, and the view goes back to where the
## first two found it. A fourth finger or a finger moving past the slop spoils
## it. Under every program rather than only under Procreate's, because three
## fingers on the canvas did nothing before, so no painter's habit is taken.
##
## **A touch the system takes back taps nothing.** A release with
## [member InputEventScreenTouch.canceled] set, which Android sends for every
## finger down when it drops a palm or a rest as the pen lands, spoils the
## two-finger and the three-finger tap alike, so a resting hand never undoes.
##
## The facade of `tools/fingers`, which only the machine names. The machine
## hands it every touch and drag on the canvas, the view they move, and itself
## on a touch, for its tools and registry the one finger's pick drives and for
## the undo. It keeps no reference to the machine past the call.
class_name SaTwoFingers
extends RefCounted

## How far either finger of a two-finger tap may move, in pixels, before it is
## a pinch. `SaOneFinger.SLOP`, the same small distance a single tap allows.
const SLOP := SaOneFinger.SLOP
## How long a two-finger tap may last from the second finger landing to the
## last one lifting, in milliseconds. Longer is a hold, which undoes nothing.
const TAP_MSEC := 500

## Index to position, for every touch down on the canvas now.
var _down: Dictionary = {}
## The two indices of the gesture in progress, empty when there is none.
var _pair: PackedInt32Array = PackedInt32Array()
var _start_distance: float = 0.0
var _start_angle: float = 0.0
var _start_zoom: float = 1.0
var _start_rotation: float = 0.0
var _anchor: Vector2 = Vector2.ZERO
## Whether the pair so far could still be a tap, where each finger landed, the
## time the second did, and the pan the view had then, which a tap puts back.
var _tap: bool = false
var _tap_landed: Dictionary = {}
var _tap_msec: int = 0
var _start_pan: Vector2 = Vector2.ZERO
## Whether the three fingers so far could still be a three-finger tap, where
## each landed and the time the third did.
var _tap3: bool = false
var _tap3_landed: Dictionary = {}
var _tap3_msec: int = 0
## One finger's tap, double tap and drag.
var _one := SaOneFinger.new()


## Whether two fingers are moving the view right now.
func is_active() -> bool:
    return _pair.size() == 2


## A finger landing or lifting. A second one landing starts the gesture, and
## the last one lifting ends a two-finger tap with an undo and a three-finger
## tap with a redo. *machine*'s tools and registry are for the eyedropper one
## finger's double tap drives, and its session and surface for the undo and
## the redo.
func touch(event: InputEventScreenTouch, view: SaView, machine: ToolMachine = null) -> void:
    var tools: Dictionary = machine.registered_tools if machine != null else {}
    var registry: SaToolRegistry = machine.registry if machine != null else null
    if event.pressed:
        _down[event.index] = event.position
        _one.touch(event, _down.size(), view, tools, registry)
        if not is_active() and _down.size() == 2:
            _begin(view)
        elif _down.size() > 2:
            _tap = false
            _tap3 = _down.size() == 3 and is_active()
            _tap3_landed = _down.duplicate()
            _tap3_msec = Time.get_ticks_msec()
        return
    _down.erase(event.index)
    if event.canceled:
        _tap = false
        _tap3 = false
    _one.touch(event, _down.size(), view, tools, registry)
    if _pair.has(event.index):
        _pair = PackedInt32Array()
    if not _down.is_empty():
        return
    if _tap3:
        _tap3 = false
        if Time.get_ticks_msec() - _tap3_msec <= TAP_MSEC:
            _put_the_view_back(view)
            _redo(machine)
        return
    if not _tap:
        return
    _tap = false
    if Time.get_ticks_msec() - _tap_msec > TAP_MSEC:
        return
    _put_the_view_back(view)
    _undo(machine)


## A finger moving. Returns true when it moved the view.
func drag(event: InputEventScreenDrag, view: SaView) -> bool:
    if not _down.has(event.index):
        return false
    _down[event.index] = event.position
    if _tap and event.position.distance_to(_tap_landed.get(event.index, event.position)) > SLOP:
        _tap = false
    if _tap3 and event.position.distance_to(_tap3_landed.get(event.index, event.position)) > SLOP:
        _tap3 = false
    if _down.size() == 1:
        return _one.drag(event, view)
    if not _pair.has(event.index):
        return false
    var a: Vector2 = _down[_pair[0]]
    var b: Vector2 = _down[_pair[1]]
    var arm := b - a
    if arm.length() < 1.0 or _start_distance < 1.0:
        return false
    var middle := (a + b) * 0.5
    view.set_zoom(clampf(_start_zoom * arm.length() / _start_distance, SaView.ZOOM_MIN, SaView.ZOOM_MAX))
    view.set_rotation(SaView.snap_rotation(wrapf(_start_rotation + arm.angle() - _start_angle, -PI, PI)))
    view.set_pan(middle - view.view_offset(_anchor))
    return true


func _begin(view: SaView) -> void:
    _pair = PackedInt32Array(_down.keys())
    var a: Vector2 = _down[_pair[0]]
    var b: Vector2 = _down[_pair[1]]
    _start_distance = a.distance_to(b)
    _start_angle = (b - a).angle()
    _start_zoom = view.get_zoom()
    _start_rotation = view.get_rotation()
    _anchor = view.screen_to_document((a + b) * 0.5)
    _start_pan = view.get_pan()
    _tap = true
    _tap_landed = _down.duplicate()
    _tap_msec = Time.get_ticks_msec()


## The view as the pair found it, which a tap's few pixels of wander nudged.
func _put_the_view_back(view: SaView) -> void:
    view.set_zoom(_start_zoom)
    view.set_rotation(_start_rotation)
    view.set_pan(_start_pan)


## The Edit menu's Undo on *machine*'s document: its open session becomes a
## step first, so the undo takes that back rather than the step under it.
static func _undo(machine: ToolMachine) -> void:
    if machine == null or machine.surface == null:
        return
    var document := machine.surface.get_document()
    if document == null:
        return
    machine.close_session()
    document.undo()


## The Edit menu's Redo on *machine*'s document: its open session becomes a
## step first, as the router's Redo closes it.
static func _redo(machine: ToolMachine) -> void:
    if machine == null or machine.surface == null:
        return
    var document := machine.surface.get_document()
    if document == null:
        return
    machine.close_session()
    document.redo()
