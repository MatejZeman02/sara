## The pattern hook, dispatched over a real texture and read back.
##
## The brush engine spec reserved binding 4 and two push-constant floats for a
## tiled mask and left the multiply for the day patterns arrived. This suite is
## that multiply asserted from the outside: a checker is bound at binding 4, one
## dab is painted across a tile boundary, and the alpha is read back through the
## same path `test_dab_dirty_rect.gd` reads, `texture_get_data` and the alpha
## channel of every texel.
##
## **The pattern's position is the whole of the risk.** A mask tiled in the dab's
## own frame travels with the dab, which is a texture painted onto the brush
## rather than onto the canvas, and no screenshot of a single dab tells the two
## apart. Every assertion below is therefore stated against the *document* texel
## rather than against the dab: the same dab painted at three centres reads the
## same tile grid, and a dab centred on a tile corner is dark in the checker's
## dark squares rather than in its own quadrants.
extends "res://tests/test_framework.gd"

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The canvas every dab is stamped into, and the workgroups that covers at the
## kernel's own `[numthreads(8, 8, 1)]`.
const SIDE: int = 64
const GROUPS: int = 8

## The pattern's own size, which is its tile size in document texels: the
## pattern resource answers a texture at its tile size and the kernel asks the
## sampler rather than a fourth push-constant float. A power of two so that a
## texel centre lands exactly on `(n + 0.5) / TILE` and the assertions below
## can be exact rather than approximate.
const TILE: int = 16

## The checker's square, half the tile, so one tile carries two dark squares and
## two light ones and a dab of this size crosses several.
const SQUARE: int = 8

## The dab: a hard circle wide enough to cover more than a whole tile, so every
## assertion sees both squares and the boundary between them.
const HALF_EXTENT := Vector2(14.0, 14.0)

## Where the dab lands, and **not a multiple of the tile or of its square**. A
## centre on the grid's own multiple is the one place a mask tiled in the dab's
## frame draws the same picture as one tiled in the document's, so a suite that
## stamped at 32 by 32 would have passed either way: the mutation that reads the
## pattern at `at - dab_center` leaves seven of the eight assertions below green
## from there and one from here.
const CENTRE := Vector2(30.0, 34.0)

## What counts as painted, the way the dirty-rect suite counts it. A texel the
## kernel wrote no coverage into is not paint.
const PAINTED: float = 1.0 / 512.0


## The checker, as an r32f texture of TILE by TILE whose texels are exactly one
## and exactly zero.
##
## Exact rather than a grey ramp on purpose: the multiply is then the identity
## or an annihilation, so `patterned == plain * factor` holds bit for bit and a
## failure is a wrong position rather than a rounding argument.
func _checker() -> SaTexture:
    var texture := SaTexture.new(Vector2i(TILE, TILE), RenderingDevice.DATA_FORMAT_R32_SFLOAT)
    var texels := PackedFloat32Array()
    texels.resize(TILE * TILE)
    for y in TILE:
        for x in TILE:
            texels[y * TILE + x] = _checker_at(x, y)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, texels.to_byte_array())
    return texture


## What the checker holds at a document texel, which is what every assertion
## compares the painted alpha against. The wrap is the tiling stated on the CPU,
## and the kernel's `fract` has to agree with it.
static func _checker_at(x: int, y: int) -> float:
    var tx := posmod(x, TILE)
    var ty := posmod(y, TILE)
    @warning_ignore("integer_division")
    var square := posmod(tx / SQUARE + ty / SQUARE, 2)
    return 1.0 if square == 0 else 0.0


## One dab into a cleared canvas, read back as an alpha per texel.
##
## The whole canvas is dispatched rather than the dab's own box, for the reason
## `test_dab_shader.gd` gives: this suite is about what the kernel computes, and
## where it is allowed to write is asserted separately below.
##
## *pattern* is the texture bound at binding 4, which is the one by one stand-in
## when the caller hands in none, exactly as the live brush binds it today.
func _paint(centre: Vector2, strength: float, offset: Vector2, pattern: SaTexture = null) -> PackedFloat32Array:
    var rgba := _paint_rgba(centre, strength, offset, pattern, Color(1, 1, 1, 1))
    var out := PackedFloat32Array()
    out.resize(SIDE * SIDE)
    for i in SIDE * SIDE:
        out[i] = rgba[i * 4 + 3]
    return out


