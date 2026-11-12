## A module that adds one sensor, Across, for the suite and scenario: how
## far across the canvas the dab is, nought at the left edge and one at a
## thousand pixels and past.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/sensor/modules`, a folder of its
## own, because the broken fixtures beside the time fixture would raise the
## Problems box over the canvas. A reading of the dab's place rather than of
## the pen, so a stroke
## dragged along the canvas shows the curve the preset drew over it, and no
## built-in sensor reads it: a curve following it can only be following this.
extends SaModule

## The key a preset ticks it by.
const KEY: String = "fixture_across"

## How many pixels from the left edge the reading reaches one.
const SPAN: float = 1000.0


func get_id() -> StringName:
    return &"sensor-fixture"


func get_name() -> String:
    return "Sensor Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.sensors.register(KEY, across)


## The reading of *info*, the dab's distance from the left edge over [constant
## SPAN], which *sensor* has no say in.
static func across(info: SaStrokeInfo, _sensor: SaSensor) -> float:
    return clampf(info.position.x / SPAN, 0.0, 1.0)
