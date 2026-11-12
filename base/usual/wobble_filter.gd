## Filter > Wobble: ripples across a node, each texel read a little to one side
## by a sine of its document pixel whose phase a noise field pushes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One neighbourhood pass over `wobble.gmacs`, whose halo is the amplitude, so
## the pass reads the chunk and the ring of neighbours a shift can reach and no
## more (hard rule 2, dirty-rect dispatch). It is meant to follow a mirror,
## where it turns a reflection into water, and it also stands alone as a
## filter of its own on any node: a layer, a group or the root, attached or
## applied once.
##
## Horizontal ripples by default, crests that run across the canvas and push
## paint left and right the way a lake's do. The parameters are kept beside the
## rows because the compositor runs an attached filter with no dialog built.
class_name SaWobbleFilter
extends SaFilter

const SHADER := "sara-base-modules/wobble"
const KERNEL := "wobble"
const DIRECTIONS: Array[String] = ["horizontal", "vertical"]
const DIRECTION_TITLES: Array[String] = ["Horizontal ripples", "Vertical ripples"]
## The widest shift a typed value may ask for, in document pixels. A halo is
## clamped to one chunk, so past that a crest would read transparent.
const HARD_AMPLITUDE := 200
const DEFAULTS := {"direction": "horizontal", "amplitude": 6.0, "wavelength": 48.0, "turbulence": 40.0}


func title() -> String:
    return "Wobble"


## Listed under Distort in the Filter menu and the browser, beside Wrap Offset.
func family() -> StringName:
    return &"distort"


func sentence() -> String:
    return "Ripple the picture sideways in waves a noise breaks up, the way a reflection wobbles on water."


func build(ui: SaDialog) -> void:
    var kinds: Array = []
    for index in DIRECTIONS.size():
        kinds.append({"id": DIRECTIONS[index], "label": DIRECTION_TITLES[index]})
    ui.dropdown("Direction", kinds, DEFAULTS["direction"])
    ui.slider("Amplitude", 0, 64, int(DEFAULTS["amplitude"]), {"hard_max": HARD_AMPLITUDE, "suffix": " px"})
    ui.slider("Wavelength", 2, 400, int(DEFAULTS["wavelength"]), {"hard_max": 4096, "suffix": " px"})
    ui.slider("Turbulence", 0, 100, int(DEFAULTS["turbulence"]), {"suffix": "%"})


func run(ctx: SaFilterContext) -> void:
    var params := pass_params(parameters())
    ctx.neighbourhood_pass(SHADER, KERNEL, params, reach(float(params["amplitude"])))


## *values*, the record's own units, as the kernel's params.
static func pass_params(values: Dictionary) -> Dictionary:
    var direction := String(values.get("direction", DEFAULTS["direction"]))
    return {
        "amplitude": clampf(float(values.get("amplitude", DEFAULTS["amplitude"])), 0.0, HARD_AMPLITUDE),
        "wavelength": maxf(float(values.get("wavelength", DEFAULTS["wavelength"])), 1.0),
        "turbulence": clampf(float(values.get("turbulence", DEFAULTS["turbulence"])), 0.0, 100.0) / 100.0,
        "vertical": 1 if direction == "vertical" else 0,
    }


## How far a shift of *amplitude* reads from its texel, plus one texel, so the
## halo covers the second texel of every bilinear read.
static func reach(amplitude: float) -> int:
    return ceili(amplitude) + 1
