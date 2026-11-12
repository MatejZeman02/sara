## The Krita import: the reader's dictionary through the mapping table
## into a preset the store holds, what did not carry said as a tag, the
## licence kept, and the table held to the fixtures.
##
## The tests hold that the two fixtures import,
## the console line names what did not carry, the tags are on the preset, and
## the mapping table has a row for every option the two fixtures carry. The
## fixtures are the committed ones under `fixtures/`, read from where the
## scenario reads them, and the pipe preset is written by `kpp_fixtures.gd` on
## the spot because a refused tip is a tag and not a file.
extends "res://tests/test_framework.gd"

const KppFixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

const FIXTURES := "res://modules/sara-base-modules/stamp-brush/tests/fixtures"
static var scratch_preset_dir: String = SaDataRoot.path("test_kpp_import_presets")
static var scratch_dir: String = SaDataRoot.path("test_kpp_import")
const SPEC := "docs/specs/brush-engine.md"
const TABLE_HEADING := "## The Krita mapping table"


func after_each() -> void:
    for folder: String in [scratch_preset_dir, scratch_dir]:
        if DirAccess.dir_exists_absolute(folder):
            var dir := DirAccess.open(folder)
            for file in dir.get_files():
                dir.remove(file)
            DirAccess.remove_absolute(folder)
    for written: String in [
        SaBrushTipMask.saved_dir().path_join(KppFixtures.TIP_FILE),
        SaBrushTipMask.saved_dir().path_join(KppFixtures.SECOND_TIP_FILE),
        SaBrushTipMask.saved_dir().path_join(KppFixtures.PIPE_FILE),
        SaBrushTipMask.saved_dir().path_join(KppFixtures.PIPE_UNKNOWN_FILE),
        SaPatternStore.saved_dir().path_join(KppFixtures.PATTERN_FILE),
    ]:
        if FileAccess.file_exists(written):
            DirAccess.remove_absolute(written)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    return store


func _loaded(store: SaPresetStore, preset_name: String) -> Resource:
    var target := SettingsScript.new()
    var loaded := store.load_preset(preset_name)
    if loaded == null:
        return null
    SaPresetStore.copy_settings(loaded, target)
    return target


func _write_pipe() -> String:
    return _write_kpp("sara-pipe.kpp", KppFixtures.pipe_kpp())


# --- The two fixtures ------------------------------------------------------------


func test_the_round_fixture_imports_onto_the_settings() -> void:
    var store := _store()
    var results := SaKppImport.import_path(FIXTURES.path_join("sara-round.kpp"), store)
    assert_eq(results.size(), 1, "one preset in the file")
    var result := results[0]
    assert_eq(result["error"], "", "imported without a refusal")
    assert_eq(result["name"], KppFixtures.ROUND_NAME, "under Krita's own name")
    assert_eq(result["not_carried"], [], "and the round fixture carries whole")
    assert_eq(result["unread"], [], "with every option read by a row")
    var settings := _loaded(store, KppFixtures.ROUND_NAME)
    assert_not_null(settings, "the store holds it")
    if settings == null:
        return
    assert_almost_eq(settings.radius, 20.0 / SaKppImport.DOCUMENT_LOWER, 1e-9, "a diameter of 40 over the default document")
    assert_eq(settings.tip.kind, SaBrushTipScript.Kind.PROCEDURAL, "a generated tip")
    assert_almost_eq(settings.hardness.value, 0.5, 1e-6, "the fades averaged onto hardness")
    assert_eq(settings.painting_mode, SettingsScript.PaintingMode.WASH, "PaintOpAction 2 is wash")
    assert_almost_eq(settings.opacity, 1.0, 1e-6, "the opacity value")
    assert_true(settings.opacity_option.enabled, "PressureOpacity on")
    assert_true(settings.opacity_option.use_curve, "reading its sensors")
    assert_eq(settings.opacity_option.active_sensors().size(), 1, "one sensor")
    assert_eq(settings.opacity_option.active_sensors()[0].id, SaSensor.Id.PRESSURE, "pressure")
    assert_eq(
        settings.opacity_option.common_curve,
        PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.75), Vector2(1.0, 1.0)]),
        "and the common curve's three points"
    )
    assert_eq(settings.opacity_option.combine, SaCurveOption.Combine.MULTIPLY, "curveMode 0 is multiply")
    assert_true(settings.size_option.enabled, "PressureSize on")
    assert_false(settings.rotation_option.enabled, "and an option the file never mentions stays off")
    assert_eq(Array(store.tags_for(KppFixtures.ROUND_NAME)), ["imported"], "tagged imported and nothing else")


