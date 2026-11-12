## Filter > Wavelet Denoise.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The third denoise, beside the Gaussian and the mean. The layer is split
## into details at `levels` scales by the a trous wavelet, each detail loses
## what lies under a threshold that halves from the finest scale to the
## coarsest, and the rest is summed back. Sensor grain lives in the finest
## details and is cut hardest, an edge is a large detail and is kept.
## `wavelet_denoise.gmacs` says how.
##
## The tiles are the chunks and the overlap is the halo. The cascade reaches
## `2 * (2^levels - 1)` texels, 30 at four levels and 62 at five, so the pass
## declares that radius and every chunk reads one ring of its neighbours, which
## is what makes a texel the same whether the run covered its chunk alone or
## the chunks around it too. A tile size of the filter's own was the rejected
## alternative: a second grid beside the chunk grid, and an attached form that
## reads a rectangle the compositor never asked for.
##
## Both forms come from [method run], one step of a neighbourhood pass per
## level, so the attached filter and the one-shot cannot disagree.
class_name SaWaveletDenoiseFilter
extends SaFilter

const DEFAULTS := {"levels": 4.0, "strength": 30.0}
## The finest level's threshold at full strength, in premultiplied colour.
const FINEST_AT_FULL: float = 0.1


func title() -> String:
    return "Wavelet Denoise"


## Listed under Noise in the Filter menu and the browser, beside Denoise.
func family() -> StringName:
    return &"noise"


func sentence() -> String:
    return "Take the grain out at several scales at once and keep the edges, finest grain first."


func build(ui: SaDialog) -> void:
    ui.slider("Levels", 1, 5, int(DEFAULTS["levels"]))
    ui.slider("Strength", 0, 100, int(DEFAULTS["strength"]), {"suffix": " %"})


func run(ctx: SaFilterContext) -> void:
    var levels := int(parameter(&"levels"))
    var threshold := float(parameter(&"strength")) / 100.0 * FINEST_AT_FULL
    ctx.neighbourhood_pass("wavelet_denoise", _kernel(0, levels), {"level": 0, "threshold": threshold}, reach(levels))
    for level in range(1, levels):
        ctx.neighbourhood_step(_kernel(level, levels), {"level": level, "threshold": threshold})


## How far a cascade of *levels* reads, in texels: the spline's two taps at
## every spacing from 1 to `2^(levels - 1)`.
static func reach(levels: int) -> int:
    return 2 * ((1 << levels) - 1)


## The kernel of *level*'s step in a cascade of *levels*: the last writes the
## chunk and every one before it the scratch.
static func _kernel(level: int, levels: int) -> String:
    return "wavelet_last" if level == levels - 1 else "wavelet_level"
