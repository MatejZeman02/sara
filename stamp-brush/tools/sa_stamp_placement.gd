## Where one evaluated dab lands on the canvas and the shape it lands in.
##
## The half of a dab between what the dynamics answer and what the kernel is
## handed: the centre snapped for sharpness, the stroke's tip sized from the
## dab, the turned and mirrored shape, the box the dispatch covers and the fade.
## It reads the dab, the brush's settings, what the walk settled for its dabs,
## the stroke's own tip and the view, and nothing of the tool that asks, which
## is why it is not the tool's: [SaDabGeometry] is the arithmetic, and this is
## the order a stamp dab asks it in.
class_name SaStampPlacement
extends RefCounted

## The smallest dab worth dispatching, in document pixels of diameter.
##
## Krita guards the same case in `KisPaintOpUtils::checkSizeTooSmall` at 0.01
## pixels, which is a bound on a rasterised mask that has to have at least one
## sample in it. Sara's dab is evaluated analytically in the kernel, so the
## bound is not a property of a mask and had to be measured instead: one dab
## into a cleared texture, read back per texel, at three hardnesses, at three
## sub-pixel centres, and for the image generator as well as the analytic ones.
## **Every generator writes nothing at 0.20 and something at 0.22 to 0.24.**
## This is set at the top of the band that writes nothing, so the guard can
## never take away ink that was landing.
##
## What it costs to leave out is not a slow brush, it is a brush whose cost goes
## up as the stroke becomes less visible: a size ramp at low pressure asks for a
## dab of about an eighth of a pixel, and because the walk's own step is floored
## at half a pixel a 960 pixel drag then pays about 1979 compute dispatches for
## a line with no lit texel anywhere in it.
const MIN_DAB_DIAMETER: float = 0.2

## The dab's centre in document pixels, scattered and snapped.
var position: Vector2
## The stroke's own tip, sized, faded and spaced for this dab.
var tip: Resource
## Whether the dab is too small for the kernel to write, in which case nothing
## past [member tip] was worked out.
var too_small: bool = false
## Half the drawn shape's extent, after the ratio and the view's stretch.
var half_extent: Vector2
## The shape's turn, its handedness folded in.
var radians: float = 0.0
## The tip's resting mirror turned over by the dab's.
var mirror_bits: int = 0
## The box the dispatch covers and no more.
var region: Rect2
## The tip's fade under the dab's softness.
var fade: Vector2


## Places *dab*, painted with *settings* and the walk's *reads*, through
## *stroke_tip*, the stroke's own copy of the tip, on a canvas *canvas_width*
## pixels wide that *view* shows. Writes the dab's `stretch`, which the
## dispatch reads after.
func _init(
    dab: SaDabParams, settings: Resource, reads: SaWalkBatch.Reads, stroke_tip: Resource, view: SaView, canvas_width: float
) -> void:
    # Sharpness pulls the centre towards the pixel grid **before** the box is
    # computed, because the box is the dirty rectangle the dispatch covers and a
    # centre snapped after it is paint that never lands.
    var sharpness := clampf(dab.sharpness, 0.0, 1.0)
    var mode := SaSmallDab.mode_diameter(settings, dab.size, reads.density)
    position = SaSmallDab.snap(dab.position + dab.scatter, sharpness, mode, reads.density)

    # The painter drags a radius and the tip is what the kernel reads, so the size
    # is copied over rather than held in two places. The size is the evaluator's
    # rather than the slider's, which is the same number while nothing modulates
    # it. Hardness goes the same way: it is the tip's two fades under the name the
    # bar already uses, and a second Fade slider would be two controls writing one
    # number. The pixel mode's floor goes on the tip and not at the three places
    # below it, because the box, the step and the push constant all read the tip
    # and none may disagree. `SaSmallDab` says whether this brush enters the mode.
    tip = stroke_tip
    tip.diameter = SaSmallDab.drawn_diameter(settings, maxf(0.1, dab.size), reads.density)
    var hardness := SaDabPacking.hardness_for_dab(reads.hardness, dab.hardness)
    tip.horizontal_fade = hardness
    tip.vertical_fade = hardness
    # Spacing goes the same way as the size and the hardness. `settings` is
    # where a preset written before the tip existed keeps its spacing, and
    # every preset has one, so the bar's number is the source and the tip's is
    # the copy the walk reads.
    tip.spacing = reads.spacing

    # A dab the kernel cannot write is skipped rather than dispatched, and the
    # tool still tells the walk where it fell, [method SaStrokeDistance.register_dab].
    if dab.size < MIN_DAB_DIAMETER:
        too_small = true
        return

    # The dab's own box rather than a square of the radius: the turned shape's
    # exact box, its antialiasing pixel and the major axis on both sides once
    # spikes fold it, and the dispatch covers that rectangle and no more. The
    # ratio option narrows the minor axis over the tip's own ratio, and the
    # rotation option turns the tip on top of its resting angle, which is added
    # here rather than folded into the dab's, the seam `SaDabParams` describes.
    half_extent = SaDabGeometry.drawn_half_extent(tip.half_extent(), dab.ratio)
    # One mirrored axis turns the frame left-handed, so its angle runs the other
    # way, and the bits are the tip's resting mirror turned over by this dab's.
    mirror_bits = SaDabGeometry.mirror_bits(tip.mirror_bits(), dab.mirror)
    radians = tip.angle + dab.rotation
    if SaDabGeometry.mirror_flips_handedness(mirror_bits):
        radians = -radians
    # Round where the view shows a sphere: stretched in x before the box is
    # drawn round it, and folded over a pole it reaches past.
    dab.stretch = view.dab_stretch(position) if view != null else 0.0
    var drawn := SaProjection.Stretched.new(half_extent, radians, dab.stretch, tip, canvas_width)
    half_extent = drawn.half_extent
    radians = drawn.radians
    # An image tip's rectangle reaches further at its corners than the ellipse,
    # so the generator actually pushed decides which shape the box is round.
    region = SaDabGeometry.region(position, half_extent, radians, tip.spikes, tip.effective_generator())

    # The softness option multiplies the fade the tip computed, which is what the
    # spec's table means by "the mask generator's fade". A default preset leaves
    # it at 1, so the fade is the tip's own and nothing else.
    #
    # The SOFT generator's curve is **not** reshaped by the option, only the
    # fade is. Reshaping it would mean writing the option into `tip.softness`,
    # which is a stored field on a resource shared across every dab of the
    # stroke, and a per-dab value has no business living there. Whoever gives
    # softness a control decides whether the table follows it.
    fade = tip.effective_fade() * dab.softness
