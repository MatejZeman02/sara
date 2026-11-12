## Filter > Blur > Low Pass, the Gaussian blur under the name a frequency
## separation uses.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## No kernel of its own, because a low pass is a blur. It runs
## [SaGaussianBlurFilter]'s `gaussian_blur.gmacs` with the same
## radius, so the broad shapes a painter separates out are the blur's own and
## the two cannot drift apart. A painter who looks for "low pass" finds it under
## that word. The radius is in document pixels, as the blur's is, and it is
## the halo it declares (hard rule 2), and nothing in the kernel clamps, so a
## value above one stays above one.
class_name SaLowPassFilter
extends SaFilter

const DEFAULT_RADIUS := 10.0


func title() -> String:
    return "Low Pass"


## Listed under Blur in the Filter menu and the browser, beside the Gaussian
## blur whose kernel it runs.
func family() -> StringName:
    return &"blur"


func sentence() -> String:
    return "Keep the broad shapes and drop the fine detail. A Gaussian blur, under the name used for frequency separation."


func build(ui: SaDialog) -> void:
    ui.title(title())
    ui.slider("Radius", 1, 50, DEFAULT_RADIUS, {"hard_max": 200, "suffix": " px"})


func run(ctx: SaFilterContext) -> void:
    var reach := int(parameter(&"radius"))
    ctx.neighbourhood_pass(SaGaussianBlurFilter.SHADER, "gaussian_blur", {"radius": reach}, reach)
