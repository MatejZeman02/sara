## The filter brush's shelf of presets, a bundle of this module with its
## licence: a filter each, to show the engine painting a blur, a sharpen, a
## desaturate and a grain.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Written through the preset store's own install, the door the noise brush's
## shelf takes: the module registers this script under
## `shipped_presets_filter`, the role the presets bar asks of the engine, and
## [method SaPresetStore.install_shipped] reads [method entries], asks
## [method build] for each and [method licence_for] for its bundle.
##
## **A recipe is fields of `filter_brush_settings.gd`**, written onto a fresh
## resource at its defaults. The filter is named by its registry key and its
## parameters are the record's own units, the numbers the filter's dialog
## shows, so a preset reads as the dialog would have been set. A recipe naming
## a field the settings do not have is not written, the stamp's rule.
##
## **Every recipe takes the pen's pressure and the format of now**, so a
## light touch lays a faint filter and the softness fades as a soft tip does.
## A recipe is written onto a resource at the declarations' values, which are
## an old saved brush's, so both are named here.
extends RefCounted

const FilterBrushSettingsScript = preload("res://modules/sara-base-modules/filter-brush/filter_brush_settings.gd")

## The bundle every recipe below belongs to, which holds the filter brush's shelf and the liquify shelf
## together.
const BUNDLE: String = "Sara Filters"

## The bundle the recipes shipped under before, named on each as `formerly`,
## so a profile that knew it keeps its record and its presets move with it.
const FORMERLY: String = "Sara filter brush"
## The bundle's version, author and sentence, written onto each preset beside
## `bundle`. Sara Filters is two tables, this one and the liquify shelf, and each
## spells the three, since a module sees the door only. A suite holds them the
## same.
const FIELDS: Dictionary = {
    "bundle_version": "1.0",
    "bundle_author": "Matěj Zeman",
    "bundle_about": "Brushes that change the paint already laid rather than laying new paint: the filter brushes and liquify.",
}

## The licence the bundle ships under, the module's own.
const LICENCES: Dictionary = {BUNDLE: "GPL-3.0-or-later"}


## The four shipped filter brushes, each over the base module's filter of that
## name. `radius` is a fraction of the canvas's smaller side, so 0.04 is about
## forty pixels on the 1080 of a default document.
static func entries() -> Array[Dictionary]:
    var recipes: Array[Dictionary] = [
        {
            "name": "Blur Filter",
            "tags": ["blend"],
            "bundle": BUNDLE,
            "about":
            (
                "Softens the picture where it passes with a Gaussian blur of up to four pixels, "
                + "more the harder the press, for lost edges."
            ),
            # Four pixels and a soft edge, because six and 0.6 at every pressure
            # read too strong and too hard: a medium press lays half of a four
            # pixel blur.
            "settings":
            {
                "filter_key": "sara-base-modules.gaussian_blur",
                "filter_parameters": {"radius": 4.0},
                "radius": 0.04,
                "opacity": 1.0,
                "softness": 0.7,
                "opacity_by_pressure": true,
                "format_version": FilterBrushSettingsScript.FORMAT_VERSION,
            },
        },
        {
            "name": "Sharpen Filter",
            "tags": ["blend"],
            "bundle": BUNDLE,
            "about": "Crisps the edges where it passes with an unsharp mask, for the eyes of a portrait or a focal point.",
            "settings":
            {
                "filter_key": "sara-base-modules.sharpen",
                "filter_parameters": {"kind": "unsharp_mask", "radius": 3.0, "amount": 120.0, "threshold": 0.0},
                "radius": 0.03,
                "opacity": 1.0,
                "softness": 0.5,
                "opacity_by_pressure": true,
                "format_version": FilterBrushSettingsScript.FORMAT_VERSION,
            },
        },
        {
            "name": "Desaturate Filter",
            "tags": ["blend"],
            "bundle": BUNDLE,
            "about": "Takes the colour out where it passes, to the grey of its own lightness, for quieting a busy area.",
            "settings":
            {
                "filter_key": "sara-base-modules.desaturate",
                "filter_parameters": {},
                "radius": 0.05,
                "opacity": 1.0,
                "softness": 0.4,
                "opacity_by_pressure": true,
                "format_version": FilterBrushSettingsScript.FORMAT_VERSION,
            },
        },
        {
            "name": "Grain Filter",
            "tags": ["texture"],
            "bundle": BUNDLE,
            "about": "Lays a film's grain where it passes, moving the lightness and never the hue, over a flat passage.",
            "settings":
            {
                "filter_key": "sara-base-modules.add_noise",
                "filter_parameters": {"kind": "film_grain", "monochrome": true, "amount": 50.0, "size": 2.0, "seed": 1.0},
                "radius": 0.05,
                "opacity": 1.0,
                "softness": 0.5,
                "opacity_by_pressure": true,
                "format_version": FilterBrushSettingsScript.FORMAT_VERSION,
            },
        },
    ]
    for recipe: Dictionary in recipes:
        recipe["formerly"] = FORMERLY
        recipe.merge(FIELDS)
    return recipes


## The licence *bundle* ships under, or "" for one this table does not know.
static func licence_for(bundle: String) -> String:
    return String(LICENCES.get(bundle, ""))


## A fresh resource of *script* at its own defaults with *entry* written onto
## it, or null when the script cannot carry the whole recipe, read by the one
## reader every engine shares.
static func build(script: Script, entry: Dictionary) -> Resource:
    return SaPresetRecipe.build(script, entry)
