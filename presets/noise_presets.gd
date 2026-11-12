## The noise brush's first shelf of presets, a bundle of this module with its
## licence.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The older note is the reason.** "Nobody enjoys setting a thousand
## parameters, so presets of the same brush are better." A painter who opens
## the noise brush finds these fifteen in the presets docker, each a brush with a
## name and a sentence saying what it is for, and the sliders behind them are
## the brush editor's for whoever wants them.
##
## **Written through the preset store's own install**, which is the door every
## shipped recipe takes: [method SaPresetStore.install_shipped] is handed this
## script, reads [method entries], asks [method build] for each and
## [method licence_for] for its bundle, and keeps the record that offers each
## preset to a profile once. The stamp's recipes reach that install through the
## `shipped_presets` role, which holds one script, so a second module claiming
## it would take the stamp's shelf away. The module registers this script
## under `shipped_presets_noise` instead, the role the presets bar asks for
## while a tool of the noise engine is active, so the shelf is written the
## first time a painter picks the brush up and never names the store.
##
## **A recipe is property paths of `noise_brush_settings.gd`**, written onto a
## fresh settings resource at its defaults, so a preset carries every default a
## later row adds. Three things are not a path: `lift_up` names the curve
## options the lift-up sensor is bound on through the door's own binding, which
## is what the brush editor's tick makes, `pressure` names the curve options the
## pressure sensor is bound on and the curve each reads it along, by the names
## the settings' `option_for` knows, `radius` for Size's among them, and a recipe
## naming a path the settings do not have is not written, the stamp's rule,
## since a preset that silently lost a row would be a lie with a name on it.
extends RefCounted

const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")

## The bundle every recipe below belongs to, written onto each preset as its
## `bundle` metadata and the name the install's record is filed under. Sara
## Advanced Paint holds the noise shelf with the stamp brush's drawn,
## and most of its basic one.
const BUNDLE: String = "Sara Advanced Paint"

## The bundle the recipes shipped under before, named on each as `formerly`,
## so a profile that knew it keeps its record and its presets move with it.
const FORMERLY: String = "Sara noise"

## The bundle's version, author and sentence, written onto each preset beside
## `bundle`. The stamp brush's table spells the same three, and this module
## spells them again, since it sees the door only. The bundles' suite under
## `ui/presets/tests` holds the two the same.
const FIELDS: Dictionary = {
    "bundle_version": "1.0",
    "bundle_author": "Matěj Zeman",
    "bundle_about": "Every other paint brush Sara ships: drawn tips, noise, pencils, markers and smudges.",
}

## The licence the bundle ships under, the module's own, since the recipes are
## source inside a GPLv3 module and are distributed as part of it.
const LICENCES: Dictionary = {BUNDLE: "GPL-3.0-or-later"}

## The curve options a lift-up is bound on read as a signed shift rather than a
## multiplier, which picks the curve the door's binding gives them.
## `SaDynamics.OFFSET_OPTIONS` says the same by the settings' field names.
const OFFSET_OPTIONS: Array[String] = ["saturation", "value"]


