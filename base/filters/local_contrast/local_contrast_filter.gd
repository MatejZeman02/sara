## Filter > Local Contrast, darktable's local laplacian filter: detail brought
## out at every scale of a pyramid, the wide steps between tones eased, and no
## halo along a strong edge.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## darktable's local contrast module defaults to the local laplacian
## filter of Paris, Hasinoff and Kautz, and this is that method with its four
## controls by their names and defaults: Detail 125 %, which is darktable's
## clarity of 0.25, Highlights and Shadows 50 %, and Midtone range 0.5.
## `local_contrast.gmacs` says how it runs, one step of a neighbourhood pass for
## the lightness, one for each level the pyramid is reduced to and one for each
## it is collapsed from, and the last writes the chunk.
##
## darktable's pyramid runs down to one pixel, which is a whole-picture reach
## and breaks hard rule 2. Here it stops at [const LEVELS] levels, five, a
## usual starting point. The reach of five is 60 texels: the coarsest level's
## lightness reads 30 out, every expansion back up adds 2^(l + 1) at level l,
## and every finer detail reads less than that. So the pass declares
## [const RADIUS], 60, and a texel reads the same whichever chunk ran it. A
## radius short of that reach lets neighbouring chunks disagree where they
## meet, so 60 is a floor and not a taste. Nothing asks for a multiple of 16:
## every chunk's levels sit on a grid from its corner less the halo, and the
## corners are a chunk apart, 256 texels, so the grids are one grid at any halo.
## A sixth level would reach 124 and pay for a frame of 504 where five pay for
## 376, nearly twice the texels on every stroke's dirty rect, for detail coarser
## than 32 px that a painter rarely means by local contrast.
##
## The pyramid lives in a storage buffer the filter keeps, sized for the frame
## a chunk of the layer pads to and made again only when a layer's frame is
## larger than any before. The colour space tail lives in a buffer too.
##
## **The tail is a buffer and not a push constant.** On the push constant it is
## 23 named fields that every one of the nine steps of the pass carries, so a
## preview run looks each one up by name on each of its dispatches, and at 1920
## by 1080 that is 40 chunks of nine steps paying for 23 lookups each on the
## CPU, which a preview cannot afford. In one buffer bound once
## it costs one binding, and the four kernel params are all a step sets by name.
class_name SaLocalContrastFilter
extends SaFilter

const SHADER := "local_contrast"
## How many levels the pyramid holds, the finest included.
const LEVELS := 5
## The reach declared to the pass, in document pixels. See the class notes.
const RADIUS := 60
const DEFAULTS := {"detail": 125.0, "highlights": 50.0, "shadows": 50.0, "midtone_range": 0.5}
## Where the pyramid's buffer is bound, the next binding after the one a step
## reads the step before it from.
const PYRAMID_BINDING := SaNeighbourhoodPass.PREVIOUS_BINDING + 1
## Where the document's colour space is bound, the pyramid's next slot: the
## floats `SaColorSpacePushConstant` writes, read by the kernel as `space.tail`.
const SPACE_BINDING := PYRAMID_BINDING + 1
## Floats a texel of level 0 holds, and of every level above it, as the kernel
## lays them out.
const FINEST_FLOATS := 2
const COARSE_FLOATS := 8
## How many floats `SaColorSpacePushConstant` writes, and how many are one matrix.
const TAIL_FLOATS := 24
const MATRIX_FLOATS := 9
## The names [method params_for] gives the tail as params, which [method run]
## drops once they are bound as [const SPACE_BINDING] instead. [method params_for]
## still answers them, because what the record's own values mean as the kernel's
## names is its whole job and the colour tail is the kernel's other half.
const TAIL_KEYS: Array[String] = [
    "doc_to_linear_srgb",
    "linear_srgb_to_doc",
    "transfer_slope",
    "transfer_threshold",
    "transfer_gain",
    "transfer_exponent",
    "coordinates",
]

## The pyramid, kept from one run to the next. Null until the first run.
var _pyramid: SaCompute.Buffer = null


func title() -> String:
    return "Local Contrast"


