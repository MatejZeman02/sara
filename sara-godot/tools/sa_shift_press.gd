## A Shift press of the left button over the canvas, with a tool that has a
## size. A drag sizes the tool, the way Krita does it, and a click that does not
## travel draws a straight line from where the tool's last stroke let go, the
## way Krita, Photoshop and Clip Studio do.
##
## The gesture starts only on a press with Shift already down, so Shift pressed
## midway through a stroke changes nothing. Releasing Shift before the mouse
## does not end it either, which is what lets the hand relax during a long drag.
## The press and everything up to its release are kept from the active tool:
## the press that starts a resize must not also lay down a dab, and the motion
## that follows must not drag a stroke across the canvas.
##
## **A click is a press the pointer never took past [constant CLICK_PIXELS]**.
## Inside that the drag sizes nothing, so the size a click leaves is the size
## it found, and a pen that slips a pixel as it lands still draws its line.
## Otherwise a Shift click would be a resize of no length that the tool never
## hears of, and it would paint nothing.
##
## **Ctrl held at the press snaps the line** to the nearest multiple of
## [constant ANGLE_STEP] about its start, keeping its length, so a level
## horizon or an exact 45 degrees needs no aim.
##
## Private to the tools package, beside the machine as `SaTwoFingers` is. The
## machine hands it every event before the tool sees it, and itself with each,
## and it holds no reference to the machine.
class_name SaShiftPress
extends RefCounted

## How far the pointer may wander from the press, in screen pixels, while the
## press is still a click.
const CLICK_PIXELS: float = 3.0

## The angle a Ctrl Shift click's line snaps to steps of, in radians. It is
## the view's rotate step, so the canvas and the line turn by the same 15
## degrees.
const ANGLE_STEP: float = SaView.ROTATION_STEP

## What the status line says to a Shift click with no stroke to start from.
const NO_STROKE_YET := "Shift+click draws a straight line from your last stroke, and there is none on this layer yet"

## A Shift press is down and this gesture holds it, as a click or as a drag.
var held: bool = false

## What the last release asked of the pointer, read by
## [method ToolMachine.warp_report]. `at` is the viewport point the ring was
## pinned to, `to` the physical pixels handed to Input.warp_mouse. Empty until
## a press has ended.
var last_warp: Dictionary = {}

## Where the press landed, in the window's viewport, and the size it found.
var _start_at: Vector2 = Vector2.ZERO
var _start_size: float = 0.0
## The pointer left the click's few pixels, so this press is a drag.
var _travelled: bool = false
## Ctrl was down with the press, so the click's line snaps its angle.
var _snaps: bool = false
## The motion with the most pressure the click sent, or null for a click that
## sent none, which a mouse's never does.
var _strongest: InputEventMouseMotion = null
## The last motion before the press, a hover's or the last stroke's.
var _hover: InputEventMouseMotion = null
## A drag moved the size and [method tell_moved_size] is queued to say so.
var _size_moved_untold: bool = false
## Tool name to the [SaShiftPress.End] its last stroke left.
var _ends: Dictionary = {}
## The painting tool the left press went to, until its release.
var _stroking: StringName = &""


## Where a painting tool's last stroke let go, and what it let go on. A line
## starts here only while the document, the active layer and the mask being
## painted are the ones the stroke was on, so a stroke on one layer never
## draws a line on another.
class End:
    extends RefCounted

    ## In document pixels.
    var at: Vector2 = Vector2.ZERO
    var _on: Array[int] = []

    func _init(document: SaDocument, point: Vector2) -> void:
        at = point
        _on = End.painted(document)

    ## Whether *document* is painting where this end was kept.
    func holds(document: SaDocument) -> bool:
        return _on == End.painted(document)

    ## The instances a stroke on *document* lands on, by id, so an end keeps no
    ## document alive.
    static func painted(document: SaDocument) -> Array[int]:
        var layer: Object = document.active_layer
        var mask: Object = document.mask_target
        return [
            document.get_instance_id(),
            layer.get_instance_id() if layer != null else 0,
            mask.get_instance_id() if mask != null else 0,
        ]


