## The Texture page: its option, its rows, the strength the dynamics answer,
## the texture the dab pipeline binds and what a preset carries.
##
## The page's clauses, each a test: the option is the tenth of the settings and
## off for a new brush, the four rows are declared under the page's title and
## the editor joins them to the curve page, the strength follows the option and
## the sensors, the dab reads the named pattern at the settings' scale, offset
## and invert through `SaDabPattern`, and a preset saved with the page on
## reloads with it. The dab assertions read alpha back the way
## `test_dab_pattern.gd` does, over a half-and-half picture written to `user://`
## rather than a checker, so an invert is a swap of two numbers and an offset
## moves an edge.
extends "res://tests/test_framework.gd"

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")

## A pattern is a texture and a dab is a dispatch.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_texture_page")
static var scratch_preset_dir: String = SaDataRoot.path("test_texture_page_presets")
## Sixteen texels wide, the left half white and the right half black, so a
## texel at x under 8 is where the dab paints in full and one at 8 or over is
## where the paper takes it all away.
const HALF_NAME := "half_paper.png"
const TILE: int = 16
const SIDE: int = 64
const GROUPS: int = 8
const HALF_EXTENT := Vector2(14.0, 14.0)
## Not a multiple of the tile, because a centre on the grid's own multiple
## cannot tell a mask on the paper from one on the brush.
const CENTRE := Vector2(30.0, 34.0)
const PAINTED: float = 1.0 / 512.0


func after_each() -> void:
    for folder: String in [scratch_dir, scratch_preset_dir]:
        if DirAccess.dir_exists_absolute(folder):
            var dir := DirAccess.open(folder)
            for file in dir.get_files():
                dir.remove(file)
            DirAccess.remove_absolute(folder)


func _write_half() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var image := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
    for y in TILE:
        for x in TILE:
            var lit := 1.0 if float(x) < float(TILE) / 2.0 else 0.0
            image.set_pixel(x, y, Color(lit, lit, lit, 1.0))
    image.save_png(scratch_dir.path_join(HALF_NAME))


func _settings(pattern_name: String, on: bool = true) -> Resource:
    var settings := SettingsScript.new()
    settings.pattern_name = pattern_name
    settings.texture_option.enabled = on
    settings.texture_option.strength = 1.0
    return settings


func _dab_pattern() -> SaDabPattern:
    _write_half()
    return SaDabPattern.new(SaPatternStore.new([scratch_dir]))


## One dab through the real binder and the real packing, read back per texel
## as alpha, the way `test_dab_pattern.gd` reads.
func _paint(pattern: SaDabPattern, settings: Resource, strength: float, offset: Vector2) -> PackedFloat32Array:
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
    # The tip's binder first, which is what puts the stand-in on binding 4,
    # and the pattern's after it, the order `state_brush.gd` keeps.
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
            offset + SaDabPattern.offset_of(settings)
        )
    )
    compute.dispatch_kernel("dab", GROUPS, GROUPS, 1)
    assert_true(mask != null, "the tip mask bound")
    var data: PackedByteArray = rd.texture_get_data(canvas.rid, 0)
    var out := PackedFloat32Array()
    out.resize(SIDE * SIDE)
    for i in SIDE * SIDE:
        out[i] = data.decode_float(i * 16 + 12)
    return out


func _at(texels: PackedFloat32Array, x: int, y: int) -> float:
    return texels[y * SIDE + x]


# --- The declaration ------------------------------------------------------------


func test_the_option_is_the_tenth_and_off_for_a_new_brush() -> void:
    var settings := SettingsScript.new()
    var options: Dictionary = settings.options()
    assert_true(options.has("texture"), "the settings list the texture option by name")
    assert_false(settings.texture_option.enabled, "and a new brush has the paper off, which is the plain dab exactly")
    assert_eq(settings.texture_scale, 1.0, "at the pattern's own size")
    assert_false(settings.texture_invert, "the right way up")


