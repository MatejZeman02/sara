## A module that registers one filter whose neighbourhood pass is a list of
## steps.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it, and its own folder
## for the reason the point fixture's header gives: the shader index files a
## kernel under the directory it lives in.
extends SaModule

const StepsFilter = preload("res://tests/fixtures/modules/steps-fixture/steps_filter.gd")


func get_id() -> StringName:
    return &"steps-fixture"


func get_name() -> String:
    return "Steps Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_filter(StepsFilter.new())
