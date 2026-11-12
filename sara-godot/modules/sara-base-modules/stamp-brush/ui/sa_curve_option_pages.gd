## The stamp brush's editor surface: the pages that are a modulated parameter
## rather than a row, what each is called and what its tooltip says.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Cut out of `module.gd` by responsibility.** Everything below answers the
## brush editor and the Tool Options docker, what a curve option page is called
## and in which order the pages come, and nothing in it reads a
## tool descriptor, the General rows or the tip's. That is the seam: `module.gd`
## registers the tools and declares their plain rows, and this class is the half
## of the declaration a painter meets as a page with a graph on it.
##
## **Declared and not drawn**, the way `SaColorPage` and `SaTexturePage` beside
## this are. The window under `ui/brush_editor/` builds a page per spec and never
## names a curve option, and the three callables each spec carries are how a
## widget the skeleton did not build reaches it. The widget and those three
## doors are `SaCurveOptionControl`'s, cut out of this file
## by responsibility: the doors answer for the control and read nothing of the
## stamp's, and the row list and its texts are the stamp's own.
##
## **No cycle at parse time.** The module names this class and this class names
## neither the module nor its settings script, only the page classes whose
## options it splices in and the control whose doors it hands on, and none of
## those names it back.
class_name SaCurveOptionPages
extends RefCounted

## The first option whose page comes after the Masking Brush page, which is a
## page of plain rows and so is not in this list. The module declares the
## options before it, then that page's switch, then the rest, because a page
## appears in the editor where its first row is declared.
const AFTER_MASKING: StringName = &"rate_option"


## The pages that are a modulated parameter rather than a row.
##
## Krita's grouping rather than Krita's list, with Hardness beside Softness and
## Sara's own additions at the end. Each is one `Kind.CURVE_OPTION` spec naming
## the `SaCurveOption` on the settings, and the editor makes a page of it with
## the checkbox bound to that resource's own `enabled`, which is why none of
## them names a `page`: a curve option's page is the option. **The list below is
## the list**, and how many there are is not written down here, because the
## number moves and a sentence carrying it would not.
##
## **Every one is `bar = false` and `advanced = true`**, and neither is
## decoration. Nine buttons on a top bar with tens of pixels spare at 1920 would
## undo the room the bar's reduction won. `advanced` is the same judgement for
## the Tool Options docker: the docker draws a `CURVE_OPTION` as a button that
## opens the editor, nine of them would sit above Size and Opacity in
## declaration order, and a painter who has not met the idea of a modulated
## parameter has no use for the door. A painter who has turns Advanced on and
## finds nine doors, each opening the editor at its own page, which is what the
## flag is for. The pages themselves are never behind it:
## `SaBrushEditorPages.pages_from` reads every spec, so the editor lists eleven
## whatever the check says.
static func rows() -> Array[SaOptionSpec]:
    # The order is the brush editor's page order, because a page appears where
    # its first row is declared: the order a painter reads a brush down, with
    # Hardness beside Softness, Mirror after Rotation, and the five colour
    # options after Ratio.
    var described: Array = [
        [
            &"size_option",
            "Size",
            "How the dab's diameter follows the sensors, as a fraction of the Size row above.",
        ],
        [&"opacity_option", "Opacity", "How the dab's opacity follows the sensors."],
        [&"flow_option", "Flow", "How much paint each dab lays down, following the sensors."],
        # Named for what it does and not "Spacing", which is the Brush Tip
        # page's row: the editor held two controls with one name and a painter
        # asked which was which. This page multiplies that row by the sensors.
        [
            &"spacing_option",
            "Spacing Dynamics",
            "Multiplies the Brush Tip page's Spacing by the sensors, so the dabs sit closer or further apart as they move.",
        ],
        [&"softness_option", "Softness", "How soft the tip's edge is, following the sensors."],
        # The second page on an edge. Softness above is the tip's fade and
        # this is the brush's Hardness row, which is why the tooltip names the
        # row rather than the edge in the abstract.
        [
            &"hardness_option",
            "Hardness",
            (
                "How much of the Hardness row each dab keeps, following the sensors. On the random "
                + "sensor one brush lays a hard edge, a soft one and a lost one in the same stroke."
            ),
        ],
        [&"rotation_option", "Rotation", "How far the tip is turned, following the sensors."],
        # The one option that is read as a threshold rather than as a
        # quantity, which is what the tooltip says instead of "how far": there
        # is no half a flip.
        [&"mirror_option", "Mirror", "Whether the tip is turned over, per dab, once the sensors read past halfway."],
        [&"ratio_option", "Ratio", "How far the tip is squashed from round, following the sensors."],
    ]
    # The five colour options share one page, so they are spliced in from that
    # page's own list rather than written out here: naming `SaColorPage.PAGE` is
    # what gathers them into a page, and the editor draws a checkbox per option
    # on a page carrying more than one. They sit after the shape pages, because
    # everything above them changes the mark and these change what colour it is.
    described.append_array(SaColorPage.OPTIONS)
    (
        described
        . append_array(
            [
                [&"scatter_option", "Scatter", "How far a dab is thrown off the stroke, following the sensors."],
                # Texture, whose page also carries the rows `SaTexturePage.rows`
                # declares, joined to it by their `page`. No ordinal, because the
                # count has moved with every option added above it.
                [&"texture_option", SaTexturePage.PAGE, "How much of the texture the dab takes, following the sensors."],
                [&"rate_option", "Airbrush Rate", "How fast the airbrush lays paint down while the pointer is still."],
                # Sharpness, appended rather than slotted beside Softness: the
                # declaration order is the editor's page order, so moving Texture down
                # would move a page a painter has already learned to find.
                [
                    &"sharpness_option",
                    "Sharpness",
                    "How much of the Sharpness row each dab takes, following the sensors.",
                ],
            ]
        )
    )
    # The smudge stage's three, which the door names for both engines.
    described.append_array(SaSmudgePage.curve_options())
    var out: Array[SaOptionSpec] = []
    for entry: Array in described:
        out.append(_option_spec(entry[0] as StringName, entry[1] as String, entry[2] as String, String(entry[0])))
    # The mask's own two options, on pages of their own beside the Masking Brush
    # page. They cannot sit on that page, because a page whose tick is the
    # mask's switch also carrying curve options would lose the tick: a page with
    # more than one curve option draws a checkbox per option and none in the
    # page list, and the mask's switch has to stay reachable.
    for entry: Array in MASK_OPTIONS:
        out.append(_option_spec(entry[0] as StringName, entry[2] as String, entry[3] as String, String(entry[1])))
    return out


