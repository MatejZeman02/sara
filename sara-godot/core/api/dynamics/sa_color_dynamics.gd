## The colour source, and the three offsets a dab shifts a picked colour by.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Where the three fields [SaDynamics] writes on [SaDabParams] become a colour,
## so a brush's saturation and value vary within one stroke. Sara's own, and it
## ports no code. [SaDynamics] never sees a colour, which is the seam between
## the dynamics and the dab pipeline.
##
## **The maths is in Oklab, not in HSV on the picked sRGB.** Krita's own Hue,
## Saturation and Value options are HSV, and HSV's value is the largest of three
## channels rather than a lightness: shifting it moves a yellow and a blue by
## amounts a painter reads as different, and shifting saturation drags lightness
## with it. Oklab's lightness and chroma are the two a painter means, and its
## hue is an angle that can be turned without either of the others following.
## The conversion is the one every non-separable blend mode already uses,
## [SaOklab], which is defined against light-linear sRGB.
##
## **The picked triple speaks the document's gamut**, so on a Display P3
## document `1, 0, 0` is P3's red. The shift carries it through the document's
## own matrix into linear sRGB before Oklab and back the same way after, which
## is what lets the three offsets land on the dialled numbers in a wide gamut.
## With no space, or one that shares sRGB's primaries, the matrix is skipped
## rather than multiplied by the identity, so those results stay to the bit.
##
## **Nothing clamps to the display cube** (hard rule 5). A lightness pushed past
## one comes back as a linear value above one, the sRGB curve carries it out with
## its sign, and the canvas is float throughout, so a stroke that goes bright
## stays bright rather than flattening to white. Only chroma has a floor, at
## nought, and it has one because a negative chroma is the same colour with its
## hue turned half a circle: the shift would come out as the opposite hue rather
## than as grey, which is not what a painter dragging saturation down means.
##
## **A grey has no hue to turn.** A hue offset on grey moves nothing, and a
## saturation offset on grey comes out at hue 0, a red, which is left as it is
## rather than made a special case.
class_name SaColorDynamics
extends RefCounted

## Where a dab's colour comes from before the three options touch it.
##
## Krita's `ColorSource/Type` has `plain`, `gradient`, `uniform random`, `total
## random` and `pattern`. Sara has `plain` and `gradient`, and the importer
## tags a preset `not carried: colour source` for the other three.
enum Source {
    PLAIN,  ## The colour the painter picked, which is what the brush has always used.
    GRADIENT,  ## The brush's ramp at the dab's Mix, Krita's `gradient`, with Mix spent on the position.
}

## The chroma one whole unit of saturation offset is worth.
##
## Oklab's chroma is not normalised: a fully saturated sRGB primary sits near
## 0.26 and the most chromatic colour the gamut holds is under 0.33, so the
## offsets are scaled onto a range a painter can spend rather than left as raw
## chroma, where the first tenth of the slider would be the whole of the effect.
## Four tenths is past the gamut on purpose, so a painter can push a colour out
## of it and the float canvas keeps what they painted.
const MAX_CHROMA_SHIFT: float = 0.4

static var _kept_curve: SaTransferFunction = null
static var _kept_linear: SaColorSpace = null

## The picked colour and the space [method _shift] last decoded, and what it
## decoded them to. A stroke shifts the one colour at every dab, and the
## decode, the matrix and the polar form were the same three answers each
## time. A space is compared as the object it is, because a document's space
## is replaced by a new descriptor rather than written in place.
static var _polar_known: bool = false
static var _polar_color: Color = Color()
static var _polar_space: SaColorSpace = null
static var _polar_wide: bool = false
static var _polar: Vector3 = Vector3.ZERO


## The name of *source*, for a dump and for a row.
static func source_name(source: int) -> String:
    match source:
        Source.PLAIN:
            return "plain"
        Source.GRADIENT:
            return "gradient"
        _:
            return "unknown"


