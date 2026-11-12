## A Krita preset in gradient map mode imports as a gradient-map brush.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The committed fixture `fixtures/sara-gradient-map.kpp` is a picture tip in
## Krita's gradient map mode, `brushApplication` 3, written by
## `kpp_fixtures.gd`. Imported, it lands in the stamp brush's Gradient Map mode
## with no tag, its gradient field empty so it reads the default, the painter's
## colour to the background colour, and the import's report says the gradient
## came from the painter's colours. A `.kpp` holds no gradient, Krita painting
## through the canvas's current one, whose default is the same pair.
##
## The last test paints one dab of the imported preset on the card, so it skips
## on a run with no rendering device, and the import itself never needs one.
extends "res://tests/test_framework.gd"

const KppFixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

const FIXTURE := "res://modules/sara-base-modules/stamp-brush/tests/fixtures/sara-gradient-map.kpp"
## The phrase the import wore before this row, and the prefix of every tag
## saying something was lost.
const OLD_PHRASE := "tip gradient map mode"

static var scratch_preset_dir: String = SaDataRoot.path("test_b2_gradient_map_presets")
static var scratch_dir: String = SaDataRoot.path("test_b2_gradient_map_kpp")

## The painter's pair, which a preset never carries and the module writes onto
## the brush, so the test writes it onto the loaded preset the same way.
const RED := Color(0.9, 0.1, 0.1, 1.0)
const BLUE := Color(0.1, 0.2, 0.9, 1.0)

## The texture one dab is painted into, the dab centred at the tip's own 64 px,
## so a picture row lands on a texel row: row r is texel row 16 + r.
const SIDE: int = 96
const CENTRE := Vector2(48, 48)
const COLUMN: int = 48
const TOP_ROW: int = 24
const MIDDLE_ROW: int = 48
const FOOT_ROW: int = 72


func after_each() -> void:
    for folder: String in [scratch_preset_dir, scratch_dir]:
        if DirAccess.dir_exists_absolute(folder):
            var dir := DirAccess.open(folder)
            for file in dir.get_files():
                dir.remove(file)
            DirAccess.remove_absolute(folder)
    for written: String in [
        SaBrushTipMask.saved_dir().path_join(KppFixtures.GRADIENT_TIP_FILE),
        SaBrushTipMask.saved_dir().path_join(KppFixtures.TIP_FILE),
        SaPatternStore.saved_dir().path_join(KppFixtures.PATTERN_FILE),
    ]:
        if FileAccess.file_exists(written):
            DirAccess.remove_absolute(written)


## The scenario imports the committed file and the suite reads the writer, so
## the two are held to each other key by key.
func test_the_committed_fixture_is_the_written_one() -> void:
    var written := SaKppReader.read_bytes(KppFixtures.gradient_map_kpp(), "sara-gradient-map.kpp")
    var committed := SaKppReader.read_file(FIXTURE)
    for key: String in ["name", "engine", "options", "tip", "format_version", "error"]:
        assert_eq(committed[key], written[key], "sara-gradient-map.kpp agrees on %s" % key)
    assert_eq(committed["error"], "", "and reads")
    var tip: Dictionary = committed["tip"]
    assert_eq(tip["kind"], SaKppReader.TIP_IMAGE, "Its tip is a picture")
    assert_eq(tip["application"], SaKppReader.APPLICATION_GRADIENT_MAP, "in Krita's gradient map mode")


## The first clause: the mode on the settings and no tag.
func test_the_fixture_imports_in_the_gradient_map_mode_and_wears_no_tag() -> void:
    var store := _store()
    var result := _import(store)
    assert_eq(result["error"], "", "imported")
    var loaded := store.load_preset(KppFixtures.GRADIENT_MAP_NAME) as SaStampBrushSettings
    assert_not_null(loaded, "and stored as a stamp brush preset")
    if loaded == null:
        return
    assert_eq(loaded.tip_mode, SaStampBrushSettings.TipMode.GRADIENT_MAP, "in the Gradient Map mode")
    assert_eq(loaded.tip.kind, SaBrushTipScript.Kind.IMAGE, "on the picture it carried")
    assert_true(loaded.tip.image_path.ends_with(KppFixtures.GRADIENT_TIP_FILE), "written to the tips folder")
    assert_eq(loaded.gradient, [], "with an empty gradient, which reads as the default")
    assert_false(Array(result["not_carried"]).has(OLD_PHRASE), "The result names no lost mode: %s" % [result["not_carried"]])
    assert_eq(result["not_carried"], [], "and nothing lost at all")
    var tags := Array(store.tags_for(KppFixtures.GRADIENT_MAP_NAME))
    for tag: String in tags:
        assert_false(tag.begins_with(SaKppImport.NOT_CARRIED_PREFIX), "and the preset wears no not-carried tag: %s" % tag)
    assert_true(tags.has(SaKppImport.IMPORTED_TAG), "only the import's own: %s" % [tags])


