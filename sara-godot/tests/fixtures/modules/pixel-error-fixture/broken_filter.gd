## The filter the fixture module registers: a pixel function whose third line
## returns a `vec3` from a function declared `vec4`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## This is the shape a generated filter takes rather than a class anybody writes by
## hand, and it is written out here because the claim is
## about what a failed compile does, not about how the filter was built.
##
## `problem()` recompiles when the file has changed and answers the first error,
## so the menu asking it on every open is the whole of "a recompile on the next
## open clears it when the file was fixed".
extends SaFilter

const PixelFunction = preload("res://core/custom-shader/compiler/sa_pixel_function.gd")

## The pixel function beside this file, loaded and compiled once at
## construction. Compiling in `_init` rather than lazily is what puts the
## failure before the registration, which is the case the fixture exists for.
var pixels: PixelFunction = null


func _init() -> void:
    pixels = PixelFunction.new(get_script().resource_path.get_base_dir().path_join("broken.gmacs"))
    pixels.compile()


func title() -> String:
    return "Broken Threshold"


func problem() -> String:
    pixels.reload_if_changed()
    return pixels.first_error()


func run(ctx: SaFilterContext) -> void:
    pixels.run_on(ctx)
