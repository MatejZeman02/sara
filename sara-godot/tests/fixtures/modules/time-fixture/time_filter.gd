## The filter whose picture is its time, for the time row's suite and its
## scenario: a point pass that writes the seconds the record holds into every
## texel, so the composite says what time the chain drew the record at.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Its `build` is the time row and nothing else, which is the whole of what a
## filter writes to declare a time. The dialog adds the pictures and the
## buttons, and the panel leaves them out.
extends SaFilter


func title() -> String:
    return "Time Fixture"


func build(ui: SaDialog) -> void:
    ui.title("Time Fixture")
    SaTimeRow.declare(ui)


func run(ctx: SaFilterContext) -> void:
    var seconds := SaTyped.real(parameter(SaTimeRow.KEY))
    ctx.point_pass("time", "time", PackedFloat32Array([0.0, 0.0, seconds, 0.0]))
