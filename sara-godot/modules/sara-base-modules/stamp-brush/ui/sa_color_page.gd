## The brush editor's Colour Dynamics page, as the rows it declares.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **One page for the five colour options and the source they read.** A page per
## curve option would give Hue, Saturation and Value one each, and five entries
## spread down the left column between Ratio and Scatter are five things a
## painter has to learn are one idea. HSV, Darken and Mix are one idea, so the
## five name this page and the editor puts them on it, each with its own
## checkbox and its own graph, under the Colour Source row they all read.
##
## **Declared and not drawn**, the way `SaTexturePage` beside this is. No file
## under `ui/brush_editor/` names a colour option or a source, and the same rows
## reach the Tool Options docker behind its Advanced check. The Gradient row is
## the one that stays off the docker, for the reason `rows` gives.
##
## **The source is above the five and not among them.** It says where the colour
## comes from before any of them touches it, so it is the row a painter reads
## first, and it is a plain enum rather than a curve because there is nothing per
## dab about it.
##
## **What this page costs the editor.** A page carrying two curve options would
## be two things claiming the page list's one checkbox, so a page carrying more
## than one draws a checkbox per option instead and the list's own checkbox
## stays for a page with exactly one, which is every other curve page in the
## app. `SaBrushEditorPages.pages_from` is where that split lives.
class_name SaColorPage
extends RefCounted

## The page's title, which every row and every curve option on it names.
##
## "Colour Dynamics" and not "Colour", because the page is about what varies per
## dab and the app already has a Colour docker holding the pair. A painter
## reading the left column should not have to open one to find out which it is.
const PAGE: String = "Colour Dynamics"

## The role the base module registers its ramp editor under, which the Gradient
## row asks the tool's role registry for. A name in the door rather than the
## control's class, which is the base module's and out of this module's sight.
const RAMP_ROLE: StringName = &"color_ramp_control"

## The five colour curve options, in the order they sit down the page, each as
## the key on the settings, the label and the tooltip.
##
## Hue, Saturation and Value first, because they are what a painter reaches for,
## then Krita's two. The order is the declaration order and the editor keeps it.
const OPTIONS: Array = [
    [
        &"hue_option",
        "Hue",
        "How far each dab turns the picked colour round the colour circle, following the sensors.",
    ],
    [
        &"saturation_option",
        "Saturation",
        "How far each dab moves the picked colour towards or away from grey, following the sensors.",
    ],
    [
        &"value_option",
        "Value",
        (
            "How far each dab lightens or darkens the colour, following the sensors. "
            + "With Random the value also varies within a stroke."
        ),
    ],
    [
        &"darken_option",
        "Darken",
        (
            "How far each dab pulls the picked colour towards black, following the sensors. "
            + "Nothing at the bottom of the range and black at the top."
        ),
    ],
    [
        &"mix_option",
        "Mix",
        (
            "How far each dab blends the picked colour towards the background colour, following the "
            + "sensors. The painting colour at the bottom of the range and the background at the top. "
            + "Under a Gradient source it is where on the gradient each dab's colour is picked instead."
        ),
    ],
]


## Whether *key* is one of the five colour options, which is what tells
## `curve_option_pages` to put the spec it is building on this page.
##
## A question asked of the list rather than a fourth column on every row of it:
## the list says what the five are once, and the module reads it.
static func owns(key: StringName) -> bool:
    for entry: Array in OPTIONS:
        if entry[0] == key:
            return true
    return false


## The rows the page carries besides its five curve options: the source, and
## under it the preset's gradient.
##
## The source sits here rather than on General because the five options below it
## are what it is for, and a row that explains five others belongs above them
## rather than a page away.
##
## The gradient is here because it is colour the preset carries, and the rows
## that will read it, a gradient-map tip and a gradient source, are colour rows.
## `Kind.CUSTOM`, so the editor builds `SaGradientRow` through the factory
## without naming it. Its value is the tool's `tip_loaded`, `on_tool`, the tip
## preview's route to the tool behind a row, because the row needs the tool's
## role registry and its settings and not a value alone. `in_docker` false,
## because the Tool Options docker is a column of short controls and a ramp with
## its stop row is a page's width, and a docker row answering the capture door
## would take the editor's `widget` step from it.
static func rows() -> Array[SaOptionSpec]:
    var source := (
        SaOptionSpec
        . make_enum(
            &"color_source",
            "Colour source",
            [SaColorDynamics.Source.PLAIN, SaColorDynamics.Source.GRADIENT],
            ["Plain", "Gradient"],
            {
                # Off the bar and behind Advanced, both rows, for the reason every curve
                # page gives: the bar is measured, and a painter who has not met the idea
                # of a colour that moves per dab has no use for the row in the docker.
                "page": PAGE,
                "bar": false,
                "advanced": true,
                "width": 84,
                "tooltip":
                (
                    "Where a dab's colour comes from before the five options below move it. Plain is the painting "
                    + "colour. Gradient takes it from the Gradient below at the Mix option's value, from its start "
                    + "at 0 to its end at 1, so Mix walks along the gradient rather than blending."
                )
            }
        )
    )
    var gradient := SaOptionSpec.make_custom(
        &"gradient",
        "Gradient",
        build_gradient,
        bind_gradient,
        {
            "page": PAGE,
            "bar": false,
            "advanced": true,
            "on_tool": true,
            "property": ^"tip_loaded",
            "in_docker": false,
            "tooltip":
            (
                "This preset's own gradient. Until a stop is edited it runs from the painting colour to the "
                + "background colour and follows them."
            )
        }
    )
    return [source, gradient]


## The Gradient row's factory, the door `Kind.CUSTOM` asks for. Here rather than
## on the row, because a static function of a node's own script that builds that
## node is the shape that leaks.
static func build_gradient(_spec: SaOptionSpec, write: Callable) -> Control:
    return SaGradientRow.new(write)


## Points a Gradient row at the tool behind *value*, the tool's `tip_loaded`.
static func bind_gradient(control: Control, value: Variant) -> void:
    var row := control as SaGradientRow
    if row != null:
        row.follow(value)
