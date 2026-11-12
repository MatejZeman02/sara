## Filter > Motion Blur: a line of samples through each texel at an angle
## and over a length.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One neighbourhood pass over `motion_blur.gmacs`, which serves the attached
## filter and the one-shot alike: the compositor evaluates the record `run`
## leaves, and Apply walks the same record over the layer. The parameters are
## kept beside the rows because the compositor runs an attached filter with no
## dialog built.
class_name SaMotionBlurFilter
extends SaFilter

const SHADER := "sara-base-modules/motion_blur"
const DEFAULT_ANGLE := 0
const DEFAULT_LENGTH := 10


func title() -> String:
    return "Motion Blur"


## Listed under Blur in the Filter menu and the browser.
func family() -> StringName:
    return &"blur"


func sentence() -> String:
    return "Smear the picture along a line at an angle, as if it moved while the shutter was open."


func build(ui: SaDialog) -> void:
    ui.title(title())
    ui.slider("Angle", 0, 360, DEFAULT_ANGLE, {"suffix": "°"})
    ui.slider("Length", 1, 200, DEFAULT_LENGTH, {"hard_max": 500})


func run(ctx: SaFilterContext) -> void:
    var values := parameters()
    var line := float(values["length"])
    var params := {"angle": float(values["angle"]), "samples": maxi(1, roundi(line))}
    ctx.neighbourhood_pass(SHADER, "motion_blur", params, reach(line))


## How far the line reaches from its centre in either axis, plus one texel, so
## the halo covers every bilinear read the kernel makes.
static func reach(line: float) -> int:
    return ceili(line * 0.5) + 1
