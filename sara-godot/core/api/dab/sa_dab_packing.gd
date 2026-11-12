## The push constant the dab kernel reads, and nothing else.
##
## Static functions that were on `state_brush.gd` until it became the longest
## script in the tree. They left first because they are the part of it that
## reads nothing off the tool: no settings, no stroke, no document, only the
## arguments handed in. That is also why every suite that dispatches the kernel
## by hand calls them, and why calling them meant preloading a five hundred
## line tool state to reach pure functions. The retired `paint` kernel's packer
## lives with its kernel in `tests/fixtures/paint_kernel.gd` in the skeleton,
## the suites being the only callers left.
##
## **This file does not port `kis_dab_cache_base.cpp`**. That file splits a dab's position into an integer origin and a
## sub-pixel remainder because it rasterises a mask into an integer buffer, and
## mirrors the origin. Nothing here does either: the centre goes to the kernel as
## a float and every texel is evaluated at its own coordinate, so there is no
## dab cache to keep.
class_name SaDabPacking
extends RefCounted

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## Where the pattern hook's three floats sit in the dab's push constant, which
## is the tail `SaDabGeometry.pack` resizes into rather than writes.
##
## Written here rather than beside the rest of the order because
## `sa_dab_geometry.gd` is the box arithmetic's file and a pattern has no box:
## the multiply happens on a coverage the box already contains, so a patterned
## dab dispatches over exactly the rectangle a plain one does and hard rule 2
## has nothing to say about it.
const PATTERN_STRENGTH_INDEX: int = 29
const PATTERN_OFFSET_X_INDEX: int = 30
const PATTERN_OFFSET_Y_INDEX: int = 31


## The dab's push constant, which is `SaDabGeometry.pack` and nothing of its
## own.
##
## The ordering belongs beside the box arithmetic that has to agree with it
## rather than beside the stroke that drives both. *tip* carries the generator,
## the shape, the spikes and the rest. Null is the plain hard circle, which is
## what the suites that predate the tip resource still ask for.
##
## *pattern_strength* and *pattern_offset* both default to the dab without a pattern: a strength of
## nothing makes the kernel return from its pattern read before it takes it. A negative strength is the
## invert, the magnitude being the strength and the sign the toggle, and a magnitude above one is the
## subtract mode carrying its strength one higher. **The offset is in document texels and carries the
## chunk's own origin**, because the kernel's coordinates are chunk-local and a tile grid stated in
## them would break at every chunk edge the tile size does not divide. A caller with a paint context
## therefore sends `target.grid_pos * chunk_size` plus whatever the painter asked for, and the tile
## size itself is not sent at all: the pattern texture is at its tile size and the kernel asks the
## sampler.
##
## *sharpness* and *sharpness_soft* are two floats and the block still carries
## exactly the two it always did. What changed under them is where the first one
## comes from: it is `SaDabParams.sharpness`, the Sharpness row after its own
## curve option has read the sensors, so it moves from dab to dab inside one
## stroke. **Nothing here had to grow for that**, and that is the whole of this
## file's part in it: the float was already in the block, and a per-dab value
## costs exactly what a per-stroke one did. The other half of sharpness, the
## snap of the centre onto the pixel grid, is applied by the caller before the
## box is computed and never reaches here.
##
## *diameter* is the dab's own, in document pixels, and the only thing it decides
## is the small-dab mode below. A caller that does not say gets the dab it always
## got, which the body's own comment gives the reason for.
static func pack_dab_params(
    dab_center: Vector2,
    render_offset: Vector2,
    color: Color,
    half_extent: Vector2,
    radians: float,
    fade: Vector2,
    flow: float,
    paint_mode: int = SaDabGeometry.PaintMode.OVER,
    alpha_lock: bool = false,
    tip: Resource = null,
    sharpness: float = 0.0,
    sharpness_soft: float = 0.0,
    dab_seed: float = 0.0,
    pattern_strength: float = 0.0,
    pattern_offset: Vector2 = Vector2.ZERO,
    diameter: float = -1.0
) -> PackedFloat32Array:
    # The small-dab mode. Under `SaDabGeometry.PIXEL_MODE_DIAMETER` the dab
    # paints whole texels, which the kernel already knows how to do: a sharpness
    # of one with no softness closes `sa_apply_threshold`'s two edges onto the
    # half coverage contour, so every texel comes out at nought or one and the
    # mark is the grid rather than a fringe over it. The Sharpness and Softness
    # rows are overridden rather than consulted, because the mode is one the
    # brush enters by its size rather than one a painter ticks.
    #
    # **The diameter is asked for rather than read off the half-extent**, and the
    # first shape of this read it off. Four suites stamp a dab of half a pixel
    # through this function to pin what the kernel does with a shape smaller than
    # a texel, and the mode rewrote all four: `test_dab_shader` and
    # `test_dab_image_tip` measure that a sub-pixel dab is a supersampled fraction
    # rather than a switch, which is the opposite of what the mode makes it. So
    # the mode is the tool's to enter, `state_brush.gd` is the only caller that
    # does, and a default of -1.0 means the caller did not say and gets the dab it
    # always got.
    var pixel_mode := SaDabGeometry.is_pixel_mode(diameter)
    var dab_sharpness := 1.0 if pixel_mode else sharpness
    var dab_sharpness_soft := 0.0 if pixel_mode else sharpness_soft
    var brush_tip: SaBrushTipScript = tip
    var data := SaDabGeometry.pack(
        dab_center,
        render_offset,
        color,
        half_extent,
        radians,
        fade,
        flow,
        2 if brush_tip == null else brush_tip.spikes,
        SaDabGeometry.Generator.DEFAULT if brush_tip == null else brush_tip.effective_generator(),
        0.0 if brush_tip == null else float(brush_tip.shape),
        true if brush_tip == null else brush_tip.antialias_edges,
        1.0 if brush_tip == null else brush_tip.density,
        0.0 if brush_tip == null else brush_tip.randomness,
        dab_seed,
        dab_sharpness,
        dab_sharpness_soft,
        paint_mode,
        alpha_lock,
        0 if brush_tip == null else brush_tip.mirror_bits()
    )
    # The three the box arithmetic has nothing to say about, written onto the
    # tail it resized into rather than passed through it. Minus one to one
    # rather than nought to one: the sign is the invert toggle, because the
    # block has no float left for a flag and a strength is never negative on
    # its own. The kernel reads the magnitude as the strength and a negative
    # as the paper turned over.
    #
    # One band per texturing mode on the same number, a magnitude above one
    # being the next mode's strength carried a whole number higher. The clamp
    # to as many bands as there are modes is `SaDabPattern.strength_for`'s,
    # which encodes the number, so the packing writes what it is handed.
    data[PATTERN_STRENGTH_INDEX] = pattern_strength
    data[PATTERN_OFFSET_X_INDEX] = pattern_offset.x
    data[PATTERN_OFFSET_Y_INDEX] = pattern_offset.y
    return data


