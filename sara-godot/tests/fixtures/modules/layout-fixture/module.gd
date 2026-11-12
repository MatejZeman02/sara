## A module that ships one layout and nothing else.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/modules`, which is the flag
## `core/loader/module_loader.gd` reads, and that is the only way one scenario can carry
## its own module without the app shipping it.
##
## It registers nothing. The claim to prove is about the `layouts/` folder
## beside this file, and a module that also registered a tool would put a second
## thing in every dump that reads it.
extends SaModule


func get_id() -> StringName:
    return &"layout-fixture"


func get_name() -> String:
    return "Layout Fixture"


func get_version() -> String:
    return "1.0.0"


func register(_ctx: SaContext) -> void:
    pass
