## Filter > Bloom, a glow that starts where a value passes a threshold.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The part of each channel above the threshold, in linear light, is blurred
## over the radius and added back, so a paint that is brighter than the
## threshold throws light onto its neighbours and a layer wholly under it comes
## out as it went in. Sara stores values past 1 unclamped, so a threshold may
## sit above 1 and only an HDR colour glows.
##
## One neighbourhood pass over `bloom.gmacs`, which serves the attached filter
## and the one-shot alike. The radius is the halo the pass declares, so the
## glow reaches past the paint that made it by exactly the radius and no
## further (hard rule 2).
class_name SaBloomFilter
extends SaFilter

const SHADER := "sara-base-modules/bloom"
const DEFAULT_RADIUS := 20.0
const DEFAULT_THRESHOLD := 1.0
const DEFAULT_STRENGTH := 1.0

## How many floats `SaColorSpacePushConstant` writes, and how many are one matrix.
const TAIL_FLOATS := 24
const MATRIX_FLOATS := 9


func title() -> String:
    return "Bloom"


## Listed under Blur in the Filter menu and the browser, beside the blurs whose
## kernel it shares the shape of.
func family() -> StringName:
    return &"blur"


func sentence() -> String:
    return "Spread the values brighter than the threshold into a glow whose reach is the radius, in pixels."


func build(ui: SaDialog) -> void:
    ui.title(title())
    ui.slider("Threshold", 0.0, 4.0, DEFAULT_THRESHOLD, {"hard_max": 1000, "step": 0.05, "decimals": 2})
    ui.slider("Radius", 1, 50, DEFAULT_RADIUS, {"hard_max": 200, "suffix": " px"})
    ui.slider("Strength", 0.0, 4.0, DEFAULT_STRENGTH, {"hard_max": 16, "step": 0.05, "decimals": 2})


func run(ctx: SaFilterContext) -> void:
    var reach := int(parameter(&"radius"))
    var params := params_for(float(parameter(&"threshold")), reach, float(parameter(&"strength")), _space_of(ctx))
    ctx.neighbourhood_pass(SHADER, "bloom", params, reach)


## The kernel's params by name: the sliders and the colour space tail.
## `origin` and `halo` are the Runner's and are written per dispatch.
static func params_for(threshold: float, radius: int, strength: float, space: SaColorSpace) -> Dictionary:
    var tail := SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb())
    var params := {"threshold": threshold, "radius": radius, "strength": strength}
    if tail.size() < TAIL_FLOATS:
        return params
    params["doc_to_linear_srgb"] = tail.slice(0, MATRIX_FLOATS)
    params["linear_srgb_to_doc"] = tail.slice(MATRIX_FLOATS, MATRIX_FLOATS * 2)
    params["transfer_slope"] = tail[18]
    params["transfer_threshold"] = tail[19]
    params["transfer_gain"] = tail[20]
    params["transfer_exponent"] = tail[21]
    params["coordinates"] = tail[22]
    return params


## The space the document stores its colours in, or null for a context with no
## document, which reads as gamma sRGB.
static func _space_of(ctx: SaFilterContext) -> SaColorSpace:
    return ctx.document.color_space if ctx.document != null else null
