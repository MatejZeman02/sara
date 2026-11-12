## F75: raising Sharpness must not change the size the brush paints.
##
## `s7-drive-stamp-engine` measured one dab of a 129.6 pixel tip at four
## sharpnesses and read 124, 90, 110 and 128 pixels of ink, while the Size row
## never moved. This suite is the same claim as texels rather than as a
## screenshot, for the reason `stamp-brush/tests/test_dab_shader.gd` gives at the
## top of itself: a picture of a stroke cannot tell 0.98 coverage from 1.0.
##
## **The size is the half-coverage width**, the run of texels along the row
## through the dab's centre whose alpha is at least a half. That is the contour
## an antialiased edge means by an edge, it is what a painter reads off a
## screenshot with a ruler, and it is the one width that has a fixed answer: the
## outermost ink and the innermost solid core both move under any binarising,
## because moving them is what binarising is.
extends "res://tests/test_framework.gd"

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const DabPacking = preload("res://core/api/dab/sa_dab_packing.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const SIDE: int = 64
const GROUPS: int = 8
const CENTRE := Vector2(32.0, 32.0)

## The four the filing measured, so the record and the suite name the same
## numbers.
const SHARPNESSES: Array = [0.0, 0.35, 0.70, 1.0]


func _tip(half_extent: Vector2, fade: Vector2) -> Resource:
    var tip := SaBrushTipScript.new()
    tip.diameter = half_extent.x * 2.0
    tip.ratio = half_extent.y / half_extent.x
    tip.horizontal_fade = fade.x
    tip.vertical_fade = fade.y
    tip.antialias_edges = true
    return tip


## One dab into a cleared texture, read back as an alpha per texel. The same
## dispatch `test_dab_shader.gd` makes, kept here rather than shared because
## that file is the stamp-brush module's and this suite is the skeleton's.
func _paint(tip: Resource, sharpness: float, sharpness_soft: float = 0.0) -> PackedFloat32Array:
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
    compute.set_buffer(SaStampBindings.MASKING_BINDING, SaStampBindings.of(mask).masking_for(null, tip.diameter).rid)
    SaSmudgeReservoir.bind(compute, null)
    compute.set_texture(StateBrushScript.HEIGHT_BINDING, SaStrokeHeights.held(null).rid)
    compute.set_sampled_texture(SaStampBindings.RAMP_BINDING, SaBrushTipMask.stand_in().rid)
    compute.set_push_constant_float_array(
        DabPacking.pack_dab_params(
            CENTRE,
            Vector2.ZERO,
            Color(1, 1, 1, 1),
            tip.half_extent(),
            0.0,
            tip.effective_fade(),
            1.0,
            SaDabGeometry.PaintMode.OVER,
            false,
            tip,
            sharpness,
            sharpness_soft,
            0.0
        )
    )
    compute.dispatch_kernel("dab", GROUPS, GROUPS, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas.rid, 0)
    var out := PackedFloat32Array()
    out.resize(SIDE * SIDE)
    for i in SIDE * SIDE:
        out[i] = data.decode_float(i * 16 + 12)
    return out


## Texels of the centre row at or above *floor*, which is a width in pixels.
func _width(alpha: PackedFloat32Array, floor_value: float) -> int:
    var row := int(CENTRE.y)
    var count := 0
    for x in SIDE:
        if alpha[row * SIDE + x] >= floor_value:
            count += 1
    return count


## One tip, four sharpnesses, one painted width.
func test_sharpness_binarises_the_dab_without_resizing_it() -> void:
    var tip := _tip(Vector2(12.0, 12.0), Vector2(0.4, 0.4))
    var widths: Array = []
    for sharpness: float in SHARPNESSES:
        widths.append(_width(_paint(tip, sharpness), 0.5))
    for index in SHARPNESSES.size():
        assert_eq(
            widths[index],
            widths[0],
            "Sharpness %.2f paints %d pixels across where sharpness 0 paints %d" % [SHARPNESSES[index], widths[index], widths[0]]
        )


## The width it keeps is the tip's own, not merely constant. A kernel that painted
## nothing at every sharpness would pass the test above.
##
## **It is the unsharpened dab's width and not the Size row's**, which is a
## distinction this suite had to make before it could assert anything. The Size
## row is the tip's support, the radius outside which every generator returns
## nothing, and a soft tip's half-coverage ring is well inside it: this one is 19
## pixels of its 24, because a fade of 0.4 puts the coverage through a half long
## before the rim. Hardness is what moves that ring, and sharpness is what must
## not.
func test_the_width_it_keeps_is_the_unsharpened_dab_s() -> void:
    var tip := _tip(Vector2(12.0, 12.0), Vector2(0.4, 0.4))
    var wanted := _width(_paint(tip, 0.0), 0.5)
    var support := int(round(tip.half_extent().x * 2.0))
    assert_true(wanted > 0 and wanted < support, "A tip faded to 0.4 is %d wide inside its %d of support" % [wanted, support])
    for sharpness: float in SHARPNESSES:
        assert_eq(_width(_paint(tip, sharpness), 0.5), wanted, "and sharpness %.2f paints that width" % sharpness)

    # A tip with a different fade has a different width, which is what says the
    # reference is the tip's own falloff rather than a number this kernel keeps
    # somewhere. The direction is the fade's business and not this test's: 0.05
    # reads 17 against 0.4's 19, and which way that goes is the generator's
    # arithmetic rather than anything sharpness touches.
    var other_tip := _tip(Vector2(12.0, 12.0), Vector2(0.05, 0.05))
    var other := _width(_paint(other_tip, 0.0), 0.5)
    assert_true(other != wanted, "A tip faded to 0.05 is %d wide against the 0.4 tip's %d" % [other, wanted])
    for sharpness: float in SHARPNESSES:
        assert_eq(_width(_paint(other_tip, sharpness), 0.5), other, "and it keeps its own width at sharpness %.2f" % sharpness)


## Binarising is still binarising. The ink and the solid core converge on the
## half-coverage contour from either side, which is the behaviour the size rule
## above constrains rather than removes.
func test_the_ink_and_the_core_converge_on_the_width_that_stays() -> void:
    var tip := _tip(Vector2(12.0, 12.0), Vector2(0.4, 0.4))
    var soft := _paint(tip, 0.0)
    var pen := _paint(tip, 1.0)
    var kept := _width(soft, 0.5)

    assert_true(_width(soft, 1e-4) > kept, "An unsharpened dab has a skirt outside its half-coverage width")
    assert_true(_width(soft, 1.0 - 1e-4) < kept, "and a solid core inside it")
    assert_eq(_width(pen, 1e-4), kept, "A pen's ink is exactly that width")
    assert_eq(_width(pen, 1.0 - 1e-4), kept, "and so is its solid core, because there is nothing partial left")
