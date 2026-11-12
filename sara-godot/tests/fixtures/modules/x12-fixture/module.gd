## A module that registers one filter and nothing else.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/modules`, which is the flag
## `core/loader/module_loader.gd` reads, and it registers through
## `ctx.register_filter` and no other door, so the menu row it produces is a
## proof of hard rule 6 rather than a picture of one.
##
## Beside `filter-menu-fixture/` rather than inside it, because the id has to
## stay the directory name: the shader index files a kernel under the directory
## it lives in, so a fixture that owns a kernel and a fixture that registers a
## filter cannot share a folder without one of them lying about what it is.
extends SaModule

const X12Filter = preload("res://tests/fixtures/modules/x12-fixture/x12_filter.gd")


func get_id() -> StringName:
    return &"x12-fixture"


func get_name() -> String:
    return "Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_filter(X12Filter.new())