func test_the_png_tip_fixture_brings_its_tip_and_its_pattern() -> void:
    var store := _store()
    var results := SaKppImport.import_path(FIXTURES.path_join("sara-png-tip.kpp"), store)
    assert_eq(results.size(), 1, "one preset")
    var result := results[0]
    assert_eq(result["error"], "", "imported")
    assert_eq(result["not_carried"], [], "and the picture and the pattern both carry")
    assert_eq(result["unread"], [], "with every option read by a row")
    var settings := _loaded(store, KppFixtures.PNG_NAME)
    assert_not_null(settings, "the store holds it under a name with a ž in it")
    if settings == null:
        return
    assert_eq(settings.tip.kind, SaBrushTipScript.Kind.IMAGE, "an image tip")
    assert_eq(settings.tip.image_path, SaBrushTipMask.saved_dir().path_join(KppFixtures.TIP_FILE), "written to the tips folder")
    assert_true(FileAccess.file_exists(settings.tip.image_path), "where a file now is")
    assert_almost_eq(settings.radius, 2.0 / SaKppImport.DOCUMENT_LOWER, 1e-9, "four texels wide at scale one")
    assert_true(settings.texture_option.enabled, "Texture/Pattern/Enabled onto the page's checkbox")
    assert_eq(settings.pattern_name, SaPatternStore.name_for(KppFixtures.PATTERN_FILE), "the pattern by the store's name")
    assert_true(
        FileAccess.file_exists(SaPatternStore.saved_dir().path_join(KppFixtures.PATTERN_FILE)),
        "written to the painter's patterns folder"
    )
    assert_true(SaPatternStore.new().has(settings.pattern_name), "where the pattern store lists it")


func test_the_bundle_imports_both_with_their_tags_and_the_licence() -> void:
    var store := _store()
    var results := SaKppImport.import_path(FIXTURES.path_join("sara-fixtures.bundle"), store)
    assert_eq(results.size(), 2, "two presets in the bundle")
    var names: Array = []
    for result: Dictionary in results:
        names.append(result["name"])
    assert_true(names.has(KppFixtures.ROUND_NAME) and names.has(KppFixtures.PNG_NAME), "both by name: %s" % [names])
    assert_eq(
        Array(store.tags_for(KppFixtures.ROUND_NAME)), ["Round", "Sara fixtures", "imported"], "the bundle's tags plus imported"
    )
    assert_eq(store.meta_for(KppFixtures.ROUND_NAME, SaKppImport.LICENCE_META), KppFixtures.BUNDLE_LICENCE, "the licence kept")
    assert_eq(store.meta_for(KppFixtures.PNG_NAME, SaKppImport.SOURCE_META), "sara-png-tip.kpp", "and the file it came from")
    assert_eq(store.meta_for(KppFixtures.PNG_NAME, SaKppImport.BUNDLE_META), "Sara fixtures", "and the bundle's title")
    assert_eq(
        store.meta_for("nobody", SaKppImport.LICENCE_META, "none"), "none", "and the fallback for a preset that is not there"
    )


func test_a_pipe_tip_imports_and_writes_its_file() -> void:
    var store := _store()
    var results := SaKppImport.import_path(_write_pipe(), store)
    assert_eq(results.size(), 1, "one preset read")
    var result := results[0]
    assert_eq(result["error"], "", "and imported")
    assert_eq(result["not_carried"], [], "with the pipe carried whole, no tag left on it")
    assert_eq(result["unread"], [], "and every option read by a row")
    var settings := _loaded(store, KppFixtures.PIPE_NAME)
    assert_not_null(settings, "the store holds it")
    if settings == null:
        return
    assert_eq(settings.tip.kind, SaBrushTipScript.Kind.IMAGE, "an image tip, the pipe being one")
    assert_eq(settings.tip.image_path, SaBrushTipMask.saved_dir().path_join(KppFixtures.PIPE_FILE), "written to the tips folder")
    assert_true(FileAccess.file_exists(settings.tip.image_path), "where a file now is")
    var mask := SaBrushTipMask.load_image(settings.tip.image_path)
    assert_true(mask.error.is_empty(), "and the file loads as a pipe: %s" % mask.error)
    assert_true(mask.has_pipe(), "with cells to advance between")
    var line := SaKppImport.describe(result)
    assert_true(line.begins_with("SaKppImport: sara-pipe.kpp imported as"), "the console line names the file: %s" % line)
    assert_false(line.contains("pipe tip"), "and no pipe tip phrase: %s" % line)


func test_a_pipe_with_an_unknown_selection_wears_the_mode_as_a_tag() -> void:
    var store := _store()
    var results := SaKppImport.import_path(_write_kpp("sara-pipe-unknown.kpp", KppFixtures.pipe_unknown_kpp()), store)
    assert_eq(results.size(), 1, "one preset read")
    var result := results[0]
    assert_eq(result["error"], "", "and imported")
    assert_eq(result["not_carried"], ["pipe selection mode sideways"], "with the mode named rather than the whole tip")
    assert_true(
        Array(store.tags_for(KppFixtures.PIPE_UNKNOWN_NAME)).has("not carried: pipe selection mode sideways"),
        "as a tag the docker can filter by"
    )
    var settings := _loaded(store, KppFixtures.PIPE_UNKNOWN_NAME)
    assert_eq(settings.tip.kind, SaBrushTipScript.Kind.PROCEDURAL, "and the tip left procedural")
    var line := SaKppImport.describe(result)
    assert_true(line.contains("not carried: pipe selection mode sideways"), "and the console says which mode: %s" % line)


