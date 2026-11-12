## A module whose one filter is a pixel function and nothing else.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/modules`, which is the flag
## `core/loader/module_loader.gd` reads.
##
## **There is no filter class file beside this one**, and that absence is the
## whole claim of the unit. The directory holds a module and a `.gmacs`, the
## registration is the file's path handed to `ctx.register_filter` through the
## same door a written filter goes through, and the dialog with its slider
## is generated from the one `uniform` line.
##
## The id has to stay the directory name. The shader index takes a shader's
## owner from the directory it lives under, and the generated kernel is filed
## under that owner too.
extends SaModule


func get_id() -> StringName:
    return &"pixel-filter-fixture"


func get_name() -> String:
    return "Pixel Filter Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    var here: String = get_script().resource_path.get_base_dir()
    ctx.register_filter(SaPixelFilter.new(here.path_join("threshold.gmacs")))
