## Filter > Colour > Red-eye Removal, the red taken out of a pupil.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A filter writes through the selection, so a marquee round the eyes says
## where. Inside it, a texel whose red stands at least Threshold times above
## the larger of its green and blue, in linear light, has its red brought down
## towards the mean of the two by Strength, so a red pupil turns a dark
## neutral and skin, whose red is two or three times its green, is left as it
## was. Every output texel reads only its own input texel, so this is a point
## filter: it records a point pass, the compositor previews it, Apply walks it,
## and it declares no radius. The kernel is `red_eye_removal.gmacs`, which says
## how the weight fades in above the threshold, and nothing clamps (hard rule
## 5).
class_name SaRedEyeRemovalFilter
extends SaFilter

## The shader file, by the key the shader index files it under.
const SHADER := "red_eye_removal"
const KERNEL := "red_eye_removal"
## Where the push constant keeps the dispatched region's origin, x then y.
const ORIGIN_SLOT := 0

## Threshold is a ratio of light, red over the larger of green and blue. Four
## sits above the three or so the darkest and ruddiest skin reaches and below
## the six and more of a pupil lit red by a flash. Strength is in percent.
const DEFAULTS := {"threshold": 4.0, "strength": 100}
## Below a ratio of one red is not above its other channels at all, and the
## kernel's fade needs a threshold above nought.
const LEAST_THRESHOLD := 1.0
const SOFT_MOST_THRESHOLD := 10.0
const HARD_MOST_THRESHOLD := 100.0


func title() -> String:
    return "Red-eye Removal"


## Listed under Colour, beside the adjustments a painter sets by hand.
func family() -> StringName:
    return &"color"


func sentence() -> String:
    return "Take the red out of red eyes in the selection, leaving skin alone, so a red pupil turns a dark neutral."


func build(ui: SaDialog) -> void:
    var threshold_options := {"hard_max": HARD_MOST_THRESHOLD, "step": 0.1, "decimals": 1, "suffix": "×"}
    ui.slider("Threshold", LEAST_THRESHOLD, SOFT_MOST_THRESHOLD, DEFAULTS["threshold"], threshold_options)
    ui.slider("Strength", 0, 100, DEFAULTS["strength"], {"suffix": " %"})


func run(ctx: SaFilterContext) -> void:
    var space := ctx.document.color_space if ctx.document != null else null
    ctx.point_pass(SHADER, KERNEL, push_for(parameters(), space), {}, ORIGIN_SLOT)


## The 112-byte push constant `red_eye_removal.gmacs` reads, from *values* in
## the record's own units, on a document stored in *space*: the region's
## origin, which the runner writes at [constant ORIGIN_SLOT], the threshold as a
## ratio, the strength as a fraction, then the colour space tail exactly as
## `SaColorSpacePushConstant` writes it.
static func push_for(values: Dictionary, space: SaColorSpace) -> PackedFloat32Array:
    var threshold := maxf(float(values.get("threshold", DEFAULTS["threshold"])), LEAST_THRESHOLD)
    var strength := clampf(float(values.get("strength", DEFAULTS["strength"])) / 100.0, 0.0, 1.0)
    var push := PackedFloat32Array([0.0, 0.0, threshold, strength])
    push.append_array(SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb()))
    return push
