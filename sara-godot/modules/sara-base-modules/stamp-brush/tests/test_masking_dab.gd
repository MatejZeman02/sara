## The masking brush multiplying the dab, dispatched over a real texture and
## read back.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The claim is a product, so every assertion here is one.** The mask is a
## second shape whose coverage scales the coverage the first one laid down, so
## the dab is painted alone, the mask's own tip is painted alone as an ordinary
## dab, and the masked dab is compared against the two multiplied together. A
## screenshot cannot tell 0.98 from 1.0 and neither can a bounding box, which is
## why this suite reads texels the way `test_dab_shader.gd` does.
##
## **Every dab here is large enough that the kernel takes one sample per texel.**
## `sa_supersample_side` goes to nine samples under five pixels of half-extent,
## and the mask is evaluated once per texel whatever the dab does, so a small dab
## and a small mask would be compared against a product of two differently
## sampled shapes and the assertions would be about the sampling rather than
## about the multiply. The one test that is about that difference says so.
extends "res://tests/test_framework.gd"

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const SIDE: int = 64
const GROUPS: int = 8
const CENTRE := Vector2(32.0, 32.0)

## The painted tip's half-extent, and the one number every other in this suite
## is chosen around: twenty pixels is one sample per texel and leaves room for a
## mask twice its size inside a sixty-four pixel texture.
const DAB_HALF: float = 20.0

## Nine texels spread over the dab, which is where the product is
## checked. Four of them are inside a mask of size 0.6, four are between
## the two outlines and one is the centre, so a product that was really a sum or
## a maximum fails at more than one of them.
const NINE: Array = [
    Vector2i(32, 32),
    Vector2i(26, 32),
    Vector2i(38, 32),
    Vector2i(32, 26),
    Vector2i(32, 38),
    Vector2i(18, 32),
    Vector2i(46, 32),
    Vector2i(32, 18),
    Vector2i(24, 24),
]


## A round tip of *half* pixels, hard-edged unless a test asks otherwise.
func _tip(half: float = DAB_HALF, fade: float = 1.0) -> Resource:
    var tip := SaBrushTipScript.new()
    tip.diameter = half * 2.0
    tip.horizontal_fade = fade
    tip.vertical_fade = fade
    return tip


## A masking block, off unless *enabled*, carrying a second tip of its own.
func _masking(enabled: bool, size: float = 0.6, shape: int = SaBrushTipScript.Shape.RECTANGLE) -> SaMaskingBrush:
    var block := SaMaskingBrush.new()
    block.enabled = enabled
    block.size = size
    block.tip = SaBrushTipScript.new()
    block.tip.shape = shape
    block.tip.horizontal_fade = 1.0
    block.tip.vertical_fade = 1.0
    return block


## One dab into a cleared 64 by 64 texture, read back as an alpha per texel.
##
## The whole texture is dispatched rather than the dab's own box, for the reason
## `test_dab_shader.gd` gives: this suite is about what the kernel computes, and
## which rectangle it was computed over is asserted separately and by the box
## arithmetic's own suite.
##
## *info* is the sample the mask's own options read, and *centre* where the dab
## lands, which is how a test paints the mask's tip alone where its scatter put
## it.
func _paint(
    tip: Resource, masking: Resource = null, radians: float = 0.0, info: SaStrokeInfo = null, centre: Vector2 = CENTRE
) -> PackedFloat32Array:
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
            centre,
            Vector2.ZERO,
            Color(1, 1, 1, 1),
            tip.half_extent(),
            radians,
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


static func _at(alpha: PackedFloat32Array, x: int, y: int) -> float:
    if x < 0 or y < 0 or x >= SIDE or y >= SIDE:
        return 0.0
    return alpha[y * SIDE + x]


## The mask's second tip as the kernel is handed it, which is what makes it
## paintable on its own: the block's size is a multiple of the dab's diameter,
## so the tip only has a size at all once a dab is named.
func _mask_tip_alone(block: SaMaskingBrush, dab_diameter: float) -> Resource:
    return block.shaped_tip(dab_diameter)


# --- The product --------------------------------------------------------------


