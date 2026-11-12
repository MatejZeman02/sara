## Filter > Laplacian, the second derivative of the usual set, laid over the
## picture in Overlay as a sharpen, or drawn as the detail map alone.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An output texel reads its four neighbours, so this is a neighbourhood filter
## of radius one, the same shape as Edge Detection beside it under Stylize and
## through the same Runner for the one-shot and the attached form.
##
## Edge Detection is the first derivative as a grey magnitude. This is the
## second, kept signed around a neutral: the kernel reads lightness, and takes a
## grey of the neutral plus the strength times the texel less the mean of its
## four neighbours. A flat area reads the neutral everywhere, a crest reads
## above it and a trough below. That map laid over the picture in Overlay
## steepens an edge, which is a sharpen, and the kernel lays it there itself, by
## the compositor's own Overlay at the Amount's opacity, so Apply sharpens the
## layer in one step. Show the raw map writes the map alone, the detail and
## nothing laid over it.
class_name SaLaplacianFilter
extends SaFilter

const DEFAULT_STRENGTH := 1.0
## The Amount slider's start, in percent: the map at full opacity in Overlay.
const DEFAULT_AMOUNT := 100

## What a flat area reads, in the document's RGB view, at the blend reference
## white of one a document starts with. The kernel holds the same number and
## scales it by a wider white, because Overlay windows its inputs by that white
## and leaves a backdrop alone for half of it.
const NEUTRAL := 0.5

## The radius declared to the neighbourhood pass, in document pixels: the four
## taps sit one texel from the one written.
const RADIUS := 1
## The shader file, by the key the shader index files it under.
const SHADER := "laplacian"
## The raw map's label. Its key is `raw`, rather than the label snake-cased.
const RAW_LABEL := "Show the raw map"


func title() -> String:
    return "Laplacian"


## Listed under Stylize in the Filter menu and the browser, beside Edge Detection.
func family() -> StringName:
    return &"stylize"


func sentence() -> String:
    return (
        "Sharpen with the second derivative, its detail map laid over the picture in Overlay at the "
        + "Amount. Show the raw map draws the map alone around mid grey."
    )


func build(ui: SaDialog) -> void:
    ui.slider("Strength", 0.0, 4.0, DEFAULT_STRENGTH, {"hard_max": 16})
    ui.slider("Amount", 0, 100, DEFAULT_AMOUNT, {"suffix": "%"})
    ui.checkbox(RAW_LABEL, false).named(&"raw")


func run(ctx: SaFilterContext) -> void:
    ctx.neighbourhood_pass(SHADER, "laplacian", params_for(parameters(), ctx.document), RADIUS)


## *values*, the record's own units, as the kernel's params over *document*:
## Edge Detection's strength and colour space tail, the amount as an opacity
## from 0 to 1, the raw map as 1 or 0, and the document's blend reference white,
## which the compositor's Overlay reads its inputs against. A null document is
## gamma sRGB with a white of one.
static func params_for(values: Dictionary, document: SaDocument) -> Dictionary:
    var space := document.color_space if document != null else null
    var params := SaEdgeDetectionFilter.params_for(float(values.get("strength", DEFAULT_STRENGTH)), space)
    params["amount"] = clampf(float(values.get("amount", DEFAULT_AMOUNT)), 0.0, 100.0) / 100.0
    params["raw"] = 1.0 if bool(values.get("raw", false)) else 0.0
    params["blend_white"] = document.blend_reference_white if document != null else 1.0
    return params
