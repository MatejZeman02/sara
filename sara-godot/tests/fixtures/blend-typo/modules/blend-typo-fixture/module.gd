## A module whose blend mode names a kernel one letter away from the one its
## shader has, so the registry's own refusal has something to refuse.
##
## The shader beside this file declares `hard_mix` and `typo_mode.gd` asks for
## `hardmix`, which is a mistake a module can make, and the
## one a painter met as a layer that composited as Normal over a line in a
## terminal.
##
## Its own root rather than `tests/fixtures/modules/`, where the other fixtures
## live. Every scenario that names that directory loads all eight of them, and
## a refused mode is a fault in the problems window at boot, so a fixture that
## exists to raise one would raise it in nine scenarios that never asked for
## it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule

const TypoMode := preload("res://tests/fixtures/blend-typo/modules/blend-typo-fixture/typo_mode.gd")


func get_id() -> StringName:
    return &"blend_typo_fixture"


func get_name() -> String:
    return "Blend typo fixture"


## The registration is refused, and the module loads anyway: the refusal is one
## mode's, not the folder's, which is what a painter with a slightly wrong
## module should get rather than a module that never arrives.
func register(ctx: SaContext) -> void:
    ctx.register_blend_mode(TypoMode.descriptor())
