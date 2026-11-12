## A module that registers one filter whose picture is its time, for the time
## row's scenario.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/modules`, as the point fixture's
## does. A folder of its own, because the shader index files its kernel under
## the directory it lives in.
extends SaModule

const TimeFilter = preload("res://tests/fixtures/modules/time-fixture/time_filter.gd")


func get_id() -> StringName:
    return &"time-fixture"


func get_name() -> String:
    return "Time Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_filter(TimeFilter.new())