## The note's last clause: the report says where the gradient came from, in
## the result and on the console line, and a mask says nothing of it.
func test_the_report_says_the_gradient_came_from_the_painters_colours() -> void:
    var store := _store()
    var result := _import(store)
    assert_eq(result["notes"], [SaKppImport.GRADIENT_FROM_THE_PAINTER], "The result carries the sentence")
    var line := SaKppImport.describe(result)
    assert_true(line.contains(SaKppImport.GRADIENT_FROM_THE_PAINTER), "and the console line says it: %s" % line)
    assert_true(line.contains("painter's colour to the background colour"), "naming the pair")
    assert_true(line.contains("not carried: nothing"), "beside a preset that lost nothing")

    var mask := _import_bytes(store, KppFixtures.png_kpp(0), "sara-mask.kpp")
    assert_eq(mask["notes"], [], "A plain mask's result has no sentence")
    assert_false(SaKppImport.describe(mask).contains("gradient"), "and its line no gradient")


## The default: the ramp the imported preset paints through is the painter's
## colour to the background colour, read at the moment of asking, so it follows
## the pair as Krita's default gradient follows its foreground and background.
func test_the_imported_ramp_is_the_painters_colour_to_the_background() -> void:
    var store := _store()
    _import(store)
    var loaded := store.load_preset(KppFixtures.GRADIENT_MAP_NAME) as SaStampBrushSettings
    if loaded == null:
        assert_true(false, "the preset loads")
        return
    loaded.color = RED
    loaded.background_color = BLUE
    var ramp := loaded.gradient_ramp()
    assert_eq(ramp.size(), 2, "Two stops")
    assert_true(_near(ramp.display_at(0.0), RED, 1e-4), "starting at the painter's colour: %s" % ramp.display_at(0.0))
    assert_true(_near(ramp.display_at(1.0), BLUE, 1e-4), "and ending at the background: %s" % ramp.display_at(1.0))
    loaded.color = Color.BLACK
    assert_true(_near(loaded.gradient_ramp().display_at(0.0), Color.BLACK, 1e-4), "and it follows a new colour")


## A Lightness row switched on beside the gradient map does not take the mode
## to Lightness Map, since Krita reads that strength in its lightness map alone.
func test_a_lightness_strength_beside_the_gradient_map_keeps_the_mode() -> void:
    var preset := SaKppReader.read_bytes(KppFixtures.gradient_map_kpp(), "sara-gradient-map.kpp")
    preset["options"]["PressureLightnessStrength"] = {"type": "internal", "value": "true"}
    preset["options"]["LightnessStrengthValue"] = {"type": "internal", "value": "0.7"}
    var settings := SaStampBrushSettings.new()
    var applied := SaKppImport.apply(preset, settings)
    assert_eq(settings.tip_mode, SaStampBrushSettings.TipMode.GRADIENT_MAP, "The mode stays Gradient Map")
    assert_eq(applied["notes"], [SaKppImport.GRADIENT_FROM_THE_PAINTER], "and says where its gradient came from")