## [method _paint] with the dab's colour said and all four channels read back,
## for the texturing modes, which are asked whether a colour over one
## comes back as itself.
func _paint_rgba(centre: Vector2, strength: float, offset: Vector2, pattern: SaTexture, colour: Color) -> PackedFloat32Array:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(canvas.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)

    var tip := SaBrushTipScript.new()
    tip.diameter = HALF_EXTENT.x * 2.0
    tip.ratio = 1.0
    tip.horizontal_fade = 1.0
    tip.vertical_fade = 1.0
    tip.antialias_edges = true

    var compute := SaCompute.new("dab")
    compute.set_texture(0, canvas.rid)
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    compute.set_texture(SaSelection.BINDING, selection.rid)
    var mask := SaBrushTipMask.load_image("")
    compute.set_buffer(StateBrushScript.SOFTNESS_BINDING, mask.softness_for(tip).rid)
    compute.set_sampled_texture(StateBrushScript.TIP_IMAGE_BINDING, mask.sampler_rid())
    var bound: RID = pattern.rid if pattern != null else SaBrushTipMask.stand_in().rid
    compute.set_sampled_texture(StateBrushScript.PATTERN_BINDING, bound)
    compute.set_buffer(SaStampBindings.MASKING_BINDING, SaStampBindings.of(mask).masking_for(null, tip.diameter).rid)
    SaSmudgeReservoir.bind(compute, null)
    compute.set_texture(StateBrushScript.HEIGHT_BINDING, SaStrokeHeights.held(null).rid)
    compute.set_sampled_texture(SaStampBindings.RAMP_BINDING, SaBrushTipMask.stand_in().rid)
    compute.set_push_constant_float_array(
        SaDabPacking.pack_dab_params(
            centre,
            Vector2.ZERO,
            colour,
            HALF_EXTENT,
            0.0,
            tip.effective_fade(),
            1.0,
            SaDabGeometry.PaintMode.OVER,
            false,
            tip,
            0.0,
            0.0,
            0.0,
            strength,
            offset
        )
    )
    compute.dispatch_kernel("dab", GROUPS, GROUPS, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas.rid, 0)
    return data.to_float32_array()


## The dab exactly as every suite before this unit packed it, with nothing said
## about a pattern at all. This is what "today's dab" means in the assertions.
func _paint_plain(centre: Vector2) -> PackedFloat32Array:
    return _paint(centre, 0.0, Vector2.ZERO)


func test_a_strength_of_zero_is_todays_dab_texel_for_texel() -> void:
    var centre := CENTRE
    var plain := _paint_plain(centre)
    var checker := _checker()
    var patterned := _paint(centre, 0.0, Vector2.ZERO, checker)
    var moved := 0
    for i in SIDE * SIDE:
        if plain[i] != patterned[i]:
            moved += 1
    assert_eq(moved, 0, "a checker bound at binding 4 with the strength at zero moves no texel of the dab")


func test_the_dab_is_dark_where_the_checker_is_dark() -> void:
    var centre := CENTRE
    var plain := _paint_plain(centre)
    var checker := _checker()
    var patterned := _paint(centre, 1.0, Vector2.ZERO, checker)
    var wrong := 0
    var worst := ""
    var dark := 0
    var light := 0
    for y in SIDE:
        for x in SIDE:
            var i := y * SIDE + x
            if plain[i] <= PAINTED:
                continue
            var expected: float = plain[i] * _checker_at(x, y)
            if _checker_at(x, y) > 0.5:
                light += 1
            else:
                dark += 1
            if absf(patterned[i] - expected) > 1e-6:
                wrong += 1
                if worst.is_empty():
                    worst = ("(%d, %d) is %.5f where the checker asks for %.5f" % [x, y, patterned[i], expected])
    assert_eq(wrong, 0, "every painted texel is the plain dab times the checker at its own document texel. %s" % worst)
    assert_true(dark > 0 and light > 0, "and the dab covered both squares, %d dark and %d light" % [dark, light])


