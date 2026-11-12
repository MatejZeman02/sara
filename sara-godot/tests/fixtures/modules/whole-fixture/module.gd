## A module that registers one filter that reads the whole node.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it, and its own folder
## for the reason the point fixture's header gives: the shader index files a
## kernel under the directory it lives in.
extends SaModule

const WholeShiftFilter = preload("res://tests/fixtures/modules/whole-fixture/whole_shift_filter.gd")


func get_id() -> StringName:
    return &"whole-fixture"


func get_name() -> String:
    return "Whole Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_filter(WholeShiftFilter.new())
