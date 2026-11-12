## A filter written the way the guide's third door is written.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `read_pixels`, a loop, `write_pixels`, and a slider so a scenario has
## something to change. That is the shape the guide prints and the shape this
## is about: the dialog calls `run` when it opens and after every change, so a
## `write_pixels` that wrote on the spot wrote the layer before the painter had
## touched anything and again on every slider frame.
##
## The loop is deliberately the obvious one and not a fast one. The lab it
## stands in for is the lab about writing an algorithm the readable way first.
extends SaFilter

var amount: SaSlider = null

## How many times the dialog asked for a run, so a scenario can say the runs
## happened and the writes did not.
var runs: int = 0


func title() -> String:
    return "Cpu invert"


func build(ui: SaDialog) -> void:
    ui.title("Cpu invert")
    ui.preview()
    amount = ui.slider("Amount", 0.0, 1.0, 1.0, {"step": 0.05, "decimals": 2})
    ui.apply_cancel()


func run(ctx: SaFilterContext) -> void:
    runs += 1
    var pixels := ctx.read_pixels(0)
    if pixels == null:
        return
    var mix := float(amount.value)
    for y in pixels.get_height():
        for x in pixels.get_width():
            var here := ctx.pixel(pixels, Vector2i(x, y))
            pixels.set_pixel(
                x,
                y,
                Color(
                    lerpf(here.r, 1.0 - here.r, mix), lerpf(here.g, 1.0 - here.g, mix), lerpf(here.b, 1.0 - here.b, mix), here.a
                )
            )
    ctx.write_pixels(pixels)
