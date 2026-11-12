## A wash dab lands at its own colour wherever nothing was under it.
##
## The dab kernel dispatched over a real texture and read back, beside
## `test_flow_builds.gd` and for the same reason: this is a claim about one
## line of arithmetic in `dab.gmacs`, and a screenshot cannot tell a red of 0.600
## from one of 0.397.
##
## What a painter saw was a dark rim on every stroke of an imported Krita
## preset, which are wash unless they say build-up, and the whole of a thin or
## lightly pressed one. The kernel measured the same: one dab of
## `Color(0.6, 0.1, 0.3, 1.0)` into a cleared texture read the paint's red times
## the texel's alpha at every step of the fade, 0.397 at alpha 0.662 and 0.061 at
## alpha 0.101, which is a premultiplied colour written into a layer that stores
## straight alpha. The compositor then multiplies by alpha again.
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

## A painter's own measurement used this one, so the numbers in the record and
## the numbers here are of the same dab.
const PAINT := Color(0.6, 0.1, 0.3, 1.0)


## A round tip of diameter 40 whose edge fades over a fifth of the radius, so the
## row through the centre carries a plateau at alpha one and a dozen texels at
## every alpha between one and zero. The bug lives in those texels and nowhere
## else, and a hard edge would have hidden it.
func _tip() -> Resource:
    var tip := SaBrushTipScript.new()
    tip.diameter = 40.0
    tip.ratio = 1.0
    tip.horizontal_fade = 0.2
    tip.vertical_fade = 0.2
    tip.antialias_edges = true
    return tip


