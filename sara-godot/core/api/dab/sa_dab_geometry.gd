## The shape of one dab, as numbers rather than as pixels.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Where the tip's box is, where its hot spot is, and how the thirty-two floats
## of `dab.gmacs`'s push constant are ordered. It sits beside the tool rather
## than inside it because the tool already carries the stroke, the pressure and
## the settings, and because a bounding box that is wrong by a pixel is a
## clipped stroke rather than a slow one: hard rule 2 dispatches over this box
## and nothing outside it is ever written.
##
## Everything here is derived from what the kernel evaluates rather than
## measured off a picture, and each function's own comment carries its
## derivation, because a box is the one number in the engine whose being wrong
## looks like a painting bug rather than like a geometry bug.
class_name SaDabGeometry
extends RefCounted

## The number of floats `dab.gmacs`'s push constant holds, which is the 128
## bytes Vulkan guarantees. Named here because the pack below has to fill it
## exactly: a short array is a block of undefined tail on some drivers.
const PUSH_FLOATS: int = 32

## What the antialiasing band costs the box, in pixels. `dab.gmacs` adds one
## pixel to the coordinates before it takes the fade norm, so a texel a pixel
## outside the ellipse can still be covered.
const ANTIALIAS_MARGIN: float = 1.0

## The half-diagonal of a square of half-side one, which is what turns a
## picture's rectangle into the ellipse through its corners. Named because
## [method falloff_radius] is the only place it means anything and a bare
## `sqrt(2)` there reads as a guess.
const CORNER_REACH: float = 1.4142135623730951

## The paint modes `dab.gmacs` reads.
enum PaintMode { OVER = 0, ALPHA_DARKEN = 1, ERASE = 2 }

## The mask generators `dab.gmacs` chooses between.
enum Generator { DEFAULT = 0, GAUSS = 1, SOFT = 2, IMAGE = 3 }

## Where the mirror bits sit in the push constant, so a caller with a per-dab
## mirror can write them onto a packed block rather than pack it twice.
##
## Named for the same reason `SaDabPacking.PATTERN_STRENGTH_INDEX` is: the
## mirror was a property of the tip when [method pack] was written, so it
## arrives through the *tip* argument the packing reads, and the mirror option
## is per dab and knows nothing about a tip. The stroke folds the two with
## [method mirror_bits] and writes the answer here.
const MIRROR_INDEX: int = 26

## The diameter under which a dab is a pixel editor rather than a shape, in
## document pixels.
##
## Measured on the mark itself rather than picked. **From 1.1 to 2.8 the mode
## paints exactly one texel**, the same one, at every hardness and from every
## sub-pixel centre the pen can fall on. That is a single-pixel editor with no
## accident left in it. So the switch sits at the top of the widest run of
## diameters that paint one texel, and the first size above it is a mark three
## times as wide however the brush is set.
##
## What it costs is a soft two-pixel brush, and that painter exists: under this
## diameter Hardness, Softness and Sharpness change nothing, because the dab is
## binarised at the contour and snapped to the grid whatever the settings say.
## The Size row is what turns the mode off, and three pixels is where.
const PIXEL_MODE_DIAMETER: float = 3.0

## The smallest diameter a dab in the mode is drawn at, in document pixels.
##
## The same measurement: **under 1.1 pixels the mode paints nothing at all**, at
## every hardness and from every sub-pixel centre, because the threshold it
## paints through wants half the texel covered and a circle that small never
## covers half of one. A brush that paints nothing is not a pixel editor, so a
## dab under this is drawn at this, and the mark stays the single texel the
## painter aimed at.
##
## 1.5 rather than the 1.1 the measurement gives, because 1.1 is the edge of a
## number read off one card and a floor standing on the edge of its own
## measurement is a floor that moves. Everything from 1.1 to 2.8 paints the same
## one texel, so the room is free.
##
## Below [constant StateBrush.MIN_DAB_DIAMETER] the dab is dropped before this is
## asked, so a size ramped to nothing still paints nothing.
const PIXEL_MODE_FLOOR: float = 1.5