func test_the_masking_fixture_brings_the_second_tip_and_wears_no_tag() -> void:
    var store := _store()
    var results := SaKppImport.import_path(_write_kpp("sara-masking.kpp", KppFixtures.masking_kpp()), store)
    assert_eq(results.size(), 1, "one preset in the file")
    var result := results[0]
    assert_eq(result["error"], "", "imported without a refusal")
    assert_eq(result["not_carried"], [], "and the masking fixture carries whole")
    assert_eq(result["unread"], [], "with every option read by a row")
    assert_eq(Array(store.tags_for(KppFixtures.MASKING_NAME)), ["imported"], "no `not carried: masking brush` tag is left on it")
    var settings := _loaded(store, KppFixtures.MASKING_NAME)
    assert_not_null(settings, "the store holds it")
    if settings == null:
        return
    var block: SaMaskingBrush = settings.masking
    assert_true(block.enabled, "the block is on")
    assert_true(block.active(), "and has a tip to read")
    assert_almost_eq(block.size, 0.75, 1e-6, "the master size coefficient is the multiplier")
    assert_almost_eq(block.spacing, 0.3, 1e-6, "the mask's own spacing, not the painted tip's 0.1")
    assert_eq(block.tip.generator, SaKppReader.GENERATORS["gauss"], "the mask's generator")
    assert_eq(block.tip.shape, SaBrushTipScript.Shape.RECTANGLE, "its shape, where the painted tip is a circle")
    assert_almost_eq(block.tip.diameter, 24.0, 1e-6, "its diameter in Krita's pixels")
    assert_almost_eq(block.tip.ratio, 0.5, 1e-6, "and its ratio")
    assert_almost_eq(block.tip.horizontal_fade, 0.4, 1e-6, "the mask keeps its own fades")
    assert_almost_eq(block.tip.vertical_fade, 0.4, 1e-6, "both of them")
    assert_almost_eq(settings.hardness.value, 0.5, 1e-6, "and the painted tip's fades still went to hardness")
    assert_eq(settings.tip.shape, SaBrushTipScript.Shape.CIRCLE, "the painted tip is untouched")
    assert_almost_eq(settings.spacing, 0.1, 1e-6, "spacing and all")


func _masking_options(extra: Dictionary) -> Dictionary:
    var options := {
        "MaskingBrush/Enabled": "true",
        "MaskingBrush/MaskingCompositeOp": "multiply",
        "MaskingBrush/UseMasterSize": "true",
        "MaskingBrush/MasterSizeCoeff": "0.75",
        "MaskingBrush/Preset/brush_definition":
        (
            '<Brush type="auto_brush" spacing="0.3">'
            + ' <MaskGenerator ratio="0.5" type="rect" id="default" diameter="24" hfade="1" vfade="1"/> </Brush>'
        ),
    }
    for name: String in extra:
        options[name] = extra[name]
    return options


func test_each_of_the_three_things_krita_s_mask_has_and_sara_s_has_not_is_named_on_its_own() -> void:
    var settings := SettingsScript.new()
    var applied := SaKppImport.apply(_preset_with(_masking_options({"MaskingBrush/MaskingCompositeOp": "linear_burn"})), settings)
    assert_eq(applied["not_carried"], ["masking composite op linear_burn"], "an op Sara's mask has not got is named by itself")
    assert_eq(settings.masking.op, SaMaskingBrush.Op.MULTIPLY, "and stays multiply")
    assert_true(settings.masking.enabled, "and the rest of the block still lands")

    settings = SettingsScript.new()
    settings.tip.diameter = 48.0
    applied = SaKppImport.apply(_preset_with(_masking_options({"MaskingBrush/UseMasterSize": "false"})), settings)
    assert_eq(applied["not_carried"], ["masking size in pixels"], "an absolute mask size is named by itself")
    assert_almost_eq(settings.masking.size, 0.5, 1e-6, "and lands as the multiple that matches at the imported size")

    settings = SettingsScript.new()
    var definition := '<Brush type="png_brush" filename="never-embedded.png" scale="1" spacing="0.3"/>'
    applied = SaKppImport.apply(_preset_with(_masking_options({"MaskingBrush/Preset/brush_definition": definition})), settings)
    assert_eq(applied["not_carried"], ["masking tip"], "a mask tip the file does not embed is named by itself")
    assert_false(settings.masking.enabled, "and the block stays off, because a mask with no shape masks nothing")


func test_the_masks_own_size_and_opacity_sensors_carry_onto_the_options() -> void:
    var sensor := '<!DOCTYPE params>\n<params id="pressure"/>\n'
    var settings := SettingsScript.new()
    var applied := (
        SaKppImport
        . apply(
            _preset_with(
                _masking_options(
                    {
                        "MaskingBrush/Preset/PressureSize": "true",
                        "MaskingBrush/Preset/SizeSensor": sensor,
                        "MaskingBrush/Preset/PressureOpacity": "true",
                        "MaskingBrush/Preset/OpacitySensor": sensor,
                    }
                )
            ),
            settings
        )
    )
    assert_eq(applied["not_carried"], [], "the mask's size and opacity sensors carry whole")
    assert_true(settings.masking.size_option.enabled, "onto the size option")
    assert_true(settings.masking.strength_option.enabled, "and the strength option")
    assert_eq(settings.masking.size_option.active_sensors().size(), 1, "with a pressure sensor on the size")
    assert_eq(settings.masking.strength_option.active_sensors().size(), 1, "and on the strength")


func test_a_ratio_sensor_on_the_mask_still_wears_a_dynamics_tag_naming_it() -> void:
    var settings := SettingsScript.new()
    var applied := SaKppImport.apply(_preset_with(_masking_options({"MaskingBrush/Preset/PressureRatio": "true"})), settings)
    assert_eq(applied["not_carried"], ["masking dynamics: ratio"], "a stem the mask has no home for is still named, by name")
    assert_false(settings.masking.size_option.enabled, "and neither option was touched")
    assert_false(settings.masking.strength_option.enabled, "by a stem it does not own")


