## The brush tip: what shape a dab is, before anything has been painted.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Written from what a tip is, not from a port**. The fields are the
## quantities a dab needs before it can be drawn: how wide it is, how round,
## which way it points, how its coverage falls off towards the edge, how far
## apart two of them sit. Each name is the word for its quantity, the one Sara's
## own rows and kernel use, rather than an importer's convenience.
##
## **Importing a Krita preset is a field-by-field map**, and the names are not
## what makes it one. A preset arrives as XML with Krita's own
## attribute names, so an importer has to name both sides whatever the fields
## here are called. What makes the map possible is that the quantities are the
## same quantities, and what makes it correct is knowing where a meaning differs:
## this file's fades are the hardness with one as the hard edge, and its softness
## lerps a curve towards full coverage rather than scaling it.
##
## **A `Resource`, so a preset stores it and nothing else has to know.**
## `core/presets/sa_preset_store.gd` round-trips a `BrushSettings` by saving the resource
## whole, so a sub-resource travels with it for free, `Curve` included.
##
## **No GPU state lives here.** The 256-entry table a soft tip needs is produced
## by [method softness_table] and uploaded by whoever is dispatching, because an
## RID inside a `Resource` would be written into every saved preset and would
## outlive the `RenderingDevice` that made it.
extends Resource

const SaDabGeometryScript = preload("res://core/api/dab/sa_dab_geometry.gd")

## A procedural tip is evaluated by the kernel. An image tip samples a texture
## `SaTipImage` loaded.
enum Kind { PROCEDURAL = 0, IMAGE = 1 }

## The outline the falloff is measured against, which is the kernel's `shape`
## slot. Two, because a norm is what the kernel measures a texel by and there are
## two norms worth having: the elliptical one, whose level sets are ellipses, and
## the per-axis one, whose level sets are rectangles. Anything else is a shape a
## painter would rather draw as an image tip.
enum Shape { CIRCLE = 0, RECTANGLE = 1 }

## How many entries the soft generator's curve is sampled into, and the number
## `dab.gmacs` indexes with.
##
## The resolution cannot be the tip's size, because one table serves every size a
## tip is ever stamped at: the kernel evaluates a falloff at a normalised radius
## and never at a pixel of a rasterised mask. So the length is a choice, and 256
## is the length every other lookup table in this repository uses, which puts one
## entry every 0.4 percent of the radius and is finer than a texel on any dab a
## painter drags.
const SOFTNESS_SAMPLES: int = 256

## The smallest multiplier [method effective_fade] will let softness be.
##
## The kernel's fade coefficient is the shape coefficient divided by the fade, so
## a fade of zero has no coefficient at all and the kernel guards it by falling
## back to one, which is a different curve rather than the limit of this one. A
## floor on the multiplier keeps the row continuous instead: at the bottom of it
## the tip still sends a hundredth of its own fade, which is a band far under a
## texel wide on any dab a painter drags and so reads as the hard edge the row
## promises there.
const SOFTNESS_FLOOR: float = 0.01

## What kind of tip this is, as a record rather than as the switch. **The field
## that decides is [member generator]**, because that is the one the kernel
## branches on and the one the Tip row writes, and two fields that can disagree
## is a brush painting a disc while the Tip row says Image. Everything that has
## to know asks [method uses_image].
@export var kind: Kind = Kind.PROCEDURAL
@export var generator: int = SaDabGeometryScript.Generator.DEFAULT
@export var shape: Shape = Shape.CIRCLE

## Document pixels, and the one field the painter's dragged size writes into.
## `BrushSettings.radius` stays the fraction of the canvas the painter drags and
## is copied here before each dab rather than duplicated.
@export var diameter: float = 42.0

## The stored fields a stroke writes at every dab, so what they hold after a
## stroke is the last dab's and never a thing the painter chose. The stamp brush
## writes the diameter from the dab's size after the sensors, the fades from the
## Hardness row times the dab's hardness and the spacing from its Spacing row.
## The noise brush writes the diameter the same way, the fades as one and the
## spacing as its own constant. No row edits these four on the tip itself, and a
## masking tip's diameter is its shaped size, its fades a Krita import's. A
## preset still saves them, and the brush editor leaves them out when it asks
## whether the brush in hand is the preset it loaded, since the
## rows they are copied from are compared where they live.
const STROKE_WRITTEN_KEYS: Array[String] = ["diameter", "horizontal_fade", "vertical_fade", "spacing"]

## Minor over major. 1.0 is a circle.
@export var ratio: float = 1.0

## How far in from the edge the coverage starts falling off, as a fraction of the
## half-extent on each axis. This is the Hardness row with nothing in between.
##
## **One is the hard edge and zero is the dome**, which is the opposite of what
## the name suggests and of what the spec's table once said. The kernel divides
## the shape coefficient by this fraction, so at one the fade norm equals the
## shape norm, every texel inside the ellipse reads as core, and the falloff has
## nowhere to happen. The name is the kernel's push-constant slot, so changing it
## belongs with the kernel.
@export var horizontal_fade: float = 1.0
@export var vertical_fade: float = 1.0

