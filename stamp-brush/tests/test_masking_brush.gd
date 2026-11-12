## The masking brush's second tip: the shape it travels in, the preset round
## trip and the version stamp.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Nothing here dispatches anything**, which is the point and not an omission.
## This is the settings shape, so what is provable here is that the block
## exists, that it is off until somebody switches it on, that a preset carries
## the second tip's own generator, size and spacing through a save and a load,
## and that a resource written before the field loads with the mask off. What
## the mask does to a dab is `test_masking_dab.gd`'s, and that test dispatches.
##
## The scratch directory is never `user://brush_presets`, for the reason
## `test_brush_presets.gd` gives: a suite that wrote there would leave rubbish in
## a painter's own list.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const OldSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

static var scratch_dir: String = SaDataRoot.path("test_masking_brush")


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


# --- The block itself ---------------------------------------------------------


func test_a_fresh_settings_carries_a_masking_block_that_is_off() -> void:
    var settings := SaStampBrushSettings.new()

    assert_not_null(settings.masking, "The settings carry a masking block")
    assert_false(settings.masking.enabled, "which is off, so every preset a painter has paints as it did")
    assert_false(settings.masking.active(), "and answers that it has nothing to say")
    assert_not_null(settings.masking.tip, "It carries a second tip of its own")
    assert_eq(settings.masking.size, 1.0, "at the size of the dab it would mask")


func test_the_second_tip_is_not_the_painted_one() -> void:
    var settings := SaStampBrushSettings.new()

    settings.masking.tip.ratio = 0.25

    assert_eq(settings.tip.ratio, 1.0, "The painted tip is a round one still")
    assert_true(settings.masking.tip != settings.tip, "because the two are different objects")


func test_the_mask_is_active_only_when_it_is_switched_on() -> void:
    var mask := SaMaskingBrush.new()

    assert_false(mask.active(), "Off is nothing to read")
    mask.enabled = true
    assert_true(mask.active(), "and on with a tip is a mask")
    mask.tip = null
    assert_false(mask.active(), "while on with no tip is nothing to read either")


func test_the_size_is_a_multiple_of_the_dabs_own_diameter() -> void:
    var mask := SaMaskingBrush.new()

    assert_almost_eq(mask.diameter_for(40.0), 40.0, 0.0001, "One is the dab's own size")
    mask.size = 1.5
    assert_almost_eq(mask.diameter_for(40.0), 60.0, 0.0001, "and half again is half again")
    assert_almost_eq(mask.diameter_for(10.0), 15.0, 0.0001, "at every size the painter drags")
    mask.size = 0.0
    assert_almost_eq(mask.diameter_for(40.0), SaMaskingBrush.SMALLEST_DIAMETER, 0.0001, "A mask of nothing is held at the floor")


func test_the_shaped_tip_carries_the_blocks_size_and_spacing() -> void:
    var mask := SaMaskingBrush.new()
    mask.size = 2.0
    mask.spacing = 0.4

    var tip := mask.shaped_tip(30.0)

    assert_true(tip == mask.tip, "The tip the mask shapes is the mask's own")
    assert_almost_eq(tip.diameter, 60.0, 0.0001, "carrying the diameter its size asks for")
    assert_almost_eq(tip.spacing, 0.4, 0.0001, "and the spacing beside it")


func test_a_block_with_no_tip_is_given_one_rather_than_raising() -> void:
    var mask := SaMaskingBrush.new()
    mask.tip = null

    var tip := mask.shaped_tip(20.0)

    assert_not_null(tip, "A block whose sub-resource went missing is repaired where it is used")
    assert_almost_eq(tip.diameter, 20.0, 0.0001, "and shaped as it was asked for")


# --- The dump -----------------------------------------------------------------


func test_the_report_says_what_the_block_holds() -> void:
    var mask := SaMaskingBrush.new()
    mask.enabled = true
    mask.size = 1.25
    mask.spacing = 0.3
    mask.tip.shape = SaBrushTipScript.Shape.RECTANGLE
    mask.tip.ratio = 0.5

    var block := mask.report()

    assert_true(block["enabled"], "The dump says the mask is on")
    assert_eq(block["size"], 1.25, "at the size it was set to")
    assert_eq(block["spacing"], 0.3, "with its own spacing")
    assert_eq(block["tip"]["shape"], int(SaBrushTipScript.Shape.RECTANGLE), "and the second tip's shape")
    assert_eq(block["tip"]["ratio"], 0.5, "and its ratio, which is what makes it a shape and not the dab")


