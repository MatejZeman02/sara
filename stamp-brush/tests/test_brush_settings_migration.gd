## The settings resource, its nine curve options and the migration into two of
## them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The grading number is the one the note names: the migrated curve's response
## has to match `pow(p, gamma * 2.4)` to within 0.01 at eleven points from 0 to
## 1. It is measured through `SaSensor.parameter`, not against the control
## points, because the control points are not what a dab reads: a dab reads a
## 256-entry table sampled off a monotone cubic through them and interpolated
## linearly, and every one of those three steps can lose the shape.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const OldSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")

## The recipes the module ships, which `install_shipped` is handed by whoever
## calls it rather than preloading itself.
const SaShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## Never the real `user://brush_presets`, for the reason `test_brush_presets.gd`
## gives: a suite that wrote there would leave rubbish in the painter's own list.
static var scratch_dir: String = SaDataRoot.path("test_brush_settings_migration")

## What the migration's note grades on, the dab at three presses, and the
## tolerance it grades to. A curve of three points holds that tolerance, where
## a finer one would need more points.
const GRADE_PRESSURES: Array[float] = [0.25, 0.5, 0.75]
const GRADE_TOLERANCE: float = 0.02


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


# --- The fresh resource -------------------------------------------------------


func test_a_fresh_resource_is_migrated_by_its_own_constructor() -> void:
    var settings := SaStampBrushSettings.new()

    assert_eq(settings.format_version, SaStampBrushSettings.FORMAT_VERSION, "A new object is already at the new version")
    assert_false(settings.migrate(), "and running the migration again does nothing")


func test_a_fresh_resource_carries_the_defaults_a_new_brush_should_have() -> void:
    var settings := SaStampBrushSettings.new()

    # The accident the spec names: the old defaults are opacity by pressure on
    # at gamma 0.5 and size by pressure off, so the constructor's migration
    # produces exactly what a new brush wants without a second table of values.
    assert_false(settings.size_option.enabled, "Size by pressure is off for a new brush")
    assert_true(settings.opacity_option.enabled, "and opacity by pressure is on")
    assert_true(settings.opacity_option.use_curve, "with its sensors read")
    assert_eq(settings.opacity_option.active_sensors().size(), 1, "which is one sensor")
    assert_eq(
        int(settings.opacity_option.active_sensors()[0].id),
        int(SaSensor.Id.PRESSURE),
        "and it is pressure, the only sensor the old fields could mean"
    )


func test_an_option_the_migration_does_not_build_holds_no_sensors() -> void:
    var settings := SaStampBrushSettings.new()

    for key: String in ["flow", "ratio", "softness", "rotation", "scatter", "spacing", "rate"]:
        var option: SaCurveOption = settings.options()[key]
        assert_true(option.sensors.is_empty(), "%s carries no sensor" % key)


## The probe of 2026-09-08, kept as an assertion. It found every option built
## with `use_curve` off, so a sensor a painter ticked was dead until they found
## "Enable pen settings", and the class and Krita both default it on.
func test_a_fresh_resource_reads_its_sensors_on_every_option() -> void:
    var settings := SaStampBrushSettings.new()

    for key: String in settings.options():
        assert_true(settings.options()[key].use_curve, "%s is born reading its sensors" % key)
    assert_true(settings.format_version >= 3, "which is what version 3 means, and every version since keeps")


## The other half of the same probe: on costs nothing while nothing is ticked.
##
## An option with the curve on and an empty sensor set answers its `strength`,
## exactly as it did with the curve off, because `ensure_one_active()` no longer
## invents pressure for a set nobody has touched. Flow is the case that would
## have shown: it has never been modulated by anything in Sara, it is enabled,
## and a pressure sensor at the press would have made a light stroke thin.
func test_an_untouched_option_answers_its_constant_and_gains_no_sensor() -> void:
    var settings := SaStampBrushSettings.new()
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 1)
    info.pressure = 0.25

    settings.flow_option.begin_stroke()

    assert_true(settings.flow_option.sensors.is_empty(), "The press gave flow no sensor")
    assert_almost_eq(settings.flow_option.size_like(info), 1.0, 1e-6, "and it answers its strength at any pressure")


