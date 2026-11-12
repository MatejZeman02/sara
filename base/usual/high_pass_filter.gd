## Filter > High Pass, the picture less its Gaussian blur, drawn about a
## neutral grey and laid over the picture in Overlay or Soft Light as a
## sharpen, or drawn as the map alone.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The picture minus that blur and nothing else, live and redrawn by patch.
## One neighbourhood pass over `high_pass.gmacs`, which serves the attached
## filter, the filter layer and the one-shot alike, and whose blur is the
## Gaussian blur's own arithmetic, so the map and the Gaussian blur at one
## radius add back to the picture. The radius is the halo the pass declares
## (hard rule 2).
##
## A flat area's map reads [const NEUTRAL] in the document's RGB view, the grey
## Soft Light and Overlay leave a backdrop alone for, so the map laid over the
## picture in either is a local contrast tool. The kernel lays it there itself,
## by the compositor's own blend in the Mode at the Amount's opacity, so Apply
## sharpens the layer in one step, as the Laplacian beside it does. Show the raw
## map writes the map alone. Nothing clamps: an edge above one reads past the
## neutral by its whole difference.
class_name SaHighPassFilter
extends SaFilter

const SHADER := "sara-base-modules/high_pass"
const DEFAULT_RADIUS := 10.0

## What a flat area reads, in the document's RGB view, at the blend reference
## white of one a document starts with. The kernel holds the same number and
## scales it by a wider white, because both blends window their inputs by that
## white and leave a backdrop alone for half of it.
const NEUTRAL := 0.5

## The blends the map is laid over the picture in, by the id a record keeps.
const OVERLAY := "overlay"
const SOFT_LIGHT := "soft_light"
const MODES: Array = [
    {"id": OVERLAY, "label": "Overlay"},
    {"id": SOFT_LIGHT, "label": "Soft Light"},
]
const DEFAULT_MODE := OVERLAY
## The Amount slider's start, in percent: the map at full opacity.
const DEFAULT_AMOUNT := 100
## The raw map's label. Its key is `raw`, rather than the label snake-cased,
## the Laplacian's key as well.
const RAW_LABEL := "Show the raw map"

## How many floats `SaColorSpacePushConstant` writes, and how many are one matrix.
const TAIL_FLOATS := 24
const MATRIX_FLOATS := 9


func title() -> String:
    return "High Pass"


## Listed under Sharpen in the Filter menu and the browser, since it sharpens.
func family() -> StringName:
    return &"sharpen"


func sentence() -> String:
    return (
        "Sharpen with the picture less its Gaussian blur, laid over the picture in the Mode at the "
        + "Amount. Show the raw map draws the detail alone around mid grey."
    )


func build(ui: SaDialog) -> void:
    ui.title(title())
    ui.slider("Radius", 1, 50, DEFAULT_RADIUS, {"hard_max": 200, "suffix": " px"})
    ui.dropdown("Mode", MODES, DEFAULT_MODE).named(&"mode")
    ui.slider("Amount", 0, 100, DEFAULT_AMOUNT, {"suffix": "%"})
    ui.checkbox(RAW_LABEL, false).named(&"raw")


func run(ctx: SaFilterContext) -> void:
    var reach := int(parameter(&"radius"))
    var params := params_for(reach, _space_of(ctx))
    params.merge(laying_params_for(parameters(), ctx.document))
    ctx.neighbourhood_pass(SHADER, "high_pass", params, reach)


## The map's params by name: the radius and the colour space tail.
## `origin` and `halo` are the Runner's and are written per dispatch.
static func params_for(radius: int, space: SaColorSpace) -> Dictionary:
    var tail := SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb())
    var params := {"radius": radius}
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


## How the map is laid over the picture, from *values* in the record's own
## units over *document*: the mode as 0 for Overlay and 1 for Soft Light, the
## amount as an opacity from 0 to 1, the raw map as 1 or 0, and the document's
## blend reference white, which both blends read their inputs against. A null
## document has a white of one.
static func laying_params_for(values: Dictionary, document: SaDocument) -> Dictionary:
    return {
        "mode": 1.0 if values.get("mode", DEFAULT_MODE) == SOFT_LIGHT else 0.0,
        "amount": clampf(float(values.get("amount", DEFAULT_AMOUNT)), 0.0, 100.0) / 100.0,
        "raw": 1.0 if bool(values.get("raw", false)) else 0.0,
        "blend_white": document.blend_reference_white if document != null else 1.0,
    }


## The space the document stores its colours in, or null for a context with no
## document, which reads as gamma sRGB.
static func _space_of(ctx: SaFilterContext) -> SaColorSpace:
    return ctx.document.color_space if ctx.document != null else null
