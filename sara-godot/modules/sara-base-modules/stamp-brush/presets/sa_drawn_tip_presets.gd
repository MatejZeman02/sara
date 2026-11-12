## The brushes Sara ships on the tips drawn for it, a table of Sara Advanced
## Paint.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Sara's own bundle, made on twenty-three tips drawn for it, which
## `scripts/make_tips.py` turned into the files under `res://tips` with the
## `brush_name` and `brush_spacing` keys a tip carries. It is a table of its own
## rather than more rows of [SaShippedPresets]' because its licence is the
## pictures', which each recipe carries as `licence`. [method
## SaShippedPresets.entries] hands the two tables out as one.
##
## **Every recipe names its picture and a hardness of one**, so the picture is
## the dab. An image tip is softened along the hardness ellipse, and a recipe
## that named none would load at the template's nought and fade every dab from
## its centre. The soft pictures carry their softness in the picture.
##
## **The crisp marks carry a Sharpness, the soft ones none.** Hardness at one
## never makes a grey solid, so a block or a speck would paint soft where it was
## meant as a mark. Sharpness cuts each dab at its half-coverage contour. Each
## amount is read off strokes at the preset's size, and a stronger cut breaks
## Ridge's thin line and drops the smaller specks. Fir Tree stays soft because
## any cut takes its light grey branches away. A copy a painter never touched
## takes new numbers through the store's stale check, and an edited one is never
## written over.
##
## The spacing is the tip's own, save for the three speck pictures (Sparse
## Specks, Scattered Dots and Dust), which step a fifth to a thirtieth of the dab
## so the specks pile up enough to show. The dynamics follow what each picture
## is: a texture turns at random each dab, a plant or tree stays upright and
## varies its size, a line is laid along the stroke. A picture laid at one step
## that nothing turns shows as a stamp, which `scripts/dab_repetition.py`
## measures.
##
## **Streaks and Dry Strokes are bundled painter's presets**, taken field by
## field from saved files, and so they leave two of these rules: Streaks paints at
## a hardness of 0.54 with no turn, and Dry Strokes at nought in Color Dodge.
class_name SaDrawnTipPresets
extends RefCounted

## The bundle the recipes below shipped under, named on each as
## `formerly` so a profile that knew it keeps its record. They ship in Sara
## Advanced Paint, which [method SaShippedPresets.entries] writes on each.
const FORMERLY: String = "Sara drawn"

## The licence the bundle ships under. It is the pictures' licence, so a painter
## may take the tips into other work with their author credited, and each tip's
## own `Copyright` key says the same. The recipes below stay GPLv3 source like
## the rest of the module, and CC BY 4.0 pictures may ship inside a GPLv3
## program.
const LICENCE: String = "CC-BY-4.0"

## Where the pictures are, the folder [SaBrushTipMask] lists as Sara's own.
const TIPS: String = "res://tips/"

## `SaBrushTip.Kind.IMAGE` and `SaDabGeometry.Generator.IMAGE`, the pair
## `SaBrushTipMask.select` writes. Numbers, because a recipe is a table of plain
## values and the two enums are the tip's and the kernel's.
const IMAGE_TIP: int = 1
const IMAGE_GENERATOR: int = 3

## The size curves, each taking the share its name gives off the dab's size at
## the bottom of its sensor and none at the top, as in the basic set. A strength
## below one is not the same thing: `size_like` multiplies the reading by it, so
## a random size at a strength of 0.4 painted a fir tree at most two fifths of
## its Size row, which the first look at this bundle showed as a row of shrubs.
## The pressure ones thin a stroke under a light touch, the random ones make
## every stamp its own height.
const SIZE_OFF_30: Array[Vector2] = [Vector2(0.0, 0.7), Vector2(1.0, 1.0)]
const SIZE_OFF_40: Array[Vector2] = [Vector2(0.0, 0.6), Vector2(1.0, 1.0)]
const SIZE_OFF_50: Array[Vector2] = [Vector2(0.0, 0.5), Vector2(1.0, 1.0)]

## The spacing curve of the stamped pictures, a random share of each step
## taken off it, down to half at the bottom of the sensor. A stamp laid at one spacing
## comes back at that distance and its multiples, which a stroke of many
## overlapping dabs shows as a regular grain, and a step that differs dab by dab
## breaks the beat without moving the stroke off its line.
const STEP_OFF_50: Array[Vector2] = [Vector2(0.0, 0.5), Vector2(1.0, 1.0)]

