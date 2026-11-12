## Filter > Brightness/Contrast, registered through the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Contrast is a power curve on linear luminance about a grey fulcrum and
## brightness a factor on the linear channels, darktable's shape, so a colour
## keeps its hue and no positive channel is pushed below zero.
## Nothing clamps, so paint outside the range goes in and comes out
## transformed.
##
## A record carries the formula it was made with. One saved before the formula
## in light names none and runs the old kernel, brightness added to the encoded
## RGB view and contrast a factor about 0.5 there, so a picture it drew draws
## the same. One saved with the first formula in light keeps its six stops and
## its doubled exponent, and a dialog opened now writes the second, which
## spans the sliders.
class_name SaBrightnessContrastFilter
extends SaAdjustFilter

## The record's key for the formula, and its three values. The kernel reads it
## from the sixth slot of the push constant.
const FORMULA_KEY := "formula"
## Offset and factor on the encoded view, what a record with no key means.
const FORMULA_ENCODED := 0.0
## The power curve on luminance and the factor in light, at six stops.
const FORMULA_IN_LIGHT := 1.0
## The same curve and factor, mapped gently enough that the whole slider is
## used, what a dialog opens on. The kernel runs both in light alike, and only
## the mapping in `to_pass_units` tells them apart.
const FORMULA_IN_LIGHT_2 := 2.0

## How many stops brightness moves at either end of its slider. Six puts the
## slope at mid grey, 0.0096 encoded per step, beside the old formula's 0.01,
## so the slider feels the same near zero where a painter uses it most. At the
## ends it goes further than the old one did in light and never below black:
## mid grey reaches about 3.0 encoded at +100 where the offset gave 1.5, and
## 0.04 at -100 where the offset gave -0.5.
const BRIGHTNESS_STOPS := 6.0

## How many stops the second formula lifts at the top of the slider and lowers
## at the bottom. Six reached 2.11 at +18, so a yellow read white a fifth of
## the way up. Two was the first guess, and in the running app the middle of a
## yellow stroke, 0.95 encoded, went pure white on screen at +30, because the
## view takes a colour white once its peak passes one and a yellow has half a
## stop of room. One stop still took it white at +55, and 0.9 holds it off
## white to about +60, so the slider is used past its middle, and mid grey,
## 0.5 encoded, reaches about 0.67 at +100.
## Darkening clips nothing, so four stops below take mid grey to about 0.12 at
## -100 and the dark half of the slider reaches the dark.
const LIGHT_2_STOPS_UP := 0.9
const LIGHT_2_STOPS_DOWN := 4.0
## How far the second formula's contrast exponent moves from one at either end
## of its slider, so +100 is 1.5 and -100 is 0.5. The first formula's 2.0 sent
## a bright yellow's luminance five times up.
const LIGHT_2_CONTRAST_REACH := 0.5

const ROWS: Array = [
    {"key": "brightness", "label": "Brightness", "min": -100.0, "max": 100.0, "default": 0.0, "suffix": ""},
    {"key": "contrast", "label": "Contrast", "min": -100.0, "max": 100.0, "default": 0.0, "suffix": ""},
]


func title() -> String:
    return "Brightness/Contrast"


## Listed under Tone in the Filter menu and the browser.
func family() -> StringName:
    return &"tone"


func sentence() -> String:
    return "Scale the light of every pixel and stretch it about mid grey. Hue is kept, and values above white are kept too."


## The command this has always answered to, so a rebound chord survives.
func action_name() -> StringName:
    return &"filter_brightness_contrast"


## Ctrl+Shift+B, out of the way of Colour Balance's Ctrl+B.
func chord() -> Array[InputEvent]:
    return SaAdjustFilter.ctrl_chord(KEY_B, true)


func kind() -> StringName:
    return SaPointAdjust.BRIGHTNESS_CONTRAST


func rows() -> Array:
    return ROWS


## Brightness as a factor of two to the power of its share of
## `BRIGHTNESS_STOPS`, and contrast as the exponent of the luminance curve. The
## exponent is the old factor, one plus the slider's hundredth, because a power
## curve's slope in log space at its fulcrum is its exponent, and the old
## factor's slope at mid grey was the factor: the two agree where the eye looks.
## A record of the old formula keeps the old units. The second formula moves
## less at both ends, `LIGHT_2_STOPS_UP` and `LIGHT_2_STOPS_DOWN` of light and
## an exponent `LIGHT_2_CONTRAST_REACH` either side of one, and hands the kernel
## the spare of the first, which runs it in light the same way.
func to_pass_units(raw: Dictionary) -> Dictionary:
    var share := float(raw["brightness"]) / 100.0
    var contrast := (100.0 + float(raw["contrast"])) / 100.0
    match formula():
        FORMULA_ENCODED:
            return {"brightness": share, "contrast": contrast}
        FORMULA_IN_LIGHT:
            var brightness := pow(2.0, BRIGHTNESS_STOPS * share)
            return {"brightness": brightness, "contrast": contrast, FORMULA_KEY: FORMULA_IN_LIGHT}
    var stops := LIGHT_2_STOPS_UP if share >= 0.0 else LIGHT_2_STOPS_DOWN
    contrast = 1.0 + LIGHT_2_CONTRAST_REACH * float(raw["contrast"]) / 100.0
    return {"brightness": pow(2.0, stops * share), "contrast": contrast, FORMULA_KEY: FORMULA_IN_LIGHT}


## Which formula the filter answers, the one its values were set for.
func formula() -> float:
    return float(parameter(StringName(FORMULA_KEY)))


## A dialog opened afresh runs the second formula in light. A record with no formula
## is one saved before the formula in light, the old kernel, and an edit window
## that opens one goes on running it.
func build(ui: SaDialog) -> void:
    ui.parameter_value(StringName(FORMULA_KEY), FORMULA_IN_LIGHT_2, FORMULA_ENCODED)
    super.build(ui)


## Black to white behind brightness, and behind contrast everything mid grey at
## the left with black beside white at the right.
func gradient_for(key: String) -> PackedColorArray:
    var stops := PackedColorArray()
    for i in GRADIENT_STOPS:
        var t := float(i) / float(GRADIENT_STOPS - 1)
        var lightness := 0.5 + (t - 0.5) * 0.9 if key == "contrast" else t
        stops.append(SaAdjustFilter.oklab_to_color(Vector3(lightness, 0.0, 0.0)))
    return stops
