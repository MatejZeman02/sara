## One point of a noise stroke's path as the kernel reads it: what the dynamics
## answered there turned into the tip's box, turn, fades, colour, height and
## lean, in the stretch's slot order, with the box its tip reaches.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The slots are the kernel's, not the stroke's.** The tool state decides when
## a point is laid, where the path goes and what the stretch is sent with. What
## a point is once the dynamics have answered is a question of the settings'
## rows and the kernel's layout alone, so it is answered here, in one place
## beside the rows that feed it, and the state holds the newest point it laid
## for the smudge stage to pick up under.
##
## **Three answers come from the state.** The Strength shift, the Hardness band
## and the lean are the tool's public questions, which suites ask the brush and
## two of them override to watch what the stroke read, so the state answers
## them through this class's statics and hands each answer in.
extends RefCounted

const NoiseTipScript = preload("res://modules/sara-noise-brush-engine/tip/noise_tip.gd")

## The smallest tip that paints, in document pixels of diameter. The tip's
## falloffs are the stamp's, measured to write nothing under this, so a point
## of the path smaller than it is laid with no tip and the stroke tapers to
## nothing there.
const MIN_DAB_DIAMETER: float = 0.2

## How much of the way from a tapered tip under three pixels up to three
## [method thinned] takes it back.
const SMALL_TIP_KEPT: float = 0.75


## The diameter a point whose options answered *size* is laid at, for a Size
## row of *whole* pixels across. A size of
## [constant SaDabGeometry.PIXEL_MODE_DIAMETER] or more is laid as the options
## answered, and one under it is taken back [constant SMALL_TIP_KEPT] of the
## way to three pixels and never past the whole row, so a larger Size still
## lays a larger tip. A size a curve took under [constant MIN_DAB_DIAMETER] is
## left alone, so it still lays nothing.
##
## **Why.** Under three pixels a dab is the pixel mode's single texel, so a
## taper that halves the tip at a press of 0.75, as Grain Round's does, laid
## the same three texels for every Size from 0.8 to 2.2 px in a grid of
## strokes at each Size, and the Size row did nothing there. A
## wide tip tapers as before, since its lightest end is wider than three
## pixels. A plain floor at three pixels laid a Size of 1.6 and of 2.2 alike,
## and taking a tip half the way back left a Size of 0.8 and of 1.2 alike.
static func thinned(size: float, whole: float) -> float:
    var pixel := SaDabGeometry.PIXEL_MODE_DIAMETER
    if size < MIN_DAB_DIAMETER or size >= pixel or size >= whole:
        return size
    return minf(whole, size + (pixel - size) * SMALL_TIP_KEPT)


## What the dynamics answered at this point.
var dab: SaDabParams = null
## The tip's centre in document pixels, snapped as the stamp snaps it.
var at: Vector2 = Vector2.ZERO
## The tip's radii after the lean's stretch, nought below [constant MIN_DAB_DIAMETER].
var half_extent: Vector2 = Vector2.ZERO
## The box the point's tip reaches, and how far past its centre the tip reaches.
var reach: Rect2 = Rect2()
var tip_reach: float = 0.0
## The point in the stretch's slot order, eight a row and the side, which its constants name.
var slots: PackedFloat32Array = PackedFloat32Array()
## The tip's generator, the one the kernel branches on.
var generator: int = 0
## The height in virtual millimetres the point builds to.
var thickness: float = 0.0
## The point's colour in the document's values, opaque, what a smudge's carry
## meets in the brush's blend mode.
var paint_color: Color = Color.BLACK