func test_a_masking_brush_that_is_off_or_has_no_definition_carries_what_it_can() -> void:
    var settings := SettingsScript.new()
    var applied := SaKppImport.apply(
        _preset_with({"MaskingBrush/Enabled": "false", "MaskingBrush/MaskingCompositeOp": "burn"}), settings
    )
    assert_eq(applied["not_carried"], [], "a block Krita has switched off costs nothing")
    assert_false(settings.masking.enabled, "and leaves the mask off")

    settings = SettingsScript.new()
    applied = SaKppImport.apply(_preset_with({"MaskingBrush/Enabled": "true"}), settings)
    assert_eq(applied["not_carried"], ["masking brush"], "a block switched on with no definition is the whole feature lost")
    assert_false(settings.masking.enabled, "and the mask stays off")


# --- The mask softness curve --------------------------------------------------


func _write_kpp(file_name: String, bytes: PackedByteArray) -> String:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join(file_name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()
    return path


## The soft fixture's generator through the import onto the tip's own `Curve`.
## Krita's points travel unchanged, because both sides are coverage against the
## squared normalised radius, and the old phrase is gone.
func test_a_softness_curve_lands_on_the_tips_curve() -> void:
    var store := _store()
    var results := SaKppImport.import_path(FIXTURES.path_join("sara-soft.kpp"), store)
    assert_eq(results.size(), 1, "one preset in the file")
    var result := results[0]
    assert_eq(result["error"], "", "imported without a refusal")
    assert_eq(result["not_carried"], [], "and nothing was left behind")
    assert_eq(result["unread"], [], "with every option read by a row")
    assert_false(
        Array(store.tags_for(KppFixtures.SOFT_NAME)).has("not carried: mask softness curve"),
        "the old phrase for the curve is gone"
    )
    var settings := _loaded(store, KppFixtures.SOFT_NAME)
    assert_not_null(settings, "the store holds it")
    if settings == null:
        return
    assert_eq(settings.tip.generator, 2, "the softbrush generator")
    var curve: Curve = settings.tip.softness_curve
    assert_not_null(curve, "the tip carries a curve")
    assert_eq(curve.point_count, 4, "the four points Krita wrote")
    assert_almost_eq(curve.get_point_position(0).x, 0.0, 1e-6, "the first at the centre")
    assert_almost_eq(curve.get_point_position(0).y, 1.0, 1e-6, "fully covered")
    assert_almost_eq(curve.get_point_position(2).x, 0.75, 1e-6, "the third where the fall begins")
    assert_almost_eq(curve.get_point_position(2).y, 0.55, 1e-6, "at just over half")
    assert_almost_eq(curve.get_point_position(3).y, 0.0, 1e-6, "and nothing at the rim")
    var table: PackedFloat32Array = settings.tip.softness_table()
    assert_almost_eq(table[0], 1.0, 1e-4, "the sampled table starts opaque")
    assert_almost_eq(table[table.size() - 1], 0.0, 1e-4, "and ends clear")
    var descends := true
    for i in range(1, table.size()):
        if table[i] > table[i - 1] + 1e-5:
            descends = false
    assert_true(descends, "and never climbs on the way")
    @warning_ignore("integer_division")
    var middle := table.size() / 2
    assert_true(table[middle] > 0.9, "holding coverage past the middle, which the default falloff does not")


## The committed file and `kpp_fixtures.gd` are one preset, the way
## `test_kpp_reader.gd` holds the other two, so the scenario's import and the
## test above cannot come apart.
func test_the_committed_soft_fixture_is_the_written_one() -> void:
    var written := SaKppReader.read_file(_write_kpp("sara-soft-written.kpp", KppFixtures.soft_kpp()))
    var committed := SaKppReader.read_file(FIXTURES.path_join("sara-soft.kpp"))
    for key: String in ["name", "engine", "options", "tip", "format_version", "error"]:
        assert_eq(committed[key], written[key], "sara-soft.kpp agrees on %s" % key)


## The identity is what a Krita preset's XML falls back to when nobody drew a
## curve, and it is a tip clear in the middle and opaque at the rim. It is
## refused for the default falloff and wears a phrase of its own, so the
## docker's tag row keeps the presets that lost a drawn curve apart from the
## ones that never had one.
func test_an_identity_curve_is_refused_and_says_which_refusal_it_is() -> void:
    var settings := SettingsScript.new()
    var before: PackedFloat32Array = settings.tip.softness_table()
    var applied := SaKppImport.apply(_soft_preset("0,0;1,1;"), settings)
    assert_eq(applied["not_carried"], ["mask softness curve, it does not descend"], "the identity is named as itself")
    assert_eq(settings.tip.softness_table(), before, "and the default falloff stands")

    applied = SaKppImport.apply(_soft_preset("0,0.2;0.5,0.5;1,0.9;"), settings)
    assert_eq(applied["not_carried"], ["mask softness curve, it does not descend"], "so is any curve that climbs")
    assert_eq(settings.tip.softness_table(), before, "which would paint a hole")

    applied = SaKppImport.apply(_soft_preset("nothing,readable;"), settings)
    assert_eq(applied["not_carried"], ["mask softness curve"], "a curve nobody can parse is the whole feature missing")
    assert_eq(settings.tip.softness_table(), before, "and the default stands there too")

    applied = SaKppImport.apply(_soft_preset(KppFixtures.SOFT_CURVE), settings)
    assert_eq(applied["not_carried"], [], "and a descending one carries")
    assert_eq(settings.tip.softness_curve.point_count, 4, "onto the tip")


## A preset dictionary whose auto brush carries *curve*, built the way the
## reader hands one over: the `MaskGenerator` attributes under `tip`.
func _soft_preset(curve: String) -> Dictionary:
    var preset := _preset_with({})
    preset["options"][SaKppReader.BRUSH_DEFINITION] = {"type": "string", "value": ""}
    preset["tip"] = {
        "kind": SaKppReader.TIP_GENERATED,
        "brush": {"type": "auto_brush"},
        "generator": {"id": "softbrush", "diameter": "90", "hfade": "1", "vfade": "1", "softness_curve": curve},
    }
    return preset


# --- The table's rows --------------------------------------------------------------


func _preset_with(options: Dictionary) -> Dictionary:
    var out := {
        "name": "made",
        "source": "made.kpp",
        "engine": "paintbrush",
        "options": {},
        "resources": {},
        "tags": PackedStringArray(),
        "licence": "",
        "error": "",
        "tip": {"kind": SaKppReader.TIP_NONE}
    }
    for name: String in options:
        out["options"][name] = {"type": "string", "value": String(options[name])}
    return out


func test_a_blend_mode_sara_lacks_is_not_carried_and_a_known_one_lands() -> void:
    var settings := SettingsScript.new()
    var applied := SaKppImport.apply(_preset_with({"CompositeOp": "behind"}), settings)
    assert_eq(applied["not_carried"], ["blend mode behind"], "an unknown composite op is named")
    assert_eq(settings.blend_mode, &"normal", "and the preset paints Normal")
    applied = SaKppImport.apply(_preset_with({"CompositeOp": "multiply", "EraserMode": "false"}), settings)
    assert_eq(applied["not_carried"], [], "a known one carries")
    assert_eq(settings.blend_mode, &"multiply", "as itself")


func test_the_features_with_no_home_each_wear_one_phrase() -> void:
    var settings := SettingsScript.new()
    var applied := (
        SaKppImport
        . apply(
            _preset_with(
                {
                    "MaskingBrush/Enabled": "true",
                    "MaskingBrush/Something": "1",
                    "ColorSource/Type": "total_random",
                    # Hue and Darken carry, so they wear no phrase and Gradient
                    # is the colour stem that still does.
                    "Pressureh": "true",
                    "PressureDarken": "true",
                    "PressureGradient": "true",
                    "Texture/Pattern/Enabled": "true",
                    # Five is one of the modes past subtract, which have no
                    # arithmetic. One is carried onto the Texture page's Mode
                    # row, so it is no longer a feature with no home.
                    "Texture/Pattern/TexturingMode": "5",
                    "Mystery": "42",
                }
            ),
            settings
        )
    )
    assert_eq(
        applied["not_carried"],
        ["texturing mode", "masking brush", "colour source", "colour gradient"],
        "one phrase per feature, and a colour stem Sara has no option for by name"
    )
    assert_eq(applied["unread"], ["Mystery"], "and the param no row names is listed")


func test_the_sensor_document_reads_a_list_with_lengths_and_a_curve() -> void:
    var xml := (
        '<!DOCTYPE params>\n<params id="sensorslist">'
        + '<sensor id="distance" length="120" periodic="0"/>'
        + '<sensor id="drawingangle" angleOffset="45" lockedAngleMode="1"><curve>0,1;1,0;</curve></sensor>'
        + '<sensor id="unknownthing"/></params>'
    )
    var read := SaKppSensors.parse_sensors(xml)
    assert_eq(read.size(), 2, "two known sensors, the unknown skipped")
    assert_eq(read[0]["key"], "distance", "distance first")
    assert_eq(int(read[0]["length"]), 120, "with its length")
    assert_false(bool(read[0]["periodic"]), "and periodic off")
    assert_eq(read[1]["key"], "drawing_angle", "then the drawing angle")
    assert_almost_eq(float(read[1]["angle_offset"]), 45.0, 1e-6, "with its offset")
    assert_true(bool(read[1]["lock_angle"]), "locked")
    assert_eq(read[1]["curve"], PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, 0.0)]), "and its own curve")
    var settings := SettingsScript.new()
    SaKppImport.apply(_preset_with({"PressureRotation": "true", "RotationSensor": xml, "RotationcurveMode": "2"}), settings)
    assert_true(settings.rotation_option.enabled, "the stem lands on the option")
    assert_eq(settings.rotation_option.active_sensors().size(), 2, "with the two sensors on")
    assert_eq(settings.rotation_option.combine, SaCurveOption.Combine.MAXIMUM, "and curveMode 2 is maximum")


