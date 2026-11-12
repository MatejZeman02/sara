## Filter > Distort > Chromatic Aberration, the red and the blue of a picture
## parted towards its edges.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Chromatic aberration, a lens and sensor effect. One neighbourhood
## pass over `chromatic_aberration.gmacs`: the red of each texel is read from a
## place pushed out from the document's centre, the blue from the place pushed
## in towards it, and the green stays where it is. The push is the one Amount
## says in document pixels at a corner and falls in a straight line to nothing
## at the centre, so the middle of the picture is untouched and a fringe grows
## towards the edges.
##
## The centre is the document's, handed to the kernel as the document's size,
## and never the layer's or the dirty rectangle's, so a layer painted in one
## corner chunk alone is parted by where its paint sits on the canvas and an
## attached filter agrees with a bake. The halo is the largest shift, the
## amount and a texel for the bilinear read (hard rule 2).
##
## The parameters are kept beside the rows because the compositor runs an
## attached filter with no dialog built.
class_name SaChromaticAberrationFilter
extends SaFilter

const SHADER := "sara-base-modules/chromatic_aberration"
const KERNEL := "chromatic_aberration"
## The widest shift a typed value may ask for, in document pixels. A halo is
## clamped to one chunk, so past that a fringe would read transparent.
const HARD_AMOUNT := 200
const DEFAULTS := {"amount": 8}


func title() -> String:
    return "Chromatic Aberration"


## Listed under Distort in the Filter menu and the browser, beside Wobble.
func family() -> StringName:
    return &"distort"


func sentence() -> String:
    return "Part the red and the blue towards the picture's edges, as a lens that focuses them apart does."


func build(ui: SaDialog) -> void:
    ui.title(title())
    ui.slider("Amount", 0, 64, DEFAULTS["amount"], {"hard_max": HARD_AMOUNT, "suffix": " px"})


func run(ctx: SaFilterContext) -> void:
    var params := pass_params(parameters(), ctx.canvas_size())
    ctx.neighbourhood_pass(SHADER, KERNEL, params, reach(float(params["amount"])))


## *values*, the record's own units, as the kernel's params, over a document of
## *canvas* pixels.
static func pass_params(values: Dictionary, canvas: Vector2i) -> Dictionary:
    return {
        "amount": clampf(float(values.get("amount", DEFAULTS["amount"])), 0.0, HARD_AMOUNT),
        "canvas": Vector2(canvas),
    }


## How far a shift of *amount* reads from its texel, plus one texel, so the
## halo covers the second texel of every bilinear read.
static func reach(amount: float) -> int:
    return ceili(amount) + 1