## The tip's own mirror turned over by *flip*, which is what the mirror option
## answers per dab.
##
## *tip_bits* is `SaBrushTip.mirror_bits()`, the resting state, and *flip* is
## the axes this dab flips: minus one for an option that is off, which leaves
## the resting state alone, and otherwise the bits to exclusive-or onto it.
##
## **Exclusive-or rather than replace**, which is Krita's own arithmetic in
## `kis_pressure_mirror_option.cpp`: it adds the option's answer to the canvas
## mirror and takes the parity, so the option turns an axis over rather than
## deciding it. Replacing would make a mirror option switched on with no sensor
## silently cancel a tip the painter had already mirrored by hand.
static func mirror_bits(tip_bits: int, flip: int) -> int:
    if flip < 0:
        return tip_bits
    return tip_bits ^ flip


## Whether *bits* turns a right-handed frame left-handed, which is the question
## the angle is measured against, asked per dab.
##
## One axis mirrored flips the handedness and two leave it alone, so it is the
## parity of the two bits. `SaBrushTip.mirror_flips_handedness()` answers the
## same question of the tip's two booleans, and this one answers it of the bits
## the kernel is actually sent, which is what a per-dab mirror needs: the tip's
## resting state is not the state the dab is drawn in.
static func mirror_flips_handedness(bits: int) -> bool:
    return ((bits & 1) != 0) != ((bits & 2) != 0)


## Whether a dab of *diameter* document pixels paints as whole texels.
##
## Nought and below mean "the caller did not say", which is what the default of
## every argument that turns the mode on is, so a suite that packs a dab with no
## diameter to hand gets the dab it always got.
static func is_pixel_mode(diameter: float) -> bool:
    return diameter > 0.0 and diameter < PIXEL_MODE_DIAMETER


## The diameter a dab of *diameter* is actually drawn at: its own above the
## threshold, and never under [constant PIXEL_MODE_FLOOR] below it.
static func drawn_diameter(diameter: float) -> float:
    return maxf(PIXEL_MODE_FLOOR, diameter) if is_pixel_mode(diameter) else diameter


## The half-extents a dab is drawn at: the tip's own *tip_half*, its minor axis
## narrowed by the ratio option's *ratio*, and that minor never under half of
## [constant PIXEL_MODE_FLOOR], the floor the pixel mode gives the diameter, nor
## over the major.
##
## **The same floor on the other axis.** A blade thinner than a pixel and a half
## covers a fraction of every texel it crosses, so its dabs, half a pixel apart
## at the walk's floor, lay fractions over fractions and never a solid line,
## and in the pixel mode a blade under half a texel is binarised to nought and
## paints nothing at all. Drawn at the floor, one dab covers the texel
## under it and the blade still reaches no further than a pixel past the
## stroke's own ends. A dab under the floor all round, a Fill that stays out of
## the pixel mode, keeps its round shape, because the minor is never drawn wider
## than the major.
static func drawn_half_extent(tip_half: Vector2, ratio: float) -> Vector2:
    var floor_half := minf(tip_half.x, PIXEL_MODE_FLOOR * 0.5)
    return Vector2(tip_half.x, maxf(tip_half.y * clampf(ratio, 0.0, 1.0), floor_half))