# --- A bundle of brush tips -----------------------------------------


## *path* through the door's `preset_import` step with no tree, which is what a
## suite has to hand, reporting into *out_dir*.
func _through_the_door(out_dir: String, path: String) -> String:
    return SaKppImportCapture.capture(null, out_dir, path)


func _write_bundle(file_name: String, writer: Callable) -> String:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join(file_name)
    writer.call(ProjectSettings.globalize_path(path))
    return path


## A Krita export of a brushes folder holds no preset at all. The tips in it
## are the point of the file, so they come across into the painter's tip
## folder and the line says how many, rather than the bundle being refused.
func test_a_bundle_of_brushes_and_no_preset_imports_the_tips() -> void:
    var path := _write_bundle("tips.bundle", KppFixtures.tips_bundle)
    var before := SaBrushTipMask.available()
    var results := SaKppImport.import_path(path, _store())
    assert_eq(results.size(), 1, "one answer for a bundle that held no preset")
    assert_eq(String(results[0]["error"]), "", "and it is not a refusal")
    assert_eq(int(results[0].get("tips", 0)), 2, "the two tips the loader reads were written")
    var available := SaBrushTipMask.available()
    assert_true(available.has(SaBrushTipMask.saved_dir().path_join(KppFixtures.TIP_FILE)), "the first tip is in the tip list")
    assert_true(available.has(SaBrushTipMask.saved_dir().path_join(KppFixtures.SECOND_TIP_FILE)), "and the second beside it")
    assert_eq(available.size(), before.size() + 2, "and only those two, the pipe not being a tip Sara reads")


