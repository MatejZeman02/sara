## The smudge stage's pages, as the rows either brush engine declares.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **One page for both engines.** The stamp brush had the stage to itself, and
## the noise brush is the same pipeline, so the stage's settings are named once
## here in the door: the three curve options, their labels and tooltips, and
## the plain rows beside them. An engine turns [method curve_options] into
## curve pages with its own builder, because the stamp's pages carry a header
## the noise brush does not, and appends [method rows] after them.
##
## **The rows that are not a modulated parameter, on the page Colour Rate
## already is.** The colour rate says how much of the brush's own colour a
## smudging dab lays beside the paint it carries, the radius says how far out
## the pickup looks for paint to carry at all, and the mode says whether what
## it finds is dragged along or averaged where it stands, so they are read
## together. Sample Merged sits on the Smudge Pickup page, beside the option
## whose meaning it changes.
##
## **Colour Rate runs the way a painter reads it**, Krita's name and Krita's
## direction: nought lays only what the brush carries and one only the brush's
## own colour. Smudge Dilution is the same mix read from the other end, and a
## brush saved with a dilution is turned over by
## [method color_rate_of] when its settings migrate.
##
## **Declared and not drawn, the way the Texture page is.** No file under
## `ui/brush_editor/` names a radius, a smudge or a dab: each row is an
## `SaOptionSpec` naming its page by title, which the editor joins to the curve
## page of the same name rather than opening a second page of it, and the same
## row reaches the Tool Options docker behind its Advanced check.
class_name SaSmudgePage
extends RefCounted

## The page the pickup's source sits on, the Smudge Pickup option's label.
const PICKUP_PAGE: String = "Smudge Pickup"

## The page the plain rows sit on, which is the title `Colour Rate`
## carries. Named once here and read as that option's label, so the rows and
## the page under them cannot drift apart and leave a row alone on a page of
## its own.
const PAGE: String = "Colour Rate"

## The three rates the stage knows, the numbers a brush's `smudge_mode` stores.
## Smearing drags what the stroke crosses along it, dulling lays the mean of
## what stands under each dab, and blurring lays at each texel the paint around
## it, softened by a Gaussian half the pickup's reach wide ([SaSmudgeBlur]).
const SMEARING: int = 0
const DULLING: int = 1
const BLURRING: int = 2

## The pickup's reach, as a multiple of the dab's own radius.
##
## One is the dab itself and the default, so a preset saved without the row
## smudges over the dab alone. Three is Krita's
## own ceiling for the radius on the engine Sara's stage follows, and it is where
## the pickup reads a disc three of the dab across.
const MIN_RADIUS: float = 0.05
const MAX_RADIUS: float = 3.0


## The stage's three curve options, each `[key, label, tooltip]`, in the order
## an engine declares its pages. Smudge Pickup's checkbox is the stage's switch
## and the other two are read only while it is ticked, which is what their
## tooltips say rather than leaving a painter to find out why a ticked Colour
## Rate does nothing alone. Each tooltip says what its option does alone and
## beside the others, and that Opacity still scales what the dab lays.
static func curve_options() -> Array:
    return [
        [
            &"smudge_pickup_option",
            PICKUP_PAGE,
            (
                "Picks paint up from under the dab and drags it along the stroke, how much each dab takes in. "
                + "Ticked alone it smudges without painting, and Colour Rate beside it lays the brush's colour too. "
                + "Opacity still scales what the dab lays."
            ),
        ],
        [
            &"smudge_color_rate_option",
            PAGE,
            (
                "How much of the brush's own colour a smudging dab lays: 0 lays only the dragged paint, "
                + "1 only the brush's colour, and between is a mix of the two. "
                + "Unticked it reads as 0, a pure smudge. Opacity still scales both. "
                + "Does nothing while Smudge Pickup is off."
            ),
        ],
        [
            &"smudge_length_option",
            "Smear Length",
            (
                "How far the dragged paint lasts along the stroke before it fades to the brush's own colour. "
                + "Does nothing while Smudge Pickup is off."
            ),
        ],
    ]


## A fresh curve option for the stage at *strength*, off and with a curve
## that is read and no sensor yet, or ticked when *on* says so, which the
## colour rate is. Its strengths start where a first smudge reads as a smudge
## rather than as a normal brush or a pure blur: some pickup, half the brush's
## own colour laid beside the carry, and a long smear.
static func option(strength: float, on: bool = false) -> SaCurveOption:
    var made := SaCurveOption.new()
    made.enabled = on
    made.use_curve = true
    made.strength = strength
    made.strength_min = 0.0
    made.strength_max = 1.0
    return made


