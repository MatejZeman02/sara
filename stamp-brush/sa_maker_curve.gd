## Carries the stamp brush on to the painter's new pressure curve, when the
## brush was made under the old one.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A stamp preset reads pressure through the table it was made under, its
## `maker_pressure_curve`. That makes it travel: a preset from
## another painter feels in this painter's hands as it did in theirs. It also
## means a painter who reshapes their own curve would find their own brushes
## deaf to it, because those carry the curve being replaced. So when the door
## announces a change, this re-stamps what was made under the old curve, the
## brush in hand and every preset in the store whose stamp is the old table,
## and leaves a preset from anybody else with its maker's.
##
## **The brush in hand at once, the store a moment later.** The curve on the
## Tablet page announces on every drag, and walking every preset file per
## mouse event would be a stall a painter can feel. So the settings the tools
## hold follow each step and the store is re-stamped once the drag has rested,
## from the table before the first step of it to the table after the last. The
## pending walk is also run when the module lets go, so quitting mid-drag loses
## nothing.
##
## **A file older than version 11 is not touched.** It carries no stamp on disk
## and is stamped with the loading machine's table every time it is read, so it
## follows the painter's curve already.
class_name SaMakerCurve
extends RefCounted

## How long the curve has to rest before the store is walked, in seconds.
## Longer than the gap between two drag events and shorter than a painter
## moving from Preferences to the canvas.
const SETTLE_SECONDS: float = 0.4

## The settings resources the tools hold, the brush's and the eraser's.
var _held: Array[Resource] = []

## The folder whose presets are re-stamped, empty for the brush presets'
## own.
var _presets_dir: String = ""

## The table before the first change nobody has walked the store for yet, or
## empty when nothing is waiting.
var _pending_was: PackedFloat32Array = PackedFloat32Array()

## Counts announcements, so a timer started by an earlier one knows a later
## one has come since and leaves the walk to that one's timer.
var _generation: int = 0


func _init(held: Array[Resource], presets_dir: String = "") -> void:
    _held = held
    _presets_dir = presets_dir
    SaPressureStamp.changes().connect(&"changed", _on_changed)


## Stops listening, running a walk that is still waiting first.
func detach() -> void:
    if SaPressureStamp.changes().is_connected(&"changed", _on_changed):
        SaPressureStamp.changes().disconnect(&"changed", _on_changed)
    flush()


## Re-stamps the store now for whatever change is waiting, and answers how many
## presets it rewrote. The timer calls this, and so does a suite that cannot
## wait on one.
func flush() -> int:
    if _pending_was.is_empty():
        return 0
    var was := _pending_was
    _pending_was = PackedFloat32Array()
    return SaPressureStamp.restamp_stored(was, SaPressureStamp.current(), _presets_dir)


func _on_changed(was: PackedFloat32Array, now: PackedFloat32Array) -> void:
    for settings in _held:
        SaPressureStamp.restamp(settings, was, now)
    if _pending_was.is_empty():
        _pending_was = was.duplicate()
    _generation += 1
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        flush()
        return
    var generation := _generation
    tree.create_timer(SETTLE_SECONDS).timeout.connect(func() -> void: _settle(generation))


func _settle(generation: int) -> void:
    if generation == _generation:
        flush()
