## A module whose one filter floods from the pixel clicked in its preview.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/modules`, the flag
## `core/loader/module_loader.gd` reads. It owns no kernel, so its folder's name
## is free, as the CPU filter fixture's is.
extends SaModule

const FloodFilter = preload("res://tests/fixtures/modules/click-fixture/flood_filter.gd")


func get_id() -> StringName:
    return &"click-fixture"


func get_name() -> String:
    return "Click Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_filter(FloodFilter.new())
