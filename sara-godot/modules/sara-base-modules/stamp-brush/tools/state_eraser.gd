## The eraser, a `StateBrush` whose settings erase.
##
## The mode is on the settings and not on the instance, because `is_eraser` is
## overwritten by `event.pen_inverted` on every motion, and a mouse or a pen
## held the right way up cleared it on the first move.
##
## The blend mode below is for a machine built without a registry, which is what
## `ToolMachine.register_tool` does for a test: there is no descriptor to carry
## `shared_settings`, so the settings this instance is born with are the ones it
## keeps. Through the registry, `stamp-brush/module.gd` sets the same mode on
## `eraser_settings`, and `_rebuild_tools` hands that object over.
extends "res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd"


func _init() -> void:
    super._init()
    settings.blend_mode = SaLayerScript.BLEND_MODE.ERASE