## The stage's plain rows: which of its rates it paints at, the reach the
## pickup samples, as a multiple of the dab, whether the height moves too
## when *moves_height* says the engine can move it, and the pickup's source.
##
## **Plain rows rather than curve options.** The pickup, the colour rate and the
## smear length are modulated per dab, because what a dab carries and lays is a
## per-dab decision. Which rate the stage is at and how far out it looks are
## properties of the brush, so each is one value.
##
## **The mode first, because it is what the other rows mean.** Smearing and
## dulling read the same numbers differently, so a painter meets the choice
## before the reach it applies to. Blurring is offered when *blurs* says the
## engine's dab reads the lattice [SaSmudgeBlur] leaves, which the stamp brush's
## does and the noise brush's does not.
static func rows(moves_height: bool, blurs: bool = false) -> Array[SaOptionSpec]:
    var values: Array = [SMEARING, DULLING]
    var labels: Array = ["Smearing", "Dulling"]
    var tooltip := (
        "What the brush does with what it picks up: smearing drags the paint it crosses along the stroke, "
        + "and dulling lays the average of the paint under each dab where it stands."
    )
    if blurs:
        values.append(BLURRING)
        labels.append("Blurring")
        tooltip = (
            "What the brush does with what it picks up: smearing drags the paint it crosses along the stroke, "
            + "dulling lays the average of the paint under each dab where it stands, "
            + "and blurring softens the paint under the brush, so an edge it crosses becomes a gradient."
        )
    # Off the bar and behind Advanced, all four rows: the bar is measured, and
    # a painter who has not met the idea of a modulated parameter has no use
    # for one more row in the docker.
    var mode := SaOptionSpec.make_enum(
        &"smudge_mode", "Smudge mode", values, labels, {"page": PAGE, "bar": false, "advanced": true, "tooltip": tooltip}
    )
    var spec := SaOptionSpec.make_float(
        &"smudge_radius",
        "Smudge radius",
        MIN_RADIUS,
        MAX_RADIUS,
        0.05,
        {
            "page": PAGE,
            "bar": false,
            "advanced": true,
            "decimals": 2,
            "suffix": "x",
            "tooltip":
            (
                "How far out the brush picks paint up, as a multiple of the dab's radius. "
                + "1 samples the dab itself, 3 reaches three times as far."
            )
        }
    )
    var out: Array[SaOptionSpec] = [mode, spec]
    # The Move Height switch, last on its page because it is about the layer
    # rather than about what the pickup reads, and only where the engine's
    # dab moves height with the colour.
    if moves_height:
        var height := SaOptionSpec.make(
            &"smudge_move_height",
            "Move impasto",
            SaOptionSpec.Kind.BOOL,
            {
                "page": PAGE,
                "bar": false,
                "advanced": true,
                "tooltip":
                (
                    "Drag the impasto along with the colour, on a layer that has impasto. "
                    + "Off, a smudge moves the colour and leaves the impasto where it stands."
                )
            }
        )
        out.append(height)
    var merged := SaOptionSpec.make(
        &"smudge_sample_merged",
        "Sample merged",
        SaOptionSpec.Kind.BOOL,
        {
            "page": PICKUP_PAGE,
            "bar": false,
            "advanced": true,
            "tooltip":
            (
                "Pick up paint from every visible layer as shown, rather than only the layer being painted. "
                + "Off, a smudge drags only what that layer holds."
            )
        }
    )
    out.append(merged)
    return out