func test_the_size_option_is_off_but_still_has_its_range() -> void:
    var settings := SaStampBrushSettings.new()

    assert_false(settings.size_option.enabled, "Off")
    assert_almost_eq(settings.size_option.strength_max, 1.0, 1e-6, "and still bounded, because the range is the option's")


# --- The options and their ranges ---------------------------------------------


func test_the_options_are_all_there_and_carry_the_spec_ranges() -> void:
    var settings := SaStampBrushSettings.new()
    var bounds := {
        "size": [0.0, 1.0],
        "opacity": [0.0, 1.0],
        "flow": [0.0, 1.0],
        "ratio": [0.0, 1.0],
        "softness": [0.1, 1.0],
        "hardness": [0.0, 1.0],
        "rotation": [0.0, 1.0],
        "scatter": [0.0, 5.0],
        "spacing": [0.0, 1.0],
        "rate": [0.0, 1.0],
        # The ordinary 0 to 1 even though the three read as signed offsets: the
        # move onto -1 to 1 happens where they are read, so the strength row
        # here means what it means on every other page.
        "hue": [0.0, 1.0],
        # The two amounts, the same range for the same reason read once more:
        # an amount on 0 to 1 is what the reducer wants, and the strength row
        # means the same thing here as everywhere.
        "darken": [0.0, 1.0],
        "mix": [0.0, 1.0],
        "saturation": [0.0, 1.0],
        "value": [0.0, 1.0],
        "texture": [0.0, 1.0],
        "sharpness": [0.0, 1.0],
        "mirror": [0.0, 1.0],
    }
    var options := settings.options()

    assert_eq(
        options.size(),
        bounds.size(),
        (
            "Every option the bounds table names and no more, hardness, sharpness, the three "
            + "colour offsets, the two colour amounts and mirror included"
        )
    )
    for key: String in bounds:
        var option: SaCurveOption = options.get(key)
        assert_not_null(option, "%s exists" % key)
        assert_almost_eq(option.strength_min, float(bounds[key][0]), 1e-6, "%s floor" % key)
        assert_almost_eq(option.strength_max, float(bounds[key][1]), 1e-6, "%s ceiling" % key)


func test_the_two_always_on_options_are_enabled_and_the_checkable_ones_are_not() -> void:
    var settings := SaStampBrushSettings.new()

    assert_true(settings.opacity_option.enabled, "Opacity draws no checkbox, so it is on")
    assert_true(settings.flow_option.enabled, "and neither does flow")
    for key: String in ["ratio", "softness", "hardness", "rotation", "scatter", "spacing", "rate", "hue", "saturation", "value"]:
        assert_false(settings.options()[key].enabled, "%s is checkable and starts off" % key)


# --- The curve ----------------------------------------------------------------


func test_the_migrated_opacity_curve_answers_the_old_response() -> void:
    var settings := SaStampBrushSettings.new()

    # gamma 0.5 times the tool's own 2.4 is an exponent of 1.2.
    _assert_response(settings.opacity_option, 1.2, "opacity at the default gamma")


func test_the_migrated_size_curve_answers_the_old_response() -> void:
    var settings := SaStampBrushSettings.new()
    settings.size_by_pressure = true
    settings.format_version = 1

    settings.migrate()

    # gamma 2.0 times 2.4 is 4.8, the steepest curve the old fields can ask for
    # and the one three points have the most trouble with.
    _assert_response(settings.size_option, 4.8, "size at the default gamma")


func test_the_tool_gamma_is_in_the_product_and_not_dropped() -> void:
    # The whole point of the 2.4. Without it the opacity curve would be
    # pow(p, 0.5), which is above the old response everywhere rather than below
    # it, and a migrated preset would paint heavier at every pressure.
    var curve := SaStampBrushSettings.pressure_curve(0.5)

    var at_half := _reading(curve, 0.5)
    assert_almost_eq(at_half, pow(0.5, 1.2), GRADE_TOLERANCE, "The curve at half a press carries the product of the two gammas")
    assert_true(at_half < pow(0.5, 0.5) - 0.1, "which is well under the curve that drops the tool's own 2.4")


