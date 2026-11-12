## Filter > Bump Map, a filter of the base module, the "bump map" of the
## usual set.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The height map that came out of the printer and a light over it: the normal
## is the normal map's, the same central differences over the same luminance,
## and what this adds is one Lambert term over the layer's own colour. Shaded
## rather than replaced, which is what "a light direction over a height" means
## and what separates this row's two halves.
##
## The light stands in the same frame the normal is in, +X right, +Y up, +Z out
## of the surface, so the azimuth is measured anticlockwise from +X and the
## elevation is above the surface. The default is a light from the upper left at
## 45 degrees, the direction every painter reads a relief by.
class_name SaBumpMapFilter
extends SaFilter

## The shader and the entry point in it, this filter's own pair.
const SHADER := "bump_map"
const KERNEL := "bump_map"
## How far a neighbour is read, in document pixels. One, because the slopes are
## central differences over one texel either way.
const RADIUS := 1
const DEFAULT_AZIMUTH := 135.0
const DEFAULT_ELEVATION := 45.0
const DEFAULT_DEPTH := 4.0
const DEFAULT_AMBIENT := 0.2
const MAX_DEPTH := 100.0


func title() -> String:
    return "Bump Map"


## Listed under 3D in the Filter menu and the browser.
func family() -> StringName:
    return &"3d"


func sentence() -> String:
    return "Shade the layer's own colour by a light over its height: an azimuth round the surface and an elevation above it."


## The stable half of the registry key, the file's own name rather than the
## title's, so a longer menu label never moves the command.
func id() -> StringName:
    return &"bump_map"


func build(ui: SaDialog) -> void:
    # Degrees on the row and radians in the kernel, converted in `run`. A
    # painter reads an azimuth as a compass bearing and no shader does.
    ui.slider("Azimuth", 0, 360, int(DEFAULT_AZIMUTH), {"suffix": "°"})
    ui.slider("Elevation", 0, 90, int(DEFAULT_ELEVATION), {"suffix": "°"})
    ui.slider("Depth", 0.1, 20.0, DEFAULT_DEPTH, {"hard_max": MAX_DEPTH})
    ui.slider("Ambient", 0.0, 1.0, DEFAULT_AMBIENT)


func run(ctx: SaFilterContext) -> void:
    var params := space_fields(ctx.document.color_space)
    params["azimuth"] = deg_to_rad(float(parameter(&"azimuth")))
    params["elevation"] = deg_to_rad(float(parameter(&"elevation")))
    params["depth"] = float(parameter(&"depth"))
    params["ambient"] = float(parameter(&"ambient"))
    ctx.neighbourhood_pass(SHADER, KERNEL, params, RADIUS)


## The half of the colour space tail this kernel's block declares, by the names
## it declares them, taken from the same twenty-four floats
## `SaColorSpace.to_push_constant` writes.
##
## The names rather than the position, because a neighbourhood pass hands its
## params over by name and a name the block does not declare is refused rather
## than sent. Repeated in `normal_map.gd` rather than shared, for the reason
## `adjust.gmacs` gives about the same helpers: a block cannot be shared between
## two files without sharing the push constant that names it, and these two
## blocks are two blocks.
static func space_fields(space: SaColorSpace) -> Dictionary:
    var tail := space.to_push_constant()
    return {
        "linear_srgb_to_doc": tail.slice(9, 18),
        "transfer_slope": tail[18],
        "transfer_threshold": tail[19],
        "transfer_gain": tail[20],
        "transfer_exponent": tail[21],
        "coordinates": tail[22],
    }
