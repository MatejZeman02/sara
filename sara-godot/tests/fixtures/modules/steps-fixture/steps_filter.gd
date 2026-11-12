## The filter the suite runs. With one step it copies, reading the previous
## binding, which a list of one binds to the source. With several it shifts the
## source one texel right per middle step and ends in a step that writes the
## shifted red beside the source's own green, so the answer says how many steps
## ran, in which order, and that the last still reads the source.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaFilter

## How many steps the pass lists, one or at least three.
var steps: int = 1


func title() -> String:
    return "Steps Fixture"


func build(ui: SaDialog) -> void:
    ui.title("Steps Fixture")
    ui.preview()
    ui.apply_cancel()


func parameters() -> Dictionary:
    return {"steps": steps}


func set_parameters(values: Dictionary) -> void:
    steps = int(values.get("steps", steps))


func run(ctx: SaFilterContext) -> void:
    if steps <= 1:
        ctx.neighbourhood_pass("steps", "copy", {}, 2)
        return
    ctx.neighbourhood_pass("steps", "shift", {}, steps - 1)
    for _index in range(steps - 2):
        ctx.neighbourhood_step("shift", {})
    ctx.neighbourhood_step("last", {})
