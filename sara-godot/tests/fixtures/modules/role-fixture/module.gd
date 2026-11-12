## A module that replaces the skeleton's crop and takes a tool away.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it, the way the
## filter menu fixture beside it is hidden. It does the two things a
## module could once not do: it
## registers a subclass of a core class under the role the skeleton asks
## for, so the Canvas Size dialog and the crop tool build its crop rather
## than the skeleton's, and it removes a built-in tool by id, so the
## toolbox no longer offers it.
##
## Through `ctx.register_role` and the tool registry's own `unregister` and
## no other door, which is what makes the test that reads it a proof of
## hard rule 6 rather than a picture of one.
extends SaModule

const CountingCrop = preload("res://tests/fixtures/modules/role-fixture/counting_crop.gd")

## The tool this module takes away. The marquee, because every launch has
## one and no scenario selects with it.
const REMOVED_TOOL := &"marquee"


func get_id() -> StringName:
    return &"role-fixture"


func get_name() -> String:
    return "Role Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_role(&"crop", CountingCrop)
    ctx.tools.unregister(REMOVED_TOOL)
