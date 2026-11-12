## One finger alone on the canvas: a tap opens the pop-up palette at the finger,
## a double tap picks the colour under it as the eyedropper does, and a drag
## pans the view. A finger never paints, only the pen does.
##
## **A tap waits for a second one.** A still tap is held for [constant
## DOUBLE_TAP_MSEC] and opens the palette when no second tap came, which is the
## least a double tap needs, Android's own timeout. A second tap in that time
## near the first is a double tap and picks a colour, and the palette never
## opens. A finger that moves past [constant SLOP] pixels is a drag from then
## on, and pans the picture by the finger's travel, the whole of it, so the
## first few pixels the slop held back are not lost.
##
## **A touch the system takes back is no tap.** Android cancels a touch it
## decides was not meant, a palm its rejection drops or a rest the pen's landing
## makes it let go, and Godot hands that on as a release with
## [member InputEventScreenTouch.canceled] set. Such a release ends the finger
## with nothing opened or picked, and the next landing starts fresh. A drag it
## ends leaves the view where the pan put it.
##
## **A second finger ends it.** Once two are down the view is
## `SaTwoFingers`'s, and nothing this class does happens again until every
## finger has lifted, so the last finger off a pinch neither taps nor pans.
##
## **The pick is the eyedropper's own**, the tool the registry files under the
## sample category, driven through [method ToolState.straight_line_to] as one
## click at the document point under the finger. So the pick reads what the
## Eyedropper's Sample row says, converts as it converts, and hands the colour
## on as it does, and this class names no module.
##
## **The palette's point is the finger's position**, which is local to the
## canvas's control. That control fills its window, so the point is in the
## window's space as well, the space `SaRightClickDocker.toggle_at` takes.
##
## A pen never arrives here: Godot hands a stylus over as mouse events, and only
## a screen touch is a finger. Private to `tools/fingers`, owned by
## `SaTwoFingers`, which hears every touch first.
class_name SaOneFinger
extends RefCounted

## How long a still tap waits for a second one, in milliseconds.
const DOUBLE_TAP_MSEC := 300
## How far a finger moves, in pixels, before it is a drag rather than a tap.
const SLOP := 12.0
## How far apart two taps may land and still be one double tap, in pixels.
const DOUBLE_TAP_REACH := 64.0
## The tool category the registry files the eyedropper under.
const SAMPLE_CATEGORY := &"sample"

## The finger down now, or -1.
var _index: int = -1
## Where it landed, and the pan the view had then.
var _landed: Vector2 = Vector2.ZERO
var _start_pan: Vector2 = Vector2.ZERO
## Whether it has moved past the slop, which makes it a drag.
var _dragging: bool = false
## Whether this finger is the second tap of a double one.
var _second: bool = false
## Whether a second finger came, which spoils everything until all lift.
var _spoilt: bool = false
## The still tap waiting for a second one, its place and its number, so a timer
## left from an older tap opens nothing.
var _waiting: bool = false
var _waiting_at: Vector2 = Vector2.ZERO
var _tap_count: int = 0


## A finger landing or lifting, with *fingers* down after it. *tools* and
## *registry* are the machine's, for the eyedropper a double tap drives.
func touch(event: InputEventScreenTouch, fingers: int, view: SaView, tools: Dictionary, registry: SaToolRegistry) -> void:
    if event.pressed:
        if fingers > 1:
            _spoil()
            return
        _index = event.index
        _landed = event.position
        _start_pan = view.get_pan()
        _dragging = false
        _second = _waiting and event.position.distance_to(_waiting_at) <= DOUBLE_TAP_REACH
        _waiting = false
        return
    if event.index != _index:
        if fingers == 0:
            _spoilt = false
        return
    _index = -1
    if fingers == 0 and _spoilt:
        _spoilt = false
        return
    if _spoilt or _dragging:
        return
    if event.canceled:
        _second = false
        return
    if _second:
        _second = false
        _pick(event.position, view, tools, registry)
        return
    _wait_for_a_second_tap(event.position)


## The finger moving. Returns true when it moved the view.
func drag(event: InputEventScreenDrag, view: SaView) -> bool:
    if _spoilt or event.index != _index:
        return false
    var travel := event.position - _landed
    if not _dragging and travel.length() <= SLOP:
        return false
    _dragging = true
    _second = false
    view.set_pan(_start_pan + travel)
    return true


func _spoil() -> void:
    _spoilt = true
    _waiting = false
    _second = false


## Holds the tap for a double tap's time, then opens the palette when it is
## still the last tap and no second one came.
func _wait_for_a_second_tap(at: Vector2) -> void:
    _waiting = true
    _waiting_at = at
    _tap_count += 1
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    tree.create_timer(DOUBLE_TAP_MSEC / 1000.0).timeout.connect(_open_palette.bind(_tap_count))


func _open_palette(tap: int) -> void:
    if not _waiting or tap != _tap_count or _index != -1:
        return
    _waiting = false
    SaRightClickDocker.toggle_at(_waiting_at, SaRightClickDocker.PALETTE)


## Picks the colour under *at* with the registry's eyedropper, one click at the
## document point there.
func _pick(at: Vector2, view: SaView, tools: Dictionary, registry: SaToolRegistry) -> void:
    var sampler := _sampler(tools, registry)
    if sampler == null:
        return
    var point := view.screen_to_document(at)
    var motion := InputEventMouseMotion.new()
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    motion.pressure = 1.0
    sampler.straight_line_to(point, point, motion)


static func _sampler(tools: Dictionary, registry: SaToolRegistry) -> ToolState:
    if registry == null:
        return null
    for id: StringName in tools:
        var descriptor := registry.get_descriptor(id)
        if descriptor != null and descriptor.category == SAMPLE_CATEGORY:
            return tools[id]
    return null
