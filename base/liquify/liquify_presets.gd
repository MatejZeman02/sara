## Liquify's shelf of presets, a bundle of the base module with its licence:
## one for each thing the engine does to paint already laid, so a painter
## picks a twirl or a shrink from the Brush Presets docker the way a pen is
## picked. Reconstruct and Smooth have no preset: each works only on what the
## same session pushed, so picked from the shelf and stroked over a painting
## it changes nothing, and the tool's Mode row is where a painter reaches for
## it in the middle of a push.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Private to the liquify folder, registered by `sa_liquify.gd` under
## `shipped_presets_liquify`, the role the presets bar asks of every engine the
## Brush paints with, and read through the preset store's own install as the
## noise and filter brushes' shelves are: [method entries], [method build] for
## each and [method licence_for] for its bundle.
##
## **A recipe is fields of `liquify_settings.gd`**, written onto a fresh
## resource at its defaults: the mode and the direction as the Mode and
## Direction rows number them, the size in document pixels and the strength
## as a share. The modes' numbers are the tool's own constants, so a recipe
## cannot drift from what the rows mean.
extends RefCounted

const StateLiquifyScript = preload("res://modules/sara-base-modules/base/liquify/state_liquify.gd")

## The bundle every recipe below belongs to, which holds the filter brush's shelf and the liquify shelf
## together.
const BUNDLE: String = "Sara Filters"

## The bundle the recipes shipped under before, named on each as `formerly`,
## so a profile that knew it keeps its record and its presets move with it.
const FORMERLY: String = "Sara liquify"
## The bundle's version, author and sentence, written onto each preset beside
## `bundle`. Sara Filters is two tables, this one and the filter brush's shelf, and each
## spells the three, since a module sees the door only. A suite holds them the
## same.
const FIELDS: Dictionary = {
    "bundle_version": "1.0",
    "bundle_author": "Matěj Zeman",
    "bundle_about": "Brushes that change the paint already laid rather than laying new paint: the filter brushes and liquify.",
}

## The licence the bundle ships under, the module's own.
const LICENCES: Dictionary = {BUNDLE: "GPL-3.0-or-later"}

## The name of the first recipe, the one the Liquify command picks until a
## painter has chosen a liquify preset.
const FIRST: String = "Liquify Push"


## Five, the push, both ways of the twirl, the shrink and the grow. The held
## modes at 160 pixels, wide enough to work a face or a fold in one place, and
## the push narrower because it follows the hand.
static func entries() -> Array[Dictionary]:
    return [
        _entry(
            FIRST,
            ["blend"],
            "Drags the paint along with the brush, for nudging a shape into place.",
            StateLiquifyScript.PUSH,
            120.0,
            0.5
        ),
        _entry(
            "Liquify Twirl Clockwise",
            ["blend"],
            "Turns the paint under it clockwise while held, Alt the other way.",
            StateLiquifyScript.TWIRL,
            160.0,
            0.5,
            StateLiquifyScript.CLOCKWISE
        ),
        _entry(
            "Liquify Twirl Anticlockwise",
            ["blend"],
            "Turns the paint under it anticlockwise while held, Alt the other way.",
            StateLiquifyScript.TWIRL,
            160.0,
            0.5,
            StateLiquifyScript.ANTICLOCKWISE
        ),
        _entry(
            "Liquify Shrink",
            ["blend"],
            "Pulls the paint under it towards the centre while held, Alt grows it.",
            StateLiquifyScript.SHRINK,
            160.0,
            0.5
        ),
        _entry(
            "Liquify Grow",
            ["blend"],
            "Pushes the paint under it out from the centre while held, Alt shrinks it.",
            StateLiquifyScript.GROW,
            160.0,
            0.5
        ),
    ]


## One recipe and the tags it carries.
static func _entry(
    name: String,
    tags: Array[String],
    about: String,
    mode: int,
    size: float,
    strength: float,
    direction: int = StateLiquifyScript.CLOCKWISE
) -> Dictionary:
    return (
        {
            "name": name,
            "tags": tags,
            "bundle": BUNDLE,
            "formerly": FORMERLY,
            "about": about,
            "settings": {"mode": mode, "direction": direction, "size": size, "strength": strength},
        }
        . merged(FIELDS)
    )


## The licence *bundle* ships under, or "" for one this table does not know.
static func licence_for(bundle: String) -> String:
    return String(LICENCES.get(bundle, ""))


## A fresh resource of *script* at its own defaults with *entry* written onto
## it, or null when the script cannot carry the whole recipe, read by the one
## reader every engine shares.
static func build(script: Script, entry: Dictionary) -> Resource:
    return SaPresetRecipe.build(script, entry)
