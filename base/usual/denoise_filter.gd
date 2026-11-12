## Filter > Denoise, Gaussian and mean.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One filter with a kind and a radius, and a threshold that is what makes it a
## denoise rather than a blur: every texel is smoothed over the square of side
## `2 * radius + 1`, by equal weights for Mean and by a Gaussian of sigma
## `radius / 2` for Gaussian, and then mixed back towards what it was by how far
## the smoothing moved it. Grain moves a texel a little and is taken out, an
## edge moves it a lot and is kept. `denoise.gmacs` says how.
##
## Both forms come from [method run]: the one-shot form through Apply and the
## attached form through the compositor's chain record the same neighbourhood
## pass, so the two cannot disagree about what a radius meant. The Gaussian blur
## is this arithmetic with no threshold and two separable passes, and neither
## row reads the other's file.
class_name SaDenoiseFilter
extends SaFilter

## The kinds, in the dropdown's order and by the number the kernel reads.
const KINDS: Array[String] = ["gaussian", "mean"]
const DEFAULTS := {"kind": "gaussian", "radius": 3.0, "threshold": 10.0}


func title() -> String:
    return "Denoise"


## Listed under Noise in the Filter menu and the browser.
func family() -> StringName:
    return &"noise"


func sentence() -> String:
    return "Smooth the grain out of an area and leave its edges, by a Gaussian or a plain average over a radius."


func build(ui: SaDialog) -> void:
    var kinds := [{"id": "gaussian", "label": "Gaussian"}, {"id": "mean", "label": "Mean"}]
    ui.dropdown("Type", kinds, DEFAULTS["kind"]).named(&"kind")
    ui.slider("Radius", 1, 20, int(DEFAULTS["radius"]), {"hard_max": 200, "suffix": " px"})
    ui.slider("Threshold", 0, 100, int(DEFAULTS["threshold"]), {"suffix": " %"})


func run(ctx: SaFilterContext) -> void:
    var reach := int(parameter(&"radius"))
    var params := {
        "radius": reach,
        "kind": maxi(KINDS.find(String(parameter(&"kind"))), 0),
        "threshold": float(parameter(&"threshold")) / 100.0,
    }
    ctx.neighbourhood_pass("denoise", "denoise", params, reach)