func test_the_curve_is_drawn_with_three_points() -> void:
    var curve := SaStampBrushSettings.pressure_curve(0.5)

    assert_eq(curve.size(), 3, "Three control points, the ends and a bend, the ends and a bend")
    assert_almost_eq(curve[0].y, 0.0, 1e-6, "starting at nothing")
    assert_almost_eq(curve[2].y, 1.0, 1e-6, "and ending at everything, whatever the exponent")


func test_three_points_hold_the_grade_and_stay_within_a_tenth_across_the_range() -> void:
    # The steepest curve the old fields can ask for. Its bend is placed to hold
    # the three graded presses, and between them it strays up to 0.09, which is
    # the price of three handles rather than nine.
    var settings := SaStampBrushSettings.new()
    settings.size_by_pressure = true
    settings.format_version = 1
    settings.migrate()

    var worst := _worst_error(settings.size_option, 4.8, 201)

    assert_true(worst <= SaPressureCurveFit.LARGEST_GAP, "The whole range is within a tenth, at %f" % worst)


# --- Idempotence --------------------------------------------------------------


func test_migrating_twice_changes_nothing_the_second_time() -> void:
    var settings := SaStampBrushSettings.new()
    var before := settings.opacity_option.common_curve.duplicate()

    assert_false(settings.migrate(), "The second run reports it did nothing")
    assert_eq(settings.opacity_option.common_curve, before, "and the curve is the one the first run drew")


func test_a_curve_drawn_by_hand_survives_the_next_migration() -> void:
    # This is what the version stamp is for. A painter who edits the opacity
    # curve in the editor and saves has a file at version 2, and a migration
    # that rebuilt from the exponent would throw their curve away on the next
    # load.
    var settings := SaStampBrushSettings.new()
    var drawn := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.4, 0.9), Vector2(1.0, 1.0)])
    settings.opacity_option.common_curve = drawn

    settings.migrate()

    assert_eq(settings.opacity_option.common_curve, drawn, "The hand-drawn curve is still there")


# --- A preset written by an older build ---------------------------------------


func test_each_shipped_preset_written_by_an_older_build_migrates() -> void:
    var store := _store()

    # The three shipped presets, written by the script that wrote them before
    # this resource existed. `install_shipped` builds them from whatever the
    # live template is, so handing it the old script is exactly a store filled
    # by an older build.
    assert_eq(store.install_shipped(OldSettingsScript.new(), SaShippedPresetsScript), 3, "Three shipped presets on disk")

    for name: String in ["Sketch", "Paint", "Fill"]:
        var old_preset := store.load_preset(name)
        assert_not_null(old_preset, "%s loads" % name)
        assert_false(old_preset.has_method("migrate"), "%s is the old resource, which has no migration" % name)

        var settings := _adopt(old_preset)

        assert_true(settings.migrate(), "%s migrates" % name)
        _assert_response(settings.opacity_option, 1.2, "%s opacity" % name)
        assert_false(settings.size_option.enabled, "%s had size by pressure off and still has" % name)
        assert_almost_eq(settings.radius, old_preset.radius, 1e-6, "%s keeps its radius" % name)
        assert_almost_eq(settings.flow.raw(), old_preset.flow.raw(), 1e-6, "%s keeps its flow" % name)
        assert_eq(settings.stabilizer_mode, old_preset.stabilizer_mode, "%s keeps its stabilizer" % name)


