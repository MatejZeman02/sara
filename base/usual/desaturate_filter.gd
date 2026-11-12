## Filter > Desaturate, Hue/Saturation/Lightness at Saturation nought in one
## click.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## No kernel of its own. Hue/Saturation/Lightness scales Oklab a and b by its
## Saturation factor (`hue_saturation_lightness` in `base/shaders/adjust.gmacs`),
## so at nought it is already the desaturation, alpha untouched. With the
## saturation model at CAM16 it takes the colour to the grey whose CAM16 J is the colour's J_HK, the
## lightness it showed with its chroma's brightness counted, so a saturated
## blue goes to a lighter grey than its Oklab L would give. A layer filed with
## no `saturation_model` keeps the Oklab grey. An entry over that kernel rather
## than a kernel of its own, so this is `SaPointAdjust`'s own kind with the
## hue and the lightness left alone, through the same record and the same
## apply Hue/Saturation takes. The two cannot drift apart. An attached record or an
## adjustment layer of it is filed as Hue/Saturation's own, see [method
## filed_as], so a double click on it opens Hue/Saturation/Lightness at
## Saturation nought.
##
## No rows. A painter who wants it partly done opens Hue/Saturation, and the
## sentence says so.
class_name SaDesaturateFilter
extends SaAdjustFilter

## What the kernel is handed whatever the dialog holds: Hue/Saturation's
## numbers with the saturation at nought, in the units the pass takes.
const VALUES := {
    "hue": 0.0, "saturation": 0.0, "lightness": 0.0, SaPointAdjust.SATURATION_MODEL: SaPointAdjust.SATURATION_IN_CAM16
}

## Hue/Saturation/Lightness's rows as its record keeps them, in the units its
## sliders show, which at Saturation nought are the same three noughts.
const FILED := {
    "hue": 0.0, "saturation": 0.0, "lightness": 0.0, SaPointAdjust.SATURATION_MODEL: SaPointAdjust.SATURATION_IN_CAM16
}


func title() -> String:
    return "Desaturate"


## Listed under Colour in the Filter menu and the browser, beside
## Hue/Saturation/Lightness, whose kernel it runs.
func family() -> StringName:
    return &"color"


func sentence() -> String:
    return "Take every colour to the grey of its own lightness. For part of the way, use Hue/Saturation/Lightness."


## Its own registry key, since `SaAdjustFilter` answers the kind, and the kind
## is Hue/Saturation's, whose key that already is.
func id() -> StringName:
    return &"desaturate"


## No chord of its own. Shift+Ctrl+U is what a painter from another program
## reaches for, and the row on the Keyboard Shortcuts page is where they give
## it one, so the filter takes no chord another module might want first.
func chord() -> Array[InputEvent]:
    return []


func kind() -> StringName:
    return SaPointAdjust.HUE_SATURATION_LIGHTNESS


func to_pass_units(_raw: Dictionary) -> Dictionary:
    return VALUES.duplicate()


## Hue/Saturation/Lightness's key under the module this registered in, and its
## rows at Saturation nought in their own units, so the record a painter
## attaches or adds a layer of is one they can turn part of the way. The two
## ids share the module half of *own_key*, which a fixture registered with no
## module leaves empty.
func filed_as(own_key: StringName) -> SaAttachedFilter:
    var module := String(own_key).trim_suffix(String(id()))
    return SaAttachedFilter.new(StringName(module + String(kind())), FILED)
