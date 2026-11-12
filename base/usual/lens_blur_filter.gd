## Filter > Lens Blur: a flat disc, the shape a round aperture throws a point
## into.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One neighbourhood pass over `lens_blur.gmacs`, which serves the attached
## filter and the one-shot alike: the compositor evaluates the record `run`
## leaves, and Apply walks the same record over the layer.
class_name SaLensBlurFilter
extends SaFilter

const SHADER := "sara-base-modules/lens_blur"
const DEFAULT_RADIUS := 8.0


func title() -> String:
    return "Lens Blur"


## Listed under Blur in the Filter menu and the browser.
func family() -> StringName:
    return &"blur"


func sentence() -> String:
    return "Spread every pixel into a flat disc of the radius, the way an out-of-focus lens does."


func build(ui: SaDialog) -> void:
    ui.title(title())
    # The soft range stops at 32 because the disc costs (2r + 1) squared reads
    # a texel, 4225 there, and the hard maximum is for a painter who asks.
    ui.slider("Radius", 1, 32, DEFAULT_RADIUS, {"hard_max": 100})


func run(ctx: SaFilterContext) -> void:
    var r := float(parameter(&"radius"))
    ctx.neighbourhood_pass(SHADER, "lens_blur", {"radius": r}, ceili(r))