func test_an_old_preset_with_size_by_pressure_on_migrates_that_too() -> void:
    var store := _store()
    var old_preset := OldSettingsScript.new()
    old_preset.size_by_pressure = true
    old_preset.opacity_by_pressure = false
    store.save_preset("Steep", old_preset)

    var settings := _adopt(store.load_preset("Steep"))
    settings.migrate()

    assert_true(settings.size_option.enabled, "The boolean became enabled")
    _assert_response(settings.size_option, 4.8, "the size curve")
    assert_false(settings.opacity_option.enabled, "and the one that was off is off")
    assert_true(settings.opacity_option.sensors.is_empty(), "carrying no sensor, so nothing reads for it")


# --- The store's hook ---------------------------------------------------------


func test_the_store_hands_back_a_preset_at_the_current_version() -> void:
    var store := _store()
    store.save_preset("Round", SaStampBrushSettings.new())

    var loaded := store.load_preset("Round")

    assert_eq(loaded.format_version, SaStampBrushSettings.FORMAT_VERSION, "At the current version")
    assert_true(loaded.opacity_option.use_curve, "with the option the migration built still built")
    assert_eq(loaded.opacity_option.active_sensors().size(), 1, "and its sensor came back through the file")


func test_the_hook_rebuilds_a_resource_that_predates_the_curve_options() -> void:
    # No file this class writes is below the current version, because the
    # constructor migrates and the saver writes the stamp. The hook is what
    # carries a resource that came from somewhere else, and version 1 is the one
    # state it rebuilds from: the four old pressure fields.
    var store := _store()
    store.save_preset("Future", SaStampBrushSettings.new())

    var loaded := store.load_preset("Future")
    loaded.format_version = 1
    loaded.opacity_option.sensors.clear()

    assert_true(loaded.migrate(), "A resource below the version migrates when asked")
    assert_eq(loaded.opacity_option.active_sensors().size(), 1, "and the option is built again from the old fields")


## The negation of the old 2 to 3 step.
##
## A painter who switched pen settings off on an option and saved has a file at
## version 2, but so does every preset that predates the curve being on by
## default, and on those all nine options loaded with the curve off, so the
## sensors they had ticked did nothing. The step corrects them, and the cost is
## that a painter who switched one off on purpose gets it back on, once.
func test_a_preset_written_at_the_old_version_has_its_curves_switched_on() -> void:
    var store := _store()
    var older := SaStampBrushSettings.new()
    older.format_version = 2
    older.rotation_option.enabled = true
    for option: SaCurveOption in older.options().values():
        option.use_curve = false
    store.save_preset("Older", older)

    var loaded := store.load_preset("Older")

    assert_eq(loaded.format_version, SaStampBrushSettings.FORMAT_VERSION, "The load stamps it up to date")
    for key: String in loaded.options():
        assert_true(loaded.options()[key].use_curve, "and %s reads its sensors again" % key)
    assert_true(loaded.rotation_option.enabled, "while `enabled`, which is the real off switch, is left where it was")


## Once, which is what the stamp is for. A painter who switches an option off
## after the correction keeps it off, because the file they save is at the
## current version and the step above it does not run again.
func test_the_correction_runs_once_and_not_over_a_file_written_since() -> void:
    var store := _store()
    var current := SaStampBrushSettings.new()
    current.rotation_option.use_curve = false
    store.save_preset("Since", current)

    var loaded := store.load_preset("Since")

    assert_eq(loaded.format_version, SaStampBrushSettings.FORMAT_VERSION, "Written at the current version")
    assert_false(loaded.rotation_option.use_curve, "so the box the painter unticked is still unticked")
    assert_true(loaded.size_option.use_curve, "and the ones they left alone are still on")


func test_the_hook_leaves_a_resource_with_no_migration_alone() -> void:
    var store := _store()
    store.save_preset("Old", OldSettingsScript.new())

    var loaded := store.load_preset("Old")

    assert_not_null(loaded, "An old preset still loads through the hook")
    assert_false(loaded.has_method("migrate"), "and is handed back as it was")


# --- The file -----------------------------------------------------------------