func test_the_masked_dab_is_the_two_coverages_multiplied() -> void:
    var tip := _tip()
    var block := _masking(true)
    var dab_alone := _paint(tip)
    var mask_alone := _paint(_mask_tip_alone(block, tip.diameter))
    var masked := _paint(tip, block)

    for point: Vector2i in NINE:
        var expected := _at(dab_alone, point.x, point.y) * _at(mask_alone, point.x, point.y)
        assert_almost_eq(
            _at(masked, point.x, point.y),
            expected,
            1e-3,
            (
                "At %d,%d the masked dab is the product, %.4f against %.4f by %.4f"
                % [
                    point.x,
                    point.y,
                    _at(masked, point.x, point.y),
                    _at(dab_alone, point.x, point.y),
                    _at(mask_alone, point.x, point.y)
                ]
            )
        )


func test_the_product_holds_over_the_whole_dab_and_not_only_at_nine_texels() -> void:
    var tip := _tip()
    var block := _masking(true)
    var dab_alone := _paint(tip)
    var mask_alone := _paint(_mask_tip_alone(block, tip.diameter))
    var masked := _paint(tip, block)

    var worst := 0.0
    for i in SIDE * SIDE:
        worst = maxf(worst, absf(masked[i] - dab_alone[i] * mask_alone[i]))
    assert_true(worst < 1e-3, "The largest disagreement over 4096 texels is %.6f" % worst)


func test_a_mask_smaller_than_the_dab_takes_the_dab_away_outside_itself() -> void:
    var tip := _tip()
    var block := _masking(true, 0.4)
    var dab_alone := _paint(tip)
    var masked := _paint(tip, block)

    # Sixteen pixels out on the x axis: inside a forty pixel dab and outside a
    # sixteen pixel mask, so the dab painted there and the masked dab does not.
    assert_true(_at(dab_alone, 32 + 16, 32) > 0.9, "The dab alone paints sixteen pixels out")
    assert_almost_eq(_at(masked, 32 + 16, 32), 0.0, 1e-4, "and the mask has taken it away")
    assert_true(_at(masked, 32, 32) > 0.9, "while the centre, which is inside both, is still painted")


func test_a_mask_larger_than_the_dab_paints_nothing_outside_the_dabs_own_box() -> void:
    var tip := _tip()
    var block := _masking(true, 2.0)
    var masked := _paint(tip, block)

    # The whole texture was dispatched, so anything outside the dab's own box
    # would be visible here. This is the claim that lets the dirty rectangle stay
    # the painted tip's own: a mask can only ever take texels away.
    var reach := int(ceil(DAB_HALF + SaDabGeometry.ANTIALIAS_MARGIN))
    for y in SIDE:
        for x in SIDE:
            if absf(float(x) - CENTRE.x) <= float(reach) and absf(float(y) - CENTRE.y) <= float(reach):
                continue
            if _at(masked, x, y) > 0.0:
                assert_true(false, "A mask twice the dab's size painted at %d,%d, outside the dab's box" % [x, y])
                return
    assert_true(true, "A mask twice the dab's size paints nothing the dab would not have painted")


# --- The mask switched off ----------------------------------------------------


func test_a_mask_switched_off_writes_exactly_what_the_dab_wrote_before() -> void:
    var tip := _tip(DAB_HALF, 0.5)
    var before := _paint(tip)
    var with_block_off := _paint(tip, _masking(false))

    for i in SIDE * SIDE:
        if before[i] != with_block_off[i]:
            # The row a flat index is on, which is what makes a failure readable.
            @warning_ignore("integer_division")
            var y := i / SIDE
            assert_true(false, "A block that is off moved texel %d,%d" % [i % SIDE, y])
            return
    assert_true(true, "A masking block that is off is the dab exactly as it was, texel for texel")


func test_a_block_with_no_second_tip_is_off_rather_than_a_crash() -> void:
    var tip := _tip()
    var block := _masking(true)
    block.tip = null
    var before := _paint(tip)
    var with_no_tip := _paint(tip, block)

    assert_false(block.active(), "A block with no tip has nothing to say")
    assert_almost_eq(_at(with_no_tip, 32, 32), _at(before, 32, 32), 1e-4, "so the dab is the dab")


# --- The second tip is its own ------------------------------------------------


