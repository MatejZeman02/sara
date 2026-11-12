## A module whose one filter is a pixel function with a colour tagged
## `source_color`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/modules`, which is the flag
## `core/loader/module_loader.gd` reads. The tag makes the dialog's swatch, the
## untagged vector beside it earns none in a source that hints, and the swatch's
## numbers reach the kernel as they are shown.
extends SaModule


func get_id() -> StringName:
    return &"colour-filter-fixture"


func get_name() -> String:
    return "Colour Filter Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    var here: String = get_script().resource_path.get_base_dir()
    ctx.register_filter(SaPixelFilter.new(here.path_join("tint.gmacs")))
