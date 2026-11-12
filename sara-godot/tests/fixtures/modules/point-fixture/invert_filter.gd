## The point filter the suite runs: an invert, recorded as a pass rather than
## shown as a texture.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The whole of a point filter's `run` is one call. Nothing is copied out of the
## layer, nothing is allocated, and the compositor previews the pass on the
## canvas while Apply walks it once over the chunks.
extends SaFilter

## How many times the dialog reached `run`, so a test can say it did.
var ran: int = 0


func title() -> String:
    return "Point Fixture Invert"


func build(ui: SaDialog) -> void:
    ui.title("Point Fixture Invert")
    ui.preview()
    ui.apply_cancel()


func run(ctx: SaFilterContext) -> void:
    ran += 1
    ctx.point_pass("invert", "invert", PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))