func test_a_tres_round_trip_keeps_the_sensor_dictionary() -> void:
    var store := _store()
    var settings := SaStampBrushSettings.new()
    settings.rotation_option.use_curve = true
    settings.rotation_option.set_sensor(SaSensor.create(SaSensor.Id.DRAWING_ANGLE, true))
    settings.rotation_option.set_sensor(SaSensor.create(SaSensor.Id.SPEED, false))
    store.save_preset("Sensors", settings)

    var loaded := store.load_preset("Sensors")

    assert_eq(loaded.rotation_option.sensors.size(), 2, "Both entries came back")
    var angle: SaSensor = loaded.rotation_option.sensor_for(SaSensor.Id.DRAWING_ANGLE)
    assert_not_null(angle, "the drawing angle by its own id")
    assert_true(angle.active, "still switched on")
    assert_false(loaded.rotation_option.sensor_for(SaSensor.Id.SPEED).active, "and the one that was off, still off")


func test_a_preset_with_no_touched_sensors_writes_no_sensor_entries() -> void:
    var store := _store()
    store.save_preset("Plain", SaStampBrushSettings.new())

    var text := FileAccess.get_file_as_string(scratch_dir.path_join("Plain.tres"))
    var loaded := store.load_preset("Plain")

    # Nine options in the file and exactly one `sensors` block among them, which
    # is the opacity option the migration built. The other eight were born with
    # an empty dictionary and an empty dictionary is the property's default, so
    # the saver writes nothing for them at all.
    assert_eq(text.count("sensors = {"), 1, "One sensor dictionary in the file")
    assert_eq(text.count("sa_sensor.gd"), 1, "and one reference to the sensor script")
    for key: String in ["flow", "ratio", "softness", "rotation", "scatter", "spacing", "rate"]:
        assert_true(loaded.options()[key].sensors.is_empty(), "%s wrote no sensor entry" % key)


func test_every_field_of_the_old_resource_is_here_under_the_same_name() -> void:
    var settings := SaStampBrushSettings.new()
    var missing: Array[String] = []

    for property: Dictionary in OldSettingsScript.new().get_property_list():
        if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
            continue
        var key := String(property["name"])
        if not key in settings:
            missing.append(key)

    # The claim that makes a preset written today still usable tomorrow. The
    # preset store copies by script variable name, so a field this resource has
    # lost is a setting an old preset silently drops.
    assert_true(missing.is_empty(), "Nothing the old resource had is gone: %s" % ", ".join(missing))


## A file written before the tip's lightness row existed comes back with it
## off.
##
## **Off and not the export default's job to say.** The field is new, so there
## is nothing in a file below eight to read and nothing the migration could
## carry: the number in the file is whatever the resource's default happened to
## be when it was written, and the step exists to promise a painter that a brush
## from before the row paints what it painted.
func test_a_file_below_eight_comes_back_with_the_lightness_row_off() -> void:
    var settings := SaStampBrushSettings.new()
    settings.tip.lightness_strength = 0.8
    settings.format_version = 7

    assert_true(settings.migrate(), "The step ran")
    assert_eq(settings.format_version, SaStampBrushSettings.FORMAT_VERSION, "and stamped the file at it")
    assert_almost_eq(settings.tip.lightness_strength, 0.0, 1e-9, "with the map off whatever the file held")
    assert_false(settings.migrate(), "and a second run does nothing, so a row a painter set survives")


## The tip a `.tres` names can be missing, and the step says so rather than
## assuming one.
func test_the_lightness_step_survives_a_settings_resource_with_no_tip() -> void:
    var settings := SaStampBrushSettings.new()
    settings.tip = null
    settings.format_version = 7

    assert_true(settings.migrate(), "The step ran")
    assert_eq(settings.format_version, SaStampBrushSettings.FORMAT_VERSION, "and stamped the file at it")


