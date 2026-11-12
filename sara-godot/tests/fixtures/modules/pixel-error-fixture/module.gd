## A module whose one filter is a pixel function that does not compile.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/modules`, which is the flag
## `core/loader/module_loader.gd` reads.
##
## It registers through `ctx.register_filter` and no other door, and it
## registers **although the kernel failed**, which is the half a picture
## cannot show: a painter whose kernel has a mistake in it still finds the entry
## they were promised, dimmed and saying why, rather than a menu that quietly
## lost a row.
##
## The id has to stay the directory name. The shader index takes a shader's
## owner from the directory it lives under, and the generated kernel is filed
## under that owner too.
extends SaModule

const BrokenFilter = preload("res://tests/fixtures/modules/pixel-error-fixture/broken_filter.gd")


func get_id() -> StringName:
    return &"pixel-error-fixture"


func get_name() -> String:
    return "Pixel Error Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_filter(BrokenFilter.new())
