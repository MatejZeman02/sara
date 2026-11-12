## Filter > Sharpen: the five-tap Laplacian and the unsharp mask, one filter
## with a kind.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One `run` records one neighbourhood pass, so the attached form and the
## one-shot are two callers of it and cannot disagree. The kernels are
## `base/shaders/sharpen.gmacs`, and the unsharp mask is three steps of the
## pass, the Gaussian across, the Gaussian down and the difference.
##
## The parameters live in four fields that the dialog's rows write and the
## record reads, rather than on the rows alone, because the compositor runs an
## attached filter with no dialog built.
class_name SaSharpenFilter
extends SaFilter

const SHARPEN: String = "sharpen"
const UNSHARP_MASK: String = "unsharp_mask"
const KINDS: Array = [
    {"id": SHARPEN, "label": "Sharpen"},
    {"id": UNSHARP_MASK, "label": "Unsharp mask"},
]

const DEFAULT_KIND: String = UNSHARP_MASK
const DEFAULT_RADIUS: int = 3
const DEFAULT_AMOUNT: float = 100.0
const DEFAULT_THRESHOLD: float = 0.0


func title() -> String:
    return "Sharpen"


## Listed under Sharpen in the Filter menu and the browser.
func family() -> StringName:
    return &"sharpen"


func sentence() -> String:
    return "Sharpen edges, simply or with an unsharp mask."


func build(ui: SaDialog) -> void:
    var kind_row := ui.dropdown("Type", KINDS, DEFAULT_KIND).named(&"kind")
    var radius := ui.slider("Radius", 1, 20, DEFAULT_RADIUS, {"hard_max": 200})
    ui.slider("Amount", 0, 300, int(DEFAULT_AMOUNT), {"suffix": " %"})
    ui.slider("Threshold", 0, 100, int(DEFAULT_THRESHOLD), {"suffix": " %"})
    # Sharpen reads no radius, and a dimmed control is a disabled one, so the
    # kernel never reads a number the painter cannot move.
    kind_row.dims(radius, [UNSHARP_MASK])


func run(ctx: SaFilterContext) -> void:
    var unsharp := String(parameter(&"kind")) == UNSHARP_MASK
    var reach := int(parameter(&"radius")) if unsharp else 1
    var params := {
        "amount": float(parameter(&"amount")) / 100.0,
        "threshold": float(parameter(&"threshold")) / 100.0,
        "radius": reach,
    }
    if not unsharp:
        ctx.neighbourhood_pass("sharpen", SHARPEN, params, reach)
        return
    ctx.neighbourhood_pass("sharpen", "unsharp_across", params, reach)
    ctx.neighbourhood_step("unsharp_down", params)
    ctx.neighbourhood_step(UNSHARP_MASK, params)
