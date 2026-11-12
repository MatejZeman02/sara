## A module that remembers one value of its own between sessions and does
## nothing else.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it.
## `core/api/tests/test_a_module_keeps_its_own_preferences.gd` registers it by hand
## into registries of its own. It keeps its value through the door every module
## has, `SaContext.preference` and `SaContext.set_preference`, rather than a
## property of the skeleton's settings, which is the whole point of the door.
extends SaModule

const KEY := &"favourite_marsupial"

## The context `register` was handed, which is where the door is.
var _context: SaContext = null


func get_id() -> StringName:
    return &"preference-fixture"


func get_name() -> String:
    return "Preference Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    _context = ctx


## Writes the fixture's one preference.
func remember(value: Variant) -> void:
    _context.set_preference(KEY, value)


## Reads it back, or *fallback* when the profile holds none.
func recalled(fallback: Variant = null) -> Variant:
    return _context.preference(KEY, fallback)
