## Filter > Hue/Saturation/Lightness, registered through the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The hue turns Oklab's a and b axes and the lightness is added to Oklab L.
## The saturation scales CAM16 chroma at the lightness the colour shows, J_HK
## of Hellwig, Stolitzka and Fairchild, so a colour made more saturated loses
## lightness and does not look brighter, and one made less saturated gains it.
## A record saved before that names no `saturation_model` and goes on scaling
## Oklab a and b at a fixed Oklab L, so a picture it drew draws the same.
## The choice is not shown: the dialog always makes the new one.
##
## Colorize, off by default, throws the layer's own hue away: every pixel
## keeps its L and its alpha and takes the one hue and the one chroma its two
## rows name, which is how a grey underpainting is tinted in one step. Its hue
## and saturation are rows of their own, an absolute hue and an absolute chroma,
## shown in place of the turn and the scale while the check is on, so turning
## Colorize off gives back the turn the painter had.
class_name SaHueSaturationLightnessFilter
extends SaAdjustFilter

const ROWS: Array = [
    {"key": "hue", "label": "Hue", "min": -180.0, "max": 180.0, "default": 0.0, "suffix": "°"},
    {"key": "colorize_hue", "label": "Hue", "min": 0.0, "max": 360.0, "default": 30.0, "suffix": "°"},
    {"key": "saturation", "label": "Saturation", "min": 0.0, "max": 200.0, "default": 100.0, "suffix": "%"},
    {"key": "colorize_saturation", "label": "Saturation", "min": 0.0, "max": 100.0, "default": 50.0, "suffix": "%"},
    {"key": "lightness", "label": "Lightness", "min": -100.0, "max": 100.0, "default": 0.0, "suffix": ""},
    {"type": "check", "key": "colorize", "label": "Colourise", "default": false},
]

## Which rows the check shows, by its value: the turn and the scale while it
## is off, the absolute hue and chroma while it is on.
const SHOWN_BY_COLORIZE := {"hue": false, "saturation": false, "colorize_hue": true, "colorize_saturation": true}


func title() -> String:
    return "Hue/Saturation/Lightness"


## Listed under Colour in the Filter menu and the browser.
func family() -> StringName:
    return &"color"


func sentence() -> String:
    return "Turn the hue, scale the colourfulness and lift the lightness, in Oklab so a hue keeps its brightness."


## The command this has always answered to, so a rebound chord survives.
func action_name() -> StringName:
    return &"filter_hue_saturation_lightness"


func chord() -> Array[InputEvent]:
    return SaAdjustFilter.ctrl_chord(KEY_U)


func kind() -> StringName:
    return SaPointAdjust.HUE_SATURATION_LIGHTNESS


func rows() -> Array:
    return ROWS


## The check hangs its rules on the rows it swaps, once the dialog has them all.
## A dialog opened afresh scales saturation in CAM16, and a record with no
## saturation model, one saved before the model was a choice, reads as Oklab.
func build(ui: SaDialog) -> void:
    ui.parameter_value(
        StringName(SaPointAdjust.SATURATION_MODEL), SaPointAdjust.SATURATION_IN_CAM16, SaPointAdjust.SATURATION_IN_OKLAB
    )
    super.build(ui)
    var check := _checks.get("colorize", null) as SaPageRow
    if check == null:
        return
    for key: String in SHOWN_BY_COLORIZE:
        check.hides(StringName(key), [SHOWN_BY_COLORIZE[key]])


## With Colorize on, the hue the pass takes is the absolute one and the
## saturation a fraction of `SaPointAdjust.COLORIZE_CHROMA`. A record written
## before the check names no `colorize` and reads as off.
func to_pass_units(raw: Dictionary) -> Dictionary:
    var model := float(raw.get(SaPointAdjust.SATURATION_MODEL, SaPointAdjust.SATURATION_IN_OKLAB))
    var colorize := bool(raw.get("colorize", false))
    if colorize:
        return {
            "hue": float(raw.get("colorize_hue", 30.0)),
            "saturation": float(raw.get("colorize_saturation", 50.0)) / 100.0,
            "lightness": float(raw["lightness"]) / 100.0,
            "colorize": true,
        }
    return {
        "hue": float(raw["hue"]),
        "saturation": float(raw["saturation"]) / 100.0,
        "lightness": float(raw["lightness"]) / 100.0,
        "colorize": false,
        SaPointAdjust.SATURATION_MODEL: model,
    }


## The ramps run through the painter's own foreground colour rather than a
## fixed red: the hue slider is the full turn centred on it, and saturation
## runs from grey to twice its chroma, since the slider goes to 200%.
func gradient_for(key: String) -> PackedColorArray:
    var picked: Color = SaInHand.Pair.foreground()
    var anchor := OkhsvConversions.linear_srgb_to_oklab(
        OkhsvConversions.srgb_transfer_function_inv(Vector3(picked.r, picked.g, picked.b))
    )
    var chroma := maxf(0.12, Vector2(anchor.y, anchor.z).length())
    var hue := atan2(anchor.z, anchor.y)
    var stops := PackedColorArray()
    for i in GRADIENT_STOPS:
        var t := float(i) / float(GRADIENT_STOPS - 1)
        var lab := Vector3(t, 0.0, 0.0)
        match key:
            "hue":
                var angle := hue + (t - 0.5) * TAU
                lab = Vector3(0.72, 0.12 * cos(angle), 0.12 * sin(angle))
            "saturation":
                var factor := 2.0 * t * chroma
                lab = Vector3(maxf(anchor.x, 0.55), factor * cos(hue), factor * sin(hue))
            "colorize_hue":
                var absolute := t * TAU
                lab = Vector3(0.72, 0.12 * cos(absolute), 0.12 * sin(absolute))
            "colorize_saturation":
                var amount := t * SaPointAdjust.COLORIZE_CHROMA
                lab = Vector3(maxf(anchor.x, 0.55), amount * cos(hue), amount * sin(hue))
        stops.append(SaAdjustFilter.oklab_to_color(lab))
    return stops
