## The left drag of a navigation tool, the pan and the zoom: the press it needs
## to begin, and a line in the log when it moved the view not at all.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The press.** The pan tool follows a drag from its own left press, so a
## Space pressed after the pen or the button was already down would put the pan
## in the hand with no press of its own, and the drag under it would move
## nothing until the button went up and down again. So a navigation tool put in
## the hand while the left button is down is handed a press where the pointer
## is, and the drag pans from there.
## The press goes to the tool itself and not to a scene layer, which the press
## the button made already went to if it was one.
##
## **The line.** A drag that pans nothing can have causes the press above does
## not cover, and the state at that moment is what tells them apart. A
## left drag that travelled at least [constant TRAVEL_PIXELS] under a
## navigation tool and left the view's pan, zoom and turn as they were prints
## one [constant LINE] line at its release, naming the tool, whether the
## machine heard the press and whether the tool was handed it, how many motions
## came and how many the tool was handed, the travel their relatives add up to
## and the travel their positions do. A drag the machine heard no press for
## is measured from its first motion with the left button in the mask and
## printed when that button is seen up. Silent while a drag moves the view, so
## a run's log holds the line only where the next one needs it.
##
## Private to the tools package, beside the machine as `SaShiftPress` is. The
## machine hands it every event it hears and every event its tool is handed,
## and itself with each, and it holds no reference to the machine.
class_name SaNavigationDrag
extends RefCounted

## The word the log line starts with, for a reader of the log to search for.
const LINE := "NAVIGATION DRAG MOVED NOTHING"

## How far a drag has to go, in screen pixels, before a view that did not move
## is worth a line. A click on the zoom tool travels less.
const TRAVEL_PIXELS: float = 8.0

## The last line printed, for a suite, empty until one is.
var last_line: String = ""

## Whether the left button is down by what the machine heard.
var _left_down: bool = false
## Where the machine last heard the pointer, in its surface's space.
var _pointer: Vector2 = Vector2.ZERO
## A drag under a navigation tool is being measured.
var _measuring: bool = false
var _press_heard: bool = false
var _press_fed: bool = false
var _motions: int = 0
var _motions_fed: int = 0
var _relative: Vector2 = Vector2.ZERO
var _first_at: Vector2 = Vector2.ZERO
var _last_at: Vector2 = Vector2.ZERO
var _tool: StringName = &""
var _view_before: Array = []


## Hands *machine*'s active tool a left press where the pointer is when it is a
## navigation tool and the left button is down, which the machine asks right
## after a held key or button changed the tool. True when it did.
func came_into_hand(machine: ToolMachine) -> bool:
    if not _left_down or not _navigates(machine) or machine.active_tool == null:
        return false
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.button_mask = MOUSE_BUTTON_MASK_LEFT
    press.position = _pointer
    press.global_position = _pointer
    machine.active_tool.handle_input(press)
    _begin(machine, false)
    _press_fed = true
    return true


## Every event *machine* hears, before any of its routes.
func heard(event: InputEvent, machine: ToolMachine) -> void:
    var mouse := event as InputEventMouse
    if mouse == null:
        return
    _pointer = mouse.position
    var button := mouse as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        _left_down = button.pressed
        if button.pressed and _navigates(machine):
            _begin(machine, true)
        elif not button.pressed:
            _end(machine)
        return
    var motion := mouse as InputEventMouseMotion
    if motion == null:
        return
    if motion.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
        _end(machine)
        return
    if not _measuring and _navigates(machine):
        _begin(machine, false)
        _first_at = motion.position
    if _measuring:
        _motions += 1
        _relative += motion.relative
        _last_at = motion.position


## Every event *machine*'s active tool is handed.
func fed(event: InputEvent) -> void:
    if not _measuring:
        return
    if event is InputEventMouseMotion:
        _motions_fed += 1
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        _press_fed = true


func _begin(machine: ToolMachine, press_heard: bool) -> void:
    _measuring = true
    _press_heard = press_heard
    _press_fed = false
    _motions = 0
    _motions_fed = 0
    _relative = Vector2.ZERO
    _first_at = _pointer
    _last_at = _pointer
    _tool = machine.active_tool_name
    _view_before = _view_of(machine)


func _end(machine: ToolMachine) -> void:
    if not _measuring:
        return
    _measuring = false
    var travel := maxf(_relative.length(), _first_at.distance_to(_last_at))
    if travel < TRAVEL_PIXELS or _view_of(machine) != _view_before:
        return
    last_line = (
        (
            "%s: the %s tool, press heard %s, handed to the tool %s, %d motions of which the tool was handed %d,"
            + " relative travel %s, position travel %s, the tool in hand now %s"
        )
        % [
            LINE,
            _tool,
            _press_heard,
            _press_fed,
            _motions,
            _motions_fed,
            _relative,
            _last_at - _first_at,
            machine.active_tool_name
        ]
    )
    print(last_line)


static func _navigates(machine: ToolMachine) -> bool:
    var descriptor := machine.get_descriptor(machine.active_tool_name)
    return descriptor != null and descriptor.category == &"navigate"


static func _view_of(machine: ToolMachine) -> Array:
    var view: SaView = machine.surface.view if machine.surface != null else null
    return [] if view == null else [view.get_pan(), view.get_zoom(), view.get_rotation()]