func test_the_page_is_declared_as_a_curve_option_and_four_rows() -> void:
    var specs: Array = ModuleScript.brush_options()
    var by_key: Dictionary = {}
    for spec: SaOptionSpec in specs:
        by_key[String(spec.key)] = spec
    var curve: SaOptionSpec = by_key.get("texture_option")
    assert_not_null(curve, "the curve option is declared")
    assert_eq(curve.kind, SaOptionSpec.Kind.CURVE_OPTION, "as a curve option, so the page has a checkbox")
    assert_eq(curve.label, SaTexturePage.PAGE, "titled Texture")
    for key: String in ["pattern_name", "texture_scale", "texture_offset_x", "texture_offset_y", "texture_invert"]:
        var row: SaOptionSpec = by_key.get(key)
        assert_not_null(row, "%s is a declared row" % key)
        if row != null:
            assert_eq(row.page, SaTexturePage.PAGE, "%s names the Texture page" % key)
            assert_false(row.bar, "%s stays off the bar" % key)
    assert_eq((by_key["pattern_name"] as SaOptionSpec).kind, SaOptionSpec.Kind.CUSTOM, "the chooser is a custom row")
    assert_true((by_key["pattern_name"] as SaOptionSpec).build_control.is_valid(), "with the pattern chooser as its widget")


func test_the_editor_joins_the_rows_to_the_curve_page() -> void:
    var pages: Array = SaBrushEditorPages.pages_from(ModuleScript.brush_options())
    var texture: Dictionary = {}
    var titled := 0
    for page: Dictionary in pages:
        if String(page["title"]) == SaTexturePage.PAGE:
            titled += 1
            texture = page
    assert_eq(titled, 1, "one Texture page, not a curve page and a plain page of the same name")
    assert_not_null(texture.get("curve"), "with the curve option behind its checkbox")
    assert_eq(
        (texture["specs"] as Array).size(),
        17,
        (
            "and the curve spec plus the five rows on it, the three randomiser rows, the mode row, the "
            + "three tone rows, the pivot switch and the three cutoff rows"
        )
    )
    var titles: Array = []
    for page: Dictionary in pages:
        titles.append(String(page["title"]))
    assert_eq(titles.find("Texture"), titles.find("Scatter") + 1, "listed after Scatter")


func test_the_chooser_row_shows_the_name_without_picking() -> void:
    var picked: Array = []
    var control := SaTexturePage.build_chooser(null, func(value: Variant) -> void: picked.append(value))
    var chooser := control as SaPatternChooser
    assert_not_null(chooser, "the row is the pattern chooser")
    SaTexturePage.bind_chooser(control, "Paper Grain")
    assert_eq(chooser.selected, "Paper Grain", "the binder presses the named tile")
    assert_eq(picked.size(), 0, "and tells the write door nothing, so a sync is not a pick")
    chooser.pick("Dot Screen")
    assert_eq(picked, ["Dot Screen"], "while a pick reaches the door with the name")
    control.free()


# --- The strength ----------------------------------------------------------------


func test_the_dynamics_answer_the_option_s_strength_and_nought_when_off() -> void:
    var settings := SettingsScript.new()
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 1)
    var dynamics := SaDynamics.new(settings)
    assert_eq(dynamics.evaluate(info, 20.0).pattern_strength, 0.0, "off is no pattern, not a full one")
    settings.texture_option.enabled = true
    settings.texture_option.strength = 0.5
    assert_almost_eq(dynamics.evaluate(info, 20.0).pattern_strength, 0.5, 1e-6, "on with no sensor is the strength")
    settings.texture_option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    dynamics.begin_stroke()
    info.feed(Vector2(1.0, 0.0), 0.5, Vector2.ZERO, 0.0, 10.0)
    assert_almost_eq(dynamics.evaluate(info, 20.0).pattern_strength, 0.25, 1e-6, "and a sensor at a half halves it")


func test_the_packed_strength_is_signed_by_the_invert_and_nought_with_no_texture() -> void:
    var pattern := _dab_pattern()
    var settings := _settings("Half Paper")
    assert_almost_eq(pattern.strength_for(0.7, settings), 0.7, 1e-6, "the strength as it is")
    settings.texture_invert = true
    assert_almost_eq(pattern.strength_for(0.7, settings), -0.7, 1e-6, "negative when the paper is turned over")
    var nameless := _settings("")
    assert_eq(pattern.strength_for(0.7, nameless), 0.0, "and nought with nothing to read, so the stand-in is never read")
    var missing := _settings("No Such Paper")
    assert_eq(pattern.strength_for(0.7, missing), 0.0, "or with a name the store does not have")
    assert_false(pattern.error.is_empty(), "which the dump can say")


# --- The texture ----------------------------------------------------------------