## Scales the fade and the SOFT curve together, so one row softens a tip whatever
## generator it uses. 1.0 changes nothing, which is why the spec's table could
## omit it and still be right about defaults.
@export var softness: float = 1.0

## Two is the plain ellipse. Above two the kernel folds the angle into one wedge
## and the box grows to the major axis on both sides.
@export var spikes: int = 2

@export var antialias_edges: bool = true

## The fraction of the dab's texels that take paint, and how far each may wander
## from full coverage. Both are read by the kernel from a hash of the texel and
## the dab's seed, because a compute kernel has no random source. The spacing
## walk gives them the seed that makes them differ between dabs.
@export var density: float = 1.0
@export var randomness: float = 0.0

## The falloff of the SOFT generator, coverage against the squared normalised
## radius: x of 0 is the centre and x of 1 is the edge.
##
## **It descends, and a curve that does not paints a hole.** The identity
## `0,0;1,1` is the one to be careful of, because it is what a curve editor
## offers first and what a Krita preset's XML falls back to: it is a tip that is
## clear in the middle and opaque at the rim. [method default_softness_curve] is
## the descending one, and it is the default here.
@export var softness_curve: Curve = default_softness_curve()

# The table [method softness_table] last built and what it was built from.
var _table := PackedFloat32Array()
var _table_curve: Curve
var _table_softness := 0.0
var _table_fresh := false

## Fraction of the tip's size between dabs. The spacing walk reads these
## three.
@export var spacing: float = 0.1
@export var auto_spacing: bool = false
@export var auto_spacing_coeff: float = 1.0

## The tip's own base rotation in radians, added to whatever the dab asks for.
@export var angle: float = 0.0

## The per-dab mirror: flips the tip inside its own rectangle, on either axis
## or both.
##
## **Not `core/api/document/sa_symmetry.gd`.** Symmetry paints several images of one dab and
## `SaPaintContext` applies it. This flips the one dab, and the two compose, so a
## painter with both on gets the images symmetry asks for and each of them
## flipped. The rows say which is which, because two Mirror controls with no
## explanation is worse than one.
##
## **On the tip rather than on the settings, where the spec's table puts them.**
## The mirror is a transform of the tip's own coordinate, and a field that
## belongs to a shape is the tip's rather than `stamp_brush_settings.gd`'s.
@export var mirror_horizontal: bool = false
@export var mirror_vertical: bool = false


## The two mirror flags as the bit field `dab.gmacs` reads, bit 0 horizontal and
## bit 1 vertical.
func mirror_bits() -> int:
    return (1 if mirror_horizontal else 0) | (2 if mirror_vertical else 0)


## Whether this mirror turns the tip's frame inside out.
##
## A mirrored stroke has to keep its angle: a tip drawn at thirty degrees and
## flipped left to right must come out at minus thirty, or the flip and the
## rotation fight and the mark lands somewhere the painter did not point. One
## flipped axis negates the determinant of the tip's frame, so an angle measured
## in it runs the other way and the dab's rotation is negated to compensate. Two
## flipped axes are a half turn, which is a rotation and leaves the frame's
## handedness alone, so nothing is negated. That is why this is the inequality of
## the two flags and not their disjunction.
func mirror_flips_handedness() -> bool:
    return mirror_horizontal != mirror_vertical


## Only for an image tip, and loaded by `SaTipImage` rather than by this.
@export var image_path: String = ""

## How far this tip's own lightness moves the dab's colour, as a share of the
## distance from mid grey to either end of the lightness range.
##
## **Zero, which is off, and that is the whole of the promise that no existing
## preset moves.** The kernel reads the shift as `(lightness - 0.5) * strength`,
## and a strength of nought skips the round trip rather than computing a nought:
## every brush that has never met this row paints the texels it would with no
## lightness map, bit for bit. An imported preset that carried Krita's
## `LightnessStrength` switches it on and gets the map.
##
## **A plain number rather than a curve option**, because what a tip has to say
## about lightness is a picture and not a sensor: Krita's own LightnessStrength
## is a strength on the map, and the sensors that would modulate it belong to
## the row's value rather than to the map. It is read only when the picture
## behind it carries colour, which `SaBrushTipMask` decides.
@export var lightness_strength: float = 0.0


## Whether the kernel samples a picture for this tip.
##
## The one question, asked by the binding and by the packer, so the texture that
## is bound and the generator that is pushed cannot disagree. A path is needed as
## well as the generator, because the Tip row can name Image before any file has
## been loaded.
func uses_image() -> bool:
    return generator == SaDabGeometryScript.Generator.IMAGE and not image_path.is_empty()


## The generator the kernel is actually pushed.
##
## Image with no picture behind it falls back to the tip's own procedural
## falloff rather than to the empty sampler, because a painter who picks Image
## in the Tip row before loading anything would otherwise paint a stroke that
## says nothing, and that is the whole reason for the fallback.
func effective_generator() -> int:
    if generator == SaDabGeometryScript.Generator.IMAGE and image_path.is_empty():
        return SaDabGeometryScript.Generator.DEFAULT
    return generator