func test_the_mask_reads_its_own_falloff_curve_and_not_the_painted_tips() -> void:
    # The painted tip is hard and the mask is soft, so anything the mask does to
    # the dab comes out of the mask's own table. A shared table would make the
    # masked dab the hard tip squared, which is the hard tip.
    var tip := _tip()
    var block := _masking(true, 0.6, SaBrushTipScript.Shape.CIRCLE)
    block.tip.generator = SaDabGeometry.Generator.SOFT
    block.tip.softness = 1.0
    var dab_alone := _paint(tip)
    var masked := _paint(tip, block)

    # Half way out along the mask's own radius, a soft falloff is a fraction and
    # a hard one is not, so the two disagree here or the mask read the wrong
    # table.
    var half_way := 32 + int(DAB_HALF * 0.6 * 0.5)
    var covered := _at(masked, half_way, 32)
    assert_true(_at(dab_alone, half_way, 32) > 0.99, "The painted tip alone is solid half way out")
    assert_true(covered > 0.0, "The soft mask leaves something there, at %.4f" % covered)
    assert_true(covered < 0.99, "and it is a fraction rather than the hard tip, at %.4f" % covered)


func test_the_masks_angle_is_its_own_and_does_not_follow_the_dab() -> void:
    var tip := _tip()
    var block := _masking(true, 0.5)
    var upright := _paint(tip, block)
    var dab_turned := _paint(tip, block, PI / 4.0)

    # The painted tip is a circle, so turning the dab changes nothing about it,
    # and the mask is a square whose own angle nobody moved. A mask that followed
    # the dab would have turned the square and moved these corners.
    var corner := int(DAB_HALF * 0.5 * 0.7)
    assert_almost_eq(
        _at(dab_turned, 32 + corner, 32 + corner),
        _at(upright, 32 + corner, 32 + corner),
        1e-4,
        "Turning the dab leaves the mask where it was"
    )


func test_the_mask_turns_when_its_own_tip_is_turned() -> void:
    var tip := _tip()
    var upright := _masking(true, 0.5)
    var turned := _masking(true, 0.5)
    turned.tip.angle = PI / 4.0

    var square := _paint(tip, upright)
    var diamond := _paint(tip, turned)

    # The corner of an upright square, which a square turned by forty-five
    # degrees does not reach.
    var corner := int(DAB_HALF * 0.5 * 0.8)
    assert_true(_at(square, 32 + corner, 32 + corner) > 0.5, "The upright mask covers its own corner")
    assert_almost_eq(_at(diamond, 32 + corner, 32 + corner), 0.0, 1e-4, "and the turned one does not")


## The mask's own rotation option, reading the pen's tilt, turns
## the square the kernel reads back, and the texels are those of a mask whose
## tip was turned by hand to the angle the option answered.
func test_a_mask_turns_with_the_pen_in_the_texels() -> void:
    var tip := _tip()
    var block := _masking(true, 0.5)
    block.rotation_option.enabled = true
    block.rotation_option.set_sensor(SaSensor.create(SaSensor.Id.TILT_DIRECTION, true))
    var east := _pen(Vector2(0.5, 0.0))
    # An eighth of a turn apart rather than a quarter, because a square turned
    # by a quarter is the same square.
    var south := _pen(Vector2(0.5, 0.5))
    var turned_east := block.dab_for(tip.diameter, east).rotation
    var turned_south := block.dab_for(tip.diameter, south).rotation
    assert_true(
        absf(turned_east - turned_south) > 0.1, "two pen angles are two mask angles, %.3f and %.3f" % [turned_east, turned_south]
    )

    for pair: Array in [[east, turned_east], [south, turned_south]]:
        var by_pen := _paint(tip, block, 0.0, pair[0])
        var by_hand := _masking(true, 0.5)
        by_hand.tip.angle = float(pair[1])
        var expected := _paint(tip, by_hand)
        var worst := 0.0
        for i in SIDE * SIDE:
            worst = maxf(worst, absf(by_pen[i] - expected[i]))
        assert_true(worst < 1e-3, "the pen's mask is the hand-turned one at %.3f, worst %.6f" % [float(pair[1]), worst])

    var east_texels := _paint(tip, block, 0.0, east)
    var south_texels := _paint(tip, block, 0.0, south)
    var differ := 0
    for i in SIDE * SIDE:
        if absf(east_texels[i] - south_texels[i]) > 0.1:
            differ += 1
    assert_true(differ > 20, "and the two pen angles paint two different masks, %d texels apart" % differ)


