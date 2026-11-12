## A module whose simulation rule is a pixel function, the Game of Life in a
## file of eighteen lines, and whose one filter is a pixel function that reads
## its time.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## In a directory of its own rather than beside the other fixtures, so that no
## scenario loading `res://tests/fixtures/modules` gains a rule or a Filter
## menu row it did not have. the scenario reaches it with
## `--modules-dir=res://tests/fixtures/life-pixel/modules`. The id is the directory
## name, because the shader index files the generated kernels under it.
extends SaModule

const PixelFunction := preload("res://core/custom-shader/compiler/sa_pixel_function.gd")

## The rule's key, which the suite and the scenario put on a layer by.
const LIFE: StringName = &"life_pixels"


func get_id() -> StringName:
    return &"life-pixel-fixture"


func get_name() -> String:
    return "Life Pixel Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    var here: String = get_script().resource_path.get_base_dir()
    PixelFunction.register_rule(ctx, here.path_join("life.gmacs"), LIFE, "Life in Pixels", 1)
    ctx.register_filter(SaPixelFilter.new(here.path_join("clock.gmacs")))