## The fifteen, one per field first, then one per thing a painter reaches for,
## then the two made of Bristle Flat, for planed wood and for wet paint, and
## last the five of the flat tip style, made of the Look page's rows.
##
## **The flat tip style five carry the look, never the files.** The flat tip
## Impasto presets are smudge brushes at full opacity laid as overlapping
## stamps, a pattern texture whose strength runs from 0.65 to one on pressure,
## paint thickness from 0.85 to one and a colour rate of 0.28 on the flat tip.
## The noise brush lays one stroke and no stamps, so Fill and Texture Tone
## carry the texture's strength as a body that fills with the pattern in its
## tone, Thickness the paint's, and the smudge rows the colour rate, and
## nothing of the bundle is read at run time.
##
## `radius` is a fraction of the canvas's smaller side, so 0.02 is about
## twenty pixels across on the 1080 of a default document. The pen's pressure
## is the cut: a texel paints where the pressure reaches the texture there plus
## Strength's shift, read along `pressure`'s curve. Thickness is virtual
## millimetres a stroke, and a layer gains height only under a brush that lays
## some.
##
## **Rewritten for the pressure cut, to keep each look.** The recipes were
## written for the cut before it, Strength times a curve the pressure lowered,
## under which a texel painted where its texture reached the cut. The shift
## that keeps a recipe painting the same texels at every pressure is the
## pressure less one plus the old cut. A recipe on the old falling line keeps
## its look exactly at a Strength one less than the old and the same falling
## line, and Canvas Scumble and Dry Brush, whose curves were their own, at
## their shift's largest, read along the share of it each pressure takes, with
## the point just past the bend the settings' migration gives one. A shift
## below nought where the old curve's other end sat is the one thing a curve of
## nought to one cannot carry, so Canvas Scumble and Dry Brush paint a hair
## less at their lightest touch.
##
## **Grain Round and Bristle Flat taper.** Their
## radius is on the pen's pressure as well, falling to a third at no pressure
## along the settings' `radius_pressure_curve`, because without it a stroke of
## either pressed in and let go thins its grain at the ends and keeps its whole
## width, and rows of them read as rows of round caps. The other six keep their
## width. A tip the taper takes under the pixel mode's three pixels is taken
## most of the way back, `NoisePoint.thinned`, so a small Grain Round still grows
## with its Size row.
##
## **Grain Round, Canvas Scumble and Dry Brush lay no height.**
## The relief a thickness shades into the grain moves the value the stroke
## lays, far enough on these three that a painter would turn the thickness off
## by hand to paint with them. Thick Impasto is the preset that lays
## height, and Living Colour and Broken Chalk keep theirs.
##
## **Bristle Flat lays a thin relief, so a return can stand higher.** Its
## strands lie opaque on the lines a return keeps, so Build Up cannot thicken
## them in alpha without bending the streaks, and the paint a return adds
## shows as height instead (`noise_built_up_height`). A thickness of 0.1, flat
## across each strand at its Relief of a half, lights as strands and not as
## blotches, and moves the lit value over the paint by about two levels of
## 255 on average, where 0.4 moved it far enough to be turned off. Where the pen comes back
## the strands stand higher.
##
## **Bristle Flat's and Wood Grain's lines say where their streaks show.**
## Both are streaked over the lighter half of a pressure ramp and solid at its
## full end, and Wood Grain held at a pressure of 0.5 leaves half its band
## bare, so the line says so as Grain Round's does.
##
## **Wood Grain keeps its grain at a full press.** A falling curve on Strength
## shifts nothing at a full press, so every texel takes paint there and the
## band reads plain, which sends a painter after a thickness whose relief then
## shows through the layers above. Its Strength is a shift of 0.35 at every
## pressure, which leaves the texels between the streaks short of the cut, and
## Hardness 0.6 widens the band beneath the cut to 0.4, so at a full press they
## take some of the paint the streaks take rather than none. A full press lays
## paint across the whole band with the streaks darker in it, and a light touch
## lays broken streaks. The shift sits in a narrow window: a bristle's skirt
## fills between the streaks, so a shift of 0.3 leaves the band's rows under 5
## L* apart, and one of 0.4 leaves a row where two broken streaks meet bare.
##
## **Thick Impasto's Strength is -0.4 on its falling line**, which leaves a
## light touch with holes in its body, and the cut's speck curve thins every
## press under a half further, for every preset alike. The bristle field
## fills most of a stroke at a working press, so the -0.7 a field of narrow
## streaks wanted lays a light touch nearly solid.
##
## **Broken Chalk and Wet Into Wet are settings painted with in earnest**,
## read off the preset files they were saved in, so a fresh profile installs
## them as they were used. Both lay a picture through a coarse
## two-channel grain, and Wet Into Wet keeps its pickup on, for mixing wet
## paint on the canvas.
##
## A function rather than the stamp's `const`, because a curve is a
## `PackedVector2Array` and its constructor is not a constant expression.
static func entries() -> Array[Dictionary]:
    var falling := PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
    var tapering := NoiseBrushSettingsScript.radius_pressure_curve()
    var recipes: Array[Dictionary] = [
        {
            "name": "Grain Round",
            "tags": ["paint"],
            "bundle": BUNDLE,
            "about":
            # gdlint:ignore=max-line-length
            "A round that paints through a fine paper grain, speckled at a light touch and solid at a hard press, for laying in colour with a tooth to it.",
            "settings":
            {
                "radius": 0.02,
                "hardness": 0.8,
                "strength": -0.1,
                "texture_field": "grain",
                "grain_scale": 4.0,
                "grain_contrast": 2.0,
                "thickness": 0.0,
                "tip:softness": 0.8,
            },
            "pressure": {"strength": falling, "radius": tapering},
        },
        # Two channels, so the height a streak lays is its bristle's own and
        # flat across it rather than the streak's round profile, at a Relief of
        # a half and a Thickness of 0.2 mm, because round ridges lit as strands
        # read as noodles laid down. The cut reads the map alone, which neither
        # row moves, so erasing is untouched.
        {
            "name": "Bristle Flat",
            "tags": ["paint"],
            "bundle": BUNDLE,
            "about":
            # gdlint:ignore=max-line-length
            "Long streaks that drag with the stroke the way a loaded flat's hairs do, broken at a light touch and closing into solid paint at a hard press, for blocking in and for hair and grass.",
            "settings":
            {
                "radius": 0.025,
                "hardness": 0.9,
                "strength": -0.2,
                "texture_field": "bristle",
                "bristle_count": 18,
                "bristle_spread": 0.4,
                "bristle_length": 4.0,
                "texture_drift": 0.8,
                "texture_channels": 2,
                "texture_relief": 0.5,
                "thickness": 0.1,
            },
            "pressure": {"strength": falling, "radius": tapering},
        },
        # Through its own pattern rather than Canvas Weave, whose value never
        # reaches nought, so a cut through it painted a square grid of thread
        # lines. Canvas Scumble's hollows are nought and its tops uneven, so a
        # cut anywhere leaves a texture. Inverted, so its thread tops need the
        # least pressure, and shifted from nought at an eighth of a press to
        # 0.35 at a full one: a light touch catches a few thread tops and a full
        # one lays broken colour over about a third of the stroke, hollows open.
        {
            "name": "Canvas Scumble",
            "tags": ["texture"],
            "bundle": BUNDLE,
            "about":
            # gdlint:ignore=max-line-length
            "Paint broken over a woven canvas, the threads taking it and the hollows left open, for scumbling one colour over another.",
            "settings":
            {
                "radius": 0.035,
                "hardness": 0.9,
                "strength": 0.35,
                "texture_field": "picture",
                "picture_name": "Canvas Scumble",
                "picture_scale": 2.0,
                "picture_rotation": 0.0,
                "picture_invert": true,
                "thickness": 0.0,
            },
            "pressure":
            {"strength": PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.125, 0.0), Vector2(0.145, 0.0229), Vector2(1.0, 1.0)])},
        },
        {
            "name": "Thick Impasto",
            "tags": ["paint"],
            "bundle": BUNDLE,
            "about":
            # gdlint:ignore=max-line-length
            "Paint laid two millimetres thick a stroke, its bristle ridges standing up to catch the light, for the passages that should sit off the canvas.",
            "settings":
            {
                "radius": 0.03,
                "hardness": 1.0,
                "strength": -0.4,
                "texture_field": "bristle",
                "texture_channels": 2,
                "texture_relief": 1.5,
                "bristle_count": 20,
                "bristle_spread": 0.4,
                "bristle_length": 6.0,
                "texture_drift": 1.0,
                "thickness": 2.0,
            },
            "pressure": {"strength": falling},
        },
        {
            "name": "Dry Brush",
            "tags": ["texture"],
            "bundle": BUNDLE,
            "about":
            # gdlint:ignore=max-line-length
            "A brush nearly out of paint, skipping over the grain's peaks however hard the press, for scratchy highlights and broken edges.",
            "settings":
            {
                "radius": 0.03,
                "opacity": 0.85,
                "hardness": 1.0,
                "strength": 0.665,
                "texture_field": "grain",
                "grain_scale": 3.0,
                "grain_contrast": 3.5,
                "thickness": 0.0,
            },
            "pressure":
            {"strength": PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.09, 0.0216), Vector2(1.0, 1.0)])},
        },
        # A grey has no hue, so the half of the specks whose saturation the
        # grain raises come out at the hue `SaColorDynamics` gives a grey, a
        # pinkish red, and the half it lowers stay grey. Laid in a grey the
        # paint reads a little red at any size, so the line says so for a
        # painter choosing it for a grey.
        {
            "name": "Living Colour",
            "tags": ["paint"],
            "bundle": BUNDLE,
            "about":
            # gdlint:ignore=max-line-length
            "Each speck of the grain turns the colour's hue and saturation its own way, so no patch is one flat colour, for skin, foliage and anything alive. A grey has no hue of its own, so on a grey the specks come out a pinkish red.",
            "settings":
            {
                "radius": 0.025,
                "hardness": 0.7,
                "strength": -0.5,
                "texture_field": "grain",
                "grain_scale": 10.0,
                "grain_contrast": 1.5,
                "chroma_variation": 0.7,
                "thickness": 0.2,
            },
            "pressure": {"strength": falling},
        },
        {
            "name": "Watery Lift",
            "tags": ["paint"],
            "bundle": BUNDLE,
            "about":
            # gdlint:ignore=max-line-length
            "Paint that thins and greys as the pen lets go, like a wet brush lifting off the paper, for glazes that fade out at their ends.",
            "settings":
            {
                "radius": 0.04,
                "hardness": 0.3,
                "strength": -0.6,
                "texture_field": "grain",
                "grain_scale": 8.0,
                "grain_contrast": 1.0,
                "thickness": 0.0,
            },
            "pressure": {"strength": falling},
            "lift_up": ["opacity", "saturation"],
        },
        # Broken Chalk and Wet Into Wet are written as they were painted with,
        # read field by field off their saved files
        # and written here as every value a fresh settings resource does not
        # hold already, with the name and the sentence the table gave them.
        # Broken Chalk lays the scumble picture through a coarse two-channel
        # grain with a raised relief, and every row but the drift and the tilt
        # wanders a little along the stroke.
        {
            "name": "Broken Chalk",
            "tags": ["texture"],
            "bundle": BUNDLE,
            "about":
            (
                "A chalk whose edge a fine paper grain breaks, every stroke meeting the same grain the way chalk "
                + "meets the tooth of one sheet, for drawing and hatching on a toned ground. It paints in a "
                + "mixing blend mode where a mixing module is installed, so over another colour it "
                + "mixes as paint does, blue over yellow turning green."
            ),
            "settings":
            {
                "radius": 0.0357339915406129,
                "hardness": 0.9,
                "strength": 0.23,
                "tip:generator": 3,
                "tip:diameter": 17.7199056904311,
                "tip:image_path": "res://tips/scumble.png",
                "randomness": 1.0,
                "texture_channels": 2,
                "texture_relief": 1.93,
                "grain_scale": 2.0,
                "grain_contrast": 2.5,
                "thickness": 0.19,
                "blend_mode": &"pigment_mix",
                "smudge_color_rate_option:enabled": false,
                "smudge_color_rate_option:strength": 0.19999999999999996,
            },
            "pen_settings":
            {
                "size": {"sensors": [_wander("size", 0.95)], "enabled": true, "use_same_curve": false},
                "opacity": {"sensors": [_wander("opacity", 0.88)], "enabled": true, "use_same_curve": false},
                "hardness": {"sensors": [_wander("hardness", 0.89)], "enabled": true, "use_same_curve": false},
                "strength": {"sensors": [_wander("strength", 0.96)], "use_same_curve": false},
                "thickness": {"sensors": [_wander("thickness", 0.95)]},
            },
            "pressure": {"strength": falling},
        },
        # Bristle Flat set for planed oak: thirty bristles twice as long and
        # drifting with the stroke at full, at half opacity, dragged level. Dry
        # Brush's grain is the same every way and its drags read as cork, these
        # read as planed oak. Its cut is its own, held off the pressure so a
        # full press keeps the grain.
        {
            "name": "Wood Grain",
            "tags": ["texture"],
            "bundle": BUNDLE,
            "about":
            # gdlint:ignore=max-line-length
            "Fine straight streaks at half opacity that run with the stroke, broken at a light touch and filled in between at a hard press, where the streaks stay darker than the paint around them, for the grain of planed wood and any texture that has a direction. A thickness adds a relief, which shows through every layer above it.",
            "settings":
            {
                "radius": 0.025,
                "opacity": 0.5,
                "hardness": 0.6,
                "strength": 0.35,
                "texture_field": "bristle",
                "bristle_count": 30,
                "bristle_spread": 0.4,
                "bristle_length": 8.0,
                "texture_drift": 1.0,
                "thickness": 0.0,
            },
            "pressure": {"radius": tapering},
        },
        # Wet Into Wet: the scrawled block picture through a
        # two-channel grain, its hue and saturation moved by the texture, the
        # smudge stage still on, and a wander along the stroke on the rows
        # Broken Chalk wanders on.
        {
            "name": "Wet Into Wet",
            "tags": ["blend"],
            "bundle": BUNDLE,
            "about":
            (
                "Bristle Flat's streaks loaded with the wet paint they cross, so a stroke opens in its own "
                + "colour and closes in what it dragged through, for mixing on the canvas alla prima. It paints in "
                + "a mixing blend mode where a mixing module is installed, so over another colour it "
                + "mixes as paint does, blue over yellow turning green."
            ),
            "settings":
            {
                "radius": 0.04148821427470957,
                "hardness": 0.9,
                "strength": 0.02,
                "tip:generator": 3,
                "tip:diameter": 29.46292452533275,
                "tip:image_path": "res://tips/scrawled-block.png",
                "texture_channels": 2,
                "texture_relief": 2.0,
                "texture_drift": 0.31,
                "grain_scale": 6.039648290761679,
                "grain_contrast": 2.44,
                "bristle_count": 18,
                "bristle_spread": 0.4,
                "bristle_length": 4.0,
                "thickness": 0.0,
                "thickness_lean": 0.01,
                "blend_mode": &"pigment_mix",
                "chroma_variation": 0.12,
                "smudge_pickup_option:enabled": true,
                "smudge_pickup_option:strength": 0.33,
                "smudge_length_option:enabled": true,
                "smudge_length_option:strength": 0.85,
            },
            "pen_settings":
            {
                "size": {"sensors": [_wander("size", 0.97)], "use_same_curve": false},
                "opacity": {"sensors": [_wander("opacity", 0.97)], "enabled": true, "use_same_curve": false},
                "hardness": {"sensors": [_wander("hardness", 0.96)], "enabled": true, "use_same_curve": false},
                "strength": {"sensors": [_wander("strength", 0.9)], "use_same_curve": false},
                "thickness": {"sensors": [_wander("thickness", 0.94)]},
                "saturation":
                {"sensors": [{"id": "texture", "curve": [Vector2(0.0, 0.482), Vector2(1.0, 0.518)]}], "use_same_curve": false},
                "hue":
                {"sensors": [{"id": "texture", "curve": [Vector2(0.0, 0.491), Vector2(1.0, 0.509)]}], "use_same_curve": false},
            },
            "pressure": {"strength": falling, "radius": tapering},
        },
        # The five below are the flat tip style shelf, built from the Look
        # page's rows. Each lays an opaque body that fills in at a working
        # press with its field shown as tone and relief rather than only as
        # holes, the one thing the flat tip sets have in common, and none of
        # them stamps: what the such presets do with overlapping dabs is
        # carried over as what it does to the look. Their Texture Tone and
        # Strand Softness are the numbers they were made with carried onto the
        # rows' wider ranges by the settings' `carry_look`, so they paint as
        # they did, the tone within a twentieth of a stop.
        {
            "name": "Firm Fill",
            "tags": ["paint"],
            "bundle": BUNDLE,
            "about":
            # gdlint:ignore=max-line-length
            "A flat, opaque fill with a firm edge, the grain showing in it as light and dark and as relief rather than as holes, in the manner of an impasto flat tip, for laying in shapes that hold.",
            "settings":
            {
                "radius": 0.03,
                "hardness": 0.9,
                "strength": -0.2,
                "texture_field": "grain",
                "grain_scale": 6.0,
                "grain_contrast": 1.5,
                "fill": 0.85,
                "texture_tone": 0.242,
                "rim_firmness": 0.6,
                "texture_channels": 2,
                "texture_relief": 1.0,
                "thickness": 0.85,
            },
            "pressure": {"strength": falling},
        },
        {
            "name": "Smeary Flat",
            "tags": ["blend"],
            "bundle": BUNDLE,
            "about":
            # gdlint:ignore=max-line-length
            "Wide, soft strands that pick up the paint they cross and push it along, so a stroke smears the colour under it into its own, in the manner of smeary brushes, for blending and for wet passages.",
            "settings":
            {
                "radius": 0.035,
                "hardness": 0.8,
                "strength": -0.3,
                "texture_field": "bristle",
                "bristle_count": 16,
                "bristle_spread": 0.45,
                "bristle_length": 5.0,
                "texture_drift": 0.8,
                "strand_width": 1.4,
                "strand_softness": 0.8,
                "fill": 0.5,
                "texture_tone": 0.075,
                "texture_channels": 2,
                "texture_relief": 0.6,
                "thickness": 0.3,
                # A pickup of 0.6 an update set the carry to the paint under
                # the pen within two updates, so the stroke laid what stood
                # where it was and dragged nothing. A slow pickup and a long
                # smear carry what the stroke crossed for radii past it. The
                # composite under an empty layer is the paper, which a merged
                # pickup took in as paint and washed the stroke out with, so
                # it reads the layer it paints.
                "smudge_pickup_option:enabled": true,
                "smudge_pickup_option:strength": 0.15,
                "smudge_length_option:enabled": true,
                "smudge_length_option:strength": 0.97,
                "smudge_color_rate_option:strength": 0.28,
                "smudge_sample_merged": false,
            },
            "pressure": {"strength": falling},
        },
        {
            "name": "Sea Sponge",
            "tags": ["texture"],
            "bundle": BUNDLE,
            "about":
            # gdlint:ignore=max-line-length
            "A sponge's open, irregular print that fills in as it is worked over the same place, in the manner of a sponge, for foliage, stone and broken ground.",
            "settings":
            {
                "radius": 0.04,
                "hardness": 0.7,
                "strength": -0.3,
                "texture_field": "grain",
                "grain_scale": 9.0,
                "grain_contrast": 3.0,
                "fill": 0.3,
                "texture_tone": 0.24,
                "rim_firmness": 0.2,
                "build_up": 1.5,
                "thickness": 0.2,
            },
            "pressure": {"strength": falling},
        },
        {
            "name": "Ribbon Pen",
            "tags": ["lines"],
            "bundle": BUNDLE,
            "about":
            # gdlint:ignore=max-line-length
            "A few broad, crisp strands that keep their width to the stroke's end like a ribbon of ink, in the manner of a ribbon pen, for lettering, folds and calligraphic marks.",
            "settings":
            {
                "radius": 0.02,
                "hardness": 0.95,
                "strength": -0.2,
                "texture_field": "bristle",
                "bristle_count": 10,
                "bristle_spread": 0.3,
                "bristle_length": 8.0,
                "texture_drift": 1.0,
                "strand_width": 1.8,
                "strand_softness": 0.15,
                "strand_taper": 0.0,
                "rim_firmness": 0.7,
                "fill": 0.6,
                "texture_tone": 0.137,
                "thickness": 0.0,
            },
            "pressure": {"strength": falling, "radius": tapering},
        },
        {
            "name": "Graphite Pencil",
            "tags": ["lines"],
            "bundle": BUNDLE,
            "about":
            (
                "A fine line in the colour picked that catches the paper's tooth at a light touch and darkens as "
                + "it is gone over again, in the manner of a pencil, for drawing and hatching."
            ),
            "settings":
            {
                "radius": 0.01,
                "hardness": 0.95,
                "strength": -0.2,
                "texture_field": "grain",
                "grain_scale": 2.5,
                "grain_contrast": 2.5,
                "fill": 0.2,
                "texture_tone": 0.192,
                "rim_firmness": 0.2,
                "build_up": 2.0,
                "thickness": 0.0,
            },
            "pressure": {"strength": falling, "radius": tapering},
        },
    ]
    for recipe: Dictionary in recipes:
        recipe["formerly"] = FORMERLY
        recipe.merge(FIELDS)
    return recipes


