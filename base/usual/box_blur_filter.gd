## Filter > Blur > Box Blur, a flat average of each pixel's neighbours in a
## square, beside Gaussian Blur.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One neighbourhood pass over `box_blur.gmacs`, whose header says how a square
## is summed as a row and then a column.
extends SaFilter

const SHADER := "sara-base-modules/box_blur"
## The key the filter had when it was a module of its own, which documents
## saved then still name for a layer's attachment and an effect layer.
const FORMER_KEY: StringName = &"box_blur.box_blur"


# The menu's word and the window's title, written the way every other row of
# the Filter menu is. The id is made from it, `box_blur`.
func title() -> String:
    return "Box Blur"


# What the menu row's tooltip and Browse Filters say the filter does.
func sentence() -> String:
    return "Soften the picture with a flat average of each pixel's neighbours in a square whose reach is the radius, in pixels."


# The Blur section, beside Gaussian Blur and the base module's other blurs.
func family() -> StringName:
    return &"blur"


# A record saved under the former key opens as this filter, its radius as it
# was saved.
func reads_records_of() -> Array[StringName]:
    return [FORMER_KEY]


# The dialog adds the title, the thumbnail, the Preview box and the buttons,
# and the filter keeps the radius, so this is the whole of the dialog.
func build(ui: SaDialog) -> void:
    ui.slider("Radius", 1, 20, 3, {"hard_max": 200})


# One neighbourhood pass of three steps, across, down and the blend, whose
# reach together is the radius. A pixel function is one function a texel and
# so could only sum the whole square, which at the typed ceiling of 200 asked
# for 160,801 reads a texel and stalled the frame for seconds.
func run(ctx: SaFilterContext) -> void:
    var radius := int(parameter(&"radius"))
    ctx.neighbourhood_pass(SHADER, "blur_across", {"radius": radius}, radius)
    ctx.neighbourhood_step("blur_down", {"radius": radius})
    ctx.neighbourhood_step("blur", {"radius": radius})
