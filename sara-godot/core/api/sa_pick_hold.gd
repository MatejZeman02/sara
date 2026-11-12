## The hold a window takes on the main canvas while it waits for a pick from
## it: the Eyedropper in the painter's hand, so a click on the canvas picks
## rather than paints, and the painter's foreground kept, which the picks would
## otherwise repaint.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Select > Colour Range took it first, for its Pick from canvas box, and the
## Levels eyedroppers take the same one, so it is a door rather than either's
## own code. [method take] puts the Eyedropper in the hand through the tool
## machine a surface holds, and [method let_go] gives back the tool and the
## foreground. The tool goes back only while the Eyedropper is still the one in
## the hand, because a painter who chose another tool meanwhile has chosen it.
## A hold taken with no machine, a suite's, keeps the foreground alone. The
## Eyedropper is whichever tool the machine's `picker_tool_name()` answers, the
## one whose descriptor sets `picks_colour`, so the skeleton names no module's
## tool id.
##
## Writing the foreground back announces it on the bus as `color_picked`, the
## signal a pick arrives on too, so a listener reads [member _restoring] to
## tell the two apart.
class_name SaPickHold
extends RefCounted

## The tool machine the hold was taken on, or null. Untyped as
## `SaSurface.tool_machine` is, so it is asked by name, the way the module
## reload asks it.
var _machine: Object = null
## True from the moment the hold took the foreground and the tool until it gave
## them back.
var _holding: bool = false
## The id of the tool that picks, as the machine named it when the hold was
## taken, or empty when it holds none.
var _picker: StringName = &""
## True while the foreground is written back.
var _restoring: bool = false
var _tool_before: StringName = &""
var _previous_tool_before: StringName = &""
var _foreground_before: Color = Color.BLACK


## Keeps the foreground and makes the Eyedropper the tool in the hand of
## *machine*, once. A machine without the tool is left alone.
func take(machine: Variant) -> void:
    if _holding:
        return
    _holding = true
    _foreground_before = SaColors.foreground
    _tool_before = &""
    _machine = machine
    _picker = &""
    if is_instance_valid(_machine) and _machine.has_method(&"picker_tool_name"):
        var picker: StringName = _machine.call(&"picker_tool_name")
        _picker = picker
    if not _has_picker():
        return
    _tool_before = _machine.get(&"default_tool_name")
    _previous_tool_before = _machine.get(&"previous_tool_name")
    _machine.call(&"set_active_tool", _picker)


## Puts the foreground and the tool back, once.
func let_go() -> void:
    if not _holding:
        return
    _holding = false
    _restoring = true
    SaColors.foreground = _foreground_before
    _restoring = false
    if _has_picker() and not String(_tool_before).is_empty() and _machine.get(&"default_tool_name") == _picker:
        _machine.call(&"set_active_tool", _tool_before)
        _machine.set(&"previous_tool_name", _previous_tool_before)
    _tool_before = &""


## Whether the hold stands and the Eyedropper is the tool in the hand, so a
## pick that arrives now came from the canvas.
func is_picking() -> bool:
    return _holding and _has_picker() and _machine.get(&"active_tool_name") == _picker


func _has_picker() -> bool:
    if not is_instance_valid(_machine) or String(_picker).is_empty():
        return false
    var tools: Dictionary = _machine.get(&"registered_tools")
    return tools.has(_picker)
