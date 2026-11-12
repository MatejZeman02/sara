## The module another one builds on.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Its folder sorts after its dependent's, so the dependent is discovered first
## and only the dependency order puts this one ahead of it. Its `unregister`
## writes its id to a list kept on the engine, where the suite reads the order
## the loader put the two down in. An engine meta rather than a static on a
## shared script, because the reload reads a module and every script it
## preloads with the cache ignored, which would hand each load its own static.
extends SaModule


func get_id() -> StringName:
    return &"d1-b-base"


func get_name() -> String:
    return "Base"


func get_version() -> String:
    return "1.0.0"


func unregister(_ctx: SaContext) -> void:
    if Engine.has_meta(&"d1_put_down"):
        (Engine.get_meta(&"d1_put_down") as Array).append(String(get_id()))
