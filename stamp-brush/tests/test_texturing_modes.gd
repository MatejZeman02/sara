## The texturing modes: what the first four do to a dab, how the one number
## carries the mode, and where the row and the import put it. The arithmetic of
## the three Krita's own code paints is read against its
## formula in `test_dab_pattern.gd`.
##
## The dab assertions read texels back the way `test_dab_pattern.gd` does, and
## they reason about the kernel's own coverage rather than about a guess at what
## a circle covers: every test reads the same dab with the paper off as well,
## which is the coverage the modes are arithmetic on.
##
## **What each of the four is allowed to move**, which is how they are told
## apart. Multiply and subtract move the coverage and leave the colour alone.
## Lightness moves the colour and leaves the coverage alone, so it is the one
## mode the coverage tests never see. Height moves the coverage again, but as a
## gate rather than a factor: every texel it paints is the dab's own coverage or
## nothing at all.
##
## Two papers, because the two pairs need different ones. The two halves of the
## first are what tells multiply from subtract on the texels they part company
## on, and its two values cannot tell two heights apart: a gate at a quarter and
## a gate at three quarters both let the black half through. The ramp's sixteen
## steps can.
extends "res://tests/test_framework.gd"

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")

## A pattern is a texture and a dab is a dispatch.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_texturing_modes")
## Sixteen texels wide, the left half white and the right half black, so a texel
## whose tile column is under 8 has no tooth and one at 8 or over has it whole.
const HALF_NAME := "half_paper.png"
## Sixteen texels wide and a dark-to-light ramp across it, so the tile's value
## at a column is that column over sixteen. The height mode reads it as a height
## field, which is what lets one strength gate more columns than another.
const RAMP_NAME := "ramp_paper.png"
const TILE: int = 16
const SIDE: int = 64
const GROUPS: int = 8
const HALF_EXTENT := Vector2(14.0, 14.0)
## Not a multiple of the tile, because a centre on the grid's own multiple
## cannot tell a mask on the paper from one on the brush.
const CENTRE := Vector2(30.0, 34.0)
## The strength both modes are read at. Three quarters rather than one, because
## at a full strength over a whole tooth a subtract closes every texel it
## touches and the two modes agree at every fully covered texel.
const STRENGTH: float = 0.75


func after_each() -> void:
    if DirAccess.dir_exists_absolute(scratch_dir):
        var dir := DirAccess.open(scratch_dir)
        for file in dir.get_files():
            dir.remove(file)
        DirAccess.remove_absolute(scratch_dir)


func _write_half() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var image := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
    for y in TILE:
        for x in TILE:
            var lit := 1.0 if float(x) < float(TILE) / 2.0 else 0.0
            image.set_pixel(x, y, Color(lit, lit, lit, 1.0))
    image.save_png(scratch_dir.path_join(HALF_NAME))


func _write_ramp() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var image := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
    for y in TILE:
        for x in TILE:
            var lit := float(x) / float(TILE)
            image.set_pixel(x, y, Color(lit, lit, lit, 1.0))
    image.save_png(scratch_dir.path_join(RAMP_NAME))


func _dab_pattern() -> SaDabPattern:
    _write_half()
    return SaDabPattern.new(SaPatternStore.new([scratch_dir]))


## The same brush over the ramp, which is the paper the height mode is read on.
func _ramp_pattern() -> SaDabPattern:
    _write_ramp()
    return SaDabPattern.new(SaPatternStore.new([scratch_dir]))


func _settings(mode: int, paper: String = HALF_NAME) -> Resource:
    var settings := SettingsScript.new()
    settings.pattern_name = SaPatternStore.name_for(scratch_dir.path_join(paper))
    settings.texture_option.enabled = true
    settings.texture_option.strength = 1.0
    settings.texture_mode = mode
    return settings


