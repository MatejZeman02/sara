## The filter class after step 4 of the guide, typed as the guide prints it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `build` is the guide's own block, copied whole, down to the argument lists,
## and `run` carries the `set_params` line step 4 prints. The kernel beside it
## declares `float strength` beside `int radius`, which is the third of step 4's
## three edits.
##
## **A filter without the kernel's `params:` block is refused.** Every run is
## refused by `SaPushConstants.complaint` for a name the block did not declare,
## with an empty preview. Step 4 prints all three edits, and this fixture is
## what following it produces.
##
## No `class_name`: the shipped `BoxBlur` already holds that one, and a fixture
## that took a global name would decide which of the two a student's `BoxBlur`
## meant.
extends SaFilter

var radius: SaSlider
var strength: SaSlider


func title() -> String:
    return "Box blur"


func build(ui: SaDialog) -> void:
    ui.title("Box blur")
    ui.preview()
    radius = ui.slider("Radius", 1, 20, 3, {"hard_max": 200})
    strength = ui.slider("Strength", 0.0, 1.0, 1.0)
    ui.apply_cancel()


func run(ctx: SaFilterContext) -> void:
    var src: SaTexture = ctx.layer_pixels(radius.value)
    var dst: SaTexture = ctx.blank_like(src)
    var kernel: SaCompute = ctx.kernel("blur")
    kernel.set_image("src", src)
    kernel.set_image("dst", dst)
    kernel.set_params({"radius": radius.value, "strength": strength.value})
    kernel.dispatch("blur", src.size)
    ctx.show(dst)
