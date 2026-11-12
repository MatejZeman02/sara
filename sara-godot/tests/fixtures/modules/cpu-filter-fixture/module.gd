## A module whose one filter goes through the CPU door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/modules`, the flag
## `core/loader/module_loader.gd` reads.
##
## It owns no kernel, so nothing about it depends on the directory's name the
## way a kernel-owning fixture does. It is here rather than in a folder of its own
## because a scenario that already loads this directory can open it beside the
## others and read what a CPU filter does to the history.
extends SaModule

const CpuFilter = preload("res://tests/fixtures/modules/cpu-filter-fixture/cpu_filter.gd")


func get_id() -> StringName:
    return &"cpu-filter-fixture"


func get_name() -> String:
    return "Cpu Filter Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_filter(CpuFilter.new())