## Takes *event* when it belongs to the gesture, and the machine then keeps it
## from the tool.
func take(event: InputEvent, machine: ToolMachine) -> bool:
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if not button.pressed:
            if not held:
                return false
            held = false
            _unpin(machine)
            if not _travelled:
                _draw_line(machine)
            return true
        var start := _size_of(machine.active_tool)
        if not button.shift_pressed or start < 0.0:
            return false
        held = true
        _travelled = false
        _snaps = button.ctrl_pressed
        _strongest = null
        _start_at = button.global_position
        _start_size = start
        _pin(machine, button.global_position)
        return true

    var motion := event as InputEventMouseMotion
    if motion == null:
        return false
    if not held:
        _hover = motion
        return false
    if not _travelled:
        if motion.global_position.distance_to(_start_at) < CLICK_PIXELS:
            if _strongest == null or motion.pressure >= _strongest.pressure:
                _strongest = motion
            return true
        _travelled = true
    _resize(motion, machine)
    return true


## Lets go of a press the machine took the tool away from.
func drop() -> void:
    held = false


## Hears a left press or release *machine* handed its active tool. A painting
## tool's release after its own press is where its stroke let go.
func fed(event: InputEvent, machine: ToolMachine) -> void:
    var button := event as InputEventMouseButton
    if button == null or button.button_index != MOUSE_BUTTON_LEFT:
        return
    var name := machine.active_tool_name
    if button.pressed:
        var descriptor := machine.get_descriptor(name)
        _stroking = name if descriptor != null and descriptor.is_painting else &""
        return
    var tool := machine.active_tool
    var doc: SaDocument = tool.surface.get_document() if tool != null and tool.surface != null else null
    if _stroking == name and not String(name).is_empty() and doc != null:
        _ends[name] = End.new(doc, tool.get_document_mouse_position())
    _stroking = &""


## Tells the surfaces a drag moved the size, once a frame however many motions
## moved it. Each telling reads every options row again, milliseconds of work, and a
## pen under Windows sends four motions a frame or more. The frame's end calls
## it, and a suite, which cannot wait, calls it through the machine.
func tell_moved_size() -> void:
    if _size_moved_untold:
        _size_moved_untold = false
        EventBus.tool_options_moved.emit()


## The drag's own work: the size follows the pointer's horizontal travel from
## the press, so the ring's edge stays under the hand at any zoom.
func _resize(motion: InputEventMouseMotion, machine: ToolMachine) -> void:
    var tool := machine.active_tool
    var dragged := _radius_settings(tool)
    var owned := dragged == null and tool != null and tool.own_size() >= 0.0
    var per_pixel := _own_size_per_screen_pixel(machine.surface) if owned else _radius_per_screen_pixel(machine.surface)
    if (dragged == null and not owned) or per_pixel <= 0.0:
        return
    var wanted: float = _start_size + (motion.global_position.x - _start_at.x) * per_pixel
    if owned:
        var before := tool.own_size()
        tool.resize_own(wanted)
        if is_equal_approx(before, tool.own_size()):
            return
    else:
        var clamped := clampf(wanted, ToolMachine.BRUSH_RADIUS_MIN, ToolMachine.BRUSH_RADIUS_MAX)
        if is_equal_approx(clamped, dragged.radius):
            return
        dragged.radius = clamped
    # Values only. Nothing observes brush settings directly, so a signal is
    # what moves the options bar's slider, and it has to be the one that says
    # "read the rows again" rather than "the tool changed": the second made
    # every surface rebind per motion event, the presets docker rebuilding its
    # whole grid each time, and a shift-drag on a tablet pinned one core. The
    # ring needs no help, the machine's `_process` already polls for the size.
    if not _size_moved_untold:
        _size_moved_untold = true
        tell_moved_size.call_deferred()


## The click's own work, on a painting tool: one stroke from where the tool's
## last stroke let go to the pointer, run by [method ToolState.straight_line_to],
## and the line's end is where the next one starts, the snapped end when Ctrl
## was down. With no end on the layer being painted it paints nothing and the
## status line says why.
func _draw_line(machine: ToolMachine) -> void:
    var tool := machine.active_tool
    var descriptor := machine.get_descriptor(machine.active_tool_name)
    var doc: SaDocument = tool.surface.get_document() if tool != null and tool.surface != null else null
    if doc == null or descriptor == null or not descriptor.is_painting:
        return
    var end: End = _ends.get(machine.active_tool_name)
    if end == null or not end.holds(doc):
        SaStrokeNote.say(tr(NO_STROKE_YET))
        return
    var to := tool.get_document_mouse_position()
    if _snaps:
        to = snapped_end(end.at, to)
    tool.straight_line_to(end.at, to, _line_motion())
    _ends[machine.active_tool_name] = End.new(doc, to)


## *to* turned about *from* to the nearest multiple of [constant ANGLE_STEP],
## at the same distance from *from*.
static func snapped_end(from: Vector2, to: Vector2) -> Vector2:
    var offset := to - from
    if offset.is_zero_approx():
        return to
    return from + Vector2.from_angle(snappedf(offset.angle(), ANGLE_STEP)) * offset.length()


