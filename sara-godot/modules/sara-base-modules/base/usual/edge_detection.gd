## Filter > Edge Detection, the Sobel of the usual set.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An output texel reads its eight neighbours, so this is a neighbourhood
## filter: it records a neighbourhood pass and declares a radius of one texel,
## which is the ring the dispatch grows by, and the one-shot form and the
## attached form are the same `run` through the same Runner.
class_name SaEdgeDetectionFilter
extends SaFilter

const DEFAULT_STRENGTH := 1.0

## The radius declared to the neighbourhood pass, in document pixels: the
## Sobel reads one texel either side of the one it writes.
const RADIUS := 1
## The shader file, by the key the shader index files it under.
const SHADER := "edge_detection"

## How many floats `SaColorSpacePushConstant` writes.
const TAIL_FLOATS := 24
## How many of them are one matrix.
const MATRIX_FLOATS := 9


func title() -> String:
    return "Edge Detection"


## Listed under Stylize in the Filter menu and the browser.
func family() -> StringName:
    return &"stylize"


func sentence() -> String:
    return "Show edges as grey lines, brightest where the image changes most sharply."


func build(ui: SaDialog) -> void:
    ui.slider("Strength", 0.0, 4.0, DEFAULT_STRENGTH, {"hard_max": 16})


func run(ctx: SaFilterContext) -> void:
    ctx.neighbourhood_pass(SHADER, "edge_detection", params_for(float(parameter(&"strength")), _space_of(ctx)), RADIUS)


## The kernel's params by name: *value* as the strength and the colour space
## tail. `origin` and `halo` are the Runner's and are written per dispatch.
##
## The tail goes in as named fields rather than as one array because the pass
## packs by name, and the split is spelled out here rather than read off
## `adjust.gmacs` so a reader of this file can see what the kernel declares.
## *value* rather than `strength`, which is the slider's own name.
static func params_for(value: float, space: SaColorSpace) -> Dictionary:
    var tail := SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb())
    if tail.size() < TAIL_FLOATS:
        return {"strength": value}
    return {
        "strength": value,
        "doc_to_linear_srgb": tail.slice(0, MATRIX_FLOATS),
        "linear_srgb_to_doc": tail.slice(MATRIX_FLOATS, MATRIX_FLOATS * 2),
        "transfer_slope": tail[18],
        "transfer_threshold": tail[19],
        "transfer_gain": tail[20],
        "transfer_exponent": tail[21],
        "coordinates": tail[22],
    }


## The space the document stores its colours in. A context built with no document
## answers null, and the tail is gamma sRGB then.
static func _space_of(ctx: SaFilterContext) -> SaColorSpace:
    return ctx.document.color_space if ctx.document != null else null
