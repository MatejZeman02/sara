## Brushes made of the basic set by setting the same options again and again,
## a table of Sara Advanced Paint.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Settings painters keep setting, turned into presets.** A painter loads a
## shipped preset and sets the same options on it stroke after stroke. An
## option set on fewer than nine strokes of ten, where the strokes that set it
## are a use of their own, is a preset beside the one it was set on, named for
## that use, and these five are the stamp brush's. Each comment says in words
## what the painter is doing with it.
##
## **A table of its own rather than more rows in the basic one**, for the reason
## the comments give: each says what the painter is doing with it, and the
## basic table stays the twenty-one the rest of Sara counts.
##
## Each keeps the settings of the preset it was made from and changes only what
## the painters changed, written the way [SaShippedPresets] writes the basic
## set. Size and opacity on the pen's pressure are written as the bar's two
## switches, `size_by_pressure` and `opacity_by_pressure`, which draw the curve
## a painter gets by ticking them and which the painters' strokes were laid
## along.
##
## **Build-up, the mode's own default, written out**, for the reason Chisel
## Marker in [SaShippedPresets] gives: the two switches are fields of the old
## settings script as well, and a recipe naming nothing that script lacks would
## be written into a legacy store too, where the dozen suites that install from
## it count on the basic set's first three.
class_name SaHabitPresets
extends RefCounted

## The bundle the recipes below shipped under, named on each as
## `formerly` so a profile that knew it keeps its record. The tag is the name
## the bundle was saved under before this class was named for what it holds,
## and it is read as it was written. They ship in Sara
## Advanced Paint, which [method SaShippedPresets.entries] writes on each.
const FORMERLY: String = "Sara residency"

## The licence the bundle ships under, the module's own, since the recipes are
## source inside a GPLv3 module and are distributed as part of it.
const LICENCE: String = "GPL-3.0-or-later"

## Pointed Mark's size along the pen's reading, a fifth of the full width at
## the lightest touch and the rest along the reading to the power 2.4, written
## at the nine points the bar's switch draws its own curve at.
##
## **The floor is a hair rather than nothing.** On the switch's own curve, the
## reading to the power 4.8 from nothing, the lightest touches lay no mark at
## all and the next lay a line a pixel wide, so a taper lifted to nought loses
## its tip and one held light ends in a grey wire. A fifth of the 9 px the
## preset ships at is a line 1.8 px wide, which reads as a full-strength hair
## wherever it falls in a texel.
##
## **The power is the switch's own at a gamma of one**, 2.4, rather than its
## 4.8, so the width rises out of the floor at the light end as well: a curve of
## 4.8 lifted onto the same floor is flat under a fifth of the pen's range,
## where every touch lays the floor and nothing else.
const POINTED_MARK_SIZE: Array[Vector2] = [
    Vector2(0.0, 0.2),
    Vector2(0.125, 0.205441),
    Vector2(0.25, 0.228717),
    Vector2(0.375, 0.275992),
    Vector2(0.5, 0.351572),
    Vector2(0.625, 0.458942),
    Vector2(0.75, 0.601086),
    Vector2(0.875, 0.780643),
    Vector2(1.0, 1.0),
]

