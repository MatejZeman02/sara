## A module that registers one point filter, an invert.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/modules`, the flag
## `core/loader/module_loader.gd` reads, which is the only way one scenario can carry
## its own module without the app shipping it.
##
## Its own folder, because the shader index files a kernel under the directory
## it lives in, so a module that owns a kernel has to be its directory's name
## and two fixtures cannot share a folder without one of them lying about what it is.
extends SaModule

const InvertFilter = preload("res://tests/fixtures/modules/point-fixture/invert_filter.gd")


func get_id() -> StringName:
    return &"point-fixture"


func get_name() -> String:
    return "Point Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_filter(InvertFilter.new())
