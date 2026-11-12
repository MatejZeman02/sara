## Filter > Hot Pixels, a sensor's stuck texels taken out and nothing else.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A hot pixel is one bright dot, and a denoise blurs it into a smudge while
## softening every texel round it. This replaces a texel that stands further
## than the threshold from every one of its eight neighbours by their median,
## channel by channel, and leaves every other texel exactly as it was, so the
## halo is one texel. A block of bright texels and a flat area above white keep
## every texel, since each of them has a neighbour like it. `hot_pixels.gmacs`
## says how.
##
## The threshold is a percentage of white in the document's stored values, with
## room above a hundred, because a dot in a radiance picture stands several
## whites from its neighbours and a threshold that stopped at one could not tell
## it from one that stands one white apart. Nothing clamps.
class_name SaHotPixelsFilter
extends SaFilter

const DEFAULTS := {"threshold": 20.0}

## The radius declared to the neighbourhood pass, in document pixels: the eight
## taps sit one texel from the one written.
const RADIUS := 1
## The shader file, by the key the shader index files it under.
const SHADER := "hot_pixels"


func title() -> String:
    return "Hot Pixels"


## Listed under Noise in the Filter menu and the browser, beside the denoises.
func family() -> StringName:
    return &"noise"


func sentence() -> String:
    return "Remove single pixels that stand apart from all their neighbours, and leave every other pixel as it was."


func build(ui: SaDialog) -> void:
    ui.slider("Threshold", 0, 100, int(DEFAULTS["threshold"]), {"hard_max": 10000, "suffix": " %"})


## One neighbourhood pass for Apply and the attached form alike. The canvas goes
## with it, so the kernel leaves out a neighbour past the edge rather than read
## the copy of the edge the runner pads with there.
func run(ctx: SaFilterContext) -> void:
    var params := {
        "threshold": float(parameter(&"threshold")) / 100.0,
        "canvas": Vector2(ctx.canvas_size()),
    }
    ctx.neighbourhood_pass(SHADER, "hot_pixels", params, RADIUS)
