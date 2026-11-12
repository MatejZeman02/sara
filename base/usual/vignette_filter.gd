## Filter > Stylize > Vignette, the picture darkened towards its edges.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Vignetting, a lens and sensor effect, as a filter for a picture
## that arrived already developed. Every output texel reads only its own input
## texel, so this is a point filter: the kernel is `vignette.gmacs` and keeps
## the contract on `SaPointPass`.
##
## The falloff is measured from the document's centre, which [method run] hands
## the kernel as the document's size, and never from the layer's or the dirty
## rectangle's, so a layer painted in one corner chunk alone is darkened by
## where its paint sits on the canvas, and a stroke's rectangle agrees with a
## whole bake. It scales light, as Exposure does: a document on a transfer
## curve is decoded, scaled and encoded again, an Oklab document is scaled in
## light and not in its coordinates, and nothing clamps (hard rule 5).
##
## Three sliders. Amount runs from -100 to 100 percent: 100 takes the far
## corner to black, 0 changes nothing and a negative amount brightens the edges
## instead, to twice the light at -100. Start is how far out from the centre the
## falloff begins, 0 at the centre and 100 at a corner, and Softness is how much
## of the way from there to the corner the fall takes, so a low softness is a
## ring and 100 is a slope that reaches its full amount at the corner.
class_name SaVignetteFilter
extends SaFilter

const SHADER := "sara-base-modules/vignette"
const KERNEL := "vignette"

const DEFAULTS := {"amount": 60, "start": 40, "softness": 100}

## Where the push constant keeps the dispatched region's origin, x then y.
const ORIGIN_SLOT := 4


func title() -> String:
    return "Vignette"


## Listed under Stylize, beside Dither.
func family() -> StringName:
    return &"stylize"


func sentence() -> String:
    return "Darken the picture towards its edges, or brighten them with a negative amount. Measured from the document's centre."


func build(ui: SaDialog) -> void:
    ui.title(title())
    ui.slider("Amount", -100, 100, DEFAULTS["amount"], {"suffix": "%"})
    ui.slider("Start", 0, 100, DEFAULTS["start"], {"suffix": "%"})
    ui.slider("Softness", 0, 100, DEFAULTS["softness"], {"suffix": "%"})


func run(ctx: SaFilterContext) -> void:
    var space := ctx.document.color_space if ctx.document != null else null
    var scale := ctx.layer.resolution_scale if ctx.layer != null else 1.0
    ctx.point_pass(SHADER, KERNEL, push_for(parameters(), space, ctx.canvas_size(), scale), {}, ORIGIN_SLOT)


## The 64-byte push constant `vignette.gmacs` reads, from *values* in the
## record's own units, on a document of *canvas* pixels stored in *space*,
## over a node of *scale* texels per document pixel. The origin and the corner
## are zero here, and the runner writes them.
static func push_for(values: Dictionary, space: SaColorSpace, canvas: Vector2i, scale: float = 1.0) -> PackedFloat32Array:
    var amount := clampf(float(values.get("amount", DEFAULTS["amount"])), -100.0, 100.0) / 100.0
    var start := clampf(float(values.get("start", DEFAULTS["start"])), 0.0, 100.0) / 100.0
    var softness := clampf(float(values.get("softness", DEFAULTS["softness"])), 0.0, 100.0) / 100.0
    var push := PackedFloat32Array([amount, start, softness, scale, 0.0, 0.0, 0.0, 0.0, float(canvas.x), float(canvas.y)])
    # The tail after the two matrices, which a point kernel that stays in the document's own coordinates never reads.
    var tail := SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb())
    push.append_array(tail.slice(18))
    return push