## The line a painter reads for such a bundle: how many arrived, and the name
## of every brush that did not, since a bundle of three that lists two leaves
## a question the console has to answer.
func test_the_line_for_a_bundle_of_brushes_counts_them_and_names_what_it_passed_over() -> void:
    var path := _write_bundle("tips.bundle", KppFixtures.tips_bundle)
    var line := SaKppImport.describe(SaKppImport.import_path(path, _store())[0])
    assert_true(line.contains("holds no preset"), "the line says the bundle carried no preset: %s" % line)
    assert_true(line.contains("2 brush tips into the tip list"), "and how many tips it carried instead: %s" % line)
    assert_true(line.contains(KppFixtures.PIPE_FILE), "and names the pipe it passed over: %s" % line)
    assert_false(line.contains("refused"), "and it is not the word refused: %s" % line)


## With neither a preset nor a tip the bundle is still refused, and the
## sentence names both folders looked in and what the zip did hold, which is
## what the old one, naming only `paintoppresets/`, left a painter guessing.
func test_a_bundle_of_neither_names_both_folders_and_what_it_held() -> void:
    var path := _write_bundle("empty.bundle", KppFixtures.empty_bundle)
    var results := SaKppImport.import_path(path, _store())
    assert_eq(results.size(), 1, "one answer, a refusal")
    var error := String(results[0]["error"])
    assert_true(error.contains(SaKppReader.BUNDLE_PRESETS_DIR), "the sentence names the preset folder: %s" % error)
    assert_true(error.contains(SaKppReader.BUNDLE_BRUSHES_DIR), "and the brushes folder: %s" % error)
    assert_true(error.contains("preview.png"), "and what the bundle did hold: %s" % error)
    assert_eq(int(results[0].get("tips", 0)), 0, "and nothing was written to the tip folder")


## A bundle that does hold presets is untouched by any of the above: the two
## committed fixtures still import as two presets and carry no tips row.
func test_a_bundle_with_presets_imports_the_same_two() -> void:
    var results := SaKppImport.import_path(FIXTURES.path_join("sara-fixtures.bundle"), _store())
    assert_eq(results.size(), 2, "the committed bundle's two presets, and no answer beside them")
    for result: Dictionary in results:
        assert_eq(String(result["error"]), "", "each one stored")
        assert_eq(int(result.get("tips", 0)), 0, "and none of them is a bundle of tips")


## The template is the settings of the tool in front of the painter, and with
## the gradient picked it is not a brush's at all. The bundle imports anyway,
## onto the brush rather than onto the gradient: no error from a field the
## template has no member for, and both presets read back as brush presets.
func test_a_bundle_imports_through_a_settings_resource_that_is_not_a_brushes() -> void:
    var store := _store()
    var results := SaKppImport.import_path(FIXTURES.path_join("sara-fixtures.bundle"), store, SaGradientEnds.new())
    assert_eq(results.size(), 2, "the committed bundle's two presets")
    for result: Dictionary in results:
        assert_eq(String(result["error"]), "", "each one stored rather than refused")
        assert_eq(int(result.get("tips", 0)), 0, "and none of them is a bundle of tips")
    var settings := _loaded(store, KppFixtures.ROUND_NAME)
    assert_not_null(settings, "the round preset is a brush preset the store holds")
    if settings != null:
        assert_eq(settings.tip.diameter, 40.0, "carrying the tip the bundle had, so the fields did land")


## The report goes beside the shots when the caller names the run's folder, which
## only a capture has.
func test_the_report_is_written_when_the_runner_has_an_out_dir() -> void:
    var path := _write_bundle("tips.bundle", KppFixtures.tips_bundle)
    var line := _through_the_door(scratch_dir, path)
    assert_true(line.contains("2 brush tip(s)"), "the summary counts the tips rather than the answers: %s" % line)
    var report := scratch_dir.path_join(SaKppImportCapture.REPORT_FILE)
    assert_true(FileAccess.file_exists(report), "and the report landed in the runner's folder")
    assert_true(FileAccess.get_file_as_string(report).contains("holds no preset"), "carrying the same line")


