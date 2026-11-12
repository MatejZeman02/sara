## The bundled painter's presets, shipped as they were saved, a table of Sara
## Advanced Paint.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A bundled preset, shipped as it was saved.** Each recipe is a preset
## file read field by field, every value it holds that a fresh settings
## resource does not, so the preset that lands paints what the file paints,
## texel for texel, which the suite beside the file in the module's fixtures
## holds it to. A recipe ships under an English name a painter reads as the
## mark it makes, rather than the file's own name.
##
## **A table of its own rather than more rows in the drawn one**, though the
## first is on a drawn tip, because the drawn bundle has rules of its own its
## suites hold: a hardness of one so the picture is the dab, the spacing the
## picture's file carries, and wash. A bundled preset keeps whatever was
## chosen in it, so it is a table those rules do not read.
##
## Written the way [SaShippedPresets] writes the basic set, the tip by path as
## [SaDrawnTipPresets] names it.
class_name SaAuthorPresets
extends RefCounted

## The bundle the recipe below shipped under, named on it as `formerly`
## so a profile that knew it keeps its record. It ships in Sara Advanced
## Paint, which [method SaShippedPresets.entries] writes on it.
const FORMERLY: String = "Sara author"

## The drawn bundle's table, for the folder its pictures are in and the pair of
## numbers that sets a tip to a picture.
const SaDrawnTipPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_drawn_tip_presets.gd")

## The licence the bundle ships under, the module's own, since the recipes are
## source inside a GPLv3 module and are distributed as part of it. A tip a recipe
## names keeps its own licence, which the drawn bundle names for its pictures.
const LICENCE: String = "GPL-3.0-or-later"

const ENTRIES: Array[Dictionary] = [
    # A recipe that matches its saved file field by field: Torn Block's picture
    # laid at a fiftieth of its width, built up in a mixing blend mode, so a
    # stroke is one dense opaque ribbon with a ragged edge where the torn dabs
    # overlap. Named Torn Gouache for an opaque body
    # colour that covers in one pass, and for the tip it shares with Torn Block.
    # Its turn is a hundredth of a circle at random each dab on the file's
    # curve, and its opacity rides the pressure on the file's bend, which a
    # build-up stroke this dense shows at its edge rather than its core.
    #
    # Build-up as the file has it, where the basic set's recipes name wash.
    # The hardness is the full 1.0, and the radius is the file's to the last
    # digit, 17 px on the 1080 of a default document. The colour rate option
    # is off with the strength the file holds, shipped so that the file and a
    # fresh install read equal. A build with no such blend mode registered paints
    # it in Normal, the fallback every unknown mode has.
    {
        "name": "Torn Gouache",
        "tags": ["paint"],
        "formerly": FORMERLY,
        "about":
        (
            "A dense ribbon of opaque paint with a ragged torn edge, built up dab on dab, a painter's own "
            + "brush. It paints in a mixing blend mode where a mixing module is installed, so "
            + "over another colour it mixes as paint does, blue over yellow turning green."
        ),
        "settings":
        {
            "radius": 0.01571224058496934,
            "hardness:value": 1.0,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.02,
            "blend_mode": &"pigment_mix",
            "painting_mode": 0,
            "tip:image_path": SaDrawnTipPresetsScript.TIPS + "torn-block.png",
            "tip:kind": SaDrawnTipPresetsScript.IMAGE_TIP,
            "tip:generator": SaDrawnTipPresetsScript.IMAGE_GENERATOR,
            "smudge_color_rate_option:enabled": false,
            "smudge_color_rate_option:strength": SaDrawnTipPresetsScript.AUTHORS_COLOUR_RATE,
        },
        "pen_settings":
        {
            "opacity":
            {
                "sensors": ["pressure"],
                "common_curve": [Vector2(0.0, 0.0), Vector2(0.33802736, 0.15228516), Vector2(1.0, 1.0)],
            },
            "rotation":
            {
                "enabled": true,
                "sensors": ["fuzzy_per_dab"],
                "common_curve": [Vector2(0.0, 0.0), Vector2(1.0, 0.016972655)],
            },
        },
    },
]
