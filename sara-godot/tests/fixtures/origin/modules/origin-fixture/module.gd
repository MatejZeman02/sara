## A module whose filter paints the rectangle it was dispatched over.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## In a directory of its own rather than beside the other fixtures, so that no
## scenario loading `res://tests/fixtures/modules` gains a Filter menu row it
## did not have. the scenario reaches it with
## `--modules-dir=res://tests/fixtures/origin/modules`.
##
## The path keeps a `modules` segment on purpose: `SaShaderIndex.owner_of`
## takes a kernel's owner from the segment after `modules`, so a fixture parked
## anywhere else files `at_origin` under the core owner.
##
## The id is the directory name, hyphen and all, which is `filter-fixture`'s
## rule and not the box blur's. A test builds an `SaFilterContext` with no
## ModuleLoader behind it, and the context then falls back to the id for the
## kernel's owner, so an id that said anything else would ask for a kernel
## nobody filed.
extends SaModule

const OriginFilter = preload("res://tests/fixtures/origin/modules/origin-fixture/origin_filter.gd")


func get_id() -> StringName:
    return &"origin-fixture"


func get_name() -> String:
    return "Origin Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_filter(OriginFilter.new())
