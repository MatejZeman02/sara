## The module that depends on `d1-b-base`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Writes its id to the same list on the engine as its dependency when it is
## put down, so the suite reads which of the two left first.
extends SaModule


func get_id() -> StringName:
    return &"d1-a-dependent"


func get_name() -> String:
    return "Dependent"


func get_version() -> String:
    return "1.0.0"


func get_dependencies() -> PackedStringArray:
    return ["d1-b-base"]


func unregister(_ctx: SaContext) -> void:
    if Engine.has_meta(&"d1_put_down"):
        (Engine.get_meta(&"d1_put_down") as Array).append(String(get_id()))
