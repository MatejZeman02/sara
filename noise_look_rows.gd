## The noise brush's Look page: the rows a flat, firm fill with a texture laid
## in its tone is made of, beside the brush settings they write.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why a page of their own.** The General page's rows say where paint goes,
## the pressure against the field. These say what the paint looks like once it
## is there: how much of the body fills whatever the field says, whether the
## field shows as tone instead of holes, how firm the outline stays, how a
## scrub builds up, and, for Bristle, how wide, soft and tapered its strands
## are. A painter after the look of a flat, hard edged fill with a texture in
## it, which is what the flat tip sets for Krita lay, finds it all here.
##
## Every row's rest paints as the brush did before the page was there, which
## `noise_brush_settings.gd` says beside each field.
extends RefCounted

const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")

## The page the rows sit on, after General and Texture in the brush editor.
const PAGE: String = "Look"


## The page's rows, the strands' three shown while Bristle is the field.
static func rows() -> Array[SaOptionSpec]:
    var fill := _share(
        &"fill",
        "Fill",
        # gdlint:ignore=max-line-length
        "How much of the stroke's body paints at a working press whatever the texture says. The texture then shows in the paint's tone and impasto rather than as holes."
    )
    var tone := _share(
        &"texture_tone",
        "Texture Tone",
        # gdlint:ignore=max-line-length
        "How far the texture darkens and lightens the paint, a stop and a half either way at 100%, so it is laid in the colour rather than cut out of it."
    )
    var firmness := _share(
        &"rim_firmness",
        "Rim Firmness",
        # gdlint:ignore=max-line-length
        "How firm the stroke's edge stays under a soft Hardness. At 0 the edge thins out as Hardness says, at 100% the texture runs whole to the outline."
    )
    var build := _share(
        &"build_up",
        "Build Up",
        "How much more paint going back over the stroke's own paint lays there. At 0 a scrub lays no more than its first pass."
    )
    var bristle: Dictionary[String, Variant] = {
        "shown_when": {"key": NoiseFieldsScript.FIELD_KEY, "value": NoiseFieldsScript.BRISTLE}
    }
    var width := _scale(
        &"strand_width",
        "Strand Width",
        0.25,
        3.0,
        # gdlint:ignore=max-line-length
        "How wide the bristles' strands are against the width each draws, from 25% at the left end to 300% at the right. At 100% each strand is as wide as it draws, and wider strands merge into a fill.",
        bristle
    )
    var softness := _scale(
        &"strand_softness",
        "Strand Softness",
        0.0,
        2.0,
        # gdlint:ignore=max-line-length
        "How soft the strands' edges are drawn, from 0% at the left end, where every strand is as sharp as a strand gets, to 200% at the right, where their edges fade over a third of their width. At 50% each strand draws its own softness, and at 100% half of them are as soft as a strand gets.",
        bristle
    )
    var taper := _share(
        &"strand_taper",
        "Strand Taper",
        "How much a strand narrows to a point where its run breaks. At 0 it keeps its width until it fades.",
        bristle
    )
    return [fill, tone, firmness, build, width, softness, taper]


## A row from nought to one shown as a percentage.
static func _share(key: StringName, label: String, tooltip: String, more: Dictionary[String, Variant] = {}) -> SaOptionSpec:
    return _scale(key, label, 0.0, 1.0, tooltip, more)


## A row whose value scales what each strand draws of its own, from *low* to
## *high*, shown as a percentage like the shares beside it.
##
## **Per cent and not a multiple.** A multiple such as "1.00 ×" stands a
## quarter of the way along a slider whose neighbours all read 0 to 100%, and
## reads as one more share set at a quarter. As a percentage, 100% reads as the
## strand's own and the tooltip names both ends, so a slider that runs past
## 100% says so in its numbers.
static func _scale(
    key: StringName, label: String, low: float, high: float, tooltip: String, more: Dictionary[String, Variant] = {}
) -> SaOptionSpec:
    var fields: Dictionary[String, Variant] = {
        "page": PAGE, "bar": false, "advanced": true, "percent": true, "suffix": "%", "decimals": 0, "tooltip": tooltip
    }
    fields.merge(more, true)
    return SaOptionSpec.make_float(key, label, low, high, 0.01, fields)
