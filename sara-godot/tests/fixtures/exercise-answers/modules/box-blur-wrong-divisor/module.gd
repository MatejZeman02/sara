## The box blur with the mistake the exercise warns about, so the checking
## scenario can be shown to fail rather than only to pass.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Under `tests/fixtures/exercise-answers/modules/` rather than beside the other
## fixtures, because every scenario that says `--modules-dir=res://tests/fixtures/modules`
## would otherwise gain a second Box blur row in the Filter menu and every dump
## those scenarios take would move. A checker points at this directory and
## nothing else does.
##
## The directory holds `modules` one level up for the reason the fixture header
## gives: the shader index takes a kernel's owner from the path, and a module
## outside any `modules/` would ask for a kernel filed under `sara`.
extends SaModule

const WrongDivisor = preload("res://tests/fixtures/exercise-answers/modules/box-blur-wrong-divisor/box_blur.gd")


func get_id() -> StringName:
    return &"box_blur_wrong"


func get_name() -> String:
    return "Box Blur With A Wrong Divisor"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_filter(WrongDivisor.new())