## The mask's own two modulated parameters. Each entry is the key, the
## property on the masking block, the label and the tooltip. The property
## differs from the key because the value lives on the `masking`
## sub-resource, so it reaches it with a colon, the same way the mask's plain
## rows do.
const MASK_OPTIONS: Array = [
    [
        &"masking_size_option",
        &"masking:size_option",
        "Mask Size",
        "How the mask's size follows the sensors, as a fraction of the Mask Size row on the Masking Brush page.",
    ],
    [
        &"masking_strength_option",
        &"masking:strength_option",
        "Mask Opacity",
        "How much of the mask the dab keeps, following the sensors. 1 keeps the whole mask, 0 removes it.",
    ],
]


## One curve option spec from its key, label, tooltip and the property the value
## lives at. The page is the label unless the key names a shared page, and every
## one carries the curve option control's three doors.
static func _option_spec(key: StringName, label: String, tooltip: String, property: String) -> SaOptionSpec:
    return (
        SaOptionSpec
        . make(
            key,
            label,
            SaOptionSpec.Kind.CURVE_OPTION,
            {
                "property": NodePath(property),
                # The five colour options name one page and every other option is its own,
                # which is the difference the editor reads.
                "page": SaColorPage.PAGE if SaColorPage.owns(key) else "",
                "tooltip": tooltip,
                "bar": false,
                "advanced": true,
                # The widget, its binding and its row text come from the control, so the
                # skeleton's editor page, bare host and docker row build and describe a
                # curve option without naming the classes that draw one.
                "build_control": SaCurveOptionControl.build_control,
                "bind_value": SaCurveOptionControl.bind_control.bind(label),
                "describe_value": SaCurveOptionControl.describe
            }
        )
    )