## The presets page has no folder when no capture is running, and says so with an
## empty string. The folder is not read off whatever node is handed in, because a
## docker has no such member: `Object.get` answers null, `String(null)` is
## "<null>", and every import a painter pressed the button for reached for
## "<null>/import.txt" and warned. There is nowhere to write, so nothing is
## written and nothing is said.
func test_a_runner_with_no_out_dir_writes_no_report() -> void:
    var path := _write_bundle("tips.bundle", KppFixtures.tips_bundle)
    var line := _through_the_door("", path)
    assert_true(line.contains("2 brush tip(s)"), "the import ran and answered: %s" % line)
    assert_false(
        FileAccess.file_exists(scratch_dir.path_join(SaKppImportCapture.REPORT_FILE)),
        "and no report was written, the runner having no folder to write one in"
    )
    assert_false(DirAccess.dir_exists_absolute("<null>"), "least of all under a folder called <null>")


# --- The mapping table ----------------------------------------------------------------


## True, after recording why, when this copy of the source has no spec page to
## hold the mapping table against.
func _lacks_the_spec() -> bool:
    var path := ProjectSettings.globalize_path("res://").path_join("..").path_join(SPEC).simplify_path()
    if FileAccess.file_exists(path):
        return false
    skip("the brush engine spec is not in this copy of the source")
    return true


func _spec_table_names() -> Dictionary:
    var path := ProjectSettings.globalize_path("res://").path_join("..").path_join(SPEC).simplify_path()
    var file := FileAccess.open(path, FileAccess.READ)
    assert_not_null(file, "the mapping table file is at %s" % path)
    if file == null:
        return {}
    var text := file.get_as_text()
    var start := text.find(TABLE_HEADING)
    var end := text.find("\n## ", start + TABLE_HEADING.length())
    var section := text.substr(start, end - start if end > start else -1)
    var names: Dictionary = {}
    var regex := RegEx.new()
    regex.compile("`([^`]+)`")
    for line: String in section.split("\n"):
        if not line.begins_with("|"):
            continue
        var cell := line.split("|")[1]
        for found: RegExMatch in regex.search_all(cell):
            var name := found.get_string(1)
            if name.contains("<S>"):
                for stem: String in SaKppSensors.OPTION_STEMS:
                    names[name.replace("<S>", stem)] = true
            else:
                names[name] = true
    return names


func test_the_table_has_a_row_for_every_option_the_fixtures_carry() -> void:
    if _lacks_the_spec():
        return
    var names := _spec_table_names()
    assert_true(names.size() > 30, "the table names its options: %d" % names.size())
    var missing: Array[String] = []
    for fixture: String in ["sara-round.kpp", "sara-png-tip.kpp"]:
        for preset: Dictionary in SaKppReader.read_path(FIXTURES.path_join(fixture)):
            for option: String in preset["options"]:
                if not names.has(option) and not missing.has(option):
                    missing.append(option)
    assert_eq(missing, [], "every option the two fixtures carry has a row in the mapping table")


# --- The colour stems ---------------------------------------------


func _write_colour() -> String:
    return _write_kpp("sara-colour.kpp", KppFixtures.colour_kpp())


## The five stems land on the colour options with their sensors, and the
## preset wears no colour tag at all, because every colour thing it has is one
## Sara carries.
func test_the_colour_fixture_carries_the_five_options_and_their_sensors() -> void:
    var store := _store()
    var results := SaKppImport.import_path(FIXTURES.path_join("sara-colour.kpp"), store)
    assert_eq(results.size(), 1, "one preset in the file")
    var result := results[0]
    assert_eq(result["error"], "", "imported without a refusal")
    for phrase: String in result["not_carried"]:
        assert_false(phrase.begins_with("colour"), "no colour phrase, and it wore %s" % phrase)
    var settings := _loaded(store, KppFixtures.COLOUR_NAME)
    assert_not_null(settings, "and it loads back")
    var expected := {
        "hue_option": ["fuzzy_per_dab", 0.35],
        "saturation_option": ["pressure", 0.6],
        "value_option": ["speed", 1.0],
        "darken_option": ["distance", 0.8],
        "mix_option": ["pressure", 1.0],
    }
    for field: String in expected:
        var option := settings.get(field) as SaCurveOption
        assert_true(option.enabled, "%s is on" % field)
        assert_almost_eq(option.strength, float(expected[field][1]), 1e-4, "%s carries its strength" % field)
        var keys: Array[String] = []
        for sensor: SaSensor in option.active_sensors():
            keys.append(SaSensor.KEYS[sensor.id])
        assert_eq(keys, [String(expected[field][0])] as Array[String], "%s reads the sensor its stem named" % field)
    assert_eq(settings.color_source, SaColorDynamics.Source.PLAIN, "and the plain colour source lands on the enum")


## Mix is the one stem turned over on the way in, so the fixture's curve comes
## back with every value flipped and its positions kept.
func test_the_mix_curve_is_turned_over_because_the_two_mixes_run_opposite_ways() -> void:
    var store := _store()
    SaKppImport.import_path(FIXTURES.path_join("sara-colour.kpp"), store)
    var settings := _loaded(store, KppFixtures.COLOUR_NAME)
    var curve := (settings.get("mix_option") as SaCurveOption).common_curve
    assert_eq(curve.size(), 3, "the three points the fixture wrote")
    assert_almost_eq(curve[0].y, 1.0, 1e-6, "Krita's nought, the background, is Sara's one")
    assert_almost_eq(curve[1].x, 0.5, 1e-6, "the middle point keeps its position")
    assert_almost_eq(curve[1].y, 0.8, 1e-6, "and its 0.2 of the painting colour is 0.8 of the background")
    assert_almost_eq(curve[2].y, 0.0, 1e-6, "and Krita's one, the painting colour, is Sara's nought")
    var hue := (settings.get("hue_option") as SaCurveOption).common_curve
    assert_almost_eq(hue[1].y, 1.0, 1e-6, "while a stem that is not Mix keeps its curve the right way up")


