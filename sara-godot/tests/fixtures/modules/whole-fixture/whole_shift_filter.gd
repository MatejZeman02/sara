## The filter the suite runs: a shift by a fixed offset, recorded as a pass
## that reads the whole node, so a texel reads a source as far away as it
## likes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaFilter

## How far to the right and down each texel reads from, in document pixels.
var offset: Vector2 = Vector2(512.0, 0.0)
## 0 shifts, 1 writes the runner's `chunk` and `source` params instead.
var mode: int = 0
## The reach the pass declares, the whole node unless a suite asks for a
## radius, so the `chunk` param can be read on a plain neighbourhood pass too.
var reach: int = SaNeighbourhoodPass.WHOLE_NODE


func title() -> String:
    return "Whole Fixture Shift"


func build(ui: SaDialog) -> void:
    ui.title("Whole Fixture Shift")
    ui.preview()
    ui.apply_cancel()


func parameters() -> Dictionary:
    return {"offset_x": offset.x, "offset_y": offset.y, "mode": mode, "reach": reach}


func set_parameters(values: Dictionary) -> void:
    offset = Vector2(float(values.get("offset_x", offset.x)), float(values.get("offset_y", offset.y)))
    mode = int(values.get("mode", mode))
    reach = int(values.get("reach", reach))


func run(ctx: SaFilterContext) -> void:
    ctx.neighbourhood_pass("shift", "shift", {"offset": offset, "mode": mode}, reach)
