## The masking brush's composite ops, a masked dab painted
## through each over a known mask and read back against Krita's formula.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The known mask is the mask painted alone.** The dab is painted alone, the
## mask's own tip is painted alone as an ordinary dab, and the masked dab is
## compared at every texel with the op of the two, the way `test_masking_dab.gd`
## checks the product. Both shapes are soft, so the dab runs from one to nought
## across the texture and the mask from one to nought inside it, and every
## branch of every formula is met: a dab above half and below it for overlay, a
## mask of nought over a dab for subtract and burn, and a mask whole.
##
## The formulas below are written from `KisMaskingBrushCompositeOp.h` and not
## from the kernel, so a kernel that drifted from Krita fails here.
extends "res://tests/test_framework.gd"

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const SIDE: int = 64
const GROUPS: int = 8
const CENTRE := Vector2(32.0, 32.0)

## Large enough for one sample per texel, for the reason `test_masking_dab.gd`
## gives, and soft enough that the dab crosses half well inside its outline.
const DAB_HALF: float = 24.0
const DAB_FADE: float = 0.2

## The mask a little smaller than the dab, so a ring of texels is dab with no
## mask over it, which is where subtract, burn and overlay part from multiply.
const MASK_SIZE: float = 0.8
const MASK_FADE: float = 0.3


func _tip(half: float, fade: float) -> Resource:
    var tip := SaBrushTipScript.new()
    tip.diameter = half * 2.0
    tip.horizontal_fade = fade
    tip.vertical_fade = fade
    return tip


func _masking(op: SaMaskingBrush.Op) -> SaMaskingBrush:
    var block := SaMaskingBrush.new()
    block.enabled = true
    block.size = MASK_SIZE
    block.op = op
    block.tip = _tip(1.0, MASK_FADE)
    return block


## One dab into a cleared texture, read back as an alpha per texel. *info* is
## the stroke the mask's own options read, null for none.
func _paint(tip: Resource, masking: Resource = null, info: SaStrokeInfo = null) -> PackedFloat32Array:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(canvas.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)

    var compute := SaCompute.new("dab")
    compute.set_texture(0, canvas.rid)
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    compute.set_texture(SaSelection.BINDING, selection.rid)
    var mask := SaBrushTipMask.load_image("")
    compute.set_buffer(StateBrushScript.SOFTNESS_BINDING, mask.softness_for(tip).rid)
    compute.set_sampled_texture(StateBrushScript.TIP_IMAGE_BINDING, mask.sampler_rid())
    compute.set_sampled_texture(StateBrushScript.PATTERN_BINDING, SaBrushTipMask.stand_in().rid)
    compute.set_buffer(SaStampBindings.MASKING_BINDING, SaStampBindings.of(mask).masking_for(masking, tip.diameter, info).rid)
    SaSmudgeReservoir.bind(compute, null)
    compute.set_texture(StateBrushScript.HEIGHT_BINDING, SaStrokeHeights.held(null).rid)
    compute.set_sampled_texture(SaStampBindings.RAMP_BINDING, SaBrushTipMask.stand_in().rid)

    compute.set_push_constant_float_array(
        SaDabPacking.pack_dab_params(
            CENTRE,
            Vector2.ZERO,
            Color(1, 1, 1, 1),
            tip.half_extent(),
            0.0,
            tip.effective_fade(),
            1.0,
            SaDabGeometry.PaintMode.OVER,
            false,
            tip
        )
    )
    compute.dispatch_kernel("dab", GROUPS, GROUPS, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas.rid, 0)
    var out := PackedFloat32Array()
    out.resize(SIDE * SIDE)
    for i in SIDE * SIDE:
        out[i] = data.decode_float(i * 16 + 12)
    return out


## Krita's masking composite of *mask* over the dab's *dab*, one line per op
## as `KisMaskingBrushCompositeOp.h` writes it for a float alpha.
static func _krita(op: SaMaskingBrush.Op, mask: float, dab: float) -> float:
    match op:
        SaMaskingBrush.Op.SUBTRACT:
            return clampf(dab - mask, 0.0, 1.0)
        SaMaskingBrush.Op.DARKEN:
            return minf(mask, dab)
        SaMaskingBrush.Op.BURN:
            if mask == 0.0:
                return 1.0 if dab == 1.0 else 0.0
            return 1.0 - clampf((1.0 - dab) / mask, 0.0, 1.0)
        SaMaskingBrush.Op.OVERLAY:
            if dab > 0.5:
                var lifted := 2.0 * dab - 1.0
                return lifted + mask - lifted * mask
            return clampf(2.0 * dab * mask, 0.0, 1.0)
        _:
            return mask * dab