## One dab through the real binder and the real packing, read back whole: four
## floats a texel, red, green, blue and alpha.
##
## *strength* is the dab's own, before the mode and the invert are folded into
## it, which is what the stroke hands over. The canvas is a bare texture rather
## than a document, so the kernel's lightness branch takes the sRGB answer
## `SaBrushTipMask.bind` writes for a caller with no document, which is what
## [method _lightness] decodes back out.
func _paint_rgba(pattern: SaDabPattern, settings: Resource, strength: float) -> PackedFloat32Array:
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
    # The tip's binder first, which is what puts the stand-in on binding 4, and
    # the pattern's after it, the order `state_brush.gd` keeps.
    var mask := SaStampBindings.bind(compute, tip, null)
    pattern.bind(compute, settings, strength)
    compute.set_push_constant_float_array(
        SaDabPacking.pack_dab_params(
            CENTRE,
            Vector2.ZERO,
            Color(1, 1, 1, 1),
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
            pattern.strength_for(strength, settings),
            SaDabPattern.offset_of(settings)
        )
    )
    compute.dispatch_kernel("dab", GROUPS, GROUPS, 1)
    assert_true(mask != null, "the tip mask bound")
    var data: PackedByteArray = rd.texture_get_data(canvas.rid, 0)
    var out := PackedFloat32Array()
    out.resize(SIDE * SIDE * 4)
    for i in SIDE * SIDE * 4:
        out[i] = data.decode_float(i * 4)
    return out


## The alpha channel of [method _paint_rgba] alone, which is the coverage the
## two modes over the half tile are read against.
func _paint(pattern: SaDabPattern, settings: Resource, strength: float) -> PackedFloat32Array:
    var rgba := _paint_rgba(pattern, settings, strength)
    var out := PackedFloat32Array()
    out.resize(SIDE * SIDE)
    for i in SIDE * SIDE:
        out[i] = rgba[i * 4 + 3]
    return out


## The Oklab lightness of the texel at *index*, decoded out of the sRGB answer
## the kernel encoded under, which is the same pair of steps `SaMeasure` takes
## and the same curve `sa_transfer_decode` reads on the GPU.
func _lightness(rgba: PackedFloat32Array, index: int) -> float:
    var curve := SaTransferFunction.srgb()
    var linear := Vector3(curve.decode(rgba[index * 4]), curve.decode(rgba[index * 4 + 1]), curve.decode(rgba[index * 4 + 2]))
    return SaOklab.from_linear_srgb(linear).x


## Whether two readbacks differ anywhere by more than a float's noise, which is
## how "four different results" is read: a mode that painted the same dab is the
## same array. The tolerance is a thousandth of a texel's worth of alpha and is
## there for the two round trips through the sRGB curve rather than for a mode
## that only nearly differs.
func _differ(one: PackedFloat32Array, other: PackedFloat32Array) -> bool:
    for i in one.size():
        if absf(one[i] - other[i]) > 1e-3:
            return true
    return false


## The tooth over the texel at *x*, which the half tile makes one or nothing.
## The columns either side of each seam are left out of every assertion, so a
## texel that sampled its neighbour cannot decide a case.
func _tooth(x: int) -> float:
    return 1.0 if x % TILE >= 8 else 0.0


## A preset naming *mode* and nothing else about its paper, in the shape the
## reader hands the import: every option is a typed cell rather than a bare
## string.
func _preset_with_mode(mode: String) -> Dictionary:
    return {
        "name": "made",
        "source": "made.kpp",
        "engine": "paintbrush",
        "options":
        {
            "Texture/Pattern/Enabled": {"type": "string", "value": "true"},
            "Texture/Pattern/TexturingMode": {"type": "string", "value": mode},
        },
        "resources": {},
        "tags": PackedStringArray(),
        "licence": "",
        "error": "",
        "tip": {"kind": SaKppReader.TIP_NONE},
    }


func _on_a_seam(x: int) -> bool:
    var column := x % TILE
    return column == 0 or column == 7 or column == 8 or column == 15