## Sara's Hardness slider as the engine's fade, and **the mapping is straight
## through, not `fade = 1 - hardness`**, which reads naturally and is inverted.
##
## `fade_coef` is `coef / fade`, so at a fade of 1
## the fade norm equals the shape norm, `nf < 1` wherever `n < 1`, and the whole
## ellipse is core: a fade of **one** is the hard edge. At a fade of zero the
## coefficient degenerates to 1 by Krita's own guard, the fade norm dwarfs the
## shape norm, and the coverage becomes about `1 - n`: a soft dome. So hardness
## maps straight through.
static func fade_for_hardness(hardness: float) -> Vector2:
    var fade := clampf(hardness, 0.0, 1.0)
    return Vector2(fade, fade)


## The Hardness row after the Hardness option has read the sensors, which is the
## number the tip's two fades are written from.
##
## Here rather than at the one line that reads the row, because it is the same
## kind of fact as `fade_for_hardness` above: what the engine does to a hardness
## before the kernel sees it. The two are not folded into one function, because
## the row is written onto the tip and the tip is what builds the pair, so the
## place that wants this one is a step earlier than the place that wants that
## one.
##
## **A multiply, and the option's neutral value is one.** `SaDynamics` answers 1
## for an option nobody switched on, so an untouched brush multiplies its row by
## one and paints exactly what it painted. A ceiling of one is also why the row
## is the maximum: the option can only soften, which is the same direction as
## Size and Opacity, and a painter who wants a harder edge than the row drags
## the row.
##
## **Zero is allowed through.** It is the lost edge: the kernel's fade
## coefficient degenerates at a fade of nothing and the coverage becomes a soft
## dome, which is what a brush that makes hard, soft and lost edges in one
## stroke needs at the bottom of its range. Nothing here floors it, unlike the
## tip's softness, whose floor exists because a fade of nothing there would be a
## dab with no mask at all.
static func hardness_for_dab(row: float, dab_hardness: float) -> float:
    return clampf(row, 0.0, 1.0) * clampf(dab_hardness, 0.0, 1.0)
