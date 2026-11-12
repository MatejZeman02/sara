## The masking brush's own flow, rotation, scatter and mirror, from the Krita
## import to the numbers the kernel is handed.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## What the kernel does with those numbers is read back from texels in
## `test_masking_dab.gd`, which needs a device. This half needs none, so a run
## without one still holds the import and the buffer to each other.
extends "res://tests/test_framework.gd"

const KppFixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

static var scratch_preset_dir: String = SaDataRoot.path("test_k3_mask_dynamics_presets")
static var scratch_dir: String = SaDataRoot.path("test_mask_dynamics")


func after_each() -> void:
    for folder: String in [scratch_preset_dir, scratch_dir]:
        if DirAccess.dir_exists_absolute(folder):
            var dir := DirAccess.open(folder)
            for file in dir.get_files():
                dir.remove(file)
            DirAccess.remove_absolute(folder)


## The dynamics fixture through the whole import, into a store and back out onto
## a fresh settings resource, which is the path a painter's file takes.
func _imported() -> Dictionary:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join("sara-masking-dynamics.kpp")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(KppFixtures.masking_dynamics_kpp())
    file.close()
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    var results := SaKppImport.import_path(path, store)
    var settings := SettingsScript.new()
    var loaded := store.load_preset(KppFixtures.MASKING_DYNAMICS_NAME)
    if loaded != null:
        SaPresetStore.copy_settings(loaded, settings)
    return {"results": results, "settings": settings if loaded != null else null, "store": store}


## A sample at *pressure*, with the pen tilted towards *tilt*.
func _sample(pressure: float, tilt: Vector2 = Vector2.ZERO) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 7)
    info.pressure = pressure
    info.tilt_x = tilt.x
    info.tilt_y = tilt.y
    return info


# --- The import ------------------------------------------------------------------


func test_a_mask_that_turns_with_the_pen_and_scatters_carries_both() -> void:
    var imported := _imported()
    var results: Array = imported["results"]
    assert_eq(results.size(), 1, "one preset in the file")
    if results.is_empty():
        return
    var result: Dictionary = results[0]
    assert_eq(result["error"], "", "imported without a refusal")
    assert_eq(result["not_carried"], ["masking dynamics: ratio"], "the one stem with no home is named, and no other")
    assert_eq(result["unread"], [], "every option read by a row")
    var settings: SaStampBrushSettings = imported["settings"]
    assert_not_null(settings, "the store holds it")
    if settings == null:
        return
    var block: SaMaskingBrush = settings.masking
    assert_true(block.rotation_option.enabled, "the mask's rotation is on")
    assert_eq(_keys(block.rotation_option), ["tilt_direction"], "reading the pen's tilt direction")
    assert_true(block.scatter_option.enabled, "its scatter is on")
    assert_eq(_keys(block.scatter_option), ["pressure"], "on pressure")
    assert_almost_eq(block.scatter_option.strength, 2.0, 1e-6, "at two of the mask's diameters")
    assert_true(block.scatter_axis_x, "along the stroke")
    assert_false(block.scatter_axis_y, "and not across it")
    assert_true(block.flow_option.enabled, "its flow is on")
    assert_true(block.mirror_option.enabled, "and its mirror")
    assert_false(block.mirror_axis_x, "turning over no horizontal axis")
    assert_true(block.mirror_axis_y, "and the vertical one, as the preset's two checkboxes say")
    var tags := Array((imported["store"] as SaPresetStore).tags_for(KppFixtures.MASKING_DYNAMICS_NAME))
    tags.sort()
    assert_eq(
        tags, ["imported", "not carried: masking dynamics: ratio"], "the store wears the one stem and no whole-feature phrase"
    )


