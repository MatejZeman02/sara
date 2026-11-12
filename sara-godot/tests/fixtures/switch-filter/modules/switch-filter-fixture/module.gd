## A module whose one filter is a pixel function switched by a drop-down and a
## checkbox.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## In a directory of its own rather than beside the other fixtures, so that no
## scenario loading `res://tests/fixtures/modules` gains a Filter menu row it
## did not have. the scenario reaches it with
## `--modules-dir=res://tests/fixtures/switch-filter/modules`. The id is the directory
## name, because the shader index files the generated kernel under it.
extends SaModule


func get_id() -> StringName:
    return &"switch-filter-fixture"


func get_name() -> String:
    return "Switch Filter Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    var here: String = get_script().resource_path.get_base_dir()
    ctx.register_filter(SaPixelFilter.new(here.path_join("switched.gmacs")))
