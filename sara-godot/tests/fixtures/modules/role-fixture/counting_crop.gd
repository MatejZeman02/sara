## A crop that counts what it is asked, for the role fixture.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It extends the skeleton's crop and re-implements one method, `resize_to`,
## which is the shape a role takes: subclass a core class,
## change what you want, and have the skeleton use yours. The record is a
## static, because the instance is built by the dialog and dropped by it,
## and the test never holds one. Written by this class alone, which is what
## the privates rule asks of a member set from outside.
extends SaCrop

## Every size this crop was asked to resize to, oldest first.
static var resizes: Array[Vector2i] = []


func resize_to(size: Vector2i, anchor: Vector2i, margin_fill: Color = Color(0, 0, 0, 0)) -> bool:
    resizes.append(size)
    return super(size, anchor, margin_fill)


## Clears the record, for a test's `before_each`.
static func forget() -> void:
    resizes.clear()