func test_a_stem_is_tagged_by_the_name_of_the_option_it_would_have_been() -> void:
    var options := {
        "MaskingBrush/Enabled": "true",
        "MaskingBrush/Preset/brush_definition":
        '<Brush type="auto_brush" spacing="0.3"> <MaskGenerator type="rect" diameter="24"/> </Brush>',
        "MaskingBrush/Preset/PressureSoftness": "true",
        "MaskingBrush/Preset/PressureSmudgeRate": "true",
        "MaskingBrush/Preset/PressureTexture/Strength/": "true",
        "MaskingBrush/Preset/PressureRotation": "true",
    }
    var preset := {"name": "made", "source": "made.kpp", "engine": "paintbrush", "options": {}, "resources": {}}
    preset["tags"] = PackedStringArray()
    preset["tip"] = {"kind": SaKppReader.TIP_NONE}
    for name: String in options:
        preset["options"][name] = {"type": "string", "value": options[name]}
    var applied := SaKppImport.apply(preset, SettingsScript.new())
    var lost: Array = applied["not_carried"]
    lost.sort()
    assert_eq(
        lost,
        ["masking dynamics: smudge length", "masking dynamics: softness", "masking dynamics: texture"],
        "one phrase per stem, and the rotation that carried is not among them"
    )


# --- The block --------------------------------------------------------------------


func test_a_fresh_block_carries_the_four_new_options_off() -> void:
    var block := SaMaskingBrush.new()
    for name: String in ["flow", "rotation", "scatter", "mirror"]:
        var option := block.option_for(name)
        assert_not_null(option, "%s has an option" % name)
        if option != null:
            assert_false(option.enabled, "%s is off, so no mask a painter has changes" % name)
    var dab := block.dab_for(40.0, _sample(0.3))
    assert_almost_eq(dab.rotation, 0.0, 1e-6, "an option that is off turns nothing")
    assert_eq(dab.scatter, Vector2.ZERO, "moves nothing")
    assert_eq(dab.mirror, -1, "and flips nothing")
    assert_almost_eq(block.evaluated_strength(_sample(0.3)), 1.0, 1e-6, "and the whole mask")


func test_the_flow_is_a_second_factor_on_the_strength() -> void:
    var block := SaMaskingBrush.new()
    _on(block.flow_option, "pressure")
    assert_almost_eq(block.evaluated_strength(_sample(0.4)), 0.4, 1e-4, "flow alone at 0.4 pressure is 0.4 of the mask")
    _on(block.strength_option, "pressure")
    assert_almost_eq(
        block.evaluated_strength(_sample(0.5)), 0.25, 1e-4, "and opacity and flow multiply, as they do per dab in Krita"
    )


func test_the_mask_turns_by_the_pen_angle_it_was_given() -> void:
    var block := _block()
    _on(block.rotation_option, "tilt_direction")
    var mask := SaStampBindings.of(SaBrushTipMask.load_image(""))
    mask.masking_for(block, 40.0, _sample(1.0, Vector2(0.5, 0.0)))
    var one := Vector2(mask.masking_values[SaStampBindings.MASK_COS], mask.masking_values[SaStampBindings.MASK_SIN])
    mask.masking_for(block, 40.0, _sample(1.0, Vector2(0.0, 0.5)))
    var other := Vector2(mask.masking_values[SaStampBindings.MASK_COS], mask.masking_values[SaStampBindings.MASK_SIN])
    assert_true(one.distance_to(other) > 0.1, "two pen angles hand the kernel two angles, %s and %s" % [one, other])
    var expected: float = block.dab_for(40.0, _sample(1.0, Vector2(0.0, 0.5))).rotation + block.tip.angle
    assert_almost_eq(other.x, cos(expected), 1e-5, "the evaluator's rotation on top of the tip's own angle")
    assert_almost_eq(other.y, sin(expected), 1e-5, "as a cosine and a sine")


