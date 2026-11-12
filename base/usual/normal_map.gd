## Filter > Height to Normal Map, a filter of the base module, the
## "height to normal map" of the usual set.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A height map in, a normal map out. The height is the luminance of the source
## texel's RGB view, so a grey ramp painted with any brush is the input and a
## colour one is read by its luminance rather than refused, and the slopes are
## central differences over one texel each way.
##
## **The convention is the output's, and it is named.** +X right, +Y up, +Z out
## of the surface, which is OpenGL's, so a surface rising towards the top of the
## canvas comes out with green below 0.5. Half the engines a painter exports to
## read the other way, so the checkbox beside the strength flips the green
## channel and the row's own sentence says which of the two it drew.
class_name SaNormalMapFilter
extends SaFilter

## The shader and the entry point in it, this filter's own pair.
const SHADER := "normal_map"
const KERNEL := "normal_map"
## How far a neighbour is read, in document pixels. One, because the slopes are
## central differences over one texel either way.
const RADIUS := 1
const DEFAULT_STRENGTH := 4.0
const MAX_STRENGTH := 100.0
## The green flip's label. Its key is `flip`, the one a record has always kept,
## rather than the label snake-cased.
const FLIP_LABEL := "Flip green (DirectX)"


func title() -> String:
    return "Height to Normal Map"


## Listed under 3D in the Filter menu and the browser.
func family() -> StringName:
    return &"3d"


func sentence() -> String:
    return (
        "Read a height as a surface: +X right, +Y up, +Z out, so a ramp rising towards the top of the "
        + "canvas reads green below 0.5. The normal is stored as the colour it shows, so a flat surface is "
        + "the lilac (128, 128, 255) on the canvas and in an export."
    )


## The stable half of the registry key, which is the file's own name rather than
## the title's, so a longer menu label never moves the command.
func id() -> StringName:
    return &"normal_map"


func build(ui: SaDialog) -> void:
    ui.slider("Strength", 0.1, 20.0, DEFAULT_STRENGTH, {"hard_max": MAX_STRENGTH})
    ui.checkbox(FLIP_LABEL, false).named(&"flip")


func run(ctx: SaFilterContext) -> void:
    var params := space_fields(ctx.document.color_space)
    params["strength"] = float(parameter(&"strength"))
    params["flip"] = 1.0 if bool(parameter(&"flip")) else 0.0
    ctx.neighbourhood_pass(SHADER, KERNEL, params, RADIUS)


## The colour space tail this kernel's block declares, by the names it declares
## them, taken from the same twenty-four floats `SaColorSpace.to_push_constant`
## writes. Both matrices, because the height is read through the document's RGB
## view and the encoded normal is written back out of it.
##
## The names rather than the position, because a neighbourhood pass hands its
## params over by name and a name the block does not declare is refused rather
## than sent. Repeated in `bump_map.gd` rather than shared, for the reason
## `adjust.gmacs` gives about the same helpers: a block cannot be shared between
## two files without sharing the push constant that names it.
static func space_fields(space: SaColorSpace) -> Dictionary:
    var tail := space.to_push_constant()
    return {
        "doc_to_linear_srgb": tail.slice(0, 9),
        "linear_srgb_to_doc": tail.slice(9, 18),
        "transfer_slope": tail[18],
        "transfer_threshold": tail[19],
        "transfer_gain": tail[20],
        "transfer_exponent": tail[21],
        "coordinates": tail[22],
    }
