## The parameters of one dab, which is the whole seam between the two halves of
## the brush engine.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The dynamics half fills one of these per interpolated sample and the dab
## pipeline reads it. Two rules keep the seam honest and both are the spec's:
## this half never touches a texture or a compute list, and the other half never
## reads a pressure, a tilt or a response curve. So this file carries no logic at
## all, which is also why it is the one file of this group with no Krita
## copyright block: it is a struct, and a table of field names is not an
## algorithm.
##
## **`position` is the point on the stroke and `scatter` is the offset from it.**
## The two are not folded together, because the dab pipeline is the consumer
## and adds them itself, so a dab and the path it came from are both still legible on the other
## side of the seam.
##
## **A fresh one paints nothing.** Every field is the value that does nothing
## rather than a plausible default, `size` above all: a bug that leaves this
## object half filled draws a dab of diameter zero, which is visible as nothing
## happening, instead of a dab of some inherited size, which is visible as the
## wrong picture and reads as a shader fault.
class_name SaDabParams
extends RefCounted

## The point on the stroke, in document pixels, before scatter is added.
var position: Vector2 = Vector2.ZERO

## Diameter in document pixels, the tip's major axis. Zero paints nothing.
var size: float = 0.0

## The dab's own alpha ceiling, 0 to 1.
var opacity: float = 0.0

## How much of that ceiling this dab lays down, 0 to 1. Read together with
## `opacity` and meaning a different thing: the ceiling a stroke can build to
## against how far one dab moves towards it.
var flow: float = 0.0

## The tip's angle in radians. The tip's own resting angle is added later, at
## mask time, and not here.
var rotation: float = 0.0

## The tip's minor over major axis, 0 to 1.
var ratio: float = 1.0

## How many times wider in the document's x the dab is drawn than its size
## says, so it comes out round where the view shows the document as a sphere:
## the kind's `SaProjection.stretch` at the dab's centre, which the view the
## stroke is painted in answers, `SaView.dab_stretch`. Nought is the flat dab,
## the one a flat view paints, neither stretched nor folded across a pole. It
## is infinite at a pole and capped where the dab is shaped,
## `SaProjection.Stretched`, because the cap is a matter of the canvas's width.
var stretch: float = 0.0

## Multiplies the mask generator's fade, 0 to 1.
var softness: float = 1.0

## Multiplies the brush's own Hardness before it becomes the kernel's fade pair,
## 0 to 1.
##
## **Not the same edge as `softness` above, and the two stay two on purpose.**
## Softness is the mask generator's fade, a property of the tip: it scales the
## falloff the generator draws and, on the SOFT generator, it is what the
## softness table is lerped towards. Hardness is the brush's edge, the number
## the Hardness row on the bar drags, and it is the value the fade pair is built
## from. The spec's option table lists them separately for the same reason, and
## a preset can want a soft tip with a hard edge or the other way round.
##
## One means the Hardness row exactly as the painter set it, which is what an
## option nobody switched on answers, so a brush that has never met this field
## paints what it always painted.
var hardness: float = 1.0

## The pixel offset from `position`, already computed and added by the consumer.
var scatter: Vector2 = Vector2.ZERO

## A multiplier on the tip's own spacing, applied after it.
var spacing: float = 1.0

## Linear, in the document's own encoding, already exposed.
var color: Color = Color(0.0, 0.0, 0.0, 0.0)

## How far this dab turns the picked colour's hue, in half-turns, wrapped over
## -1 to 1 the way every rotation-like reading is.
##
## **The three below are offsets and not multipliers**, which is why their
## neutral value is nought where every scaled parameter above is one.
## Saturation and value vary within one stroke, and a multiplier can
## only ever take colour away: a brush whose saturation is modulated downwards
## fades and never lifts, and what was asked for is variation either side of
## what the painter picked.
##
## Nothing here is a colour. The dynamics half fills these three and
## [SaColorDynamics] turns them into one, which is what keeps this file a struct
## and that half free of the document's colour space.
var hue_shift: float = 0.0