# --- The arithmetic --------------------------------------------------------------


func test_multiply_thins_the_coverage_and_subtract_takes_it_away() -> void:
    var pattern := _dab_pattern()
    var plain := _paint(pattern, _settings(SaDabPattern.Mode.MULTIPLY), 0.0)
    var multiplied := _paint(pattern, _settings(SaDabPattern.Mode.MULTIPLY), STRENGTH)
    var subtracted := _paint(pattern, _settings(SaDabPattern.Mode.SUBTRACT), STRENGTH)
    var partial := 0
    var whole := 0
    var apart := 0
    for y in SIDE:
        for x in SIDE:
            if _on_a_seam(x):
                continue
            var index := y * SIDE + x
            var covered := plain[index]
            if covered <= 0.0:
                continue
            var tooth := _tooth(x)
            assert_almost_eq(
                multiplied[index], covered * (1.0 - STRENGTH * tooth), 2e-3, "multiply thins the coverage in proportion"
            )
            assert_almost_eq(subtracted[index], maxf(covered - STRENGTH * tooth, 0.0), 2e-3, "subtract takes the tooth off it")
            if tooth > 0.0:
                if covered >= 0.999:
                    whole += 1
                elif covered > 0.2 and covered < 0.8:
                    partial += 1
                    if absf(multiplied[index] - subtracted[index]) > 0.05:
                        apart += 1
    assert_true(whole > 100, "the dab covers a body of texels over the tooth whole, %d of them" % whole)
    assert_true(partial > 4, "and a ring of them partly, %d of them" % partial)
    assert_eq(apart, partial, "where the two modes part company, which is the whole of the difference")


# --- The two added later -------------------------------------------------------


func test_the_lightness_mode_moves_the_colour_and_leaves_the_coverage() -> void:
    var pattern := _dab_pattern()
    var plain := _paint_rgba(pattern, _settings(SaDabPattern.Mode.MULTIPLY), 0.0)
    var shifted := _paint_rgba(pattern, _settings(SaDabPattern.Mode.LIGHTNESS), 1.0)
    # Four texels either side of the dab's centre and four columns clear of the
    # tile's seams, so the white one has no tooth and the black one has it whole.
    var white := 34 * SIDE + 34
    var black := 34 * SIDE + 26
    assert_true(plain[white * 4 + 3] > 0.9, "the white half's texel is under the dab whole")
    assert_true(plain[black * 4 + 3] > 0.9, "and so is the black half's")
    var moved := 0
    for i in SIDE * SIDE:
        if absf(shifted[i * 4 + 3] - plain[i * 4 + 3]) > 1e-4:
            moved += 1
    assert_eq(moved, 0, "the lightness mode does not touch the coverage, texel for texel")
    assert_almost_eq(_lightness(plain, white), _lightness(plain, black), 1e-3, "the dab with the paper off is one colour")
    var lit := _lightness(plain, white)
    assert_almost_eq(_lightness(shifted, white), lit + 0.5, 0.02, "the white half carries the colour half a step up")
    assert_almost_eq(_lightness(shifted, black), lit - 0.5, 0.02, "and the black half half a step down")


