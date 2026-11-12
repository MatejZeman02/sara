## The left-button drag of a `FactorSlider`, from the press to the release, and
## the value it stood at when the press came, which a cancel puts back.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It answers the share of the box the pointer's drag stands at and nothing
## else. Writing the value, rounding it to the step and telling the row is the
## slider's, which asks this class where to put it.
##
## A drag with Shift held moves at a tenth of the rate. The rate changes under
## the hand without the value jumping, because the drag is measured from an
## anchor that is taken again whenever Shift goes down or up. A plain press
## anchors at the pointer, so a plain drag is the pointer's place in the box.
##
## **A right press or Escape ends the drag and the value goes back**, as in
## Blender, whose fields take both for a cancel. The slider joins [constant
## GROUP] for as long as a drag is held, so the shortcut router, which sees
## Escape in a dialog before anything inside the dialog does, can ask
## [method cancel_live] whether the key is a drag's before it closes the window.
class_name SaSliderDrag
extends RefCounted

## What a pixel of hand moves with Shift held, as a share of what it moves
## without. A tenth, so a painter can land between the values a plain drag
## jumps across.
const FINE_RATE: float = 0.1

## The group of the slider whose drag is held, none while nobody is dragging.
const GROUP: StringName = &"sa_slider_drag"

## Whether a press began a drag that no release or cancel has ended.
var held: bool = false

## The value at the press, taken before the press moved it.
var from_value: float = 0.0

## The share of the box the drag stands at, unclamped, so a pointer that ran
## past an end has to come back to it before the value moves again.
var ratio: float = 0.0

## Where the drag is measured from: the share it stood at, the pointer's x
## there and whether Shift was held. And the pointer's last x, which a change
## of Shift anchors at.
var _anchor_ratio: float = 0.0
var _anchor_x: float = 0.0
var _anchor_fine: bool = false
var _last_x: float = 0.0

## The slider being dragged, a node the slider's own drag cannot outlive.
var _host: FactorSlider = null


## The share of a box *width* wide that *mx* is at, held between the ends.
static func share_of(mx: float, width: float) -> float:
    return clampf(mx / width, 0.0, 1.0) if width > 0.0 else 0.0


## Cancels the drag held in *viewport*'s tree, if any, for an Escape press, and
## says whether it did, handing the key on to nobody when it did. A window
## outside the tree has no tree to hold a drag in, and asking it for one is a
## script error, which an attached filter's editor built by a suite reached.
static func cancel_live(event: InputEvent, viewport: Viewport) -> bool:
    if viewport == null or not viewport.is_inside_tree() or not event.is_pressed() or event.is_echo():
        return false
    for slider: Node in viewport.get_tree().get_nodes_in_group(GROUP):
        (slider as FactorSlider).cancel_drag()
        viewport.set_input_as_handled()
        return true
    return false


## Starts a drag of *host* at *mx*, and takes the value it stands at, which a
## cancel puts back. A plain press puts the share under the pointer. One with
## Shift held leaves it where it is, since a jump to the pointer is the opposite
## of what a painter holding Shift is asking for.
func begin(host: FactorSlider, mx: float, fine: bool) -> void:
    _host = host
    host.add_to_group(GROUP)
    held = true
    from_value = host.value
    ratio = host.ratio_of_value(host.value, host.drag_max()) if fine else share_of(mx, host.size.x)
    _anchor(mx, fine)


## The share of the box a motion to *mx* leaves the drag at, held between the
## ends. A change of Shift anchors again at the last point the drag reached, so
## the value goes on from where it stands at the new rate.
func move(mx: float, fine: bool) -> float:
    var width := _host.size.x
    if fine != _anchor_fine:
        ratio = clampf(ratio, 0.0, 1.0)
        _anchor(_last_x, fine)
    var rate := FINE_RATE if fine else 1.0
    ratio = _anchor_ratio + (mx - _anchor_x) / width * rate if width > 0.0 else _anchor_ratio
    _last_x = mx
    return clampf(ratio, 0.0, 1.0)


## Ends the drag, a release or a cancel alike, and answers the value it began
## at.
func end() -> float:
    held = false
    _host.remove_from_group(GROUP)
    return from_value


func _anchor(mx: float, fine: bool) -> void:
    _anchor_ratio = ratio
    _anchor_x = mx
    _anchor_fine = fine
    _last_x = mx