func test_a_block_with_no_tip_still_reports() -> void:
    var mask := SaMaskingBrush.new()
    mask.tip = null

    var block := mask.report()

    assert_true(block["tip"].is_empty(), "A missing tip is an empty block rather than a crash")
    assert_false(block["active"], "and the mask says it has nothing to say")


# --- The mask's own options ----------------------------------------------


func test_a_fresh_block_carries_two_options_that_are_off() -> void:
    var mask := SaMaskingBrush.new()

    assert_not_null(mask.size_option, "The block carries a size option")
    assert_not_null(mask.strength_option, "and a strength option")
    assert_false(mask.size_option.enabled, "both off, so every preset a painter has paints as it did")
    assert_false(mask.strength_option.enabled, "which is the whole mask and the row's size")
    assert_true(mask.size_option.active_sensors().is_empty(), "with no sensor ticked")
    assert_true(mask.strength_option.active_sensors().is_empty(), "on either of them")


func test_the_size_option_scales_the_size_and_the_strength_option_the_strength() -> void:
    var mask := SaMaskingBrush.new()
    mask.size = 1.5
    mask.size_option.enabled = true
    mask.size_option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
    mask.strength_option.enabled = true
    mask.strength_option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))

    assert_almost_eq(mask.evaluated_size(null), 1.5, 0.0001, "With no stroke the size is the row's")
    assert_almost_eq(mask.evaluated_size(_info_at(0.2)), 0.3, 0.0001, "and a light touch shrinks it")
    assert_almost_eq(mask.evaluated_size(_info_at(1.0)), 1.5, 0.0001, "while a full press is the whole size")
    assert_almost_eq(mask.evaluated_strength(null), 1.0, 0.0001, "With no stroke the strength is the whole mask")
    assert_almost_eq(mask.evaluated_strength(_info_at(0.5)), 0.5, 0.0001, "and a half press keeps half of it")


func test_an_option_that_is_off_answers_the_neutral_values() -> void:
    var mask := SaMaskingBrush.new()
    mask.size = 0.75

    assert_almost_eq(mask.evaluated_size(_info_at(0.2)), 0.75, 0.0001, "An off size option is the row's size at any pressure")
    assert_almost_eq(mask.evaluated_strength(_info_at(0.2)), 1.0, 0.0001, "and an off strength option is the whole mask")


func test_the_report_names_the_options_and_the_ramp() -> void:
    var mask := SaMaskingBrush.new()
    mask.size = 1.0
    mask.size_option.enabled = true
    mask.size_option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))

    var block := mask.report()

    assert_true(block["size_option"]["enabled"], "The dump says the size option is on")
    assert_eq(block["size_option"]["active"], ["pressure"], "and which sensor it reads")
    assert_eq(block["size_ramp"].size(), 5, "with the size at five pressures")
    assert_true(block["size_ramp"][0] < block["size_ramp"][4], "rising, so the size slot follows the sensors")


func test_a_resource_written_before_the_options_loads_with_them_off() -> void:
    var settings := SaStampBrushSettings.new()
    settings.masking.enabled = true
    settings.masking.size_option.enabled = true
    settings.masking.strength_option.enabled = true
    settings.format_version = 5

    assert_true(settings.migrate(), "A resource below version 6 migrates")

    assert_false(settings.masking.size_option.enabled, "and the size option comes back off")
    assert_false(settings.masking.strength_option.enabled, "with the strength option off too")
    assert_true(settings.masking.enabled, "while the mask itself stays on")
    assert_eq(settings.format_version, SaStampBrushSettings.FORMAT_VERSION, "stamped at the current version")


## One stroke sample at *pressure*, which is all the mask's options read.
func _info_at(pressure: float) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 1)
    info.hovering = false
    info.pressure = pressure
    return info


# --- The preset round trip ----------------------------------------------------


