## The brush editor's Brush Tip page, as the rows it declares.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Its own file rather than lines in `module.gd`**, as the Colour, Texture
## and Masking pages are, because the rows of the page are one responsibility
## and the module's registration another. It was cut out when every row came
## to be written in one expression and the module passed a thousand lines.
## The module hands [method rows] to the Masking Brush page and names this
## page's constants for its own conditions, and this file names the
## module back nowhere, since a page naming the module it is declared by is a
## cycle at parse time.
class_name SaTipPage
extends RefCounted

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The page's title, every row's `page` but the four on General.
const PAGE: String = "Brush Tip"

## The module's General page, which Cross and the airbrush three moved to.
const GENERAL_PAGE: String = "General"

## The `tip_generator` id that means a picture rather than a formula, and the two
## headings the Brush Tip page's rows sit under.
##
## Named rather than written as a 3 in six conditions: the ids are the generator
## enum's and a generator inserted before Image would move it, which is exactly
## the trap a stored choice id avoids everywhere else in Sara.
const TIP_IMAGE_ID: int = 3
const SECTION_PROCEDURAL: String = "Procedural"
const SECTION_MASK: String = "Mask"


## The tip's own rows, which reach into `settings.tip` rather than sitting on
## the settings themselves.
##
## **There is no Fade row.** Hardness above already is it: the kernel's fade
## slot is the hardness with nothing in between, so a second slider here would
## be two controls writing one number and whichever moved last would win. The
## tip keeps `horizontal_fade` and `vertical_fade` as separate fields because a
## Krita preset has two, and the brush writes both from Hardness before each
## dab.
##
## Every row is `bar = false`: at 1920 the top bar has tens of pixels spare once
## the preset button is on it, which is also what puts everything past Shape and
## Ratio behind the advanced toggle.
static func rows() -> Array[SaOptionSpec]:
    var generator := SaOptionSpec.make_enum(
        &"tip_generator",
        "Tip",
        [0, 1, 2, 3],
        ["Default", "Gaussian", "Soft Curve", "Image"],
        {
            "page": PAGE,
            "property": ^"tip:generator",
            "bar": false,
            "width": 96,
            "tooltip":
            (
                "How the edge fades. Default has a firm edge, Gaussian fades smoothly, Soft Curve follows "
                + "the Falloff curve, and Image paints with a picture."
            )
        }
    )

    var shape := SaOptionSpec.make_enum(
        &"tip_shape",
        "Shape",
        [0, 1],
        ["Circle", "Rectangle"],
        {
            "page": PAGE,
            "property": ^"tip:shape",
            "bar": false,
            "width": 96,
            "tooltip": "The outline the falloff is measured against. A rectangle ignores the Tip setting above.",
            "section": SECTION_PROCEDURAL,
            "shown_when": {"key": &"tip_generator", "value": TIP_IMAGE_ID, "equals": false}
        }
    )

    var ratio := SaOptionSpec.make_float(
        &"tip_ratio",
        "Ratio",
        0.01,
        1.0,
        0.01,
        {
            "page": PAGE,
            "property": ^"tip:ratio",
            "bar": false,
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "tooltip": "Roundness. 100 is a circle, lower values flatten it.",
            "section": SECTION_PROCEDURAL,
            "shown_when": {"key": &"tip_generator", "value": TIP_IMAGE_ID, "equals": false}
        }
    )

    # The tip's fixed turn, Krita's Angle beside Ratio. Every dab turns by it
    # before the Rotation option's sensors add theirs, and an imported `.kpp`
    # sets it, so without a row an imported tip's angle is invisible and a
    # painter cannot set one. Stored in radians, as `SaBrushTip.angle` reads it,
    # and shown in degrees through the display scale. No section, because an
    # image tip turns by it as well. The noise brush declares the same row word
    # for word under the same key, because the docker builds one row for a key
    # whichever engine came first.
    var angle := SaOptionSpec.make_float(
        &"tip_angle",
        "Angle",
        0.0,
        TAU,
        deg_to_rad(1.0),
        {
            "page": PAGE,
            "property": ^"tip:angle",
            "bar": false,
            "display_scale": 180.0 / PI,
            "decimals": 0,
            "suffix": "°",
            "tooltip": "The tip's fixed turn. The Rotation page's sensors turn it further from here."
        }
    )

    var softness := (
        SaOptionSpec
        . make_float(
            &"tip_softness",
            "Softness",
            0.0,
            1.0,
            0.01,
            {
                "page": PAGE,
                "property": ^"tip:softness",
                "bar": false,
                "advanced": true,
                "percent": true,
                "suffix": "%",
                "decimals": 0,
                "section": SECTION_PROCEDURAL,
                "shown_when": {"key": &"tip_generator", "value": TIP_IMAGE_ID, "equals": false},
                # "Isn't it just our hardness?" It is not the same number today, and the
                # tooltip says which is which rather than leaving a painter to find out.
                "tooltip":
                (
                    "Scales the edge's fade and the Soft Curve tip's falloff: 0 is a hard edge, 100 changes nothing. "
                    + "Hardness on the bar sets how wide that fade is, and this scales it."
                )
            }
        )
    )

    # The curve the softness above scales, on a graph of its own.
    #
    # Under Softness because the two shape one edge: Softness lerps this curve
    # towards full coverage and this is the curve it lerps. A `.kpp` carries
    # one, so without this row an imported brush paints a falloff its painter
    # cannot see or undo.
    var falloff := SaOptionSpec.make(
        &"tip_falloff",
        "Falloff",
        SaOptionSpec.Kind.CURVE,
        {
            "page": PAGE,
            "property": ^"tip:softness_curve",
            "bar": false,
            "advanced": true,
            "section": SECTION_PROCEDURAL,
            "shown_when": {"key": &"tip_generator", "value": TIP_IMAGE_ID, "equals": false},
            "tooltip": "The shape the edge falls off along, from full coverage at the centre to nothing at the rim."
        }
    )

    var spikes := SaOptionSpec.make_float(
        &"tip_spikes",
        "Spikes",
        2.0,
        20.0,
        1.0,
        {
            "page": PAGE,
            "kind": SaOptionSpec.Kind.INT,
            "property": ^"tip:spikes",
            "bar": false,
            "advanced": true,
            "width": 84,
            "tooltip": "2 is the plain ellipse. More folds the shape into that many petals.",
            "in_editor": false
        }
    )

    var density := SaOptionSpec.make_float(
        &"tip_density",
        "Density",
        0.0,
        1.0,
        0.01,
        {
            "page": PAGE,
            "property": ^"tip:density",
            "bar": false,
            "advanced": true,
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "tooltip": "The share of the dab's pixels that take paint at all, which is a spatter rather than a fade.",
            "in_editor": false
        }
    )

    var randomness := SaOptionSpec.make_float(
        &"tip_randomness",
        "Randomness",
        0.0,
        1.0,
        0.01,
        {
            "page": PAGE,
            "property": ^"tip:randomness",
            "bar": false,
            "advanced": true,
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "tooltip": "How far each pixel that does take paint may fall short of full coverage.",
            "section": SECTION_PROCEDURAL,
            "shown_when": {"key": &"tip_generator", "value": TIP_IMAGE_ID, "equals": false}
        }
    )

    var antialias := SaOptionSpec.make(
        &"tip_antialias",
        "Anti-aliasing",
        SaOptionSpec.Kind.BOOL,
        {
            "page": PAGE,
            "property": ^"tip:antialias_edges",
            "bar": false,
            "advanced": true,
            "tooltip": "Smooth the edge of the dab.",
            "in_editor": false
        }
    )

    # --- The spacing rows ------------------------------------------------
    #
    # The spacing walk reads `spacing` every dab, and without a row a painter
    # could change it only by editing a preset file.
    var spacing := SaOptionSpec.make_float(
        &"spacing",
        "Spacing",
        0.01,
        1.0,
        0.01,
        {
            "page": PAGE,
            "bar": false,
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "tooltip": "How far the brush travels between dabs, as a share of the tip's size."
        }
    )

    var auto_spacing := SaOptionSpec.make(
        &"tip_auto_spacing",
        "Auto spacing",
        SaOptionSpec.Kind.BOOL,
        {
            "page": PAGE,
            "property": ^"tip:auto_spacing",
            "bar": false,
            "advanced": true,
            "tooltip":
            (
                "Space the dabs by the square root of the tip's size instead of a share of it, "
                + "so a very large brush does not paint in visible lumps."
            )
        }
    )

    var auto_coeff := SaOptionSpec.make_float(
        &"tip_auto_spacing_coeff",
        "Auto spacing amount",
        0.1,
        3.0,
        0.05,
        {
            "page": PAGE,
            "property": ^"tip:auto_spacing_coeff",
            "bar": false,
            "advanced": true,
            "decimals": 2,
            "tooltip": "Multiplies the automatic spacing. Only used with Auto spacing.",
            "enabled_when": &"tip_auto_spacing",
            "enabled_when_values": [true]
        }
    )

    # --- Sharpness --------------------------------------------------------
    #
    # Both advanced, which the bar's handful of spare pixels would decide
    # anyway. Sharpness at anything above zero is a different kind of brush
    # rather than a stronger one, so it is not a row a painter meets by
    # accident.
    var sharpness := SaOptionSpec.make_float(
        &"sharpness",
        "Sharpness",
        0.0,
        1.0,
        0.01,
        {
            "page": PAGE,
            "bar": false,
            "advanced": true,
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "in_editor": false,
            "tooltip":
            (
                "Snaps each dab onto the pixel grid and cuts its edge to opaque or clear. "
                + "At 100 the brush is a pen rather than a brush."
            )
        }
    )

    var sharpness_softness := SaOptionSpec.make_float(
        &"sharpness_softness",
        "Edge softness",
        0.0,
        1.0,
        0.01,
        {
            "page": PAGE,
            "bar": false,
            "advanced": true,
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "in_editor": false,
            "tooltip": "How much of the soft edge Sharpness keeps. Only used when Sharpness is above 0."
        }
    )

    # --- The per-dab mirror -----------------------------------------------
    #
    # Two Mirror controls exist now and they are not the same thing, so both
    # tooltips say which is which rather than leaving a painter to find out.
    # Which tip, as the door's grid of the tips' pictures under a filter of
    # their folders. The value is the file's path, so a stored layout keeps a
    # name and a scenario can name a file. A picture rather than an `ENUM` of
    # names, whose choices would be fixed when this spec is made, because a list
    # of names is no way to choose a picture.
    var tip_file := (
        SaOptionSpec
        . make_tip_image(
            &"tip_image_path",
            "Tip image",
            {
                "page": PAGE,
                "bar": false,
                "advanced": true,
                "section": SECTION_MASK,
                "shown_when": {"key": &"tip_generator", "value": TIP_IMAGE_ID},
                # The noise brush's sentence word for word, because the docker builds one
                # row for the key whichever engine declared it first.
                "tooltip":
                (
                    "The tip image. Choose from Sara's tips, imported tips or a folder. "
                    + "The filter above shows one folder at a time."
                )
            }
        )
    )

    # The door for an image tip. An action rather than a text field, because a
    # painter picks a file and a path typed by hand is a path typed wrong.
    # Picking Image in the Tip row above without ever having loaded one paints
    # nothing, which is why the tooltip names this row.
    var load_tip := SaOptionSpec.make(
        &"tip_load",
        "Load Tip",
        SaOptionSpec.Kind.ACTION,
        {
            "page": PAGE,
            "on_tool": true,
            "property": ^"load_tip_dialog",
            "bar": false,
            "advanced": true,
            "section": SECTION_MASK,
            "shown_when": {"key": &"tip_generator", "value": TIP_IMAGE_ID},
            "tooltip": "Reads a .png or a .gbr and paints with it. A .gih pipe paints its cells. An .abr lists its tips to pick."
        }
    )

    # What the picture does to the dab, Krita's brush application, under the
    # Mask heading above the Lightness row it decides about. A grey picture is a
    # mask whose lightness is mid grey throughout, so its gradient map is the
    # ramp's middle, which the tooltip says rather than a row that hides.
    var mode := SaOptionSpec.make_enum(
        &"tip_mode",
        "Mode",
        [0, 1, 2],
        ["Mask", "Lightness Map", "Gradient Map"],
        {
            "page": PAGE,
            "property": ^"tip_mode",
            "bar": false,
            "advanced": true,
            "width": 120,
            "section": SECTION_MASK,
            "shown_when": {"key": &"tip_generator", "value": TIP_IMAGE_ID},
            "tooltip":
            (
                "What the picture does to the colour. Mask lays the brush colour through its shape, Lightness Map "
                + "moves that colour by the picture's lightness, and Gradient Map paints each part in the colour "
                + "the Gradient row on the Colour Dynamics page holds at that lightness. A grey picture has mid grey "
                + "lightness throughout, so it maps to the gradient's middle."
            )
        }
    )

    # The tip's own lightness over the dab's colour. On the Brush Tip page
    # under the Mask heading, with the other rows that only mean something for
    # a picture, and advanced for the reason the two below are: at nought it
    # changes nothing and at anything else it is a different kind of brush
    # rather than a stronger one.
    #
    # **Only shown for a tip whose picture carries colour**, which is what the
    # row acts on: a grey mask has no lightness of its own to apply, and a row
    # that moved nothing on it would be a control that lies.
    var lightness := SaOptionSpec.make_float(
        &"tip_lightness",
        "Lightness",
        0.0,
        1.0,
        0.01,
        {
            "page": PAGE,
            "property": ^"tip:lightness_strength",
            "bar": false,
            "advanced": true,
            "percent": true,
            "suffix": "%",
            "decimals": 0,
            "section": SECTION_MASK,
            "shown_when": {"key": &"tip_generator", "value": TIP_IMAGE_ID},
            "enabled_when": &"tip_mode",
            "enabled_when_values": [int(SettingsScript.TipMode.LIGHTNESS_MAP)],
            "tooltip":
            (
                "How far the tip picture's own lightness moves the colour this brush lays: dark areas darken it "
                + "and light areas lighten it, with the middle of the picture changing nothing. "
                + "Read off a picture that carries colour, and nothing at all off a grey tip. Only in Lightness Map mode."
            )
        }
    )

    var mirror_h := SaOptionSpec.make(
        &"tip_mirror_horizontal",
        "Mirror Tip H",
        SaOptionSpec.Kind.BOOL,
        {
            "page": PAGE,
            "property": ^"tip:mirror_horizontal",
            "bar": false,
            "advanced": true,
            "label": "H",
            "section": SECTION_MASK,
            "shown_when": {"key": &"tip_generator", "value": TIP_IMAGE_ID},
            "pair_with": &"tip_mirror_vertical",
            "pair_label": "Mirror tip",
            "tooltip":
            (
                "Flips the tip inside its own dab, left for right. Not the same as Mirror H on the top bar, "
                + "which paints a second image of the whole stroke."
            )
        }
    )

    var mirror_v := SaOptionSpec.make(
        &"tip_mirror_vertical",
        "Mirror Tip V",
        SaOptionSpec.Kind.BOOL,
        {
            "page": PAGE,
            "property": ^"tip:mirror_vertical",
            "bar": false,
            "advanced": true,
            "label": "V",
            "section": SECTION_MASK,
            "shown_when": {"key": &"tip_generator", "value": TIP_IMAGE_ID},
            "tooltip":
            (
                "Flips the tip inside its own dab, top for bottom. Not the same as Mirror V on the top bar, "
                + "which paints a second image of the whole stroke."
            )
        }
    )

    # --- The painting mode ------------------------------------------------
    #
    # Not advanced. It is the difference between a stroke that darkens where it
    # crosses itself and one that does not, which is the first thing a painter
    # coming from another program looks for, and it is one dropdown. "Cross"
    # names what it settles: how a stroke that crosses its own path composes. On
    # General rather than the Brush Tip page, because it is not a tip setting.
    var painting_mode := SaOptionSpec.make_enum(
        &"painting_mode",
        "Cross",
        [0, 1],
        ["Build-up", "Wash"],
        {
            "bar": false,
            "page": GENERAL_PAGE,
            "width": 96,
            "tooltip":
            (
                "What happens where a stroke crosses itself. Build-up darkens there, Wash reaches the opacity "
                + "it was set to and stops. Erasing and an alpha-locked layer always build up."
            )
        }
    )

    # --- The airbrush -----------------------------------------------------
    var airbrush := SaOptionSpec.make(
        &"airbrush_enabled",
        "Airbrush",
        SaOptionSpec.Kind.BOOL,
        {
            "bar": false,
            "advanced": true,
            "page": GENERAL_PAGE,
            "tooltip": "Keeps depositing paint while the pointer is held still, on a clock rather than on travel."
        }
    )

    var airbrush_rate := SaOptionSpec.make_float(
        &"airbrush_rate",
        "Rate",
        1.0,
        100.0,
        1.0,
        {
            "bar": false,
            "advanced": true,
            "decimals": 0,
            "suffix": "/s",
            "page": GENERAL_PAGE,
            "enabled_when": &"airbrush_enabled",
            "enabled_when_values": [true],
            "tooltip": "Dabs per second while the pen is held down. Only used with Airbrush."
        }
    )

    var airbrush_ignore := SaOptionSpec.make(
        &"airbrush_ignore_spacing",
        "Ignore spacing",
        SaOptionSpec.Kind.BOOL,
        {
            "bar": false,
            "advanced": true,
            "page": GENERAL_PAGE,
            "enabled_when": &"airbrush_enabled",
            "enabled_when_values": [true],
            "tooltip": "Place dabs by time only, ignoring how far the pen moves. Only used with Airbrush."
        }
    )

    var out: Array[SaOptionSpec] = [
        generator,
        shape,
        ratio,
        angle,
        spacing,
        painting_mode,
        tip_file,
        load_tip,
        mode,
        lightness,
        airbrush,
        airbrush_rate,
        airbrush_ignore,
        sharpness,
        sharpness_softness,
        mirror_h,
        mirror_v,
        softness,
        falloff,
        spikes,
        density,
        randomness,
        antialias,
        auto_spacing,
        auto_coeff,
    ]
    return out