func test_the_scatter_offsets_the_mask_within_its_amplitude_and_on_its_axis() -> void:
    var block := _block()
    _on(block.scatter_option, "pressure")
    block.scatter_axis_y = false
    var mask := SaStampBindings.of(SaBrushTipMask.load_image(""))
    var moved := false
    for pressure: float in [0.2, 0.5, 0.9]:
        var info := _sample(pressure)
        mask.masking_for(block, 40.0, info)
        var offset := Vector2(
            mask.masking_values[SaStampBindings.MASK_OFFSET_X], mask.masking_values[SaStampBindings.MASK_OFFSET_Y]
        )
        # One axis is along the drawing direction, which is image X for a pen
        # that has not moved yet.
        var reach := 40.0 * block.size * pressure
        assert_true(offset.length() <= reach + 1e-4, "at %.1f the mask moves at most %.1f pixels, %s" % [pressure, reach, offset])
        moved = moved or offset.length() > 0.01
    assert_true(moved, "and it does move")


func test_an_option_that_is_off_leaves_the_offset_at_nought() -> void:
    var mask := SaStampBindings.of(SaBrushTipMask.load_image(""))
    mask.masking_for(_block(), 40.0, _sample(0.7))
    assert_almost_eq(mask.masking_values[SaStampBindings.MASK_OFFSET_X], 0.0, 1e-6, "no scatter is no offset")
    assert_almost_eq(mask.masking_values[SaStampBindings.MASK_OFFSET_Y], 0.0, 1e-6, "on either axis")


func test_the_mirror_turns_the_mask_over_and_runs_its_angle_the_other_way() -> void:
    var block := _block()
    block.tip.angle = 0.3
    _on(block.mirror_option, "pressure")
    var mask := SaStampBindings.of(SaBrushTipMask.load_image(""))
    mask.masking_for(block, 40.0, _sample(0.2))
    assert_almost_eq(mask.masking_values[SaStampBindings.MASK_MIRROR], 1.0, 1e-6, "light pressure flips the X axis")
    assert_almost_eq(
        mask.masking_values[SaStampBindings.MASK_SIN], sin(-0.3), 1e-6, "and one flipped axis runs the angle backwards"
    )
    mask.masking_for(block, 40.0, _sample(0.9))
    assert_almost_eq(mask.masking_values[SaStampBindings.MASK_MIRROR], 0.0, 1e-6, "past the middle it does not")
    assert_almost_eq(mask.masking_values[SaStampBindings.MASK_SIN], sin(0.3), 1e-6, "and the angle is the tip's own")


func test_the_options_survive_a_save_and_a_load() -> void:
    var block := _block()
    _on(block.rotation_option, "drawing_angle")
    block.scatter_axis_x = false
    block.mirror_axis_y = true
    var path := SaDataRoot.path("test_k3_mask_block.tres")
    assert_eq(ResourceSaver.save(block, path), OK, "saved")
    var loaded: SaMaskingBrush = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
    DirAccess.remove_absolute(path)
    assert_not_null(loaded, "and loaded")
    if loaded == null:
        return
    assert_true(loaded.rotation_option.enabled, "the rotation option")
    assert_eq(_keys(loaded.rotation_option), ["drawing_angle"], "with its sensor")
    assert_false(loaded.scatter_axis_x, "the scatter's axes")
    assert_true(loaded.mirror_axis_y, "and the mirror's")


func test_the_report_names_every_option() -> void:
    var block := _block()
    _on(block.scatter_option, "pressure")
    var report := block.report()
    for name: String in ["flow_option", "rotation_option", "scatter_option", "mirror_option", "scatter_axes", "mirror_axes"]:
        assert_true(report.has(name), "the report says %s" % name)
    assert_true(bool(report["scatter_option"]["enabled"]), "and which of them are on")


static func _block() -> SaMaskingBrush:
    var block := SaMaskingBrush.new()
    block.enabled = true
    block.size = 0.5
    block.tip = SaBrushTipScript.new()
    block.tip.shape = SaBrushTipScript.Shape.RECTANGLE
    return block


static func _on(option: SaCurveOption, key: String) -> void:
    option.enabled = true
    option.set_sensor(SaSensor.create(SaSensor.id_of(key) as SaSensor.Id, true))


static func _keys(option: SaCurveOption) -> Array[String]:
    var keys: Array[String] = []
    for sensor: SaSensor in option.active_sensors():
        keys.append(SaSensor.key_of(sensor.id))
    return keys