## The Paint and Smudge slider, the Colour Rate as a row of the Tool Options
## docker and the bar: smudge at the left, the carry alone, and paint at the
## right, the brush's colour alone.
##
## **One number for the mix, beside the brush.** With the rate on the editor's
## page alone, mixing paint and smudge means leaving the canvas for a page, so
## the same option comes out to where Opacity is. It
## writes the option's `ticked_strength`, which ticks it as it sets the
## strength, so a brush whose rate was off paints when the slider says paint,
## and a rate with a sensor curve keeps its curve while the slider moves the
## strength it is scaled by.
##
## **Drawn only for a brush that smudges**, by a rule on Smudge Pickup's tick,
## which the docker and the bar both honour. Off the editor, whose Colour Rate
## page is this number already.
##
## *fields* are the engine's own, its page above all, laid over these as
## [method SaOptionSpec.make_float] takes them.
static func slider(fields: Dictionary[String, Variant] = {}) -> SaOptionSpec:
    var own: Dictionary[String, Variant] = {
        "property": ^"smudge_color_rate_option:ticked_strength",
        "percent": true,
        "suffix": "%",
        "decimals": 0,
        "tooltip":
        (
            "How much of the brush's own colour a smudge lays: 0 smudges only the paint it drags, "
            + "100 paints only the brush's colour, and between mixes the two. The Colour Rate of the brush editor."
        ),
        "shown_when": {"key": &"smudge_pickup_option:enabled", "value": true},
        "off_when": {"key": &"smudge_color_rate_option:enabled", "value": false},
        "in_editor": false,
        # On Radius, the last of the size and the strength, Radius standing after
        # Opacity. Hardness anchors there too and registers first, so the slider
        # lands after Hardness and before Flow.
        "bar_after": "radius",
        "bar_group": SaOptionSpec.BAR_GROUP_BRUSH
    }
    own.merge(fields, true)
    return SaOptionSpec.make_float(&"paint_and_smudge", "Paint and Smudge", 0.0, 1.0, 0.01, own)


## The Colour Rate that lays what *dilution*, the Smudge Dilution option of a
## brush saved before the rename, laid, as a fresh option. Both engines'
## migrations call it, so the two turn a dilution over the same way.
##
## **The mix is the same mix read from the other end.** The dab laid the carry
## at the dilution's reading and the brush's colour at one less it, so the
## colour rate is one less the dilution wherever the dilution was read. A
## dilution switched off read as one, all carry, and a colour rate switched off
## reads as nought, which is the same stroke, so off stays off and carries the
## complement of its strength for the day a painter ticks it.
##
## **A curve is turned over at its points.** A reading of one sensor through a
## curve f at strength s was `s * f`, so the colour rate is `1 - s * f`: each
## control point's height becomes one less s times it, and the strength one.
## The monotone cubic the sensor samples is built from the points' heights and
## slopes alone, and turning every height by the same line turns the cubic by
## that line, so a pen read at any pressure lays what it laid. With several
## scaling sensors each curve is turned the same way, which the product of the
## readings does not keep exactly, and no shipped brush reads more than one.
## An additive or angle sensor is left as it stood, since it was never a
## height on the dilution's curve.
static func color_rate_of(dilution: SaCurveOption) -> SaCurveOption:
    var made: SaCurveOption = dilution.duplicate(true)
    # A copy of each sensor too, since a dictionary's resources are shared by
    # a deep duplicate, and the turn below writes their curves.
    for id: Variant in made.sensors:
        var held: Variant = made.sensors[id]
        if held is SaSensor:
            var sensor: SaSensor = held
            made.sensors[id] = sensor.duplicate()
    var low := maxf(dilution.strength_min, 0.0)
    var high := minf(dilution.strength_max, 1.0)
    made.strength_min = 0.0
    made.strength_max = 1.0
    # The stroke wakes pressure on an option whose sensors are all asleep, so
    # the turn reads the set the stroke would have read.
    made.ensure_one_active()
    var scaling: Array[SaSensor] = []
    if made.use_curve:
        for sensor: SaSensor in made.active_sensors():
            if not sensor.is_additive() and not sensor.is_absolute_rotation():
                scaling.append(sensor)
    if not made.enabled or scaling.is_empty():
        made.strength = 1.0 - clampf(dilution.strength, low, high)
        return made
    made.strength = 1.0
    made.common_curve = _turned(made.common_curve, dilution.strength, low, high)
    for sensor: SaSensor in scaling:
        sensor.curve = _turned(sensor.curve, dilution.strength, low, high)
    return made


## *points* with each height y made one less *strength* times y, held to the
## band *low* to *high* the dilution's reading was clamped to.
static func _turned(points: PackedVector2Array, strength: float, low: float, high: float) -> PackedVector2Array:
    var out := PackedVector2Array()
    for point: Vector2 in points:
        out.append(Vector2(point.x, 1.0 - clampf(strength * point.y, low, high)))
    return out