## The mask's own scatter moves its centre and the kernel reads the product at
## the moved centre: the masked dab is the dab times the mask's tip painted
## alone where the offset put it.
func test_a_scattered_mask_is_the_product_at_its_moved_centre() -> void:
    var tip := _tip()
    var block := _masking(true, 0.5)
    block.scatter_option.enabled = true
    block.scatter_option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    var info := _pen(Vector2.ZERO, 0.8)
    var mask := SaStampBindings.of(SaBrushTipMask.load_image(""))
    mask.masking_for(block, tip.diameter, _pen(Vector2.ZERO, 0.8))
    var offset := Vector2(mask.masking_values[SaStampBindings.MASK_OFFSET_X], mask.masking_values[SaStampBindings.MASK_OFFSET_Y])
    assert_true(offset.length() > 1.0, "the mask moved, by %s" % offset)

    var dab_alone := _paint(tip)
    var mask_alone := _paint(block.shaped_tip(tip.diameter), null, 0.0, null, CENTRE + offset)
    var masked := _paint(tip, block, 0.0, info)
    var worst := 0.0
    for i in SIDE * SIDE:
        worst = maxf(worst, absf(masked[i] - dab_alone[i] * mask_alone[i]))
    assert_true(worst < 1e-3, "the product holds at the moved centre, worst %.6f" % worst)


## A sample of a pen tilted towards *tilt* at *pressure*, seeded, so two calls
## with the same arguments draw the same scatter.
static func _pen(tilt: Vector2, pressure: float = 1.0) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 11)
    info.pressure = pressure
    info.tilt_x = tilt.x
    info.tilt_y = tilt.y
    return info


func test_the_masks_size_follows_the_dabs_diameter() -> void:
    var block := _masking(true, 0.5)
    var small := _paint(_tip(8.0), block)
    var large := _paint(_tip(DAB_HALF), block)

    # The mask is half of whatever it masks, so its own painted radius is a
    # quarter of the dab's diameter at both sizes rather than a fixed number of
    # pixels. Four pixels out is inside the large dab's mask and outside the
    # small one's.
    assert_true(_at(large, 32 + 5, 32) > 0.5, "Half of a forty pixel dab reaches five pixels out")
    assert_almost_eq(_at(small, 32 + 5, 32), 0.0, 1e-4, "and half of a sixteen pixel one does not")


# --- The buffer ---------------------------------------------------------------


func test_the_buffer_is_updated_in_place_rather_than_rebuilt_per_dab() -> void:
    var mask := SaStampBindings.of(SaBrushTipMask.load_image(""))
    var block := _masking(true)

    var first := mask.masking_for(block, 40.0)
    var same := mask.masking_for(block, 40.0)
    var moved := mask.masking_for(block, 80.0)

    assert_true(first == same, "The same numbers answer the same buffer")
    assert_true(first == moved, "and moved numbers answer the same buffer rather than a new one")
    assert_eq(
        mask.masking_values.size(),
        SaStampBindings.MASK_HEADER + SaBrushTipScript.SOFTNESS_SAMPLES,
        "whose length is the header and one table"
    )


func test_the_whole_block_is_written_even_when_the_mask_is_off() -> void:
    var mask := SaStampBindings.of(SaBrushTipMask.load_image(""))
    mask.masking_for(_masking(true), 40.0)
    var carried: float = mask.masking_values[SaStampBindings.MASK_HALF_X]
    assert_true(carried > 0.0, "A mask that is on has a size")

    mask.masking_for(_masking(false), 40.0)

    assert_almost_eq(mask.masking_values[SaStampBindings.MASK_ACTIVE], 0.0, 1e-6, "Switching it off says so")
    assert_almost_eq(mask.masking_values[SaStampBindings.MASK_HALF_X], 0.0, 1e-6, "and blanks the size behind it")


func test_a_null_block_is_a_mask_that_is_off() -> void:
    var mask := SaStampBindings.of(SaBrushTipMask.load_image(""))

    mask.masking_for(null, 40.0)

    assert_almost_eq(mask.masking_values[SaStampBindings.MASK_ACTIVE], 0.0, 1e-6, "Null is off")
    assert_eq(
        mask.masking_values.size(),
        SaStampBindings.MASK_HEADER + SaBrushTipScript.SOFTNESS_SAMPLES,
        "at the same length, so the kernel indexes the same way either way"
    )