func test_the_texture_is_the_pattern_at_the_settings_scale() -> void:
    var pattern := SaDabPattern.new(SaPatternStore.new([SaPatternStore.SHIPPED_DIR]))
    var settings := _settings("Paper Grain")
    var own := pattern.texture(settings)
    assert_not_null(own, "the shipped grain answers a texture")
    assert_eq(own.size, Vector2i(256, 256), "at its tile at a scale of one")
    assert_true(own == pattern.texture(settings), "the second ask is the first texture")
    settings.texture_scale = 2.0
    var doubled := pattern.texture(settings)
    assert_eq(doubled.size, Vector2i(512, 512), "and twice the tile at two, generated rather than stretched")
    settings.texture_scale = 0.25
    assert_eq(pattern.texture(settings).size, Vector2i(64, 64), "and a quarter at a quarter")


func test_a_picture_is_resampled_at_the_scale() -> void:
    var pattern := _dab_pattern()
    var settings := _settings("Half Paper")
    assert_eq(pattern.texture(settings).size, Vector2i(TILE, TILE), "a picture at its own size")
    settings.texture_scale = 2.0
    assert_eq(pattern.texture(settings).size, Vector2i(TILE * 2, TILE * 2), "and twice it at two")
    var report := pattern.report(settings)
    assert_eq(report["name"], "Half Paper", "the dump names the pattern")
    assert_eq(report["texture_size"], [TILE * 2, TILE * 2], "and the texture that is bound")


# --- The dab -------------------------------------------------------------------


func test_the_dab_reads_the_paper_and_the_invert_turns_it_over() -> void:
    var pattern := _dab_pattern()
    var settings := _settings("Half Paper")
    var painted := _paint(pattern, settings, 1.0, Vector2.ZERO)
    # Two texels a tile apart on the dab's own row, one in a lit half and one
    # in a dark half of the paper, both well inside the circle.
    var lit := _at(painted, 20, 34)
    var dark := _at(painted, 26, 34)
    assert_true(lit > 0.99, "the dab paints in full where the paper is white: %f" % lit)
    assert_true(dark <= PAINTED, "and nothing where it is black: %f" % dark)
    settings.texture_invert = true
    var turned := _paint(pattern, settings, 1.0, Vector2.ZERO)
    assert_true(_at(turned, 20, 34) <= PAINTED, "turned over, the white half takes the paint away")
    assert_true(_at(turned, 26, 34) > 0.99, "and the black half lets it through")


func test_the_offset_moves_the_grid_and_the_strength_blends() -> void:
    var pattern := _dab_pattern()
    var settings := _settings("Half Paper")
    settings.texture_offset_x = 8
    var shifted := _paint(pattern, settings, 1.0, Vector2.ZERO)
    assert_true(_at(shifted, 20, 34) <= PAINTED, "eight texels along, the lit texel reads the dark half")
    assert_true(_at(shifted, 26, 34) > 0.99, "and the dark one the lit half")
    settings.texture_offset_x = 0
    var half := _paint(pattern, settings, 0.5, Vector2.ZERO)
    assert_almost_eq(_at(half, 26, 34), 0.5, 1e-3, "at half strength the dark half is a half")
    var off := _paint(pattern, settings, 0.0, Vector2.ZERO)
    assert_true(_at(off, 26, 34) > 0.99, "and at nought the paper is not read at all")


func test_the_grid_origin_carries_the_chunk_s_own_origin() -> void:
    var target := SaPaintContext.Target.new()
    target.grid_pos = Vector2i(2, 1)
    var settings := _settings("Half Paper")
    settings.texture_offset_x = 3
    settings.texture_offset_y = 5
    assert_eq(
        SaDabPattern.offset_for(target, 256, settings), Vector2(515.0, 261.0), "the chunk's document origin plus the painter's"
    )


# --- The preset ------------------------------------------------------------------


func test_a_preset_saved_with_the_page_on_reloads_with_it() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    var settings := _settings("Paper Grain")
    settings.texture_option.strength = 0.6
    settings.texture_scale = 1.5
    settings.texture_offset_x = 12
    settings.texture_invert = true
    assert_eq(store.save_preset("Papery", settings), "Papery", "saved under its name")
    var loaded := store.load_preset("Papery")
    assert_not_null(loaded, "and loads")
    if loaded == null:
        return
    var target := SettingsScript.new()
    SaPresetStore.copy_settings(loaded, target)
    assert_true(target.texture_option.enabled, "with the page on")
    assert_almost_eq(target.texture_option.strength, 0.6, 1e-6, "at its strength")
    assert_eq(target.pattern_name, "Paper Grain", "the pattern")
    assert_almost_eq(target.texture_scale, 1.5, 1e-6, "the scale")
    assert_eq(target.texture_offset_x, 12, "the offset")
    assert_true(target.texture_invert, "and the invert")