func test_the_tile_grid_is_the_documents_rather_than_the_dabs() -> void:
    # Half a square, so a grid tied to the dab would move by four texels and a
    # grid tied to the document would not move at all.
    var checker := _checker()
    var first := _paint(CENTRE, 1.0, Vector2.ZERO, checker)
    var second := _paint(CENTRE + Vector2(4.0, 0.0), 1.0, Vector2.ZERO, checker)
    var plain := _paint_plain(CENTRE + Vector2(4.0, 0.0))
    var wrong := 0
    for y in SIDE:
        for x in SIDE:
            var i := y * SIDE + x
            if plain[i] <= PAINTED:
                continue
            if absf(second[i] - plain[i] * _checker_at(x, y)) > 1e-6:
                wrong += 1
    assert_eq(wrong, 0, "the dab moved four texels and the tile grid stayed where the canvas put it")
    var differences := 0
    for i in SIDE * SIDE:
        if absf(first[i] - second[i]) > 1e-6:
            differences += 1
    assert_true(differences > 0, "and the two dabs are not the same picture, which is what the move was for")


func test_the_offset_moves_the_grid_by_whole_texels() -> void:
    var centre := CENTRE
    var plain := _paint_plain(centre)
    var checker := _checker()
    var shifted := _paint(centre, 1.0, Vector2(float(SQUARE), 0.0), checker)
    var wrong := 0
    for y in SIDE:
        for x in SIDE:
            var i := y * SIDE + x
            if plain[i] <= PAINTED:
                continue
            if absf(shifted[i] - plain[i] * _checker_at(x + SQUARE, y)) > 1e-6:
                wrong += 1
    assert_eq(wrong, 0, "an offset of one square reads the checker one square along, which is what a tile offset means")


func test_half_the_strength_is_half_the_way_to_the_pattern() -> void:
    var centre := CENTRE
    var plain := _paint_plain(centre)
    var checker := _checker()
    var half := _paint(centre, 0.5, Vector2.ZERO, checker)
    var wrong := 0
    for y in SIDE:
        for x in SIDE:
            var i := y * SIDE + x
            if plain[i] <= PAINTED:
                continue
            # `mix(1, sampled, strength)`, which is what makes zero the dab
            # untouched and one the pattern whole.
            var factor: float = 1.0 + (_checker_at(x, y) - 1.0) * 0.5
            if absf(half[i] - plain[i] * factor) > 1e-5:
                wrong += 1
    assert_eq(wrong, 0, "half the strength leaves half the checker's cut, so the dial is a blend and not a switch")


func test_a_patterned_dab_writes_nothing_outside_its_own_box() -> void:
    # Hard rule 2 from the direction `test_dab_dirty_rect.gd` asks it: the
    # pattern is a multiply on the coverage and moves no texel of the box, so a
    # dab dispatched over the whole canvas still writes only inside it.
    var centre := CENTRE
    var checker := _checker()
    var patterned := _paint(centre, 1.0, Vector2.ZERO, checker)
    var box := SaDabGeometry.region(centre, HALF_EXTENT, 0.0)
    var outside := 0
    for y in SIDE:
        for x in SIDE:
            if patterned[y * SIDE + x] <= PAINTED:
                continue
            if box.intersects(Rect2(float(x), float(y), 1.0, 1.0)):
                continue
            outside += 1
    assert_eq(outside, 0, "a dab at full pattern strength wrote nothing outside %s" % str(box))


# --- The three texturing modes ----------------------------------------------------


## A ramp across the tile, as an r32f texture whose column *c* holds exactly
## `c / 15`, so the first column is a paper of nothing, the last one a paper of
## one, and every value between is a float the kernel reads without rounding.
func _ramp() -> SaTexture:
    var texture := SaTexture.new(Vector2i(TILE, TILE), RenderingDevice.DATA_FORMAT_R32_SFLOAT)
    var texels := PackedFloat32Array()
    texels.resize(TILE * TILE)
    for y in TILE:
        for x in TILE:
            texels[y * TILE + x] = _ramp_at(x)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, texels.to_byte_array())
    return texture


static func _ramp_at(x: int) -> float:
    return float(posmod(x, TILE)) / float(TILE - 1)


## Krita's `colorBurnAlpha` over one texel, stated on the CPU the way
## `KisMaskingBrushCompositeOp.h` states it: the dab is the coverage times the
## strength, and a paper of nothing keeps the dab only where it is whole.
static func _burned(sampled: float, coverage: float, amount: float) -> float:
    var dab := coverage * amount
    if sampled <= 0.0:
        return dab if dab >= 1.0 else 0.0
    return 1.0 - clampf((1.0 - dab) / sampled, 0.0, 1.0)