const ENTRIES: Array[Dictionary] = [
    # Fill with its size on pressure, for a mark as a hard stroke that comes to
    # a point: pressed from its least to full at the middle and back, a hard
    # stroke is a lens that comes to a point, where a round end reads as a pill.
    # Fill's own radius is two hundred pixels for covering ground, and this is
    # the median the painters laid such marks at, 4.5 px.
    #
    # Its opacity is off the pen, so only the width follows it, and its size
    # runs along [constant POINTED_MARK_SIZE]. With the opacity on the pen as
    # well, a taper's end goes pale before it goes thin.
    {
        "name": "Pointed Mark",
        "tags": ["lines"],
        "formerly": FORMERLY,
        "about":
        (
            "A hard round whose size alone follows the pen's pressure, so a stroke pressed in and let go comes to a point "
            + "and shows its length and its direction. The lightest touch lays a hair a fifth of its width, "
            + "in the colour picked."
        ),
        "settings":
        {
            "radius": 0.004167,
            "hardness:value": 1.0,
            "opacity": 1.0,
            "flow:value": 1.0,
            "stabilizer_mode": 0,
            "pixel_mode_when_small": false,
            "painting_mode": 0,
            "size_by_pressure": true,
            "opacity_by_pressure": false,
        },
        "pen_settings": {"size": {"common_curve": POINTED_MARK_SIZE}},
    },
    # Paint with its size on pressure and its opacity off it, for a soft round
    # in the darker side's colour along an edge, its radius growing along the
    # stroke as the edge softens, from a few pixels at the object to tens of
    # them along a cast shadow. Paint's stabilizer stays, because a scripted
    # path needs no smoothing and a hand does.
    {
        "name": "Shadow Edge",
        "tags": ["paint"],
        "formerly": FORMERLY,
        "about":
        (
            "A soft round whose size follows the pen's pressure while its colour stays whole, "
            + "for an edge that softens along its length, a cast shadow's from the object out."
        ),
        "settings":
        {
            "radius": 0.023148,
            "hardness:value": 0.0,
            "opacity": 1.0,
            "flow:value": 0.5,
            "stabilizer_mode": 1,
            "stabilizer_amount": 0.5,
            "painting_mode": 0,
            "size_by_pressure": true,
            "opacity_by_pressure": false,
        },
    },
    # Blender reading its own layer alone, for blending the steps of a turn
    # under glazes that sit on layers of their own. A Blender that reads every
    # layer lays the glaze's colour into the paint under it, which the glaze
    # then glazes a second time. Over a bare part of its layer its pickup is
    # nothing, so there it lays the colour picked, and the about line says so.
    {
        "name": "Layer Blender",
        "tags": ["blend"],
        "formerly": FORMERLY,
        "about":
        (
            "A soft round that blends the paint of the layer it is on and nothing else, "
            + "so a glaze or a shadow on another layer is not blended into it. "
            + "Where the layer is bare there is nothing to blend, and it lays the colour picked."
        ),
        "settings":
        {
            "radius": 0.037,
            "hardness:value": 0.1,
            "opacity": 1.0,
            "flow:value": 0.5,
            "spacing": 0.05,
            "smudge_mode": 2,
            "smudge_pickup_option:enabled": true,
            "smudge_pickup_option:strength": 1.0,
            "smudge_color_rate_option:enabled": true,
            "smudge_color_rate_option:strength": 0.0,
            "smudge_length_option:enabled": true,
            "smudge_length_option:strength": 0.9,
            "smudge_sample_merged": false,
        },
        "pen_settings": {"opacity": {"enabled": true, "sensors": ["pressure"]}},
    },
    # Fill in wash through the Paper Grain, for a watercolour or an ink wash.
    # Wash only stops a stroke below full opacity, so the strokes that count as
    # this use are the ones laid under it, and the radius, the hardness and the
    # opacity are the medians the painters laid the grain's washes at, 35 px and
    # 0.36. Everything else is Fill's. Named for the paper rather than
    # Watercolour, a word wider than any other preset's, which would widen every
    # cell of the docker's grid and take two columns.
    {
        "name": "Paper Wash",
        "tags": ["paint"],
        "formerly": FORMERLY,
        "about":
        (
            "A soft wash through the paper's grain that stops at its opacity however often a stroke crosses itself, "
            + "so a passage laid in one pass is one even tint, for watercolour and ink washes."
        ),
        "settings":
        {
            "radius": 0.032407,
            "hardness:value": 0.15,
            "opacity": 0.36,
            "flow:value": 1.0,
            "stabilizer_mode": 0,
            "pixel_mode_when_small": false,
            "painting_mode": 1,
            "pattern_name": "Paper Grain",
            "texture_contrast": 0.6,
        },
        "pen_settings": {"texture": {"enabled": true, "strength": 0.8}},
    },
    # Eraser in wash, for lifting a lighter value out of a wash or out of a
    # graphite tone: the hair and the reflected light of a head, and the wet
    # edge of a watercolour. The strokes that count as this use are the ones in
    # wash under full opacity, and the hardness and the opacity are the
    # commonest the painters set. Everything else is Eraser's.
    {
        "name": "Lift",
        "tags": ["eraser"],
        "formerly": FORMERLY,
        "about":
        (
            "An eraser that lifts paint to half its strength and no further however often a stroke crosses "
            + "itself, for taking a lighter value out of a wash or a graphite tone. It paints in the Erase "
            + "mode, so the colour picked plays no part."
        ),
        "settings":
        {
            "radius": 0.028,
            "hardness:value": 0.8,
            "opacity": 0.5,
            "flow:value": 1.0,
            "spacing": 0.06,
            "blend_mode": &"erase",
            "painting_mode": 1,
        },
        "pen_settings": {"size": {"enabled": true, "sensors": ["pressure"]}},
    },
]
