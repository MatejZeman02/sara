## Filter > Exposure, registered through the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One slider, Stops, and the values move by it: every colour channel is
## multiplied by two to the power of the stops, in linear light. It is
## darktable's exposure and not the view's, so Bake writes the scaled values,
## Attach hangs them on the layer as a record and Layer puts them in a filter
## layer, and the stored paint moves with the first only.
##
## A document on the sRGB curve is decoded, scaled and encoded again, and an
## Oklab document is scaled in light and not in its coordinates. Alpha is left
## alone and a negative channel is scaled with the rest, so nothing clamps (hard
## rule 5). The kernel is `exposure` in `adjust.gmacs`.
class_name SaExposureFilter
extends SaAdjustFilter

## The kernel's name, which `SaPointAdjust.KINDS` lists by the same word. The
## kernel reads its factor from the slot brightness uses, so a record's values
## carry it as "brightness".
const KIND: StringName = &"exposure"

## How many stops a drag of the slider reaches either way. Eight covers a
## painter lifting a dark layer into the light of a bright one, and the 16 of
## an HDR colour on its own is the paint exposure's range and not this one's.
## A typed number goes past it to [constant SaPaintExposure.FLOAT_STOPS] either
## way, the most a float factor holds, and the record keeps it as typed (hard
## rule 5).
const REACH := 8.0

## The slider moves in tenths of a stop, which is finer than an eye tells apart
## on a layer and coarse enough to land on a whole stop with the keys.
const STEP := 0.1

## A slider's `step` and `decimals` are optional keys of a row in
## `SaAdjustFilter`, a whole number being what a row without them gets.
const ROWS: Array = [
    {
        "key": "stops",
        "label": "Stops",
        "min": -SaPaintExposure.FLOAT_STOPS,
        "max": SaPaintExposure.FLOAT_STOPS,
        "soft_min": -REACH,
        "soft_max": REACH,
        "default": 0.0,
        "suffix": " EV",
        "step": STEP,
        "decimals": 1
    },
]


func title() -> String:
    return "Exposure"


## Listed under Tone in the Filter menu and the browser.
func family() -> StringName:
    return &"tone"


func sentence() -> String:
    return (
        "Move every value by stops of light, so +1 doubles it and -1 halves it. "
        + "Hue is kept, and values above white are kept too."
    )


func kind() -> StringName:
    return KIND


func rows() -> Array:
    return ROWS


## The factor the kernel multiplies the light by, two to the power of the stops.
func to_pass_units(raw: Dictionary) -> Dictionary:
    return {"brightness": pow(2.0, float(raw["stops"]))}


## Dark at the bottom of the slider and bright at the top, a ramp of grey on
## the scale the eye reads stops by.
func gradient_for(_key: String) -> PackedColorArray:
    var stops := PackedColorArray()
    for i in GRADIENT_STOPS:
        var t := float(i) / float(GRADIENT_STOPS - 1)
        stops.append(SaAdjustFilter.oklab_to_color(Vector3(0.15 + 0.85 * t, 0.0, 0.0)))
    return stops