## The imported preset painted: one dab of its own tip, settled the way the
## brush's press settles it, reads the painter's colour along the tip's black
## top rows, the background along its white foot, and the ramp at the grey's
## lightness through its middle.
func test_the_imported_preset_paints_its_tip_through_the_painters_colours() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        skip("no rendering device to paint the dab on")
        return
    var store := _store()
    _import(store)
    var loaded := store.load_preset(KppFixtures.GRADIENT_MAP_NAME) as SaStampBrushSettings
    if loaded == null:
        assert_true(false, "the preset loads")
        return
    loaded.color = RED
    loaded.background_color = BLUE
    var data := _paint(rd, loaded)
    var top := _rgba(data, COLUMN, TOP_ROW)
    var middle := _rgba(data, COLUMN, MIDDLE_ROW)
    var foot := _rgba(data, COLUMN, FOOT_ROW)
    var grey := KppFixtures.GRADIENT_TIP_GREY
    var expected := _ramp_at(loaded, SaTipImage.luminance_of(Color(grey, grey, grey)))

    assert_true(top.a > 0.5 and foot.a > 0.5, "The dab covers its rows: %s, %s" % [top, foot])
    assert_true(_near(top, RED, 0.01), "Where the tip is black it reads the painter's colour: %s" % top)
    assert_true(_near(foot, BLUE, 0.01), "where it is white the background: %s" % foot)
    assert_true(_near(middle, expected, 2e-3), "and through the grey the ramp at its lightness, %s, %s" % [middle, expected])
    assert_false(_near(middle, RED, 0.1) or _near(middle, BLUE, 0.1), "which is neither end: %s" % middle)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    return store


func _import(store: SaPresetStore) -> Dictionary:
    var results := SaKppImport.import_path(FIXTURE, store)
    assert_eq(results.size(), 1, "one preset read")
    return results[0] if not results.is_empty() else {}


func _import_bytes(store: SaPresetStore, bytes: PackedByteArray, file_name: String) -> Dictionary:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join(file_name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()
    var results := SaKppImport.import_path(path, store)
    assert_eq(results.size(), 1, "one preset read from %s" % file_name)
    return results[0] if not results.is_empty() else {}


## One dab of *settings*' own tip at the tip's own size, through the bindings
## the brush binds, its ramp settled first as a press settles it.
func _paint(rd: RenderingDevice, settings: SaStampBrushSettings) -> PackedByteArray:
    var tip: Resource = settings.tip
    var mask := SaBrushTipMask.new()
    SaStampBindings.of(mask).ramp.settle(settings, null)
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(canvas.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)
    var compute := SaCompute.new("dab")
    compute.set_texture(0, canvas.rid)
    # Held to the dispatch, because the texture is freed with its last reference.
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    compute.set_texture(SaSelection.BINDING, selection.rid)
    mask = SaStampBindings.bind(compute, tip, mask, null, null, null)
    var params := SaDabPacking.pack_dab_params(
        CENTRE,
        Vector2.ZERO,
        settings.color,
        tip.half_extent(),
        0.0,
        tip.effective_fade(),
        1.0,
        SaDabGeometry.PaintMode.OVER,
        false,
        tip,
        0.0,
        0.0,
        0.0
    )
    compute.set_push_constant_float_array(params)
    @warning_ignore("integer_division")
    compute.dispatch_kernel("dab", SIDE / SaPaintContext.WORKGROUP, SIDE / SaPaintContext.WORKGROUP, 1)
    return rd.texture_get_data(canvas.rid, 0)


static func _rgba(data: PackedByteArray, x: int, y: int) -> Color:
    var at := (y * SIDE + x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


## The ramp the kernel samples at *lightness*, read the way a linear sampler
## clamped to its edge reads the texels the bindings upload.
static func _ramp_at(settings: SaStampBrushSettings, lightness: float) -> Color:
    var texels := SaStampBindings.Ramp.texels(settings.gradient_ramp(), null)
    @warning_ignore("integer_division")
    var count := texels.size() / 4
    var x := clampf(lightness * count - 0.5, 0.0, count - 1.0)
    var low := mini(int(floor(x)), count - 2)
    var t := x - low
    var a := Color(texels[low * 4], texels[low * 4 + 1], texels[low * 4 + 2], texels[low * 4 + 3])
    var b := Color(texels[low * 4 + 4], texels[low * 4 + 5], texels[low * 4 + 6], texels[low * 4 + 7])
    return a.lerp(b, t)


static func _near(a: Color, b: Color, within: float) -> bool:
    return absf(a.r - b.r) <= within and absf(a.g - b.g) <= within and absf(a.b - b.b) <= within