func test_the_height_mode_gates_the_coverage_and_paints_only_the_valleys() -> void:
    var pattern := _ramp_pattern()
    var plain := _paint(pattern, _settings(SaDabPattern.Mode.MULTIPLY, RAMP_NAME), 0.0)
    var light := _paint(pattern, _settings(SaDabPattern.Mode.HEIGHT, RAMP_NAME), 0.3)
    var heavy := _paint(pattern, _settings(SaDabPattern.Mode.HEIGHT, RAMP_NAME), 0.8)
    var whole := 0
    var fraction := 0
    var light_total := 0.0
    var heavy_total := 0.0
    for i in SIDE * SIDE:
        light_total += light[i]
        heavy_total += heavy[i]
        if plain[i] <= 0.0:
            continue
        if is_equal_approx(heavy[i], plain[i]) or heavy[i] <= 0.0:
            whole += 1
        else:
            fraction += 1
    assert_eq(fraction, 0, "the height mode gates the coverage rather than scaling it, %d texels kept whole" % whole)
    assert_true(light_total > 0.0, "a light touch paints the valleys")
    assert_true(heavy_total > light_total, "and a heavier one paints more of them, %f against %f" % [heavy_total, light_total])
    # Three columns under the dab's body at one row, each with a different tile
    # value: a valley a quarter of the way up, one a little past half and one a
    # little past two thirds. The first is painted at both strengths, and the
    # two above the light gate only at the heavy one.
    var valley := 34 * SIDE + 33
    var slope := 34 * SIDE + 41
    var ridge := 34 * SIDE + 43
    assert_true(light[valley] > 0.0 and heavy[valley] > 0.0, "the lightest column is painted at both strengths")
    assert_almost_eq(heavy[valley], plain[valley], 2e-3, "and keeps the coverage the dab laid there whole")
    assert_true(light[slope] <= 0.0 and heavy[slope] > 0.0, "a column past the light gate arrives at the heavy one")
    assert_true(light[ridge] <= 0.0 and heavy[ridge] > 0.0, "and so does one further up")


func test_the_seven_modes_paint_seven_different_dabs() -> void:
    var pattern := _ramp_pattern()
    var modes: Array[int] = []
    modes.assign(SaDabPattern.MODES)
    var dabs: Array = []
    for mode: int in modes:
        dabs.append(_paint_rgba(pattern, _settings(mode, RAMP_NAME), STRENGTH))
    for i in modes.size():
        for j in range(i + 1, modes.size()):
            assert_true(
                _differ(dabs[i], dabs[j]),
                "%s and %s paint different dabs" % [SaDabPattern.mode_name(modes[i]), SaDabPattern.mode_name(modes[j])]
            )


func test_the_paper_off_is_the_same_dab_in_either_mode() -> void:
    var pattern := _dab_pattern()
    var multiply_off := _paint(pattern, _settings(SaDabPattern.Mode.MULTIPLY), 0.0)
    var subtract_off := _paint(pattern, _settings(SaDabPattern.Mode.SUBTRACT), 0.0)
    var differing := 0
    for i in SIDE * SIDE:
        if not is_equal_approx(multiply_off[i], subtract_off[i]):
            differing += 1
    assert_eq(differing, 0, "a strength of nothing is the dab as it was, whichever mode the row names")


# --- The carrier -----------------------------------------------------------------


func test_the_mode_rides_the_band_and_the_invert_still_rides_the_sign() -> void:
    var pattern := _dab_pattern()
    var multiply := _settings(SaDabPattern.Mode.MULTIPLY)
    var subtract := _settings(SaDabPattern.Mode.SUBTRACT)
    var lightness := _settings(SaDabPattern.Mode.LIGHTNESS)
    var height := _settings(SaDabPattern.Mode.HEIGHT)
    assert_almost_eq(pattern.strength_for(0.4, multiply), 0.4, 1e-6, "multiply is the strength itself")
    assert_almost_eq(pattern.strength_for(0.4, subtract), 1.4, 1e-6, "subtract is one higher")
    assert_almost_eq(pattern.strength_for(0.4, lightness), 2.4, 1e-6, "lightness two higher")
    assert_almost_eq(pattern.strength_for(0.4, height), 3.4, 1e-6, "and height three, one whole number a band")
    subtract.texture_invert = true
    multiply.texture_invert = true
    height.texture_invert = true
    assert_almost_eq(pattern.strength_for(0.4, multiply), -0.4, 1e-6, "and the invert is still the sign")
    assert_almost_eq(pattern.strength_for(0.4, subtract), -1.4, 1e-6, "in every band")
    assert_almost_eq(pattern.strength_for(0.4, height), -3.4, 1e-6, "the highest one too")
    assert_eq(pattern.strength_for(0.0, subtract), 0.0, "a strength of nothing is off, not a subtract of nothing")
    assert_eq(pattern.strength_for(0.0, height), 0.0, "nor a height of nothing")