## How far this dab moves the picked colour's chroma, -1 to 1, scaled onto real
## chroma by [constant SaColorDynamics.MAX_CHROMA_SHIFT].
var saturation_shift: float = 0.0

## How far this dab moves the picked colour's lightness, -1 to 1, which is
## Oklab's own lightness and needs no scale.
var value_shift: float = 0.0

## How far this dab pulls the picked colour towards black, 0 to 1. Nought is
## the colour untouched and one is black.
##
## **The two below are amounts and not offsets**, so their neutral value is
## nought like the three above but their range is one-sided: there is no
## un-darkening a colour and no un-mixing it, which is the difference between
## what Krita's Darken and Mix do and what H, S and V do. A painter who wants a
## colour lifted reaches for Value, which is signed and says so.
var darken: float = 0.0

## How far this dab blends the picked colour towards the background colour, 0 to
## 1. Nought is the painting colour and one is the background.
##
## Nothing here is a colour, the background included: the dynamics half fills
## this number and [SaColorDynamics] is handed the pair it blends, which is what
## keeps this file a struct and that half free of the picker.
var mix: float = 0.0

## Which way the tip is turned over for this dab, as the two bits `dab.gmacs`
## reads, bit 0 horizontal and bit 1 vertical, **exclusive-ored onto the tip's
## own two** rather than replacing them. Minus one is the mirror option switched
## off, which is not the same as a flip of nothing: off leaves the tip's two
## booleans exactly as they stand, and zero is the option on with this dab's
## sample landing above its threshold.
##
## The one field here whose neutral value is not zero, and the reason is the
## rule at the top of this file: a fresh one has to do nothing, and zero here
## would be an option that is on and answering no flip, which is a claim about a
## sample nobody took.
var mirror: int = -1

## How far this dab is pulled onto the pixel grid and its mask cut to a hard
## edge, 0 to 1, which is the Sharpness row after its own curve has read the
## sensors. Zero is the dab with no sharpness: no snap and no cut.
##
## Here rather than on the settings alone because the two halves of sharpness
## are applied at opposite ends of the dab pipeline, the snap before the box is
## computed and the cut inside the kernel, and both have to be told the same
## number for one dab. A field on the seam is the only place that number can be
## stated once.
var sharpness: float = 0.0

## How much of the pattern the dab's coverage is given over to, 0 to 1, which
## is `pattern_strength` after the Texture page's curve has read the sensors.
## Zero is no pattern, the dab exactly as it was. The pattern itself is not
## here: this half never touches a texture, and the dab pipeline binds the
## one the settings name.
var pattern_strength: float = 0.0

## Whether the smudge stage runs for this dab, and its three numbers after their
## curves have read the sensors, each nought to one. False is the dab exactly as
## it was, and the three are not read while it is.
##
## Here rather than on the settings for the reason `sharpness` above gives: the
## pickup runs before the dab and the mix inside it, and both have to be told the
## same numbers for one dab.
var smudge: bool = false
var smudge_pickup: float = 0.0
var smudge_color_rate: float = 0.0
var smudge_length: float = 0.0


## What a dab reports about itself, for a state dump and for a test that wants to
## say what it read rather than what it computed.
func report() -> Dictionary[String, Variant]:
    return {
        "position": [position.x, position.y],
        "size": size,
        "opacity": opacity,
        "flow": flow,
        "rotation": rotation,
        "ratio": ratio,
        "stretch": stretch,
        "softness": softness,
        "hardness": hardness,
        "scatter": [scatter.x, scatter.y],
        "spacing": spacing,
        "mirror": mirror,
        "color": color.to_html(true),
        "hue_shift": hue_shift,
        "saturation_shift": saturation_shift,
        "value_shift": value_shift,
        "darken": darken,
        "mix": mix,
        "pattern_strength": pattern_strength,
        "sharpness": sharpness,
        "smudge": smudge,
        "smudge_pickup": smudge_pickup,
        "smudge_color_rate": smudge_color_rate,
        "smudge_length": smudge_length,
    }
