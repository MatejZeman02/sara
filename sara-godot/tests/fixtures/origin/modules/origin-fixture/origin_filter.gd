## The filter the scenario runs: one kernel that paints where it thinks it is.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Written the way the box blur is written, because that is the shape the door
## is measured against: the widget declared in `build`, read in `run`, one
## kernel, one `ctx.show`. What it is not is an example of anything worth
## copying. It shows the rectangle's own position as a colour, so a texel read
## after Apply says where the dispatch ran and not merely that it ran.
##
## The red and green channels carry the origin in document pixels, unscaled,
## because the canvas is float throughout and an out-of-range value survives
## paint, composite and readback by hard rule 5. So a texel that reads 512 is
## the answer in the units the question was asked in, and the preview showing
## it as white is the preview doing what it should with a colour past one.
extends SaFilter

var scale: SaSlider


func title() -> String:
    return "Where am I"


func build(ui: SaDialog) -> void:
    ui.title("Where am I")
    ui.preview()
    scale = ui.slider("Scale", 1, 4, 1)
    ui.apply_cancel()


func run(ctx: SaFilterContext) -> void:
    var src: SaTexture = ctx.layer_pixels(0)
    var dst: SaTexture = ctx.blank_like(src)
    var kernel: SaCompute = ctx.kernel("at_origin")
    kernel.set_image("dst", dst)
    kernel.dispatch("at_origin", src.size)
    ctx.show(dst)