## *color*, an sRGB colour as the picker shows it, shifted by the three offsets
## and the two amounts on *dab*, mixing towards *background*.
##
## Answers the colour unchanged, the same object's values to the bit, when all
## five readings are nought. That is the guard that a brush nobody switched a
## colour option on paints exactly the colour picked: the round
## trip through Oklab is close to exact but it is not exact, and "close" in a
## test that asserts a texel is a failure.
##
## **Darken and Mix are applied after the three offsets and outside Oklab**.
## Both are Krita's, both are stated in Krita as arithmetic on the colour's own
## channels, and doing them in Oklab would change what they are: a darken
## through Oklab's lightness is a perceptual dimming that keeps the hue, and
## Krita's is a multiply that pulls a saturated colour towards black through its
## own channels. Mix is a blend between two colours the painter chose, and
## blending it anywhere but between those two would answer a third colour
## neither of them is. So H, S and V move a colour in the space a painter reads
## and these two do what Krita says they do, which is the honest split rather
## than one space for the sake of one space.
##
## **The order is darken then mix, and it is not symmetric.** Darkening a colour
## and then blending it towards the background leaves the background reachable
## at a mix of one, which is what the option's top of range has to mean.
## Blending first and darkening after would take the background down with it, so
## a full mix beside any darken at all would paint neither colour.
##
## The picked colour rather than the document's own encoding, because the
## conversion into that encoding is one line further on in the brush. *space*
## is the document's, which says whose primaries the picked triple names, and
## null reads it as sRGB's.
##
## **Under a gradient *source* the Mix is the place on the ramp**, as Krita's
## `selectColor(mix)` makes it, so the colour the options then move is
## [method ramp_at] the dab's Mix and the Mix blends towards *background* no
## longer, having been spent. Read nought-neutral like every colour option here,
## so a Mix at nought, or switched off, takes the ramp's start. *ramp* answers
## the [SaColorRamp], the brush's `gradient_ramp`, and is asked only under a
## gradient source, so a plain brush builds no ramp per dab. A source with no
## ramp to ask walks *color* to *background*, the ramp a preset with no
## gradient of its own holds.
static func apply(
    color: Color,
    dab: SaDabParams,
    background: Color = Color.BLACK,
    space: SaColorSpace = null,
    source: int = Source.PLAIN,
    ramp: Callable = Callable()
) -> Color:
    var gradient := source == Source.GRADIENT
    # The commonest dab of all, a plain colour none of the five moves, answered
    # before the three calls below that would each hand it back untouched.
    if (
        not gradient
        and is_zero_approx(dab.hue_shift)
        and is_zero_approx(dab.saturation_shift)
        and is_zero_approx(dab.value_shift)
        and is_zero_approx(dab.darken)
        and is_zero_approx(dab.mix)
    ):
        return color
    var start := ramp_at(_ramp_of(ramp, color, background), dab.mix, space) if gradient else color
    var shifted := _shift(start, dab, space)
    var mix := 0.0 if gradient else dab.mix
    if is_zero_approx(dab.darken) and is_zero_approx(mix):
        return shifted
    # Straight multiplies on the channels, Krita's own arithmetic, and nothing
    # clamps: a colour the exposure row has already pushed above one darkens
    # towards black from wherever it is rather than from the top of the cube.
    var darkened := Color(
        shifted.r * (1.0 - dab.darken), shifted.g * (1.0 - dab.darken), shifted.b * (1.0 - dab.darken), shifted.a
    )
    # The alpha stays the dab's own. A mix towards a background the painter set
    # to transparent is a mix of colour and not of coverage, and coverage is the
    # opacity option's answer one step earlier.
    return Color(
        lerpf(darkened.r, background.r, mix),
        lerpf(darkened.g, background.g, mix),
        lerpf(darkened.b, background.b, mix),
        darkened.a
    )


## The colour *ramp* holds at *at*, as a picker shows it in *space*'s gamut,
## which is the triple a plain source's picked colour is.
##
## The ramp is walked in Oklab with its stops read in *space*'s gamut, as
## Gradient Map reads them, and comes back out through the same matrix and the
## sRGB curve, so a P3 document's ramp from P3's red starts at P3's red. Nothing
## clamps, and the alpha is the ramp's, which the brush replaces with its
## coverage as it replaces a plain colour's.
static func ramp_at(ramp: SaColorRamp, at: float, space: SaColorSpace = null) -> Color:
    var lab := ramp.oklab_at(at, space)
    var linear := SaOklab.to_linear_srgb(Vector3(lab.r, lab.g, lab.b))
    if space != null and not space.shares_gamut(_linear_srgb()):
        linear = space.from_linear_srgb_matrix() * linear
    var curve := _srgb_curve()
    return Color(curve.encode(linear.x), curve.encode(linear.y), curve.encode(linear.z), lab.a)


## What *ramp* answers, or *color* to *background* when there is nothing to ask
## or it answers no ramp.
static func _ramp_of(ramp: Callable, color: Color, background: Color) -> SaColorRamp:
    var answer: Variant = ramp.call() if ramp.is_valid() else null
    return answer if answer is SaColorRamp else SaColorRamp.from_pair(color, background)


## *color* moved by the three Oklab offsets alone, which is what [method apply]
## does before Krita's two amounts touch it.
static func _shift(color: Color, dab: SaDabParams, space: SaColorSpace = null) -> Color:
    if is_zero_approx(dab.hue_shift) and is_zero_approx(dab.saturation_shift) and is_zero_approx(dab.value_shift):
        return color
    var curve := _srgb_curve()
    if not _polar_known or color != _polar_color or space != _polar_space:
        _polar_known = true
        _polar_color = color
        _polar_space = space
        var linear := Vector3(curve.decode(color.r), curve.decode(color.g), curve.decode(color.b))
        _polar_wide = space != null and not space.shares_gamut(_linear_srgb())
        if _polar_wide:
            linear = space.to_linear_srgb_matrix() * linear
        _polar = SaOklab.to_polar(SaOklab.from_linear_srgb(linear))
    var wide := _polar_wide
    var polar := _polar
    # Value is Oklab's lightness, which already runs 0 to 1 for the display
    # range, so one whole unit of offset is the whole of it and needs no scale.
    var lightness := polar.x + dab.value_shift
    var chroma := maxf(polar.y + dab.saturation_shift * MAX_CHROMA_SHIFT, 0.0)
    # Half-turns, which is what the rotation-like reducer answers in, so a whole
    # unit of hue offset is the far side of the colour circle either way round.
    var hue := polar.z + dab.hue_shift * PI
    var shifted := SaOklab.to_linear_srgb(SaOklab.from_polar(Vector3(lightness, chroma, hue)))
    if wide:
        shifted = space.from_linear_srgb_matrix() * shifted
    return Color(curve.encode(shifted.x), curve.encode(shifted.y), curve.encode(shifted.z), color.a)


## The sRGB curve and the linear sRGB space, made once and kept, since making
## either builds a descriptor, and the space its matrices, at every dab. Neither
## is ever written once made.
static func _srgb_curve() -> SaTransferFunction:
    if _kept_curve == null:
        _kept_curve = SaTransferFunction.srgb()
    return _kept_curve


static func _linear_srgb() -> SaColorSpace:
    if _kept_linear == null:
        _kept_linear = SaColorSpace.linear_srgb()
    return _kept_linear