## Listed under Sharpen in the Filter menu and the browser, beside Sharpen and
## High Pass.
func family() -> StringName:
    return &"sharpen"


func sentence() -> String:
    return "Bring out detail at every scale and ease the wide steps between tones, with no halo along a strong edge."


func build(ui: SaDialog) -> void:
    ui.title(title())
    ui.slider("Detail", 0, 300, int(DEFAULTS["detail"]), {"hard_max": 500, "suffix": " %"})
    ui.slider("Highlights", 0, 200, int(DEFAULTS["highlights"]), {"suffix": " %"})
    ui.slider("Shadows", 0, 200, int(DEFAULTS["shadows"]), {"suffix": " %"})
    ui.slider("Midtone range", 0.001, 1.0, float(DEFAULTS["midtone_range"]), {"step": 0.001, "decimals": 3})


func run(ctx: SaFilterContext) -> void:
    var pyramid := _pyramid_for(SaFilterDensity.side_of(ctx.layer))
    if pyramid == null:
        return
    var space: SaColorSpace = ctx.document.color_space if ctx.document != null else null
    var params := params_for(parameters(), space)
    var tail := SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb())
    if tail.size() < TAIL_FLOATS:
        return
    for key: String in TAIL_KEYS:
        params.erase(key)
    var kept := SaCompute.Buffer.new(tail.to_byte_array())
    var buffers := {PYRAMID_BINDING: pyramid, SPACE_BINDING: kept}
    ctx.neighbourhood_pass(SHADER, "local_contrast_lightness", _at(params, 0), RADIUS, buffers)
    # A reduce and a collapse count their threads on the level they write, so
    # the runner cuts their dispatches in that level's space.
    for level in range(1, LEVELS):
        ctx.neighbourhood_step("local_contrast_reduce", _at(params, level), level)
    for level in range(LEVELS - 2, 0, -1):
        ctx.neighbourhood_step("local_contrast_collapse", _at(params, level), level)
    ctx.neighbourhood_step("local_contrast_last", _at(params, 0))


## *values*, the record's own units, as the kernel's params in *space*:
## darktable's sigma, shadows, highlights and clarity, and the colour space
## tail. A null space is gamma sRGB.
static func params_for(values: Dictionary, space: SaColorSpace) -> Dictionary:
    var params := {
        "sigma": maxf(float(values.get("midtone_range", DEFAULTS["midtone_range"])), 0.001),
        "shadows": float(values.get("shadows", DEFAULTS["shadows"])) / 100.0,
        "highlights": float(values.get("highlights", DEFAULTS["highlights"])) / 100.0,
        "clarity": float(values.get("detail", DEFAULTS["detail"])) / 100.0 - 1.0,
    }
    var tail := SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb())
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


## The floats the pyramid of a chunk *side* texels across takes, padded by the
## halo [const RADIUS] makes on it: two a texel of the padded frame, and eight
## a texel of every coarser level, each a half of the one below rounded up.
static func floats_for(side: int) -> int:
    var frame := side + 2 * clampi(SaFilterDensity.length(RADIUS, side), 0, side)
    var total := frame * frame * FINEST_FLOATS
    for level in range(1, LEVELS):
        var across := ((frame - 1) >> level) + 1
        total += across * across * COARSE_FLOATS
    return total


## *params* for the step that writes *level*.
static func _at(params: Dictionary, level: int) -> Dictionary:
    var out := params.duplicate()
    out["level"] = level
    return out


## The pyramid's buffer, large enough for a chunk *side* texels across, made
## once and made again only for a larger side.
func _pyramid_for(side: int) -> SaCompute.Buffer:
    var bytes := floats_for(side) * 4
    if _pyramid != null and _pyramid.rid.is_valid() and _pyramid.size >= bytes:
        return _pyramid
    var zeros := PackedByteArray()
    zeros.resize(bytes)
    var made := SaCompute.Buffer.new(zeros)
    if not made.rid.is_valid():
        SaProblems.report("SaLocalContrastFilter", "the pyramid's buffer of %d bytes could not be made." % bytes)
        return null
    _pyramid = made
    return _pyramid
