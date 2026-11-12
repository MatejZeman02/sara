## Filter > Gaussian Blur, the first of the usual set.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One neighbourhood pass over `gaussian_blur.gmacs`, which serves the attached
## filter and the one-shot alike: the compositor evaluates the record `run`
## leaves, and Apply walks the same record over the layer. The kernel is
## separable inside its one dispatch, and its header says how.
class_name SaGaussianBlurFilter
extends SaFilter

const SHADER := "sara-base-modules/gaussian_blur"
const DEFAULT_RADIUS := 10.0


func title() -> String:
    return "Gaussian Blur"


## Listed under Blur in the Filter menu and the browser.
func family() -> StringName:
    return &"blur"


func sentence() -> String:
    return "Soften the picture with a bell-shaped blur whose reach is the radius, in pixels."


func build(ui: SaDialog) -> void:
    ui.title(title())
    # Tenths of a pixel, because a soft blur under 2 px is the one a painter
    # reaches for most and 1.5 is a blur of its own.
    ui.slider("Radius", 1, 50, DEFAULT_RADIUS, {"hard_max": 200, "suffix": " px", "step": 0.1, "decimals": 1})


## The radius goes to the kernel with its fraction, and the pass reads its
## neighbours out to the radius rounded up, the last tap the bell reaches.
func run(ctx: SaFilterContext) -> void:
    var radius := float(parameter(&"radius"))
    ctx.neighbourhood_pass(SHADER, "gaussian_blur", {"radius": radius}, ceili(radius))
