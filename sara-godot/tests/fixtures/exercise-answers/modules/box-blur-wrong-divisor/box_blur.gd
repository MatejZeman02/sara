## The exercise's box blur, line for line, with one number wrong.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Everything here is the box blur the scripting guide prints except the title, which
## has to differ so the two register under different keys. The mistake is in the
## kernel beside this file and not in this one, because the mistake the exercise
## warns about is arithmetic and not wiring: a radius of 24 is a box 49 across,
## which is 2401 texels and not 576, and a picture divided by 576 looks like a
## bad exposure rather than like a bug.
extends SaFilter

var radius: SaSlider


func title() -> String:
    return "Box blur with a wrong divisor"


func build(ui: SaDialog) -> void:
    ui.title("Box blur")
    ui.preview()
    radius = ui.slider("Radius", 1, 20, 3, {"hard_max": 200})
    ui.apply_cancel()


func run(ctx: SaFilterContext) -> void:
    var src := ctx.layer_pixels(radius.value)
    var dst := ctx.blank_like(src)
    var kernel := ctx.kernel("blur")
    kernel.set_image("src", src)
    kernel.set_image("dst", dst)
    kernel.set_params({"radius": radius.value})
    kernel.dispatch("blur", src.size)
    ctx.show(dst)
