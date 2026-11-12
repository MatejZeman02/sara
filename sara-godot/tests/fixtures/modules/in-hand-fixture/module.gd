## A module that reads what a docker reads, the colour pair, a preference and
## the canvas in front, through `SaInHand` alone.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it.
## `core/api/tests/test_a_module_reads_the_settings_the_colour_pair_and_the_canvas_through_the_door.gd`
## builds it by hand and reads its source as well, to hold that it names no
## class behind the door. That is the claim: a third party's module reads what
## the built-ins reached past the door for, and a scan of it finds no reach.
extends SaModule

## The preference it reads, one the Exposure docker reads.
const SETTING := &"display_exposure_stops"


func get_id() -> StringName:
    return &"in-hand-fixture"


func get_name() -> String:
    return "In Hand Fixture"


func get_version() -> String:
    return "1.0.0"


func register(_ctx: SaContext) -> void:
    pass


## The pair as a colour docker shows it: both colours and the paint exposure.
func pair() -> Dictionary:
    return {
        "foreground": SaInHand.Pair.foreground(),
        "background": SaInHand.Pair.background(),
        "stops": SaInHand.Pair.exposure_stops(),
    }


## The preference this module reads, and its bounds.
func setting() -> Dictionary:
    return {
        "value": SaInHand.Settings.read(SETTING),
        "max": SaInHand.Settings.MAX_EXPOSURE_STOPS,
    }


## Moves the preference, as the docker's slider would.
func move_setting(stops: float) -> void:
    SaInHand.Settings.write(SETTING, stops)


## What a docker reads of *surface*'s canvas, or of the one in front when none
## is handed in: the document's size, the texture it binds, whether it has the
## canvas's shader to compose over, and the filter it samples with at 2.
func canvas(surface: SaSurface = null) -> Dictionary:
    var shown := surface if surface != null else SaInHand.Canvas.front()
    if shown == null:
        return {}
    SaInHand.Canvas.request_composite(shown)
    return {
        "size": shown.get_canvas_size(),
        "output": SaInHand.Canvas.output_rid(shown),
        "has_shader": SaInHand.Canvas.shader(shown) != null,
        "filter": SaInHand.Canvas.texture_filter_for(2.0),
    }