## Step 11. A version 10 file carries no maker's table, and
## the stroke then read the pressure through the table of the machine painting
## with it, so it loads stamped with the loading machine's table and answers
## exactly what it answered before the row.
func test_a_file_below_eleven_loads_stamped_with_the_loading_machines_table() -> void:
    var was := SaTablet.correction
    var store := _store()
    var older := SaStampBrushSettings.new()
    older.format_version = 10
    older.maker_pressure_curve = PackedFloat32Array()
    store.save_preset("Ten", older)
    var table := PackedFloat32Array()
    for i in range(256):
        table.append(sqrt(float(i) / 255.0))
    SaTablet.correction = table

    var loaded := store.load_preset("Ten")

    assert_eq(loaded.format_version, SaStampBrushSettings.FORMAT_VERSION, "The load stamps it up to date")
    assert_true(SaTablet.same_table(loaded.maker_pressure_curve, table), "with the table of the machine that loaded it")
    var worst := 0.0
    for i in range(21):
        var raw := float(i) * 0.05
        var before := SaStrokeInfo.new()
        before.feed(Vector2.ZERO, raw, Vector2.ZERO, 0.0, 0.0)
        var after := SaStrokeInfo.new()
        after.feed(Vector2.ZERO, raw, Vector2.ZERO, 0.0, 0.0, loaded.maker_pressure_curve)
        worst = maxf(worst, absf(before.pressure - after.pressure))
    assert_true(worst <= 1e-5, "and reads every pressure as the painter's own table did, worst %f" % worst)
    SaTablet.correction = was


## A fresh brush is made on this machine, so the constructor's step stamps it
## with this painter's table, and an uncalibrated pen is stamped with the
## diagonal written out rather than left empty.
func test_a_fresh_resource_is_stamped_with_the_painters_table() -> void:
    var was := SaTablet.correction
    SaTablet.correction = PackedFloat32Array()
    assert_eq(SaStampBrushSettings.new().maker_pressure_curve, PackedFloat32Array([0.0, 1.0]), "The diagonal, written out")
    SaTablet.correction = PackedFloat32Array([0.0, 0.8, 1.0])
    assert_eq(SaStampBrushSettings.new().maker_pressure_curve, PackedFloat32Array([0.0, 0.8, 1.0]), "and the painter's own")
    SaTablet.correction = was


# --- Helpers ------------------------------------------------------------------


## *option*'s response at eleven pressures against `pow(p, exponent)`.
##
## Read through a sensor rather than off the control points, because the table
## and its linear read are between the two and are where a shape is lost.
func _assert_response(option: SaCurveOption, exponent: float, what: String) -> void:
    var worst := 0.0
    for pressure: float in GRADE_PRESSURES:
        worst = maxf(worst, absf(_reading(option.common_curve, pressure) - pow(pressure, exponent)))
    assert_true(worst <= GRADE_TOLERANCE, "%s is within %f of the old response, worst %f" % [what, GRADE_TOLERANCE, worst])


## The largest gap between *option*'s curve and `pow(p, exponent)` over *count*
## evenly spaced pressures.
func _worst_error(option: SaCurveOption, exponent: float, count: int) -> float:
    var sensor := SaSensor.create(SaSensor.Id.PRESSURE, true)
    sensor.curve = option.common_curve.duplicate()
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 1)
    var worst := 0.0

    for i in range(count):
        var pressure := float(i) / float(count - 1)
        info.pressure = pressure
        worst = maxf(worst, absf(sensor.parameter(info) - pow(pressure, exponent)))
    return worst


## What a pressure sensor carrying *curve* answers at *pressure*.
func _reading(curve: PackedVector2Array, pressure: float) -> float:
    var sensor := SaSensor.create(SaSensor.Id.PRESSURE, true)
    sensor.curve = curve.duplicate()
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 1)
    info.pressure = pressure
    return sensor.parameter(info)


## An old preset's fields on a resource that has never been migrated.
##
## `format_version` is set back to 1 by hand, which is the one thing the switch
## to this resource has to do for itself: the old script has no such field, so
## the preset store's copy leaves the target at 2 and the migration would skip.
## See the record.
func _adopt(old_preset: Resource) -> SaStampBrushSettings:
    var settings := SaStampBrushSettings.new()
    SaPresetStore.copy_settings(old_preset, settings)
    settings.format_version = 1
    return settings


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store
