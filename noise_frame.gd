## The motions a frame of a noise stroke brought, laid together at the frame.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Once a frame, not once a motion.** A pen reports more often than the
## display draws, and a frame that ran long lets its reports pile up, two dozen
## and more on a tablet. Each motion is still swept into points as it comes, so
## every sample keeps its place, its pressure, its tilt and its time, but the
## update that lays those points, writes the stretch, binds the kernel, puts the
## front back and lays it again and sends the list, waits here for the frame's
## `process_frame`, which comes after the frame's input and before the easel
## composites. A backlog then costs one update rather than one a motion, and a
## slow frame no longer makes the next one slower. The stamp's `SaWalkBatch`
## sends its walks' dabs on the same signal for the same reason.
##
## Anything that sends the stroke's update at once, the press, a held press
## laid, the lift and a reset, lays what was gathered with it and settles what
## was owed, so nothing is laid twice and nothing waits past the lift.
extends RefCounted

## Whether a motion swept since the last update waits to be laid, and the pen's
## pressure at the newest such motion, which the front under the pen ends on.
var owed: bool = false
var pressure: float = 0.0

## Whether the frame's `process_frame` is already asked for.
var _armed: bool = false
## What lays the update, the brush's, taking the pressure.
var _lay: Callable


func _init(lay_update: Callable) -> void:
    _lay = lay_update


## A motion at *at_pressure* was swept, and its update waits for the frame,
## asked for once however many motions come. With no tree to ask it lays now.
func owe(at_pressure: float) -> void:
    owed = true
    pressure = at_pressure
    if _armed:
        return
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        lay()
        return
    _armed = true
    tree.process_frame.connect(_on_frame, CONNECT_ONE_SHOT)


## The stroke's update was sent by something else, which laid what was owed.
func settled() -> void:
    owed = false


## Lays what the frame's motions owe, now, or nothing when they owe nothing.
func lay() -> void:
    if not owed:
        return
    owed = false
    _lay.call(pressure)


## The frame's lay, whose ask is used up.
func _on_frame() -> void:
    _armed = false
    lay()