func test_the_block_travels_at_the_indices_the_kernel_reads() -> void:
    var mask := SaStampBindings.of(SaBrushTipMask.load_image(""))
    var block := _masking(true, 0.75)
    block.tip.ratio = 0.5
    block.tip.angle = 0.25

    mask.masking_for(block, 40.0)

    var values := mask.masking_values
    assert_almost_eq(values[SaStampBindings.MASK_ACTIVE], 1.0, 1e-6, "On")
    assert_almost_eq(values[SaStampBindings.MASK_STRENGTH], 1.0, 1e-6, "at the whole mask, until a strength row exists")
    assert_almost_eq(values[SaStampBindings.MASK_HALF_X], 15.0, 1e-4, "three quarters of a forty pixel dab, halved")
    assert_almost_eq(values[SaStampBindings.MASK_HALF_Y], 7.5, 1e-4, "and its ratio on the minor axis")
    assert_almost_eq(values[SaStampBindings.MASK_COS], cos(0.25), 1e-6, "the second tip's own angle")
    assert_almost_eq(values[SaStampBindings.MASK_SIN], sin(0.25), 1e-6, "as a cosine and a sine")
    assert_almost_eq(values[SaStampBindings.MASK_SHAPE], 1.0, 1e-6, "and the rectangle it was given")


## What the document stores travels beside the lightness row, because the kernel
## has no other way to learn it: an Oklab document's shift is one add and an RGB
## document's is a curve away from one.
##
## **Nothing predating the row may move**, which is the assertion with no
## document in it: a caller that knows of no document binds the sRGB answer, and
## the kernel's RGB branch through the sRGB curve is the maths this file's shift
## did before the mode existed.
func test_the_block_says_what_the_document_stores() -> void:
    var mask := SaStampBindings.of(SaBrushTipMask.load_image(""))

    mask.masking_for(null, 40.0)
    var values := mask.masking_values
    assert_almost_eq(
        values[SaStampBindings.MASK_TIP_LIGHTNESS_MODE], SaStampBindings.LIGHTNESS_RGB, 1e-6, "No document is an RGB document"
    )
    var srgb := SaTransferFunction.srgb().to_params()
    assert_almost_eq(values[SaStampBindings.MASK_TRANSFER_SLOPE], srgb[0], 1e-6, "on the sRGB curve,")
    assert_almost_eq(values[SaStampBindings.MASK_TRANSFER_THRESHOLD], srgb[1], 1e-6, "which is the one curve")
    assert_almost_eq(values[SaStampBindings.MASK_TRANSFER_GAIN], srgb[2], 1e-6, "every caller that predates")
    assert_almost_eq(values[SaStampBindings.MASK_TRANSFER_EXPONENT], srgb[3], 1e-6, "the row painted through")

    mask.masking_for(
        null,
        40.0,
        null,
        0.0,
        SaStampBindings.lightness_mode_for(SaColorSpace.oklab()),
        SaStampBindings.transfer_for(SaColorSpace.oklab())
    )
    assert_almost_eq(
        mask.masking_values[SaStampBindings.MASK_TIP_LIGHTNESS_MODE],
        SaStampBindings.LIGHTNESS_OKLAB,
        1e-6,
        "An Oklab document says so, and the kernel takes the add"
    )

    # A document whose curve Sara's kernel has never heard of still travels
    # whole, which is the reason the four numbers are sent rather than a name.
    var gamma22 := SaColorSpace.srgb()
    gamma22.transfer = SaTransferFunction.gamma22()
    var params := gamma22.transfer.to_params()
    mask.masking_for(null, 40.0, null, 0.0, SaStampBindings.lightness_mode_for(gamma22), SaStampBindings.transfer_for(gamma22))
    values = mask.masking_values
    assert_almost_eq(
        values[SaStampBindings.MASK_TIP_LIGHTNESS_MODE], SaStampBindings.LIGHTNESS_RGB, 1e-6, "An RGB document stays RGB"
    )
    assert_almost_eq(values[SaStampBindings.MASK_TRANSFER_EXPONENT], params[3], 1e-6, "and carries its own gamma")
    assert_true(not is_equal_approx(params[3], srgb[3]), "which is not the sRGB one, so the assertion means something")
