## A picture a tool asks to stand under the pointer where the pointer is now,
## beside the stock shape [method ToolState.cursor_shape] asks for there.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The descriptor's `cursor_texture` is one picture for the whole tool, set
## once when it registers, which is right for the Eyedropper and wrong for a
## tool whose pointer says what a press would do where it is. The Transform
## turns its box from just outside a corner and moves it everywhere else, and
## Godot has no rotate shape among its stock ones, so the arrow it shows there
## is a picture of its own and is shown only there. A tool builds one and hands
## the same one back on every ask, because the machine asks every frame and
## tells a change by the object.
class_name SaCursorPicture
extends RefCounted

## What the picture is called, which the cursor policy keeps the resized copy
## under and a state dump names, the Transform's `rotate`.
var name: StringName = &""

## The picture itself, which the policy resizes to the edge every tool picture
## is drawn at.
var texture: Texture2D = null

## Where the point is, as a fraction of the picture's size, which is what the
## descriptor's `cursor_hotspot` is and for the same reason.
var hotspot: Vector2 = Vector2.ZERO

## Whether the picture stands wherever the pointer is in the window, over a
## docker as much as over the canvas, because a gesture the tool holds goes on
## there. A turn of the Transform dragged across a docker still turns the box.
## Off for a picture that says what a press would do, which belongs over the
## canvas alone, the rule every tool picture keeps.
var held: bool = false


func _init(picture_name: StringName = &"", picture: Texture2D = null, point: Vector2 = Vector2.ZERO, holds: bool = false) -> void:
    name = picture_name
    texture = picture
    hotspot = point
    held = holds
