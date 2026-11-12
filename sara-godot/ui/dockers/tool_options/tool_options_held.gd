## What a held key shows on the Tool Options docker's rows: Add, Subtract or
## Intersect on a selection tool's mode row while Shift, Alt or both are down,
## and the painter's own choice again once they are let go.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The tool answers [method ToolState.held_options] and this puts the answer on
## the rows through `ToolOptionControls.show_value`, which fills a control in
## and writes nothing, so the stored `selection_mode` keeps the painter's
## choice throughout. Asked once a frame rather than on a key event, because
## the keyboard reaches whichever window has focus and a floating docker is a
## window of its own, and because a press made with the key down keeps its
## mode after the key is let go, which only the tool knows.
##
## **Its own class rather than lines in `tool_options_docker.gd`**, which stood
## at 973 lines, because it owns one thing, which rows a held key is showing,
## and the docker owns which rows there are. Reached by path rather than by
## `class_name`, as `tool_options_floor.gd` is.
extends RefCounted

## The controls the rows hold, which this shows values on.
var _options: ToolOptionControls

## Option key to the value a held key put on its row at the last ask, and the
## tool it was asked of. Empty while no key shows anything.
var _shown: Dictionary = {}
var _shown_for: StringName = &""


func _init(controls: ToolOptionControls) -> void:
    _options = controls


## Puts on the rows what the shown tool's held keys ask for, and the tool's own
## value back on a row whose key was let go. Nothing happens on a frame where
## the answer is the last one, so a frame with no key down costs one call.
func follow(machine: ToolMachine, tool_id: StringName) -> void:
    var tool: ToolState = machine.get_tool(tool_id) if machine != null and not String(tool_id).is_empty() else null
    var wanted: Dictionary = tool.held_options() if tool != null else {}
    if wanted == _shown and tool_id == _shown_for:
        return
    # A change of tool has had its rows read again by the docker's own sync.
    if tool_id == _shown_for and tool != null:
        for key: StringName in _shown:
            if not wanted.has(key):
                _options.show_value(key, _options.read(key, tool, tool_id))
    for key: StringName in wanted:
        _options.show_value(key, wanted[key])
    _shown = wanted
    _shown_for = tool_id


## What a held key shows on the rows now, option key to value. What a suite
## and a dump read.
func shown() -> Dictionary:
    return _shown.duplicate()