func test_the_packing_keeps_the_band_the_kernel_reads() -> void:
    var packed := SaDabPacking.pack_dab_params(
        CENTRE,
        Vector2.ZERO,
        Color(1, 1, 1, 1),
        HALF_EXTENT,
        0.0,
        Vector2.ONE,
        1.0,
        SaDabGeometry.PaintMode.OVER,
        false,
        null,
        0.0,
        0.0,
        0.0,
        -1.75,
        Vector2.ZERO
    )
    assert_almost_eq(packed[SaDabPacking.PATTERN_STRENGTH_INDEX], -1.75, 1e-6, "an inverted subtract survives the clamp whole")


## The packing carries the band the seven modes need: height at the top of its
## range, and linear height inverted at the top of its own, which is the
## largest magnitude `SaDabPattern.strength_for` hands over. The clamp is that
## function's.
func test_the_packing_keeps_the_highest_band_the_kernel_reads() -> void:
    var packed := SaDabPacking.pack_dab_params(
        CENTRE,
        Vector2.ZERO,
        Color(1, 1, 1, 1),
        HALF_EXTENT,
        0.0,
        Vector2.ONE,
        1.0,
        SaDabGeometry.PaintMode.OVER,
        false,
        null,
        0.0,
        0.0,
        0.0,
        4.0,
        Vector2.ZERO
    )
    assert_almost_eq(packed[SaDabPacking.PATTERN_STRENGTH_INDEX], 4.0, 1e-6, "a height at full strength is the top of its band")
    var top := SaDabPacking.pack_dab_params(
        CENTRE,
        Vector2.ZERO,
        Color(1, 1, 1, 1),
        HALF_EXTENT,
        0.0,
        Vector2.ONE,
        1.0,
        SaDabGeometry.PaintMode.OVER,
        false,
        null,
        0.0,
        0.0,
        0.0,
        -7.0,
        Vector2.ZERO
    )
    assert_almost_eq(
        top[SaDabPacking.PATTERN_STRENGTH_INDEX], -7.0, 1e-6, "and an inverted linear height at full strength survives whole"
    )


func test_a_settings_without_the_row_paints_multiply() -> void:
    var settings := SettingsScript.new()
    assert_eq(settings.texture_mode, SaDabPattern.Mode.MULTIPLY, "a new brush multiplies, which is the plain dab")
    assert_eq(SaDabPattern.mode_of(null), SaDabPattern.Mode.MULTIPLY, "and so does nothing at all")
    assert_eq(
        SaDabPattern.mode_of(Resource.new()),
        SaDabPattern.Mode.MULTIPLY,
        "and so does a preset written before the row, which is what an additive key means"
    )
    var unknown := SettingsScript.new()
    unknown.texture_mode = 5
    assert_eq(
        SaDabPattern.mode_of(unknown),
        SaDabPattern.Mode.MULTIPLY,
        "and so does one of Krita's nine modes this engine has no arithmetic for"
    )
    assert_eq(SaDabPattern.band_of(SaDabPattern.Mode.MULTIPLY), 0, "multiply is the floor of the band")
    assert_eq(SaDabPattern.band_of(SaDabPattern.Mode.HEIGHT), 3, "and height three whole numbers above it")
    assert_eq(SaDabPattern.band_of(SaDabPattern.Mode.COLOR_BURN), 4, "with colour burn above height")
    assert_eq(SaDabPattern.band_of(SaDabPattern.Mode.HARD_MIX_SOFTER), 5, "hard mix softer above that")
    assert_eq(SaDabPattern.band_of(SaDabPattern.Mode.LINEAR_HEIGHT), 6, "and linear height at the top")