## A preset with only Gradient on wears the
## phrase for Gradient and no longer the one for all seven.
func test_a_preset_with_only_gradient_on_is_tagged_for_gradient() -> void:
    var settings := SettingsScript.new()
    var applied := SaKppImport.apply(_preset_with({"PressureGradient": "true", "GradientValue": "1"}), settings)
    assert_true(applied["not_carried"].has("colour gradient"), "tagged colour gradient")
    assert_false(applied["not_carried"].has("colour dynamics"), "and not colour dynamics, which no longer exists")
    assert_false(applied["unread"].has("GradientValue"), "and its stem's params are read, not left over")


## Lightness is carried, so the old tag is gone and the number it
## writes is what the preset said.
##
## Three cases in one method because the three are one behaviour: a value
## written, a bare switch, and a preset that never mentions the stem.
func test_a_preset_with_lightness_on_is_carried_onto_the_tip() -> void:
    var settings := SettingsScript.new()
    var applied := SaKppImport.apply(
        _preset_with({"PressureLightnessStrength": "true", "LightnessStrengthValue": "0.4"}), settings
    )
    assert_false(applied["not_carried"].has("colour lightness"), "no longer tagged, the row exists")
    assert_eq(applied["not_carried"], [], "and nothing else is lost either")
    assert_almost_eq(settings.tip.lightness_strength, 0.4, 1e-6, "the preset's own value lands on the tip")
    assert_false(applied["unread"].has("LightnessStrengthValue"), "and its stem's params are read, not left over")

    # A preset that switched the map on and wrote no value gets the whole of it,
    # which is what a bare switch means everywhere else in the format.
    var bare := SettingsScript.new()
    var switched := SaKppImport.apply(_preset_with({"PressureLightnessStrength": "true"}), bare)
    assert_eq(switched["not_carried"], [], "A switch with no value beside it is carried")
    assert_almost_eq(bare.tip.lightness_strength, 1.0, 1e-6, "at full strength")

    # And a preset that never mentions the stem leaves the row off, so a brush
    # nobody switched the map on paints what it always did.
    var silent := SettingsScript.new()
    var untouched := SaKppImport.apply(_preset_with({}), silent)
    assert_eq(untouched["not_carried"], [], "and a stem nobody mentioned tags nothing")
    assert_almost_eq(silent.tip.lightness_strength, 0.0, 1e-6, "and leaves the row off")


## A colour source Sara has not got is still tagged, and plain and gradient,
## which Sara carries, are not.
func test_only_a_colour_source_sara_lacks_is_tagged() -> void:
    var plain := SaKppImport.apply(_preset_with({"ColorSource/Type": "plain"}), SettingsScript.new())
    assert_false(plain["not_carried"].has("colour source"), "plain carries")
    var gradient := SaKppImport.apply(_preset_with({"ColorSource/Type": "gradient"}), SettingsScript.new())
    assert_false(gradient["not_carried"].has("colour source"), "a gradient source carries")
    var random := SaKppImport.apply(_preset_with({"ColorSource/Type": "total_random"}), SettingsScript.new())
    assert_true(random["not_carried"].has("colour source"), "a total random source is tagged")


## The mapping table names a Sara setting for each
## of the five, in a row that does not say not carried.
func test_the_mapping_table_names_a_sara_setting_for_each_of_the_five() -> void:
    if _lacks_the_spec():
        return
    var path := ProjectSettings.globalize_path("res://").path_join("..").path_join(SPEC).simplify_path()
    var text := FileAccess.get_file_as_string(path)
    var wanted := {
        "Pressureh": "hue_option",
        "Pressures": "saturation_option",
        "Pressurev": "value_option",
        "PressureDarken": "darken_option",
        "PressureMix": "mix_option",
    }
    for stem: String in wanted:
        var row := ""
        for line: String in text.split("\n"):
            if line.begins_with("|") and line.split("|")[1].contains("`%s`" % stem):
                row = line
        assert_false(row.is_empty(), "%s has a row" % stem)
        assert_true(row.contains("`%s`" % wanted[stem]), "%s names %s" % [stem, wanted[stem]])
        assert_false(row.contains("**not carried**"), "and %s is not a not-carried row" % stem)


## The committed colour fixture is what the writer writes, key by key, the way
## the soft one is held: the scenario reads the committed file and the test
## reads the writer, and nothing else would notice the two drifting.
func test_the_committed_colour_fixture_is_the_written_one() -> void:
    var written := SaKppReader.read_file(_write_colour())
    var committed := SaKppReader.read_file(FIXTURES.path_join("sara-colour.kpp"))
    for key: String in ["name", "engine", "options", "tip", "format_version", "error"]:
        assert_eq(committed[key], written[key], "sara-colour.kpp agrees on %s" % key)