## Krita's `hardMixSofterPhotoshopAlpha`.
static func _hard_mixed(sampled: float, coverage: float, amount: float) -> float:
    return clampf(3.0 * coverage * amount - 2.0 * (1.0 - sampled), 0.0, 1.0)


## Krita's linear height, with its strength scaled by 0.99.
static func _linear_height(sampled: float, coverage: float, amount: float) -> float:
    var inverted := 1.0 - 0.99 * amount
    var lifted := coverage / inverted - inverted
    return clampf(maxf(lifted * (1.0 - sampled), lifted - sampled), 0.0, 1.0)


## Every texel of one dab through *mode* at *amount* against *formula*, and how
## many of them the mode moved off the plain dab, so a mode that painted the
## plain dab everywhere is caught even where its formula happens to agree.
func _held_to(mode: SaDabPattern.Mode, amount: float, formula: Callable) -> void:
    var ramp := _ramp()
    var plain := _paint_plain(CENTRE)
    var strength := amount + float(SaDabPattern.band_of(mode))
    var painted := _paint(CENTRE, strength, Vector2.ZERO, ramp)
    var covered := 0
    var wrong := 0
    var moved := 0
    var first_wrong := ""
    for y in SIDE:
        for x in SIDE:
            var index := y * SIDE + x
            if plain[index] <= 0.0:
                continue
            covered += 1
            var expected: float = formula.call(_ramp_at(x), plain[index], amount)
            if absf(painted[index] - expected) > 1e-4:
                wrong += 1
                if first_wrong.is_empty():
                    first_wrong = "(%d, %d) painted %f against %f" % [x, y, painted[index], expected]
            if absf(painted[index] - plain[index]) > 1e-3:
                moved += 1
    var name := SaDabPattern.mode_name(mode)
    assert_true(covered > 400, "%s: the dab covers a body of texels, %d of them" % [name, covered])
    assert_eq(wrong, 0, "%s at %.2f is Krita's formula texel for texel, first miss %s" % [name, amount, first_wrong])
    assert_true(moved > 50, "%s at %.2f moved %d texels off the plain dab" % [name, amount, moved])


func test_colour_burn_is_krita_s_formula() -> void:
    _held_to(SaDabPattern.Mode.COLOR_BURN, 0.75, _burned)
    _held_to(SaDabPattern.Mode.COLOR_BURN, 0.5, _burned)


func test_hard_mix_softer_is_krita_s_formula() -> void:
    _held_to(SaDabPattern.Mode.HARD_MIX_SOFTER, 0.75, _hard_mixed)
    _held_to(SaDabPattern.Mode.HARD_MIX_SOFTER, 0.4, _hard_mixed)


func test_linear_height_is_krita_s_formula() -> void:
    _held_to(SaDabPattern.Mode.LINEAR_HEIGHT, 0.75, _linear_height)
    _held_to(SaDabPattern.Mode.LINEAR_HEIGHT, 1.0, _linear_height)


## Rule 5 through the three: they answer a coverage and never touch the colour,
## so a dab of a colour over one comes back over one, as itself, on every texel
## any of them painted.
func test_a_colour_over_one_comes_back_whole_through_each_new_mode() -> void:
    var ramp := _ramp()
    var colour := Color(4.0, 2.5, 1.25, 1.0)
    for mode: SaDabPattern.Mode in [
        SaDabPattern.Mode.COLOR_BURN, SaDabPattern.Mode.HARD_MIX_SOFTER, SaDabPattern.Mode.LINEAR_HEIGHT
    ]:
        var rgba := _paint_rgba(CENTRE, 0.9 + float(SaDabPattern.band_of(mode)), Vector2.ZERO, ramp, colour)
        var painted := 0
        var clamped := 0
        for i in SIDE * SIDE:
            if rgba[i * 4 + 3] <= PAINTED:
                continue
            painted += 1
            var back := Color(rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2])
            if absf(back.r - colour.r) > 1e-3 or absf(back.g - colour.g) > 1e-3 or absf(back.b - colour.b) > 1e-3:
                clamped += 1
        var name := SaDabPattern.mode_name(mode)
        assert_true(painted > 50, "%s painted %d texels" % [name, painted])
        assert_eq(clamped, 0, "and %s gave each of them the colour over one back unclamped" % name)