## The axis-aligned half-extents of a shape rotated by *radians*, plus the
## antialiasing band: an ellipse of half-axes *half_extent* for every
## generator but IMAGE, and the rectangle *half_extent* draws its picture
## into for that one.
##
## For half-axes a and b at angle t the ellipse's axis-aligned half-extents
## are `sqrt((a cos t)^2 + (b sin t)^2)` and `sqrt((a sin t)^2 + (b cos t)^2)`,
## which is exact rather than a bound: it is where the rotated ellipse's own
## tangent is vertical and horizontal. A rectangle's own corners reach
## further at the same half-axes, `|a cos t| + |b sin t|` and
## `|a sin t| + |b cos t|`, which is where its own rotated corner lands
## rather than a tangent point, and an image tip fills that rectangle rather
## than the ellipse inscribed in it (`falloff_radius`'s own doc comment).
## Boxing it with the ellipse's formula left three texels of every corner
## outside hard rule 2's dispatch at any rotation off the axes, never
## painted whatever Hardness asked for.
static func half_box(half_extent: Vector2, radians: float, spikes: int = 2, generator: int = Generator.DEFAULT) -> Vector2:
    var axes := spiked_half_extent(half_extent, spikes)
    var c := cos(radians)
    var s := sin(radians)
    var hx: float
    var hy: float
    if generator == Generator.IMAGE:
        hx = absf(axes.x * c) + absf(axes.y * s)
        hy = absf(axes.x * s) + absf(axes.y * c)
    else:
        hx = sqrt(pow(axes.x * c, 2.0) + pow(axes.y * s, 2.0))
        hy = sqrt(pow(axes.x * s, 2.0) + pow(axes.y * c, 2.0))
    return Vector2(hx, hy) + Vector2(ANTIALIAS_MARGIN, ANTIALIAS_MARGIN)


## The half-axes to compute a box from, which are the real ones for a plain
## ellipse and the major axis on both sides once spikes fold the shape.
##
## **Why a spiked dab is boxed as a square.** More than two spikes means the
## kernel folds the angle into a wedge and evaluates the same ellipse inside
## each one, so the petals point in every direction the fold produces rather
## than along the tip's two axes. A petal that points along the minor axis still
## reaches out by the major half-axis, and where exactly it reaches depends on
## the spike count, the rotation and the fade together. Taking the major
## half-axis on both sides bounds every one of them without solving for any: it
## is the smallest square that contains the ellipse, and a box that is too large
## costs a few texels of dispatch while one that is too small clips the paint.
##
## Two spikes is the unfolded ellipse and needs no widening, which is why the
## square only appears above two.
static func spiked_half_extent(half_extent: Vector2, spikes: int) -> Vector2:
    if spikes > 2:
        return Vector2(half_extent.x, half_extent.x)
    return half_extent


## The ellipse an image tip's Hardness softens along, in pixels.
##
## An image tip fills the rectangle `dab.gmacs` maps its picture into, which is
## *half_extent* on each side of the centre, and Hardness multiplies the
## picture's own coverage by the DEFAULT generator's falloff on this ellipse.
##
## **Through the corners rather than inscribed**, which is the whole of the
## number. Full hardness has to paint the picture unchanged, and an
## ellipse inscribed in the rectangle reads a squared norm above one at every
## corner, so it would cut them off at every setting: a picture stamped through a
## round hole rather than a hard tip. Scaled to reach the corners, the norm is
## exactly one there, the whole rectangle is core at a fade of one, and lowering
## Hardness pulls the falloff in from the corners first. The ellipse keeps the
## rectangle's own proportions, so a tip squashed by its ratio softens along its
## own outline.
static func falloff_radius(half_extent: Vector2) -> Vector2:
    return half_extent * CORNER_REACH


