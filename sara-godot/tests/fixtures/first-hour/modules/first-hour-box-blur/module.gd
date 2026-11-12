## The box blur as the guide's first hour leaves it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules` and not under the other fixtures either, so no
## ordinary launch sees it and no scenario that loads
## `res://tests/fixtures/modules` gains a row it did not have. the scenario
## reaches it with `--modules-dir=res://tests/fixtures/first-hour/modules`.
##
## Its directory has a `modules` segment on purpose: `SaShaderIndex.owner_of`
## takes a kernel's owner from the segment after `modules`, so a fixture parked
## anywhere else would file `blur` under the core owner and collide with Sara's
## own names.
##
## What it holds is not an example worth copying. It is what a student has on
## disk after typing exactly what the scripting guide says in steps 3
## and 4, kept so the scenario can shoot the result rather than describe it.
extends SaModule

const FirstHourBoxBlur = preload("res://tests/fixtures/first-hour/modules/first-hour-box-blur/first_hour_box_blur.gd")


func get_id() -> StringName:
    return &"first_hour_box_blur"


func get_name() -> String:
    return "First Hour Box Blur"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_filter(FirstHourBoxBlur.new())
