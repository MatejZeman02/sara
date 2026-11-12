## Filter > Tone > Posterize, every channel cut to a few even levels.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Each channel of the document's RGB view is rounded to the nearest of Levels
## even steps of its encoded value, the encoding Dither quantises in, so on an
## Oklab document the steps are those of the picture the painter sees. Every
## output texel reads only its own input texel, so this is a point filter: it
## records a point pass, the compositor previews it and Apply walks it, and it
## declares no radius, which is what lets an adjustment layer and an attached
## record hold it. The kernel is `posterise.gmacs`.
##
## Dither at Strength 0 does the same sum, but it is a finishing filter that
## always runs last and is listed under Stylize, and its title never says the
## word a painter searches for. This one runs where it stands in a chain, and
## nothing clamps (hard rule 5): a value above one lands on the next step
## beyond it.
class_name SaPosteriseFilter
extends SaFilter

## The shader file, by the key the shader index files it under.
const SHADER := "posterise"
const KERNEL := "posterise"
## Where the push constant keeps the dispatched region's origin, x then y.
const ORIGIN_SLOT := 0

const DEFAULTS := {"levels": 4}


func title() -> String:
    return "Posterize"


## The key is British where the title is American, because saved records,
## adjustment layers and scenarios on a painter's disk name the filter by it.
func id() -> StringName:
    return &"posterise"


## Listed under Tone, beside the adjustments a painter sets by hand.
func family() -> StringName:
    return &"tone"


func sentence() -> String:
    return "Cut every channel to a few even levels, for flat bands of colour."


func build(ui: SaDialog) -> void:
    ui.slider("Levels", 2, 16, DEFAULTS["levels"], {"hard_max": 256})


func run(ctx: SaFilterContext) -> void:
    var space := ctx.document.color_space if ctx.document != null else null
    ctx.point_pass(SHADER, KERNEL, push_for(parameters(), space), {}, ORIGIN_SLOT)


## The 112-byte push constant `posterise.gmacs` reads, from *values* in the
## record's own units, on a document stored in *space*: the region's origin,
## which the runner writes at [constant ORIGIN_SLOT], the levels, a spare, then
## the colour space tail exactly as `SaColorSpacePushConstant` writes it.
static func push_for(values: Dictionary, space: SaColorSpace) -> PackedFloat32Array:
    var levels := clampf(float(values.get("levels", DEFAULTS["levels"])), 2.0, 256.0)
    var push := PackedFloat32Array([0.0, 0.0, levels, 0.0])
    push.append_array(SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb()))
    return push
