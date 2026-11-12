## Oil Smudge dragged from paint over an empty layer area thins
## out as the paint it carries thins.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The painter dragged Oil Smudge off a dark disc over an empty, transparent
## part of the layer and it laid the brush's colour at full alpha to the end of
## the drag. The dab's alpha was its own, the coverage times the flow, and over
## an empty texel nothing else stood between it and full opacity. The carry now
## holds a load at `SaSmudgeReservoir.LOAD`, how much paint it has, which the
## pickup keeps at one over paint and decays by the smear length off it, and
## the dab scales its alpha by the load over an empty texel and by exactly one
## over an opaque one.
##
## The dab kernel is dispatched over a real texture and read back, the way
## `test_flow_builds.gd` reads it, with a carry written by hand, so the number
## read is the rule alone. The pickup's half is read off a carry the way
## `test_smudge_stage.gd` reads one. The stroke through the door is the
## scenario of the same name under `scenarios/`.
extends "res://tests/test_framework.gd"

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const DabPacking = preload("res://core/api/dab/sa_dab_packing.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const SIDE: int = 64
## The workgroups one dispatch of the whole texture needs, at the kernel's
## eight by eight.
const GROUPS: int = 8
const CENTRE := Vector2(32.0, 32.0)
## Oil Smudge's flow as it ships.
const FLOW: float = 0.9

## The pickup's snapshot, and where its dab sits on it.
const SNAPSHOT := Vector2i(16, 16)
const PICK_CENTRE := Vector2(8.0, 8.0)

const NOTHING := Color(0.0, 0.0, 0.0, 0.0)
const PAINT := Color(0.2, 0.15, 0.3, 1.0)
const INK := Color(0.95, 0.93, 0.9, 1.0)


## A hard round tip, so the centre texel's coverage is exactly one and the
## alpha read there is the flow and the load alone.
func _tip() -> Resource:
    var tip := SaBrushTipScript.new()
    tip.diameter = 20.0
    tip.ratio = 1.0
    tip.horizontal_fade = 1.0
    tip.vertical_fade = 1.0
    tip.antialias_edges = true
    return tip


## A carry of *size* whose load is *amount*, or the stand-in when *size* is one
## texel, with nothing in its colour, so the dab lays the brush's own colour
## and only the alpha can move.
func _carry(amount: float, size: Vector2i = SaSmudgeReservoir.SIZE) -> SaTexture:
    var carry := SaTexture.new(size)
    carry.clear(NOTHING)
    if size.x > SaSmudgeReservoir.LOAD:
        var texels := PackedFloat32Array()
        texels.resize(size.x * size.y * 4)
        texels[SaSmudgeReservoir.LOAD * 4] = amount
        GlobalShaderCompiler.get_rd().texture_update(carry.rid, 0, texels.to_byte_array())
    return carry


## One dab of the brush's own colour at *flow* onto a canvas cleared to
## *ground*, reading *carry*, read back as the four channels of every texel.
func _stamp(carry: SaTexture, ground: Color, flow: float = FLOW) -> PackedFloat32Array:
    var tip := _tip()
    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    canvas.clear(ground)

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
    compute.set_texture(SaSmudgeReservoir.BINDING, carry.rid)
    compute.set_texture(StateBrushScript.HEIGHT_BINDING, SaStrokeHeights.held(null).rid)
    compute.set_sampled_texture(SaStampBindings.RAMP_BINDING, SaBrushTipMask.stand_in().rid)
    compute.set_push_constant_float_array(
        DabPacking.pack_dab_params(
            CENTRE,
            Vector2.ZERO,
            INK,
            tip.half_extent(),
            0.0,
            tip.effective_fade(),
            flow,
            SaDabGeometry.PaintMode.OVER,
            false,
            tip,
            0.0,
            0.0,
            0.0
        )
    )
    compute.dispatch_kernel("dab", GROUPS, GROUPS, 1)
    return rd.texture_get_data(canvas.rid, 0).to_float32_array()


## The alpha of the centre texel, whose coverage is one.
static func _centre_alpha(texels: PackedFloat32Array) -> float:
    return texels[(int(CENTRE.y) * SIDE + int(CENTRE.x)) * 4 + 3]


## One pickup of *snapshot* into *carry*, as `test_smudge_stage.gd` dispatches
## it, at Oil Smudge's pickup, length and colour rate. *mode* nought smears and
## one dulls.
func _pick(snapshot: SaTexture, carry: SaTexture, first: bool, mode: int = 0) -> void:
    var compute := SaCompute.new("smudge_pickup")
    var variance := SaCompute.Buffer.new(PackedFloat32Array([0.0]).to_byte_array())
    compute.use_storage_format(snapshot.format)
    compute.set_texture(0, snapshot.rid)
    compute.set_texture(1, carry.rid)
    compute.set_buffer(SaSmudgeReservoir.BUFFER_BINDING, variance.rid)
    var exchange := SaCompute.Buffer.new(PackedInt32Array([0, 0]).to_byte_array())
    compute.set_buffer(SaSmudgeReservoir.EXCHANGE_BINDING, exchange.rid)
    compute.set_push_constant_float_array(
        PackedFloat32Array([PICK_CENTRE.x, PICK_CENTRE.y, 4.0, 0.6, 0.75, 0.5, 1.0 if first else 0.0, float(mode)])
    )
    compute.dispatch_kernel("smudge_pickup", 1, 1, 1)


## The carry's load, which the dab reads in red.
func _load(carry: SaTexture) -> float:
    return GlobalShaderCompiler.get_rd().texture_get_data(carry.rid, 0).to_float32_array()[SaSmudgeReservoir.LOAD * 4]


func _snapshot(colour: Color) -> SaTexture:
    var texture := SaTexture.new(SNAPSHOT)
    texture.clear(colour)
    return texture


# --- The dab ------------------------------------------------------------------


## Over an empty chunk the alpha laid is the carry's load
## times the flow.
func test_over_an_empty_texel_the_dab_lays_the_load_times_the_flow() -> void:
    for amount: float in [1.0, 0.75, 0.5, 0.1]:
        var alpha := _centre_alpha(_stamp(_carry(amount), NOTHING))
        assert_almost_eq(alpha, amount * FLOW, 1e-5, "A carry at a load of %.2f lays %.3f" % [amount, amount * FLOW])


## And at nothing for a carry of nothing, anywhere on the canvas.
func test_a_carry_of_nothing_lays_nothing_on_an_empty_layer() -> void:
    var texels := _stamp(_carry(0.0), NOTHING)
    var most := 0.0
    for i in range(3, texels.size(), 4):
        most = maxf(most, texels[i])
    assert_almost_eq(most, 0.0, 1e-7, "No texel takes any alpha from a carry with no paint in it")


## A smudge over paint lays what it laid before the unit, to the bit: over an
## opaque texel the load scales the alpha by exactly one, whatever it is.
func test_over_opaque_paint_the_load_changes_nothing() -> void:
    var before := _stamp(_carry(0.0, Vector2i.ONE), PAINT)
    for amount: float in [0.0, 0.3, 1.0]:
        var after := _stamp(_carry(amount), PAINT)
        assert_eq(after, before, "A carry at a load of %.2f lays over paint what the stand-in laid" % amount)


## A full load is no thinning at all, over an empty texel or a half painted
## one, so a smudge whose pickup reads the ground as paint lays as it did.
func test_a_full_load_lays_what_the_stand_in_laid() -> void:
    for ground: Color in [NOTHING, Color(PAINT, 0.4)]:
        assert_eq(_stamp(_carry(1.0), ground), _stamp(_carry(0.0, Vector2i.ONE), ground), "A full load thins nothing")


## A carry too narrow for the load, as a suite's two texel one was, lays as the
## dab did before the load.
func test_a_two_texel_carry_lays_as_it_did() -> void:
    assert_eq(
        _stamp(_carry(0.0, Vector2i(2, 1)), NOTHING),
        _stamp(_carry(0.0, Vector2i.ONE), NOTHING),
        "A carry with no load texel lays the dab's own alpha"
    )


# --- The pickup ---------------------------------------------------------------


## The load is exactly one over paint, though the strength the colour is mixed
## by is not, and the smear length decays it once the dab leaves the paint, so
## the fall is the length's own.
func test_the_load_is_full_over_paint_and_falls_by_the_length_off_it() -> void:
    var carry := SaTexture.new(SaSmudgeReservoir.SIZE)
    carry.clear(NOTHING)
    var paint := _snapshot(PAINT)
    _pick(paint, carry, true)
    for _dab in range(4):
        _pick(paint, carry, false)
    assert_eq(_load(carry), 1.0, "The load is one, exactly, while the dab is over paint")

    var bare := _snapshot(NOTHING)
    var expected := 1.0
    for dab in range(6):
        _pick(bare, carry, false)
        expected *= 0.75
        assert_almost_eq(_load(carry), expected, 1e-6, "and the length leaves %.4f of it %d dabs off it" % [expected, dab + 1])


## A stroke begun over nothing starts with a full load, the brush's own colour
## it was dipped in, and runs out by the length as a drag off paint does.
func test_a_stroke_begun_over_nothing_lays_its_own_paint_and_runs_out() -> void:
    var carry := SaTexture.new(SaSmudgeReservoir.SIZE)
    carry.clear(NOTHING)
    var bare := _snapshot(NOTHING)
    _pick(bare, carry, true)
    assert_eq(_load(carry), 1.0, "The first dab over nothing starts the load full")
    _pick(bare, carry, false)
    _pick(bare, carry, false)
    assert_almost_eq(_load(carry), 0.5625, 1e-6, "and two dabs on it holds the length squared")


## Dulling lays what stands where it is rather than a carry that runs out, so
## its load stays full over paint. Over nothing it is nought, so a dulling or
## blurring brush lays no blot of the swatch on an empty layer.
func test_a_dulling_dab_keeps_a_full_load() -> void:
    var carry := SaTexture.new(SaSmudgeReservoir.SIZE)
    carry.clear(NOTHING)
    var painted := _snapshot(PAINT)
    _pick(painted, carry, true, 1)
    for _dab in range(3):
        _pick(painted, carry, false, 1)
    assert_eq(_load(carry), 1.0, "A dulling dab over paint keeps the load at one")
    _pick(_snapshot(NOTHING), carry, false, 1)
    assert_eq(_load(carry), 0.0, "and one over nothing holds none, so it lays nothing there")