## The motion the line is walked at, which carries the pen's pressure, tilt and
## eraser end: the click's own strongest, or the hover's for a click that sent
## none. A pen that touched and lifted between two reports said no pressure,
## and full pressure is a tap's rule in both brush engines. A mouse's hover
## stays at none, which the engines read as a mouse and paint at full.
func _line_motion() -> InputEventMouseMotion:
    if _strongest != null:
        return _strongest
    var motion := _hover.duplicate() as InputEventMouseMotion if _hover != null else InputEventMouseMotion.new()
    if motion.pressure <= 0.0 and (motion.tilt != Vector2.ZERO or motion.pen_inverted):
        motion.pressure = 1.0
    return motion


## The ring stays where the press was for the length of the gesture.
##
## Without it the preview circle would travel with the hand, so the size the
## painter picked would show somewhere other than where their next stroke
## begins. The pin is in the window's viewport
## space, the same space the event carries, and `_start_at` still reads the
## real pointer, so the drag measures what the hand did while the cursor says
## where the brush is. The machine is the pin's holder, so its `_process` drops
## a pin this gesture let go of.
func _pin(machine: ToolMachine, at: Vector2) -> void:
    var window := machine.get_window() if machine.is_inside_tree() else null
    if window != null:
        SaCursorPolicy.pin_pointer(machine, window, at)


## Drops the pin and asks for the pointer back where the press was.
##
## The warp is refused under Wayland, which is Sara's target, and honoured under
## X11. Refused is survivable, because what matters is that the preview stops
## following the drag. What a refused warp leaves is a pointer
## left where the drag ended, which is where the painter put it.
##
## Two spaces meet here. `Input.warp_mouse` counts physical pixels
## from the window's own corner, and `pointer_in_window` answers in the
## viewport's logical ones, so the target has to go back through the window's
## final transform. Handing over the logical point would divide the target by
## the content scale, so at 150 percent a release at (700, 500) would ask for
## (467, 333) and the cursor would jump a third of the way towards the top left
## corner.
func _unpin(machine: ToolMachine) -> void:
    var window := machine.get_window() if machine.is_inside_tree() else null
    if window != null and SaCursorPolicy.pointer_is_pinned():
        var at := SaCursorPolicy.pointer_in_window(window)
        var to: Vector2 = window.get_final_transform() * at
        last_warp = {"at": [at.x, at.y], "to": [to.x, to.y]}
        Input.warp_mouse(to)
    SaCursorPolicy.unpin_pointer(machine)


## *tool*'s settings, when it has a radius to resize. Null for the tools that
## do not, which is what leaves Shift plus drag alone on pan and zoom.
static func _radius_settings(tool: ToolState) -> Resource:
    if tool == null:
        return null
    var settings: Resource = tool.get("settings")
    if settings == null or not ("radius" in settings):
        return null
    return settings


## The size a drag starts from: the brush settings' radius, or the size *tool*
## keeps as its own, [method ToolState.own_size]. Negative when the tool has
## neither, which leaves the press to the tool.
static func _size_of(tool: ToolState) -> float:
    var settings := _radius_settings(tool)
    if settings != null:
        return settings.radius
    return tool.own_size() if tool != null else -1.0


## How much of a tool's own size one screen pixel of drag is worth. The size is a
## diameter in document pixels, and the ring is drawn at half of it, so the edge
## under the pointer follows the hand at any zoom as a brush's does.
static func _own_size_per_screen_pixel(surface: SaSurface) -> float:
    if surface == null or surface.view == null:
        return 0.0
    var zoom := surface.view.get_zoom()
    return 2.0 / zoom if zoom > 0.0 else 0.0


## How much of the radius fraction one screen pixel of drag is worth.
##
## Radius is stored as a fraction of `SaDocument.brush_side`, the canvas's smaller
## dimension until a crop keeps the one it had, and the ring is drawn in screen
## pixels, so both that side and the zoom have to come out of it. The result is that the ring grows by exactly the distance the
## pointer travelled, at any zoom.
static func _radius_per_screen_pixel(surface: SaSurface) -> float:
    if surface == null or surface.view == null:
        return 0.0
    var doc := surface.get_document()
    if doc == null:
        return 0.0
    var side := doc.brush_side
    var zoom := surface.view.get_zoom()
    if side <= 0.0 or zoom <= 0.0:
        return 0.0
    return 1.0 / (side * zoom)