## The point *info* reads, which the dynamics answered as *dab*, at *along* of
## travelled length less the drift, its colour in *color_space*. *shift*,
## *band* and *lean* are the state's answers there. The tip's diameter is
## written onto the settings' tip, which the kernel's tip binding reads.
func _init(
    settings: Resource,
    info: SaStrokeInfo,
    answered: SaDabParams,
    along: float,
    color_space: SaColorSpace,
    shift: float,
    band: float,
    lean: Vector2
) -> void:
    dab = answered
    var tip: Resource = settings.tip
    tip.diameter = SaDabGeometry.drawn_diameter(maxf(0.1, dab.size))
    # The tip is the mask of where the stroke may paint, applied after the cut,
    # so its fades are its own, and Hardness is the cut's band and the rim the
    # kernel thins the grain towards, both from the point's band.
    at = SaDabGeometry.snap_to_pixels(dab.position + dab.scatter, 0.0, dab.size)
    half_extent = tip.half_extent()
    half_extent.y *= clampf(dab.ratio, 0.0, 1.0)
    var mirror_bits := SaDabGeometry.mirror_bits(tip.mirror_bits(), dab.mirror)
    # The tip's own angle and the Rotation option's turn, nought unless the
    # preset switched it on with a sensor, as on the stamp. Nothing else turns
    # a tip with an angle of its own, not the lean's stretch, not the heading,
    # which steers only the field, and not the twist, which reaches the turn
    # through that option's Rotation sensor alone.
    var radians: float = tip.angle + dab.rotation
    if SaDabGeometry.mirror_flips_handedness(mirror_bits):
        radians = -radians
    generator = tip.effective_generator()
    var reported_tilt := Vector2(info.tilt_x, info.tilt_y)
    var shows_angle: bool = NoiseTipScript.shows_angle(tip, generator, half_extent)
    var stretched := NoiseTipScript.stretch(half_extent, radians, reported_tilt, stretch_for(settings, info), shows_angle)
    half_extent = Vector2(stretched.x, stretched.y)
    radians = stretched.z
    if dab.size < MIN_DAB_DIAMETER:
        half_extent = Vector2.ZERO
    reach = SaDabGeometry.region(at, half_extent, radians, 2, NoiseTipScript.box_generator(tip, generator))
    tip_reach = NoiseTipScript.reach(tip, generator, half_extent)

    # The picked colour in the document's own encoding, and the point's alpha
    # is the opacity option's answer alone: the stroke's opacity is on the
    # buffer, which is what wash means. The door's colour dynamics come first,
    # on the picked sRGB colour as the stamp does, so a Saturation option greys
    # the paint before the conversion. They answer the colour untouched while
    # no colour option modulates.
    var shifted: Color = SaColorDynamics.apply(settings.color, dab, settings.background_color, color_space)
    var color: Color = color_space.from_display(shifted) if color_space != null else shifted
    # No exposure here, as on the stamp: the paint exposure is the
    # foreground's own stops in `SaColors`, so the colour is painted as picked.
    paint_color = Color(color.r, color.g, color.b, 1.0)
    color.a = clampf(dab.opacity, 0.0, 1.0)
    var fade: Vector2 = tip.effective_fade() * dab.softness
    var falloff := SaDabGeometry.falloff_radius(half_extent)
    thickness = thickness_for(settings, info)
    var turn := Vector2.from_angle(radians)
    var heading := Vector2.from_angle(info.drawing_angle(false))
    slots = PackedFloat32Array([at.x, at.y, along, info.pressure, half_extent.x, half_extent.y, turn.x, turn.y])
    slots.append_array([fade.x, fade.y, falloff.x, falloff.y, shift, band, thickness, float(mirror_bits)])
    slots.append_array([color.r, color.g, color.b, color.a, heading.x, heading.y, lean.x, lean.y])
    # The side the across is counted on, which only a reversal of the held path turns over.
    slots.append(1.0)
    # The place along the path, which the stretch writes as it takes the point.
    slots.append(0.0)


## Queues the smudge stage's pickup at this point into *carry*. The box is the
## point's own, its major radius times the Smudge Radius row of *settings* is
## how far out the pickup reads, and the point's colour is what the carry meets
## in the brush's blend mode, a bristle's tone moving it from there.
func pick_up_into(carry: SaSmudgeReservoir, settings: Resource) -> void:
    var radius: float = half_extent.x * settings.smudge_radius
    var rate := dab.smudge_color_rate
    carry.pick_up(reach, at, radius, dab.smudge_pickup, dab.smudge_length, rate, settings.smudge_mode, paint_color)


## The height in virtual millimetres the brightest texel under this point
## builds to: the Thickness row times its curve option, the pen's pressure by
## default, which is the spec's lightness times Thickness times pressure with
## the lightness left to the kernel.
static func thickness_for(settings: Resource, info: SaStrokeInfo) -> float:
    var option: SaCurveOption = settings.thickness_option
    var factor := 1.0
    if option != null and option.enabled:
        factor = option.size_like(info)
    return maxf(settings.thickness * factor, 0.0)


## How far this sample's lean stretches the tip, nought to one, the stretch
## option's answer: the pen's elevation along a falling line by default.
static func stretch_for(settings: Resource, info: SaStrokeInfo) -> float:
    var option: SaCurveOption = settings.stretch_option
    if option == null or not option.enabled:
        return 0.0
    return clampf(option.size_like(info), 0.0, 1.0)


## Which way this sample's height grows across the tip and by how much: the
## unit vector along the pen's lean, the axis [method stretch_for] stretches
## the tip along, times the Thickness Lean row times its option's answer, the
## elevation along a falling line by default. Nought for a pen with no lean,
## and pointing the other way when the row is below nought.
static func lean_for(settings: Resource, info: SaStrokeInfo) -> Vector2:
    var tilt := Vector2(info.tilt_x, info.tilt_y)
    if tilt.length() < 0.001:
        return Vector2.ZERO
    var share := clampf(settings.thickness_lean, -1.0, 1.0)
    var option: SaCurveOption = settings.thickness_lean_option
    if option != null and option.enabled:
        share *= clampf(option.size_like(info), 0.0, 1.0)
    return tilt.normalized() * share


## The width of the soft band under the cut at this point: the Hardness
## row times its curve option's answer, read the other way round. The kernel
## reads it twice, as the band and as how far in from the rim the grain
## starts to thin, so a band of nought is a hard dab with its grain full to
## the edge. A randomise control on Hardness rolls it along the stroke through
## the option's fuzzy sensor, which is what gives hard, soft and lost edges in
## one stroke.
static func band_for(settings: Resource, answered: SaDabParams) -> float:
    return clampf(1.0 - SaDabPacking.hardness_for_dab(settings.hardness, answered.hardness), 0.0, 1.0)


## How far the field is shifted against the pressure at this point: the
## Strength row times its curve option, which reads nothing by default since
## the pressure is the cut itself. Read here rather than by `SaDynamics`,
## because the door's dab has no field for a shift and the stamp has no use for
## one.
static func shift_for(settings: Resource, info: SaStrokeInfo) -> float:
    var option: SaCurveOption = settings.strength_option
    var factor := 1.0
    if option != null and option.enabled:
        factor = option.size_like(info)
    return clampf(settings.strength * factor, -1.0, 1.0)
