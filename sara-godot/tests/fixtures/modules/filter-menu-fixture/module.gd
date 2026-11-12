## A module that registers one filter and nothing else.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/modules`, which is the flag
## `core/loader/module_loader.gd` reads, and that is the only way one scenario can
## carry its own module without the app shipping it.
##
## It registers through `ctx.register_filter` and no other door, which is what
## makes the Filter menu row it produces a proof of hard rule 6 rather than a
## picture of one.
##
## Beside `filter-fixture/` rather than inside it, because that one owns a kernel and
## its id has to stay its directory name: the shader index files a kernel under
## the directory it lives in, so a fixture that owns a kernel and a fixture that
## registers a filter cannot share a folder without one of them lying about what
## it is.
extends SaModule

const TintFilter = preload("res://tests/fixtures/modules/filter-menu-fixture/tint_filter.gd")


func get_id() -> StringName:
    return &"filter-menu-fixture"


func get_name() -> String:
    return "Filter Menu Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_filter(TintFilter.new())
