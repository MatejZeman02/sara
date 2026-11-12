## A module that ships one Krita bundle file and nothing else.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/modules`, the flag
## `core/loader/module_loader.gd` reads, which is the only way one scenario can carry
## its own module without the app shipping it.
##
## It registers nothing. The claim to prove is about the `bundles/` folder
## beside this file, which holds a copy of the fixture bundle the stamp brush's
## reader and importer suites commit, and the stamp brush's `shipped_bundles`
## role is what imports it.
extends SaModule


func get_id() -> StringName:
    return &"bundle-fixture"


func get_name() -> String:
    return "Bundle Fixture"


func get_version() -> String:
    return "1.0.0"


func register(_ctx: SaContext) -> void:
    pass
