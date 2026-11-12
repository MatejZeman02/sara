## Filter > Noise > Drifting Noise: a value noise over the paint that drifts
## as its time plays, at a speed and in a direction the painter sets.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A filter of the stateless half of time on the canvas. It declares
## the time row of `SaTimeRow`, so the dialog and the attached record's panel
## show a play button and a scrubber, and its picture is a function of that
## time and of nothing that came before it. Frame n is one pass, as frame one
## is, and the same time gives the same picture however the painter reached it.
##
## One neighbourhood pass of radius zero over `drifting_noise.gmacs`, as Add
## Noise is, because the noise is drawn from the document pixel and only the
## neighbourhood runner tells a kernel where its chunk sits. The pass covers
## the dirty rectangle and reads nothing past it (hard rule 2).
##
## Scale is turned into the field's frequency here and speed and direction
## into its velocity, in cells a second, so the kernel runs neither a division
## nor a sine, the two calls a driver may round its own way. The field slides
## along the direction and turns over in place by a fifth of how far it
## slides, which is what makes it drift as a mist rather
## than slide as a wallpaper. At a speed of nought it holds still at every
## time. The parameters are kept beside the rows because the compositor runs
## an attached filter with no dialog built.
class_name SaDriftingNoiseFilter
extends SaFilter

const SHADER := "sara-base-modules/drifting_noise"
const KERNEL := "drifting_noise"

## How far the field turns over in place for every cell it slides, in cells.
const TURNOVER: float = 0.2

## The fastest speed a typed value may ask for, in document pixels a second.
const HARD_SPEED := 4000
## The coarsest feature a typed value may ask for, in document pixels.
const HARD_SCALE := 4096

const DEFAULTS := {"amount": 20.0, "scale": 48.0, "speed": 24.0, "direction": 0.0}


func title() -> String:
    return "Drifting Noise"


## Listed under Noise in the Filter menu and the browser, after Add Noise.
func family() -> StringName:
    return &"noise"


func sentence() -> String:
    return "A soft noise over the paint that drifts as its time plays, at the speed and in the direction you set."


func build(ui: SaDialog) -> void:
    ui.title(title())
    ui.slider("Amount", 0, 100, int(DEFAULTS["amount"]), {"suffix": "%"})
    ui.slider("Scale", 2, 400, int(DEFAULTS["scale"]), {"hard_max": HARD_SCALE, "suffix": " px"})
    ui.slider("Speed", 0, 200, int(DEFAULTS["speed"]), {"hard_max": HARD_SPEED, "suffix": " px/s"})
    ui.slider("Direction", 0, 360, int(DEFAULTS["direction"]), {"suffix": "°"})
    SaTimeRow.declare(ui)


func run(ctx: SaFilterContext) -> void:
    ctx.neighbourhood_pass(SHADER, KERNEL, pass_params(parameters()), 0)


## *values*, the record's own units, as the kernel's params. The direction is
## in degrees anticlockwise from rightwards, as Motion Blur's angle is, and the
## document's y runs down, so up is a negative y.
static func pass_params(values: Dictionary) -> Dictionary:
    var cell := clampf(float(values.get("scale", DEFAULTS["scale"])), 1.0, HARD_SCALE)
    var speed := clampf(float(values.get("speed", DEFAULTS["speed"])), 0.0, HARD_SPEED)
    var angle := deg_to_rad(float(values.get("direction", DEFAULTS["direction"])))
    var cells := speed / cell
    return {
        "amount": clampf(float(values.get("amount", DEFAULTS["amount"])), 0.0, 100.0) / 100.0,
        "frequency": 1.0 / cell,
        "drift": Vector2(cos(angle), -sin(angle)) * cells,
        "turnover": TURNOVER * cells,
        "seconds": maxf(SaTyped.real(values.get(String(SaTimeRow.KEY)), 0.0), 0.0),
    }
