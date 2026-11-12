## The filter the scenario opens: every widget kind the spec names, and a run
## that actually dispatches, so the preview has something to change.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It is written the way the box blur is written, because that is the shape every
## door is measured against: members declared in `build`, read in
## `run`, one kernel, one `ctx.show`. What it is not is an example of anything
## worth copying, and the `.gmacs` beside it says the same: it scales what it
## reads by the slider, which is the shortest thing whose result a scenario can
## see change.
extends SaFilter

var amount: SaSlider = null
var tint: SaPageRow = null
var invert: SaPageRow = null
var channel: SaPageRow = null
var mode: SaPageRow = null

## How many times each half of the door reached this class, so a test can say
## the dialog called the filter rather than that something happened somewhere.
var built: int = 0
var ran: int = 0


func title() -> String:
    return "Dialog Fixture Tint"


func build(ui: SaDialog) -> void:
    built += 1
    ui.title("Dialog Fixture Tint")
    ui.preview()
    amount = ui.slider("Amount", 0.0, 2.0, 1.0, {"hard_max": 8.0, "step": 0.05, "decimals": 2})
    tint = ui.color("Tint", Color(1.0, 0.5, 0.25, 1.0))
    invert = ui.checkbox("Invert", false)
    channel = ui.dropdown("Channel", ["All", "Red", "Green"], 0)
    mode = ui.radio("Mode", ["Scale", "Add"], 0)
    ui.button("Reset the amount", reset)
    ui.apply_cancel()


func run(ctx: SaFilterContext) -> void:
    ran += 1
    var src: SaTexture = ctx.layer_pixels(0)
    var dst: SaTexture = ctx.blank_like(src)
    var kernel: SaCompute = ctx.kernel("tint")
    (
        kernel
        . run(
            "tint",
            {"src": src, "dst": dst},
            {
                "amount": float(amount.value),
                "tint": tint.value as Color,
                "invert": 1 if bool(invert.value) else 0,
                "channel": int(channel.value),
                "mode": int(mode.value),
            },
            Rect2i(Vector2i.ZERO, dst.size)
        )
    )
    ctx.show(dst)


## What the button row does, so a scenario has something to press that moves a
## widget rather than the window.
func reset() -> void:
    if amount != null:
        amount.write(1.0)
