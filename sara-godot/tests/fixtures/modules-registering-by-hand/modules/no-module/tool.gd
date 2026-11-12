## The tool in this fixture set, a descriptor that writes itself, so the folder's
## default registration can make it with no arguments.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaToolDescriptor

const State = preload("state.gd")


func _init() -> void:
    id = &"tool"
    tool_script = State
    display_name = "Fixture Tool"