## *count* dabs of *paint* stamped on the same spot in *mode*, into a texture
## cleared to *ground*, read back as the whole RGBA per texel.
##
## One `SaCompute` reused across the dabs, because the kernel reads the canvas it
## writes and a fresh compute per dab would prove the same thing more slowly.
func _stamp(count: int, mode: int, paint: Color = PAINT, ground: Color = Color(0, 0, 0, 0)) -> PackedFloat32Array:
    var stamped := _tip()
    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(canvas.rid, ground, 0, 1, 0, 1)

    var compute := SaCompute.new("dab")
    compute.set_texture(0, canvas.rid)
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    compute.set_texture(SaSelection.BINDING, selection.rid)
    var mask := SaBrushTipMask.load_image("")
    compute.set_buffer(StateBrushScript.SOFTNESS_BINDING, mask.softness_for(stamped).rid)
    compute.set_sampled_texture(StateBrushScript.TIP_IMAGE_BINDING, mask.sampler_rid())
    compute.set_sampled_texture(StateBrushScript.PATTERN_BINDING, SaBrushTipMask.stand_in().rid)
    # The masking block and the smudge reservoir added: a
    # declared binding with nothing in it is a set that refuses to build, and a
    # set that never built paints nothing.
    compute.set_buffer(SaStampBindings.MASKING_BINDING, SaStampBindings.of(mask).masking_for(null, stamped.diameter).rid)
    SaSmudgeReservoir.bind(compute, null)
    compute.set_texture(StateBrushScript.HEIGHT_BINDING, SaStrokeHeights.held(null).rid)
    compute.set_sampled_texture(SaStampBindings.RAMP_BINDING, SaBrushTipMask.stand_in().rid)

    for i in count:
        compute.set_push_constant_float_array(
            DabPacking.pack_dab_params(
                CENTRE,
                Vector2.ZERO,
                paint,
                stamped.half_extent(),
                0.0,
                stamped.effective_fade(),
                1.0,
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
    out.resize(SIDE * SIDE * 4)
    for i in SIDE * SIDE * 4:
        out[i] = data.decode_float(i * 4)
    return out


static func _texel(rgba: PackedFloat32Array, x: int, y: int) -> Color:
    var i := (y * SIDE + x) * 4
    return Color(rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3])


## The regression, over the whole fade rather than at one texel. Every texel the
## dab touched carries the paint's own colour, whatever its alpha, which is what
## the lerp by `src_a` alone never did on a cleared texture.
func test_a_wash_dab_lands_at_its_colour_at_every_alpha() -> void:
    var rgba := _stamp(1, SaDabGeometry.PaintMode.ALPHA_DARKEN)
    var seen_in_the_fade := 0
    for x in range(SIDE):
        var texel := _texel(rgba, x, 32)
        if texel.a <= 0.0:
            continue
        if texel.a < 0.999:
            seen_in_the_fade += 1
        assert_almost_eq(texel.r, PAINT.r, 1e-3, "Texel %d at alpha %.3f keeps the paint's red" % [x, texel.a])
        assert_almost_eq(texel.g, PAINT.g, 1e-3, "Texel %d at alpha %.3f keeps the paint's green" % [x, texel.a])
        assert_almost_eq(texel.b, PAINT.b, 1e-3, "Texel %d at alpha %.3f keeps the paint's blue" % [x, texel.a])
    assert_true(seen_in_the_fade >= 4, "and the row really has a fade to check, %d texels" % seen_in_the_fade)


## The old behaviour, stated as the number it would give, so a revert fails here
## rather than in a screenshot. `mix( dst, src, src_a )` on a cleared texel is
## the paint's colour times the alpha, so a painter's table read 0.397 where the
## paint's red is 0.600.
func test_the_fade_is_no_longer_the_colour_times_the_alpha() -> void:
    var rgba := _stamp(1, SaDabGeometry.PaintMode.ALPHA_DARKEN)
    for x in range(SIDE):
        var texel := _texel(rgba, x, 32)
        if texel.a <= 0.0 or texel.a > 0.9:
            continue
        assert_true(
            texel.r > PAINT.r * texel.a + 1e-3,
            "Texel %d at alpha %.3f is above the %.3f premultiplication left" % [x, texel.a, PAINT.r * texel.a]
        )


## The fix had to keep this: a dab lands at its own colour
## whatever is already under it. Over opaque paint the weight is `src_a` exactly,
## so this is the plain lerp the comment describes and a second wash dab of a
## different colour covers the first.
func test_a_second_wash_dab_covers_the_first() -> void:
    var green := Color(0.1, 0.7, 0.2, 1.0)
    var rgba := _stamp(1, SaDabGeometry.PaintMode.ALPHA_DARKEN, green, Color(PAINT.r, PAINT.g, PAINT.b, 1.0))
    var centre := _texel(rgba, 32, 32)
    assert_almost_eq(centre.r, green.r, 1e-3, "The centre is the second dab's red")
    assert_almost_eq(centre.g, green.g, 1e-3, "and its green")
    assert_almost_eq(centre.b, green.b, 1e-3, "and its blue")


## Over opaque paint the weight is unchanged, so the fade of a dab laid on a full
## layer still blends towards what is under it rather than jumping to the paint.
## This is the half of the old rule that was right, and the one a later reader is
## most likely to undo along with the other half.
func test_over_opaque_paint_the_fade_still_blends() -> void:
    var green := Color(0.1, 0.7, 0.2, 1.0)
    var rgba := _stamp(1, SaDabGeometry.PaintMode.ALPHA_DARKEN, green, Color(PAINT.r, PAINT.g, PAINT.b, 1.0))
    var blended := 0
    for x in range(SIDE):
        var texel := _texel(rgba, x, 32)
        if texel.a <= 0.0:
            continue
        if texel.r > minf(green.r, PAINT.r) + 1e-3 and texel.r < maxf(green.r, PAINT.r) - 1e-3:
            blended += 1
    assert_true(blended >= 4, "The fade over opaque paint is a blend of the two, %d texels" % blended)


## Build-up is untouched. Its own branch already divided the premultiplied sum by
## the blended alpha, which is why a painter's table read 0.600 down its column,
## and this unit changed no line of it.
func test_build_up_still_lands_at_its_colour() -> void:
    var rgba := _stamp(1, SaDabGeometry.PaintMode.OVER)
    for x in range(SIDE):
        var texel := _texel(rgba, x, 32)
        if texel.a <= 0.0:
            continue
        assert_almost_eq(texel.r, PAINT.r, 1e-3, "Build-up texel %d at alpha %.3f keeps the paint's red" % [x, texel.a])


## Alpha is not touched by any of this, so the earlier measurements stand. One dab at
## full flow lays its own coverage, and the plateau through the centre is one.
func test_the_alpha_is_what_f72_left_it() -> void:
    var rgba := _stamp(1, SaDabGeometry.PaintMode.ALPHA_DARKEN)
    assert_almost_eq(_texel(rgba, 32, 32).a, 1.0, 1e-4, "The centre of a full-flow dab is opaque")
    assert_almost_eq(_texel(rgba, 0, 32).a, 0.0, 1e-4, "and a texel the tip never reached is clear")
