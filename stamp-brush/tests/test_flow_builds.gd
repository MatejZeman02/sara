## A flow below one still reaches the opacity it was set to.
##
## The dab kernel dispatched over a real texture and read back, the way
## `stamp-brush/tests/test_dab_shader.gd` reads it, because this is a claim about
## one line of arithmetic in `dab.gmacs` and a screenshot of a stroke cannot tell
## an alpha of 0.74 from one of 1.0.
##
## Measured on the running app before the fix: one stroke of 110 dabs at
## opacity 0.8 and flow 0.25 left the stroke's own axis at 124 where the arithmetic asks for
## 38, in wash, and at 105 in build-up. After it, wash at flow 0.25, 0.5 and 1.0
## all read 37 on that axis and build-up saturates.
extends "res://tests/test_framework.gd"

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const DabPacking = preload("res://core/api/dab/sa_dab_packing.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const SIDE: int = 64
## The workgroups one dispatch of the whole texture needs, written out because
## the kernel's own `[numthreads(8, 8, 1)]` is what this has to agree with.
const GROUPS: int = 8
const CENTRE := Vector2(32.0, 32.0)


## A hard round tip, so the centre texel's coverage is exactly one and the
## alphas below are the rule alone rather than the rule times a falloff.
func _tip(radius: float = 10.0) -> Resource:
    var tip := SaBrushTipScript.new()
    tip.diameter = radius * 2.0
    tip.ratio = 1.0
    tip.horizontal_fade = 1.0
    tip.vertical_fade = 1.0
    tip.antialias_edges = true
    return tip


## *count* dabs of *tip* stamped on the same spot at *flow*, in *mode*, into a
## cleared texture, read back as an alpha per texel.
##
## One `SaCompute` reused across the dabs, because the kernel reads the canvas it
## writes and a fresh compute per dab would prove the same thing more slowly.
func _stamp(count: int, flow: float, mode: int, dab_opacity: float = 1.0, tip: Resource = null) -> PackedFloat32Array:
    var stamped: Resource = tip if tip != null else _tip()
    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(canvas.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)

    var compute := SaCompute.new("dab")
    compute.set_texture(0, canvas.rid)
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    compute.set_texture(SaSelection.BINDING, selection.rid)
    var mask := SaBrushTipMask.load_image("")
    compute.set_buffer(StateBrushScript.SOFTNESS_BINDING, mask.softness_for(stamped).rid)
    compute.set_sampled_texture(StateBrushScript.TIP_IMAGE_BINDING, mask.sampler_rid())
    compute.set_sampled_texture(StateBrushScript.PATTERN_BINDING, SaBrushTipMask.stand_in().rid)
    compute.set_buffer(SaStampBindings.MASKING_BINDING, SaStampBindings.of(mask).masking_for(null, stamped.diameter).rid)
    SaSmudgeReservoir.bind(compute, null)
    compute.set_texture(StateBrushScript.HEIGHT_BINDING, SaStrokeHeights.held(null).rid)
    compute.set_sampled_texture(SaStampBindings.RAMP_BINDING, SaBrushTipMask.stand_in().rid)

    for i in count:
        compute.set_push_constant_float_array(
            DabPacking.pack_dab_params(
                CENTRE,
                Vector2.ZERO,
                Color(1, 1, 1, dab_opacity),
                stamped.half_extent(),
                0.0,
                stamped.effective_fade(),
                flow,
                mode,
                false,
                stamped,
                0.0,
                0.0,
                float(i)
            )
        )
        compute.dispatch_kernel("dab", GROUPS, GROUPS, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas.rid, 0)
    var out := PackedFloat32Array()
    out.resize(SIDE * SIDE)
    for i in SIDE * SIDE:
        out[i] = data.decode_float(i * 16 + 12)
    return out


static func _at(alpha: PackedFloat32Array, x: int, y: int) -> float:
    return alpha[y * SIDE + x]


## The regression. Four dabs at a quarter flow reach the opacity the dab carries,
## which is what the old `max( dst_a, src_a )` never did however many were sent.
func test_a_flow_below_one_reaches_the_dab_opacity_in_wash() -> void:
    for flow: float in [0.25, 0.5, 1.0]:
        var alpha := _stamp(8, flow, SaDabGeometry.PaintMode.ALPHA_DARKEN)
        assert_almost_eq(_at(alpha, 32, 32), 1.0, 1e-4, "Eight dabs at flow %.2f reach the dab's own opacity" % flow)


## The old behaviour, stated as the number it would give, so a revert fails here
## rather than in a screenshot. `max( dst_a, src_a )` leaves the alpha at one
## dab's `coverage * opacity * flow` whatever the count.
func test_the_wash_alpha_is_no_longer_one_dabs_worth() -> void:
    var alpha := _stamp(8, 0.25, SaDabGeometry.PaintMode.ALPHA_DARKEN)
    assert_true(_at(alpha, 32, 32) > 0.25 + 1e-3, "and is not the 0.25 the old rule stopped at")


## Flow still means something. One dab lays exactly its share, which is the half
## of the old rule that was right and which a painter sees at a stroke's leading
## edge and wherever the spacing is too coarse to overlap.
func test_one_dab_at_a_quarter_flow_lays_a_quarter() -> void:
    for flow: float in [0.25, 0.5, 1.0]:
        var alpha := _stamp(1, flow, SaDabGeometry.PaintMode.ALPHA_DARKEN)
        assert_almost_eq(_at(alpha, 32, 32), flow, 1e-4, "One dab at flow %.2f lays %.2f" % [flow, flow])


## The climb is linear rather than geometric, which is the decision this unit
## took and the one a later reader is most likely to undo. Closing a `flow`
## fraction of the remaining gap gives `1 - 0.75 ^ 4`, which is 0.684, and the
## measurement that rejected it was a stroke still reading 61 against 38.
func test_four_dabs_at_a_quarter_flow_are_full_rather_than_two_thirds() -> void:
    var alpha := _stamp(4, 0.25, SaDabGeometry.PaintMode.ALPHA_DARKEN)
    assert_almost_eq(_at(alpha, 32, 32), 1.0, 1e-4, "Four quarters are one")
    assert_true(_at(alpha, 32, 32) > 0.9, "and not the 0.684 a geometric approach would leave")


## The alpha never passes the dab's own opacity, which is the spec's sentence and
## the reason for the `min`. A half-opacity dab stamped eight times is still a
## half-opacity stroke.
func test_the_alpha_never_climbs_past_the_dab_opacity() -> void:
    var alpha := _stamp(8, 0.25, SaDabGeometry.PaintMode.ALPHA_DARKEN, 0.5)
    assert_almost_eq(_at(alpha, 32, 32), 0.5, 1e-4, "Eight dabs of a half-opacity tip stop at a half")


## Build-up is untouched by all of this. Its dabs still accumulate with `over`,
## so eight of them at a quarter flow are darker than one and the mode a painter
## picks still changes what a crossing does.
func test_build_up_still_accumulates_where_wash_stops() -> void:
    var one := _stamp(1, 0.25, SaDabGeometry.PaintMode.OVER)
    var many := _stamp(8, 0.25, SaDabGeometry.PaintMode.OVER)
    assert_almost_eq(_at(one, 32, 32), 0.25, 1e-4, "One build-up dab at a quarter flow lays a quarter")
    assert_true(_at(many, 32, 32) > 0.85, "and eight of them pile up, %.4f" % _at(many, 32, 32))