func test_the_second_tip_survives_a_save_and_a_load() -> void:
    var store := _store()
    var settings := SaStampBrushSettings.new()
    settings.masking.enabled = true
    settings.masking.size = 1.75
    settings.masking.spacing = 0.42
    settings.masking.tip.generator = SaDabGeometry.Generator.SOFT
    settings.masking.tip.shape = SaBrushTipScript.Shape.RECTANGLE
    settings.masking.tip.ratio = 0.35
    settings.masking.tip.angle = 0.5
    store.save_preset("Masked", settings)

    var loaded := store.load_preset("Masked")

    assert_true(loaded.masking.enabled, "The mask comes back on")
    assert_eq(loaded.masking.tip.generator, SaDabGeometry.Generator.SOFT, "with the second tip's generator")
    assert_almost_eq(loaded.masking.size, 1.75, 0.0001, "its size")
    assert_almost_eq(loaded.masking.spacing, 0.42, 0.0001, "and its spacing")
    assert_eq(loaded.masking.tip.shape, SaBrushTipScript.Shape.RECTANGLE, "The shape travels too")
    assert_almost_eq(loaded.masking.tip.ratio, 0.35, 0.0001, "and the ratio")
    assert_almost_eq(loaded.masking.tip.angle, 0.5, 0.0001, "and the angle")


func test_the_loaded_block_is_nobodys_but_its_own() -> void:
    var store := _store()
    var settings := SaStampBrushSettings.new()
    settings.masking.enabled = true
    settings.masking.size = 1.5
    store.save_preset("Masked", settings)

    var loaded := store.load_preset("Masked")
    settings.masking.size = 3.0
    settings.masking.tip.ratio = 0.1

    assert_almost_eq(loaded.masking.size, 1.5, 0.0001, "Dragging the live row does not move what was saved")
    assert_almost_eq(loaded.masking.tip.ratio, 1.0, 0.0001, "and the second tip is a copy rather than the same object")


func test_applying_a_preset_carries_the_mask_onto_the_live_settings() -> void:
    var store := _store()
    var saved := SaStampBrushSettings.new()
    saved.masking.enabled = true
    saved.masking.size = 2.5
    store.save_preset("Masked", saved)

    var live := SaStampBrushSettings.new()
    assert_true(store.apply_preset("Masked", live), "The preset applies")

    assert_true(live.masking.enabled, "The mask arrives with it")
    assert_almost_eq(live.masking.size, 2.5, 0.0001, "at the size it was saved at")
    assert_true(live.masking != saved.masking, "and as its own object rather than the saved one")


# --- The version stamp --------------------------------------------------------


func test_a_resource_written_before_the_field_loads_with_the_mask_off() -> void:
    # The one resource that really predates the field, rather than a stand-in
    # for one: the script an older build wrote, which has no `masking` at all.
    var old_preset := OldSettingsScript.new()
    var settings := SaStampBrushSettings.new()
    SaPresetStore.copy_settings(old_preset, settings)
    settings.format_version = 1

    assert_true(settings.migrate(), "A resource below the version migrates")

    assert_not_null(settings.masking, "and comes back carrying a masking block")
    assert_false(settings.masking.enabled, "which is off, because the file it came from could not have had one on")
    assert_eq(settings.format_version, SaStampBrushSettings.FORMAT_VERSION, "stamped at the current version")


func test_a_file_at_the_old_version_has_its_mask_switched_off() -> void:
    var store := _store()
    var older := SaStampBrushSettings.new()
    older.masking.enabled = true
    older.masking.size = 2.0
    older.format_version = 3
    store.save_preset("Older", older)

    var loaded := store.load_preset("Older")

    assert_false(loaded.masking.enabled, "The step runs over a file below version 4")
    assert_almost_eq(loaded.masking.size, 2.0, 0.0001, "and touches nothing else in the block")
    assert_eq(loaded.format_version, SaStampBrushSettings.FORMAT_VERSION, "the stamp on the settings being what runs it once")


func test_the_step_runs_once_and_not_over_a_file_written_since() -> void:
    var store := _store()
    var current := SaStampBrushSettings.new()
    current.masking.enabled = true
    store.save_preset("Since", current)

    var loaded := store.load_preset("Since")

    assert_eq(loaded.format_version, SaStampBrushSettings.FORMAT_VERSION, "Written at the current version")
    assert_true(loaded.masking.enabled, "so the mask the painter switched on is still on")
    assert_false(loaded.migrate(), "and the migration has nothing left to do")


func test_a_fresh_resource_is_at_the_version_the_mask_arrived_in() -> void:
    var settings := SaStampBrushSettings.new()

    assert_true(settings.format_version >= 4, "which is what version 4 means, reading %d" % settings.format_version)
    assert_false(settings.migrate(), "and a second run over it does nothing")


# --- Helpers ------------------------------------------------------------------


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store