## The falloff a fresh soft tip gets: opaque at the centre, clear at the edge.
static func default_softness_curve() -> Curve:
    var curve := Curve.new()
    curve.add_point(Vector2(0.0, 1.0))
    curve.add_point(Vector2(1.0, 0.0))
    return curve


## The half-extents in pixels: the major radius, and the minor one that `ratio`
## defines. This is what `SaDabGeometry` boxes and what the kernel is handed.
##
## **A dab's shape is a diameter, a ratio and an angle, and there is no scale.**
## A tip that is a picture has a size of its own, so a shape for one has to be a
## multiplier over that size and a squash of it, and the height then comes out as
## the product of the two. Nothing here has a size of its own: a procedural tip is
## an analytic falloff with no resolution, and an image tip is sampled at the
## dab's own inverse transform, so its pixel dimensions never reach the brush.
## [member diameter] is the size in document pixels directly, and the dynamics
## multiply into it before it arrives. So the product a scaled shape would need is
## already done, and one number less travels to the kernel.
func half_extent(diameter_px: float = -1.0) -> Vector2:
    var d: float = diameter if diameter_px < 0.0 else diameter_px
    var major := maxf(d, 0.0) * 0.5
    return Vector2(major, major * clampf(ratio, 0.0, 1.0))


## The fade fraction the kernel is sent, which is this tip's two fades
## **multiplied** by softness.
##
## The spec's push-constant table says the slot arrives "already divided by
## softness", and that is the wrong operation for the way the kernel uses it. What
## the kernel divides is the *coefficient*, which is the reciprocal of the fade
## times the half-extent, so dividing a coefficient by softness is multiplying a
## fade by it. Send the quotient instead and a softness below one sharpens the
## edge, which is the row promising a blur and delivering the opposite.
func effective_fade() -> Vector2:
    var s := maxf(SOFTNESS_FLOOR, softness)
    return Vector2(clampf(horizontal_fade, 0.0, 1.0) * s, clampf(vertical_fade, 0.0, 1.0) * s)


## The SOFT generator's curve as [constant SOFTNESS_SAMPLES] floats, sampled at
## evenly spaced squared radii from the centre to the edge.
##
## **The samples are reshaped and the curve is not.** Softness is a row a painter
## drags while the curve control beside it holds the shape they drew, and the two
## are different pieces of state. Reshape the `Curve` and the softness is written
## into the points the control is showing, so the drawn shape drifts every time
## the row moves and there is no way back to it. Reshaping the table leaves the
## resource alone, and the table is rebuilt from the curve and the row on every
## dispatch anyway.
##
## **Softness zero is the hard edge, not the empty dab**. A reshaping that
## multiplies each interior sample by the softness sends the whole table to zero
## at the bottom of the row and leaves only the held centre sample: a 58 pixel dab
## becomes a 3 texel spike, and a stroke of those spikes reads as an untouched
## canvas. It is a lerp towards full coverage instead, so the row runs from a
## hard-edged disc at zero to the painter's own curve at one. That is the same
## direction the row already means everywhere else, because
## [method effective_fade] multiplies the fade by softness and a fade of nothing
## is a hard edge, and it keeps the tooltip's promise that 100 changes nothing.
##
## **Built once and kept until the row or the curve moves**.
## The brush asks for the table on every dab, and 256 samples of a `Curve` in
## GDScript were the largest single cost of a dab, so a 2 px tip, which paints
## sixty times the dabs of a 128 px one over the same stroke, fell behind the
## pen. The kept table is keyed on the softness and on which curve it came from,
## and the curve's own `changed` drops it, so an edit in the curve control is
## read on the next dab as it always was.
func softness_table() -> PackedFloat32Array:
    if _table_fresh and _table_curve == softness_curve and _table_softness == softness:
        return _table
    if softness_curve != null and not softness_curve.changed.is_connected(_drop_table):
        softness_curve.changed.connect(_drop_table)
    _table = _built_softness_table()
    _table_curve = softness_curve
    _table_softness = softness
    _table_fresh = true
    return _table


func _drop_table() -> void:
    _table_fresh = false


func _built_softness_table() -> PackedFloat32Array:
    var table := PackedFloat32Array()
    table.resize(SOFTNESS_SAMPLES)
    if softness_curve == null:
        # A tip with no curve is the default falloff rather than an empty dab,
        # because a null here is a preset that predates the field.
        for i in SOFTNESS_SAMPLES:
            table[i] = 1.0 - float(i) / float(SOFTNESS_SAMPLES - 1)
        return table

    var s := clampf(softness, 0.0, 1.0)
    var last := SOFTNESS_SAMPLES - 1
    for i in SOFTNESS_SAMPLES:
        var at := float(i) / float(last)
        var value := clampf(softness_curve.sample_baked(at), 0.0, 1.0)
        if i > 0 and i < last:
            value = clampf(lerpf(1.0, value, s), 0.0, 1.0)
        table[i] = value
    return table