## The turn a picture with a direction of its own is given each dab, a few
## degrees either way, so streaks stay diagonal and dry strokes and grass
## upright while no two dabs lie on one another exactly.
const SMALL_TURN: float = 0.03

## The opacity curve the saved presets these recipes copy carry, pressure to
## the power 1.2 sampled at nine points, where the bar's switch draws the same
## shape in three. A preset taken from a saved file keeps the nine, so it
## equals the file field for field.
const OPACITY_NINE: Array[Vector2] = [
    Vector2(0.0, 0.0),
    Vector2(0.125, 0.08246925),
    Vector2(0.25, 0.18946457),
    Vector2(0.375, 0.30820346),
    Vector2(0.5, 0.4352753),
    Vector2(0.625, 0.56892633),
    Vector2(0.75, 0.7080656),
    Vector2(0.875, 0.8519413),
    Vector2(1.0, 1.0),
]

## The colour rate the saved files carry, off and at the complement of the
## dilution they were written with. A brush that does not smudge never reads
## it, and a preset taken from a saved file keeps it so the two are equal
## field by field.
const AUTHORS_COLOUR_RATE: float = 0.19999999999999996

const ENTRIES: Array[Dictionary] = [
    {
        "name": "Torn Block",
        "tags": ["texture"],
        "formerly": FORMERLY,
        "about": "A block of flat colour with a torn edge, turned at random each dab so the edge never repeats.",
        "settings":
        {
            "radius": 0.02778,
            "hardness:value": 1.0,
            "sharpness": 0.6,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.12,
            "tip:image_path": TIPS + "torn-block.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "rotation": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
        },
    },
    {
        "name": "Smoky Blot",
        "tags": ["soft"],
        "formerly": FORMERLY,
        "about": "A smoky blot of uneven darkness, for clouds of colour and soft shadows.",
        "settings":
        {
            "radius": 0.04167,
            "hardness:value": 1.0,
            "opacity": 1.0,
            "flow:value": 0.6,
            "spacing": 0.15,
            "tip:image_path": TIPS + "smoky-blot.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "rotation": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
        },
    },
    {
        "name": "Storm Cloud",
        "tags": ["soft"],
        "formerly": FORMERLY,
        "about": "A cloud mass with light veins through it, for skies, smoke and foam.",
        "settings":
        {
            "radius": 0.06481,
            "hardness:value": 1.0,
            "opacity": 1.0,
            "flow:value": 0.7,
            "spacing": 0.2,
            "tip:image_path": TIPS + "storm-cloud.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "rotation": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
            "size": {"enabled": true, "sensors": ["fuzzy_per_dab"], "common_curve": SIZE_OFF_30},
        },
    },
    {
        "name": "Scrawled Block",
        "tags": ["texture"],
        "formerly": FORMERLY,
        "about": "A dense block of scrawled strokes, for rough fills that read as drawn.",
        "settings":
        {
            "radius": 0.03241,
            "hardness:value": 1.0,
            "sharpness": 0.7,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.2,
            "tip:image_path": TIPS + "scrawled-block.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "size": {"enabled": true, "sensors": ["pressure"], "common_curve": SIZE_OFF_30},
            "rotation": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
        },
    },
    {
        "name": "Splattered Block",
        "tags": ["scatter"],
        "formerly": FORMERLY,
        "about": "A dark block breaking into splatter on one side, for weathered and broken surfaces.",
        "settings":
        {
            "radius": 0.03704,
            "hardness:value": 1.0,
            "sharpness": 0.7,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.2,
            "tip:image_path": TIPS + "splattered-block.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "rotation": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
        },
    },
    # One round dot, the one picture of the bundle made rather than drawn: a
    # disc seven tenths of its 204 texel square, soft over its last six. The
    # drawn row of dashes it replaced, stamped at 0.9 of itself and turned to
    # the stroke, painted a train of scratchy marks. Spacing is a share of the
    # tip's width, so 1.4 leaves a gap as wide as a dot. A dot has no
    # direction and is not turned. The pen sizes a dot rather than fading it,
    # down to half at the lightest touch rather than losing it, and the two
    # pressure switches are set too, so Tool Options says so.
    {
        "name": "Dotted Line",
        "tags": ["lines"],
        "formerly": FORMERLY,
        "about": "A row of round dots laid along the stroke, for stitching, tracks and dotted edges.",
        "settings":
        {
            "radius": 0.02315,
            "hardness:value": 1.0,
            "sharpness": 0.6,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 1.4,
            "size_by_pressure": true,
            "opacity_by_pressure": false,
            "tip:image_path": TIPS + "dotted-line.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "size": {"enabled": true, "sensors": ["pressure"], "common_curve": SIZE_OFF_50},
        },
    },
    {
        "name": "Sparse Specks",
        "tags": ["scatter"],
        "formerly": FORMERLY,
        "about":
        (
            "A few far-apart specks thrown round the stroke, for dust on a surface or distant birds. "
            + "Under a size of about 10 px its specks are finer than a pixel and it lays little or nothing."
        ),
        "settings":
        {
            "radius": 0.05556,
            "hardness:value": 1.0,
            "sharpness": 0.6,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.03,
            "tip:image_path": TIPS + "sparse-specks.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "rotation": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
            "scatter": {"enabled": true, "strength": 0.5, "sensors": ["fuzzy_per_dab"]},
            "size": {"enabled": true, "sensors": ["fuzzy_per_dab"], "common_curve": SIZE_OFF_50},
        },
    },
    {
        "name": "Scattered Dots",
        "tags": ["scatter"],
        "formerly": FORMERLY,
        "about": "A spray of small dots, each dab turned and sized at random, for snow, pebbles and stippling.",
        "settings":
        {
            "radius": 0.04167,
            "hardness:value": 1.0,
            "sharpness": 0.6,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.15,
            "tip:image_path": TIPS + "scattered-dots.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "rotation": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
            "size": {"enabled": true, "sensors": ["fuzzy_per_dab"], "common_curve": SIZE_OFF_40},
        },
    },
    {
        "name": "Dust",
        "tags": ["scatter"],
        "formerly": FORMERLY,
        "about": "Faint broken specks of grit, for dust, rust and the tooth of an old surface.",
        "settings":
        {
            "radius": 0.0463,
            "hardness:value": 1.0,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.25,
            "tip:image_path": TIPS + "dust.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "rotation": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
        },
    },
    {
        "name": "Streaks",
        "tags": ["soft"],
        "formerly": FORMERLY,
        "about":
        (
            "A band of fine streaks running with the stroke, soft at their ends, for rain, speed and hatched "
            + "shading. It paints in a mixing blend mode where a mixing module is installed, so "
            + "over another colour it mixes as paint does, blue over yellow turning green."
        ),
        "settings":
        {
            "radius": 0.02778,
            "hardness:value": 0.54,
            "opacity": 1.0,
            "flow:value": 0.7,
            "spacing": 0.15,
            "blend_mode": &"pigment_mix",
            "painting_mode": 0,
            "tip:image_path": TIPS + "streaks.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
            "tip:auto_spacing": true,
            "tip:auto_spacing_coeff": 0.45,
            "smudge_color_rate_option:enabled": false,
            "smudge_color_rate_option:strength": AUTHORS_COLOUR_RATE,
        },
        "pen_settings":
        {
            "opacity": {"sensors": ["pressure"], "common_curve": OPACITY_NINE},
            "size": {"enabled": true, "sensors": ["pressure"], "common_curve": SIZE_OFF_30},
        },
    },
    # Drawn as a horizontal ridge, so the drawing angle lays it along the stroke
    # and half its length between dabs keeps the line joined.
    {
        "name": "Ridge",
        "tags": ["lines"],
        "formerly": FORMERLY,
        "about": "A rough ragged line laid along the stroke, for skylines, ridges and broken edges.",
        "settings":
        {
            "radius": 0.03241,
            "hardness:value": 1.0,
            "sharpness": 0.5,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.5,
            "tip:image_path": TIPS + "ridge.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "rotation": {"enabled": true, "strength": 1.0, "sensors": [{"id": "drawing_angle", "angle_offset": 0.0}]},
            "mirror": {"enabled": true, "sensors": ["fuzzy_per_dab"]},
            "spacing": {"enabled": true, "sensors": ["fuzzy_per_dab"], "common_curve": STEP_OFF_50},
        },
    },
    {
        "name": "Palm Fronds",
        "tags": ["scatter"],
        "formerly": FORMERLY,
        "about": "A spray of long leaves spaced at their own width, for palms and broad-leaved plants.",
        "settings":
        {
            "radius": 0.07407,
            "hardness:value": 1.0,
            "sharpness": 0.7,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 1.0,
            "tip:image_path": TIPS + "palm-fronds.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "size": {"enabled": true, "sensors": ["fuzzy_per_dab"], "common_curve": SIZE_OFF_30},
        },
    },
    # A small turn and no more, because a twig turned upside down reads as a
    # different plant.
    {
        "name": "Leafy Twig",
        "tags": ["scatter"],
        "formerly": FORMERLY,
        "about": "A twig with leaves, tilted a little at random each stamp, for hedges and branches.",
        "settings":
        {
            "radius": 0.06019,
            "hardness:value": 1.0,
            "sharpness": 0.6,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.8,
            "tip:image_path": TIPS + "leafy-twig.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "rotation": {"enabled": true, "strength": 0.08, "sensors": ["fuzzy_per_dab"]},
            "size": {"enabled": true, "sensors": ["fuzzy_per_dab"], "common_curve": SIZE_OFF_30},
            "mirror": {"enabled": true, "sensors": ["fuzzy_per_dab"]},
            "spacing": {"enabled": true, "sensors": ["fuzzy_per_dab"], "common_curve": STEP_OFF_50},
        },
    },
    {
        "name": "Bush",
        "tags": ["scatter"],
        "formerly": FORMERLY,
        "about": "A bush of upright strokes, overlapping into undergrowth along the stroke.",
        "settings":
        {
            "radius": 0.05556,
            "hardness:value": 1.0,
            "sharpness": 0.6,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.5,
            "tip:image_path": TIPS + "bush.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "size": {"enabled": true, "sensors": ["fuzzy_per_dab"], "common_curve": SIZE_OFF_40},
            "mirror": {"enabled": true, "sensors": ["fuzzy_per_dab"]},
        },
    },
    {
        "name": "Grass Tuft",
        "tags": ["scatter"],
        "formerly": FORMERLY,
        "about": "A tuft of grass blades, laid close so a stroke is a strip of meadow.",
        "settings":
        {
            "radius": 0.04167,
            "hardness:value": 1.0,
            "sharpness": 0.7,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.35,
            "tip:image_path": TIPS + "grass-tuft.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "size": {"enabled": true, "sensors": ["fuzzy_per_dab"], "common_curve": SIZE_OFF_30},
            "rotation": {"enabled": true, "strength": SMALL_TURN, "sensors": ["fuzzy_per_dab"]},
            "mirror": {"enabled": true, "sensors": ["fuzzy_per_dab"]},
            "spacing": {"enabled": true, "sensors": ["fuzzy_per_dab"], "common_curve": STEP_OFF_50},
        },
    },
    # Upright and never turned, so a row of them stands like a forest, and only
    # the height varies. The tree is drawn in tones on a photograph, and its
    # texels cover a third on average, so a stamp lays the colour picked at full
    # in its darkest needles alone. The layer holds that colour to the level,
    # and on a light ground the tree reads paler, which the line says rather
    # than the tree being redrawn.
    {
        "name": "Fir Tree",
        "tags": ["scatter"],
        "formerly": FORMERLY,
        "about":
        (
            "A fir tree stamped along the stroke at varying heights, for a forest edge in one line. "
            + "The tree is drawn in tones, so only its darkest needles lay the colour at full "
            + "and the rest of it reads paler."
        ),
        "settings":
        {
            "radius": 0.07407,
            "hardness:value": 1.0,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.6,
            "tip:image_path": TIPS + "fir-tree.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "size": {"enabled": true, "sensors": ["fuzzy_per_dab"], "common_curve": SIZE_OFF_40},
            "mirror": {"enabled": true, "sensors": ["fuzzy_per_dab"]},
            "spacing": {"enabled": true, "sensors": ["fuzzy_per_dab"], "common_curve": STEP_OFF_50},
        },
    },
    {
        "name": "Scribble Marks",
        "tags": ["texture"],
        "formerly": FORMERLY,
        "about": "Loose scribbled marks, turned at random, for lively texture over a flat area.",
        "settings":
        {
            "radius": 0.03704,
            "hardness:value": 1.0,
            "sharpness": 0.7,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.3,
            "tip:image_path": TIPS + "scribble-marks.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "rotation": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
        },
    },
    {
        "name": "Dry Strokes",
        "tags": ["texture"],
        "formerly": FORMERLY,
        "about":
        (
            "A dry, scratchy band along the stroke, for catching the light on bark, wood and rough fabric. "
            + "It paints in Colour Dodge, so it brightens what lies under it towards white whatever the colour "
            + "picked, and lays nothing visible on white."
        ),
        "settings":
        {
            "radius": 0.01259497966823432,
            "hardness:value": 0.0,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.25,
            "blend_mode": &"color_dodge",
            "painting_mode": 0,
            "tip:image_path": TIPS + "dry-strokes.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
            "tip:angle": 0.8203047484373349,
            "smudge_color_rate_option:enabled": false,
            "smudge_color_rate_option:strength": AUTHORS_COLOUR_RATE,
        },
        "pen_settings":
        {
            "opacity": {"sensors": ["pressure"], "common_curve": OPACITY_NINE},
            "size": {"enabled": true, "sensors": ["pressure"], "common_curve": SIZE_OFF_30},
            "rotation":
            {
                "enabled": true,
                "use_same_curve": false,
                "common_curve": [Vector2(0.0, 0.0), Vector2(1.0, 0.334368)],
                "sensors":
                [
                    {"id": "fuzzy_per_dab", "curve": [Vector2(0.0, 0.0), Vector2(1.0, 0.31034455)]},
                    {"id": "fuzzy_per_stroke", "curve": [Vector2(0.0, 0.0), Vector2(0.37448853, 0.16865417), Vector2(1.0, 1.0)]},
                ],
            },
        },
    },
    {
        "name": "Lichen",
        "tags": ["texture"],
        "formerly": FORMERLY,
        "about": "A mottled disc of dark rings and light holes, for lichen, foam and stone.",
        "settings":
        {
            "radius": 0.04167,
            "hardness:value": 1.0,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.3,
            "tip:image_path": TIPS + "lichen.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "rotation": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
        },
    },
    {
        "name": "Scumble",
        "tags": ["texture"],
        "formerly": FORMERLY,
        "about": "Broken scumbled colour, turned at random, for foliage masses and rough paint.",
        "settings":
        {
            "radius": 0.04167,
            "hardness:value": 1.0,
            "opacity": 1.0,
            "flow:value": 0.8,
            "spacing": 0.3,
            "tip:image_path": TIPS + "scumble.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "rotation": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
        },
    },
    {
        "name": "Flecks",
        "tags": ["scatter"],
        "formerly": FORMERLY,
        "about": "A cluster of flecks with strays round it, for leaves in the wind and broken highlights.",
        "settings":
        {
            "radius": 0.03704,
            "hardness:value": 1.0,
            "sharpness": 0.7,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.4,
            "tip:image_path": TIPS + "flecks.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "rotation": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
            "size": {"enabled": true, "sensors": ["fuzzy_per_dab"], "common_curve": SIZE_OFF_30},
        },
    },
    {
        "name": "Soft Haze",
        "tags": ["soft"],
        "formerly": FORMERLY,
        "about": "A soft haze with a grain in it, for glow, mist and gentle shading.",
        "settings":
        {
            "radius": 0.06019,
            "hardness:value": 1.0,
            "opacity": 1.0,
            "flow:value": 0.3,
            "spacing": 0.08,
            "tip:image_path": TIPS + "soft-haze.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "rotation": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
        },
    },
    {
        "name": "Cloud Puff",
        "tags": ["soft"],
        "formerly": FORMERLY,
        "about": "A soft puff of cloud, turned and sized at random, for skies and smoke.",
        "settings":
        {
            "radius": 0.05556,
            "hardness:value": 1.0,
            "opacity": 1.0,
            "flow:value": 0.6,
            "spacing": 0.2,
            "tip:image_path": TIPS + "cloud-puff.png",
            "tip:kind": IMAGE_TIP,
            "tip:generator": IMAGE_GENERATOR,
        },
        "pen_settings":
        {
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "rotation": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
            "size": {"enabled": true, "sensors": ["fuzzy_per_dab"], "common_curve": SIZE_OFF_30},
        },
    },
]