## The largest disagreement over the texture between the masked dab and the
## formula, and how many texels exercised each side of the formula, so a
## passing test cannot be one whose shapes never reached a branch.
func _worst(op: SaMaskingBrush.Op, strength: float = 1.0, info: SaStrokeInfo = null) -> Dictionary:
    var tip := _tip(DAB_HALF, DAB_FADE)
    var block := _masking(op)
    if info != null:
        block.strength_option.enabled = true
        block.strength_option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    var dab_alone := _paint(tip)
    var mask_alone := _paint(block.shaped_tip(tip.diameter))
    var masked := _paint(tip, block, info)
    var worst := 0.0
    var bare := 0
    var high := 0
    var low := 0
    for i in SIDE * SIDE:
        var dab := dab_alone[i]
        var mask := mask_alone[i]
        var expected := lerpf(dab, _krita(op, mask, dab), strength)
        worst = maxf(worst, absf(masked[i] - expected))
        if dab > 0.0 and mask == 0.0:
            bare += 1
        if mask > 0.0 and dab > 0.5:
            high += 1
        if mask > 0.0 and dab > 0.0 and dab <= 0.5:
            low += 1
    return {"worst": worst, "bare": bare, "high": high, "low": low}


func _assert_op(op: SaMaskingBrush.Op, name: String) -> void:
    var found := _worst(op)
    assert_true(found["bare"] > 0, "%s: some dab texels have no mask over them" % name)
    assert_true(found["high"] > 0, "%s: some masked texels are over half" % name)
    assert_true(found["low"] > 0, "%s: and some are under it" % name)
    assert_true(found["worst"] < 1e-3, "%s matches Krita's formula to %.6f over 4096 texels" % [name, found["worst"]])


func test_subtract_cuts_the_mask_out_of_the_dab() -> void:
    _assert_op(SaMaskingBrush.Op.SUBTRACT, "subtract")


func test_darken_keeps_the_lower_of_the_two() -> void:
    _assert_op(SaMaskingBrush.Op.DARKEN, "darken")


func test_burn_eats_the_dab_where_the_mask_thins() -> void:
    _assert_op(SaMaskingBrush.Op.BURN, "burn")


func test_overlay_lifts_above_half_and_lowers_below() -> void:
    _assert_op(SaMaskingBrush.Op.OVERLAY, "overlay")


func test_multiply_is_still_the_product() -> void:
    _assert_op(SaMaskingBrush.Op.MULTIPLY, "multiply")


## The ops part from one another where the mask is nought, which is the point of
## carrying them: a subtract mask leaves the dab there and a multiply one takes
## it away. Read at one texel so the difference is a sentence and not a number.
func test_outside_the_mask_subtract_keeps_the_dab_and_multiply_takes_it() -> void:
    var tip := _tip(DAB_HALF, DAB_FADE)
    var dab_alone := _paint(tip)
    var subtract := _paint(tip, _masking(SaMaskingBrush.Op.SUBTRACT))
    var multiply := _paint(tip, _masking(SaMaskingBrush.Op.MULTIPLY))
    var ring := 12 * SIDE + 32
    assert_true(dab_alone[ring] > 0.05, "the texel is inside the dab, %.4f" % dab_alone[ring])
    assert_almost_eq(subtract[ring], dab_alone[ring], 1e-3, "subtract leaves it")
    assert_almost_eq(multiply[ring], 0.0, 1e-3, "multiply takes it")


## The mask's strength fades from the dab to the op's answer for every op, which
## for multiply is the old line and for the rest is the one promise the slot
## made: nought is the dab untouched.
func test_the_strength_fades_from_the_dab_to_the_composite() -> void:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 1)
    info.pressure = 0.5
    for op: SaMaskingBrush.Op in [SaMaskingBrush.Op.SUBTRACT, SaMaskingBrush.Op.OVERLAY, SaMaskingBrush.Op.MULTIPLY]:
        var found := _worst(op, 0.5, info)
        assert_true(found["worst"] < 1e-3, "op %d at half strength is halfway, off by %.6f" % [op, found["worst"]])


func test_the_op_travels_in_its_slot() -> void:
    var tip_mask := SaStampBindings.of(SaBrushTipMask.load_image(""))
    tip_mask.masking_for(_masking(SaMaskingBrush.Op.BURN), 48.0)
    assert_almost_eq(tip_mask.masking_values[SaStampBindings.MASK_OP], 3.0, 0.0, "burn is 3 at the op slot")
    tip_mask.masking_for(null, 48.0)
    assert_almost_eq(tip_mask.masking_values[SaStampBindings.MASK_OP], 0.0, 0.0, "and no mask is multiply")