# --- The row and the import ------------------------------------------------------


func test_the_page_declares_the_mode_as_seven_choices() -> void:
    var by_key: Dictionary = {}
    for spec: SaOptionSpec in ModuleScript.brush_options():
        by_key[String(spec.key)] = spec
    var row: SaOptionSpec = by_key.get("texture_mode")
    assert_not_null(row, "the Mode row is declared")
    if row == null:
        return
    assert_eq(row.kind, SaOptionSpec.Kind.ENUM, "as a choice and not a toggle, so a third mode is a third entry")
    assert_eq(row.page, SaTexturePage.PAGE, "on the Texture page")
    assert_false(row.bar, "off the bar with the rest of the page")
    assert_eq(row.choices.size(), 7, "with the seven modes Sara paints")
    assert_eq(row.choices[0]["id"], SaDabPattern.Mode.MULTIPLY, "multiply first, which is what a dab did before")
    assert_eq(String(row.choices[1]["label"]), "Subtract", "and subtract beside it")
    assert_eq(row.choices[2]["id"], SaDabPattern.Mode.LIGHTNESS, "the lightness mode third, where Krita has it")
    assert_eq(String(row.choices[2]["label"]), "Lightness", "under its own name")
    assert_eq(row.choices[3]["id"], SaDabPattern.Mode.COLOR_BURN, "colour burn next, at Krita's eighth number")
    assert_eq(String(row.choices[3]["label"]), "Colour Burn", "under its own name")
    assert_eq(row.choices[4]["id"], SaDabPattern.Mode.HARD_MIX_SOFTER, "hard mix softer at Krita's twelfth")
    assert_eq(String(row.choices[4]["label"]), "Hard Mix Softer", "under its own name")
    assert_eq(row.choices[5]["id"], SaDabPattern.Mode.HEIGHT, "height at Krita's own thirteenth number")
    assert_eq(String(row.choices[5]["label"]), "Height", "under its own name too")
    assert_eq(row.choices[6]["id"], SaDabPattern.Mode.LINEAR_HEIGHT, "and linear height last, at its fourteenth")
    assert_eq(String(row.choices[6]["label"]), "Linear Height", "under its own name")


func test_the_import_carries_krita_s_seven_modes_and_names_the_rest() -> void:
    for pair: Array in [
        ["0", SaDabPattern.Mode.MULTIPLY, "the first is the first"],
        ["1", SaDabPattern.Mode.SUBTRACT, "Krita's second mode is Sara's second mode"],
        ["2", SaDabPattern.Mode.LIGHTNESS, "and its third is the lightness mode"],
        ["12", SaDabPattern.Mode.HEIGHT, "with height at its own thirteenth number"],
        ["7", SaDabPattern.Mode.COLOR_BURN, "colour burn at its eighth"],
        ["11", SaDabPattern.Mode.HARD_MIX_SOFTER, "hard mix softer at its twelfth"],
        ["13", SaDabPattern.Mode.LINEAR_HEIGHT, "and linear height at its fourteenth"],
    ]:
        var settings := SettingsScript.new()
        var applied := SaKppImport.apply(_preset_with_mode(String(pair[0])), settings)
        assert_eq(settings.texture_mode, pair[1], String(pair[2]))
        assert_eq(applied["not_carried"], [], "so it is carried rather than named as lost")
    # The nine of Krita's sixteen that no bundled preset names, which are left
    # for a preset that does.
    for left: String in ["3", "4", "5", "6", "8", "9", "10", "14", "15"]:
        var unknown := SettingsScript.new()
        var named := SaKppImport.apply(_preset_with_mode(left), unknown)
        assert_eq(unknown.texture_mode, SaDabPattern.Mode.MULTIPLY, "mode %s, with no arithmetic, paints multiply" % left)
        assert_eq(named["not_carried"], ["texturing mode"], "and mode %s says so once" % left)
