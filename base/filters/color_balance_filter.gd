## Filter > Colour Balance, registered through the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Nine sliders at once rather than three under a band chooser, which is the
## shape Photoshop uses. A chooser hides six of the nine numbers, and hiding
## them is what makes colour balance hard to learn: the whole point of the pass
## is that one axis does different things to the dark and the light of the same
## picture, and that is only visible when the nine sit together.
class_name SaColorBalanceFilter
extends SaAdjustFilter

## How far a ramp runs either side of grey. The same quarter of the encoded
## range the kernel's BALANCE_STRENGTH shifts by, so the ramp behind a slider
## is what dragging it to that end does to a mid grey.
const BALANCE_RAMP := 0.25

## What a painter reads beside each axis, in the order of
## `SaPointAdjust.BALANCE_AXES`.
const AXIS_LABELS: Array[String] = ["Cyan-Red", "Magenta-Green", "Yellow-Blue"]


func title() -> String:
    return "Colour Balance"


## Listed under Colour in the Filter menu and the browser.
func family() -> StringName:
    return &"color"


func sentence() -> String:
    return "Shift the shadows, the midtones and the highlights along three colour axes each."


## The command this has always answered to, so a rebound chord survives.
func action_name() -> StringName:
    return &"filter_color_balance"


## Ctrl+B, the chord a painter arriving from Photoshop or Krita presses.
func chord() -> Array[InputEvent]:
    return SaAdjustFilter.ctrl_chord(KEY_B)


func kind() -> StringName:
    return SaPointAdjust.COLOR_BALANCE


## A heading and three sliders per band, then the toggle. Built by a loop
## rather than written out, which a function may do and a const may not.
func rows() -> Array:
    var out: Array = []
    for band: String in SaPointAdjust.BALANCE_BANDS:
        out.append({"type": "heading", "label": band.capitalize()})
        for axis in SaPointAdjust.BALANCE_AXES.size():
            var key := "%s_%s" % [band, SaPointAdjust.BALANCE_AXES[axis]]
            out.append({"key": key, "label": AXIS_LABELS[axis], "min": -100.0, "max": 100.0, "default": 0.0, "suffix": ""})
    out.append({"type": "check", "key": "preserve_luminosity", "label": "Preserve Luminosity", "default": false})
    return out


func to_pass_units(raw: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    for key: String in raw:
        # Not a ternary: one arm is a bool and the other a float, and a ternary
        # over two types is a warning the gate fails on.
        if raw[key] is bool:
            out[key] = raw[key]
        else:
            out[key] = float(raw[key]) / 100.0
    return out


## What the slider does to a mid grey: the shift it is worth added to one
## channel, so the left end is the complement the slider is named for and the
## right end is the primary. Built in the encoded view rather than in Oklab,
## because that is the view the kernel adds the shift in.
func gradient_for(key: String) -> PackedColorArray:
    var stops := PackedColorArray()
    var axis := SaPointAdjust.BALANCE_AXES.find(key.get_slice("_", 1))
    if axis < 0:
        return stops
    for i in GRADIENT_STOPS:
        var amount := (float(i) / float(GRADIENT_STOPS - 1) - 0.5) * 2.0 * BALANCE_RAMP
        var rgb := Vector3(0.5, 0.5, 0.5)
        rgb[axis] = 0.5 + amount
        stops.append(Color(rgb.x, rgb.y, rgb.z, 1.0))
    return stops
