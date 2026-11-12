## Hard rule 2 from the other direction: nothing outside the box is written.
##
## `sa_dab_geometry.gd` computes a dirty rect per dab and `state_brush.gd`
## dispatches only the chunks that rect overlaps. Every other suite here asks
## whether the mask inside the box is right. This one asks the opposite question,
## which is the one a clipped stroke is made of: **is there a parameterisation
## whose paint lands outside the box that was dispatched for it?**
##
## A box that is too large costs a few texels. A box that is too small clips the
## dab, silently, at one rotation and one ratio and nowhere else, which is what
## the spikes, the sharpness snap and the mirror each nearly did and what no
## screenshot would have shown.
##
## **A hundred dabs, parameterised from a fixed seed.** Random rather than a
## grid, because the failures this is for are corners of a five-dimensional space
## and a grid coarse enough to run in a second visits none of them. Fixed, so a
## failure names a case a reader can reproduce: the seed and the index are in
## every message.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The texture every dab is stamped into, and the workgroups that covers at the
## kernel's own `[numthreads(8, 8, 1)]`.
const SIDE: int = 96
const GROUPS: int = 12

## How many dabs, and the seed they come from.
const DABS: int = 100
const SEED: int = 0x5A5A12

## What counts as painted. A texel the kernel wrote zero coverage into is not
## paint, and the float path leaves a few of those at the antialiased edge.
const PAINTED: float = 1.0 / 512.0


func test_no_dab_writes_a_texel_outside_the_box_computed_for_it() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = SEED
    var outside_total := 0
    var worst := ""
    var worst_by := 0.0

    for index in DABS:
        var case := _case(rng)
        # The snap before the box, which is the order `state_brush.gd` keeps and
        # the order the pixel mode makes matter for a dab of any size: under the
        # threshold the round happens the whole way with the Sharpness row at
        # nothing, so it moves a centre the box has not been drawn around yet.
        var centre: Vector2 = SaDabGeometry.snap_to_pixels(case["centre"], case["sharpness"], case["diameter"])
        case["centre"] = centre
        var alpha := _stamp(case)
        var box: Rect2 = SaDabGeometry.region(centre, case["half_extent"], case["radians"], case["spikes"])
        for y in SIDE:
            for x in SIDE:
                if alpha[y * SIDE + x] <= PAINTED:
                    continue
                # A texel is inside when its own square meets the box, which is
                # what a dispatch over the box covers: the rect is in document
                # units and the dispatch is in whole texels.
                if box.intersects(Rect2(float(x), float(y), 1.0, 1.0)):
                    continue
                outside_total += 1
                var by := _distance_outside(box, Vector2(float(x), float(y)))
                if by > worst_by:
                    worst_by = by
                    worst = (
                        "dab %d of seed 0x%X wrote (%d, %d) at coverage %.3f, %.2f texels outside %s"
                        % [index, SEED, x, y, alpha[y * SIDE + x], by, str(box)]
                    )

    assert_eq(outside_total, 0, "a hundred dabs wrote nothing outside their own box. %s" % worst)


## One dab's parameters, over the ranges the engine actually reaches.
##
## The half-extents stay clear of the texture's edge at every rotation, because
## a dab clipped by the texture would read as a dab clipped by the box and the
## question here is only about the box.
##
## **A fifth of them are under the pixel-mode threshold**. That mode rounds the
## centre the whole way whatever the Sharpness row says, so it moves a dab by up
## to half a texel on each axis after the painter's own coordinate and before the
## box, which is the same trap the sharpness snap was: a centre moved after the
## box was drawn is paint outside the dispatch. The stamp below snaps first and
## boxes the snapped centre, the way `state_brush.gd` does, and the size goes
## through the mode's own floor first for the same reason: a dab drawn larger
## than the box was computed for is the same bug from the other end.
func _case(rng: RandomNumberGenerator) -> Dictionary:
    var small := rng.randf() < 0.2
    var asked := rng.randf_range(0.3, 2.9) if small else rng.randf_range(3.0, 16.0)
    var major := SaDabGeometry.drawn_diameter(asked) * 0.5
    var ratio := rng.randf_range(0.15, 1.0)
    return {
        "diameter": major * 2.0,
        "centre": Vector2(rng.randf_range(30.0, 66.0), rng.randf_range(30.0, 66.0)),
        "half_extent": Vector2(major, major * ratio),
        "radians": rng.randf_range(0.0, TAU),
        "spikes": 2 if rng.randf() < 0.6 else rng.randi_range(3, 8),
        "fade": Vector2(rng.randf_range(0.0, 1.0), rng.randf_range(0.0, 1.0)),
        "sharpness": 0.0 if rng.randf() < 0.5 else rng.randf_range(0.0, 1.0),
        "seed": rng.randf(),
    }


## Stamps *case* into a cleared texture over the whole of it, and answers the
## alpha per texel.
##
## The whole texture rather than the box, deliberately: dispatching the box
## would make the assertion true by construction. What is being asked is where
## the kernel writes when nothing stops it.
func _stamp(case: Dictionary) -> PackedFloat32Array:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(canvas.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)

    var tip := SaBrushTipScript.new()
    tip.diameter = case["half_extent"].x * 2.0
    tip.ratio = case["half_extent"].y / case["half_extent"].x
    tip.horizontal_fade = case["fade"].x
    tip.vertical_fade = case["fade"].y
    tip.spikes = case["spikes"]
    tip.antialias_edges = true

    var compute := SaCompute.new("dab")
    compute.set_texture(0, canvas.rid)
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    compute.set_texture(SaSelection.BINDING, selection.rid)
    var mask := SaBrushTipMask.load_image("")
    compute.set_buffer(StateBrushScript.SOFTNESS_BINDING, mask.softness_for(tip).rid)
    compute.set_sampled_texture(StateBrushScript.TIP_IMAGE_BINDING, mask.sampler_rid())
    compute.set_sampled_texture(StateBrushScript.PATTERN_BINDING, SaBrushTipMask.stand_in().rid)
    compute.set_buffer(SaStampBindings.MASKING_BINDING, SaStampBindings.of(mask).masking_for(null, tip.diameter).rid)
    SaSmudgeReservoir.bind(compute, null)
    compute.set_texture(StateBrushScript.HEIGHT_BINDING, SaStrokeHeights.held(null).rid)
    compute.set_sampled_texture(SaStampBindings.RAMP_BINDING, SaBrushTipMask.stand_in().rid)
    compute.set_push_constant_float_array(
        SaDabPacking.pack_dab_params(
            case["centre"],
            Vector2.ZERO,
            Color(1, 1, 1, 1),
            case["half_extent"],
            case["radians"],
            tip.effective_fade(),
            1.0,
            SaDabGeometry.PaintMode.OVER,
            false,
            tip,
            case["sharpness"],
            0.0,
            case["seed"],
            0.0,
            Vector2.ZERO,
            case["diameter"]
        )
    )
    compute.dispatch_kernel("dab", GROUPS, GROUPS, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas.rid, 0)
    var out := PackedFloat32Array()
    out.resize(SIDE * SIDE)
    for i in SIDE * SIDE:
        out[i] = data.decode_float(i * 16 + 12)
    return out


## How far *point* is from *box*, in texels, so a failure says by how much
## rather than only that it happened. A near miss and a clipped stroke are
## different bugs and the number is what tells them apart.
static func _distance_outside(box: Rect2, point: Vector2) -> float:
    var dx := maxf(maxf(box.position.x - point.x, point.x - box.end.x), 0.0)
    var dy := maxf(maxf(box.position.y - point.y, point.y - box.end.y), 0.0)
    return maxf(dx, dy)