## A slow wander along the stroke for the row *row*, from *lowest* of the row
## up to the whole of it, the sensor Broken Chalk and Wet Into Wet name by
## the row it moves.
static func _wander(row: String, lowest: float) -> Dictionary:
    return {"id": "fuzzy_along_stroke", "resource_name": row, "curve": [Vector2(0.0, lowest), Vector2(1.0, 1.0)]}


## The licence *bundle*'s recipes ship under, or empty for a bundle this table
## does not know.
static func licence_for(bundle: String) -> String:
    return String(LICENCES.get(bundle, ""))


## A fresh resource of *script* at its own defaults with *entry* written onto
## it, or null when the script cannot carry the whole recipe, read by the one
## reader every engine shares and bound by this engine's `_bind`.
static func build(script: Script, entry: Dictionary) -> Resource:
    return SaPresetRecipe.build(script, entry, _bind)


## Binds the curve options *entry* names under `lift_up` and `pressure` on
## *settings*, which the shared reader has already found there.
static func _bind(settings: Resource, entry: Dictionary) -> void:
    for key: String in entry.get("lift_up", []):
        var option := SaPresetRecipe.option(settings, key) as SaCurveOption
        # On, since Opacity's option starts off and a binding on an option
        # that is off paints nothing different.
        option.enabled = true
        option.bind_lift_up(OFFSET_OPTIONS.has(key))
    var bound: Dictionary = entry.get("pressure", {})
    for key: String in bound:
        NoiseBrushSettingsScript.bind_pressure(SaPresetRecipe.option(settings, key) as SaCurveOption, bound[key])