## The dab centre pulled towards the pixel grid by *sharpness*.
##
## What a painter asks for with Sharpness is a dab that lands on whole pixels,
## because a mask evaluated at a fractional centre is antialiased against the
## grid however hard its own edge is, and the softness that leaves is the whole
## of the difference between a brush and a pen. So the two ends are the centre
## as it came and the centre rounded, and the slider between them is the plain
## blend of the two, `sharpness * round(c) + (1 - sharpness) * c`. Nothing about
## the mask changes, only where it is evaluated from.
##
## **Called before the box, never after.** The box is what hard rule 2
## dispatches over, so a centre snapped a pixel after the box was computed is
## paint that never lands. This docstring says so because the order is
## invisible at the call site.
##
## *diameter* is the dab's own, and a dab under [constant PIXEL_MODE_DIAMETER]
## snaps the whole way whatever the Sharpness row says: the mode is entered
## by size rather than ticked, so the slider has nothing to say about it. The
## default means the caller did not say and the slider is the whole of the
## answer, which is every suite that packs a dab by hand.
##
## **The mode takes the texel under the point, the floor rather than the
## round.** The kernel stamps texel `i` as centred on `i`, while the canvas
## shows texel `i` over `[i, i + 1)`, so the texel a painter sees under a
## document point is its floor. Rounding took the texel below it for every
## point in the lower half of a texel, and a point on a texel's centre, y + 0.5,
## sat on the tie, where a view's last bit of float error chose the row: an
## Eraser at radius 1.2 drawn along each row took the even rows and left the
## odd ones. The floor gives every point of a texel that texel. The Sharpness
## row above the mode keeps its round, the blend it is.
static func snap_to_pixels(center: Vector2, sharpness: float, diameter: float = -1.0) -> Vector2:
    if is_pixel_mode(diameter):
        return center.floor()
    var amount := clampf(sharpness, 0.0, 1.0)
    if amount <= 0.0:
        return center
    if is_equal_approx(amount, 1.0):
        return center.round()
    return center.round() * amount + center * (1.0 - amount)


## The dab's own rectangle in document coordinates, which is what goes to
## `SaPaintContext.for_region`.
##
## *center* is the dab's centre after any sharpness snap: the snap happens
## before the box rather than after it, because a snapped
## dab a pixel outside the box that was dispatched for it is paint that never
## lands. *generator* has to be the one `dab.gmacs` is actually pushed,
## `SaBrushTip.effective_generator()` rather than a second reading of whether
## the tip is an image, or the box and the kernel can disagree the way `kind`
## and `generator` once did.
static func region(
    center: Vector2, half_extent: Vector2, radians: float, spikes: int = 2, generator: int = Generator.DEFAULT
) -> Rect2:
    var half := half_box(half_extent, radians, spikes, generator)
    return Rect2(center - half, half * 2.0)


## The thirty-two floats of the push constant, in `dab.gmacs`'s order.
##
## Every argument past *flow* has a default that means "not asked for", so this
## unit and the tests read as the dab they describe rather than as a wall of
## zeroes, and the units that turn each one on pass it by name.
static func pack(
    dab_center: Vector2,
    render_offset: Vector2,
    color: Color,
    half_extent: Vector2,
    radians: float,
    fade: Vector2,
    flow: float,
    spikes: int = 2,
    generator: int = Generator.DEFAULT,
    shape: float = 0.0,
    antialias: bool = true,
    density: float = 1.0,
    randomness: float = 0.0,
    dab_seed: float = 0.0,
    sharpness: float = 0.0,
    sharpness_soft: float = 0.0,
    paint_mode: int = PaintMode.OVER,
    alpha_lock: bool = false,
    mirror: int = 0
) -> PackedFloat32Array:
    # The hardness ellipse is derived rather than passed, because it is the
    # picture's own rectangle and there is no dab that wants a different one.
    # Sent for every generator: the kernel reads it on the image branch only,
    # and a slot written at one value is one thing to reason about rather than
    # two.
    var falloff := falloff_radius(half_extent)
    var data := PackedFloat32Array(
        [
            dab_center.x,
            dab_center.y,
            render_offset.x,
            render_offset.y,
            color.r,
            color.g,
            color.b,
            color.a,
            half_extent.x,
            half_extent.y,
            cos(radians),
            sin(radians),
            fade.x,
            fade.y,
            flow,
            float(spikes),
            float(generator),
            shape,
            1.0 if antialias else 0.0,
            density,
            randomness,
            dab_seed,
            sharpness,
            sharpness_soft,
            float(paint_mode),
            1.0 if alpha_lock else 0.0,
            float(mirror),
            falloff.x,
            falloff.y,
        ]
    )
    data.resize(PUSH_FLOATS)
    return data
