## Tablet pressure calibration: the maths, the recorder, the stored setting, and
## the page that measures one from a pen.
##
## The number under test spent a long time as `max_tablet_pressure = 0.73` inside
## `state_brush.gd`, where nothing could reach it. So the assertions that matter
## most here are the two that say it is no longer a constant: that the brush
## reads the setting every time rather than a copy of its own, and that a profile
## written before the setting existed still paints the way it did before the setting.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

static var scratch_path: String = SaDataRoot.path("test_tablet_scratch.cfg")
static var scratch_other_path: String = SaDataRoot.path("test_tablet_other.cfg")

var _saved_max_pressure: float
var _saved_path: String


func before_each() -> void:
    _saved_max_pressure = SaSettings.tablet_max_pressure
    _saved_path = SaSettings.settings_path


func after_each() -> void:
    SaSettings.settings_path = _saved_path
    SaSettings.tablet_max_pressure = _saved_max_pressure
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_other_path))


# --- The maths ---------------------------------------------------------------------


## The whole point of a calibration: ordinary force has to reach a full-strength
## dab, and the travel beyond it is not a second, harder half of the range.
func test_the_maximum_rescales_the_part_of_the_range_a_hand_reaches() -> void:
    assert_almost_eq(SaTablet.normalize(0.73, 0.73, 1.0), 1.0, 0.0001, "The calibrated maximum is full pressure")
    assert_almost_eq(SaTablet.normalize(0.365, 0.73, 1.0), 0.5, 0.0001, "and half of it is half pressure")
    assert_almost_eq(SaTablet.normalize(0.95, 0.73, 1.0), 1.0, 0.0001, "Leaning past it stays at full rather than overshooting")
    assert_almost_eq(SaTablet.normalize(0.365, 1.0, 1.0), 0.365, 0.0001, "An uncalibrated pen passes its raw reading through")


## The two halves are not interchangeable. The maximum is hardware and the gamma
## is taste, so the curve has to bend what is left rather than move the top.
func test_the_gamma_bends_the_range_without_moving_its_top() -> void:
    assert_almost_eq(SaTablet.normalize(0.365, 0.73, 2.4), pow(0.5, 2.4), 0.0001, "The curve applies after the rescale")
    assert_almost_eq(SaTablet.normalize(0.73, 0.73, 2.4), 1.0, 0.0001, "and full pressure is still full whatever the curve")


## A maximum of zero would divide by zero, and one above the hardware range would
## make a full-strength dab unreachable. Both are what a hand-edited config file
## can contain.
func test_a_maximum_outside_the_usable_range_is_clamped_rather_than_divided_by() -> void:
    assert_almost_eq(SaTablet.clamp_max_pressure(0.0), SaTablet.MIN_MAX_PRESSURE, 0.0001, "Zero clamps up")
    assert_almost_eq(SaTablet.clamp_max_pressure(-4.0), SaTablet.MIN_MAX_PRESSURE, 0.0001, "and so does a negative")
    assert_almost_eq(SaTablet.clamp_max_pressure(5.0), SaTablet.MAX_MAX_PRESSURE, 0.0001, "Above the hardware range clamps down")
    assert_almost_eq(SaTablet.clamp_max_pressure(NAN), SaTablet.DEFAULT_MAX_PRESSURE, 0.0001, "and a non-number is not a maximum")

    var result := SaTablet.normalize(0.5, 0.0, 1.0)
    assert_true(is_finite(result), "A zero maximum must not reach the division")
    assert_almost_eq(result, 1.0, 0.0001, "It clamps to the smallest real maximum, which 0.5 is well past")


## `clamp()` launders a NaN into a plausible number,
## and a plausible pressure is one that paints.
func test_a_nan_reading_paints_nothing_rather_than_being_clamped_into_a_stroke() -> void:
    assert_almost_eq(SaTablet.normalize(NAN, 0.73, 2.4), 0.0, 0.0001, "A driver reporting nonsense lays down no paint")


# --- The recorder ------------------------------------------------------------------


func test_the_recorder_keeps_the_hardest_reading() -> void:
    var recorder := SaTablet.new()

    assert_true(recorder.observe(0.4), "The first real reading moves the peak")
    assert_false(recorder.observe(0.2), "A lighter one does not")
    assert_almost_eq(recorder.peak, 0.4, 0.0001, "and does not lower it either")
    assert_true(recorder.observe(0.6), "A harder one does")
    assert_almost_eq(recorder.peak, 0.6, 0.0001, "The peak is the hardest reading of the run")


## Zero is what a mouse reports, and what a pen in range but off the surface
## reports. Counting either would let the wrong device look like a measurement.
func test_a_reading_of_nothing_is_not_a_reading() -> void:
    var recorder := SaTablet.new()

    assert_false(recorder.observe(0.0), "Zero pressure is not a sample")
    assert_false(recorder.observe(-1.0), "nor is a negative one")
    assert_false(recorder.observe(NAN), "nor a non-number")
    assert_eq(recorder.sample_count, 0, "None of them counted")


func test_a_peak_is_not_offered_until_enough_readings_have_made_it() -> void:
    var recorder := SaTablet.new()
    recorder.observe(0.6)

    assert_false(recorder.has_usable_peak(), "One stray event is not a calibration")

    for _i in SaTablet.MIN_SAMPLES:
        recorder.observe(0.6)
    assert_true(recorder.has_usable_peak(), "A press that kept reporting is")

    recorder.reset()
    assert_false(recorder.has_usable_peak(), "and a cleared recorder has nothing to offer")
    assert_almost_eq(recorder.peak, 0.0, 0.0001, "with no peak left behind")


## Only motion events carry the axis, which is why the pad asks for a drag rather
## than a tap. A button event returning 0.0 would read as a pen pressed to nothing.
func test_only_a_motion_event_carries_a_pressure_at_all() -> void:
    var motion := InputEventMouseMotion.new()
    motion.pressure = 0.42
    assert_almost_eq(SaTablet.pressure_of(motion), 0.42, 0.0001, "Motion carries the axis")

    assert_true(SaTablet.pressure_of(InputEventMouseButton.new()) < 0.0, "A button press carries none")
    assert_true(SaTablet.pressure_of(InputEventKey.new()) < 0.0, "and neither does a key")


# --- The stored setting ------------------------------------------------------------


func test_the_stored_maximum_survives_a_save_and_a_load() -> void:
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    SaSettings.tablet_max_pressure = 0.62

    # Every setter saves, so moving away from the value has to happen against a
    # different file or it would overwrite the one under test.
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_other_path)
    SaSettings.tablet_max_pressure = 0.31

    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    SaSettings.load_settings()

    assert_almost_eq(SaSettings.tablet_max_pressure, 0.62, 0.0001, "The calibration comes back")


func test_a_hand_edited_maximum_is_clamped_like_one_from_the_slider() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", SaSettings.SETTINGS_VERSION)
    config.set_value("ui", "scale", SaSettings.ui_scale)
    config.set_value("input", "tablet_max_pressure", 0.0)
    config.save(ProjectSettings.globalize_path(scratch_path))

    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    SaSettings.load_settings()

    assert_almost_eq(
        SaSettings.tablet_max_pressure, SaTablet.MIN_MAX_PRESSURE, 0.0001, "A zero from disk is bounded, not divided by"
    )


## A stored setting that changes meaning must be migrated.
## Here nothing was stored at all, and the
## meaning changed anyway: what was 0.73 for everybody is now whatever the
## profile says, and a profile that says nothing would silently get 1.0 and make
## every pen heavier overnight.
func test_a_profile_from_before_the_setting_keeps_the_pressure_it_was_painted_with() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", 3)
    # Carried across so the load does not reset the running UI scale for every
    # suite after this one. The settings autoload is shared by the whole run.
    config.set_value("ui", "scale", SaSettings.ui_scale)
    config.save(ProjectSettings.globalize_path(scratch_path))

    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    SaSettings.load_settings()

    assert_almost_eq(
        SaSettings.tablet_max_pressure,
        SaSettingsMigrations.LEGACY_MAX_PRESSURE,
        0.0001,
        "An older profile carries the figure the brush once compiled in"
    )

    var written := ConfigFile.new()
    written.load(ProjectSettings.globalize_path(scratch_path))
    assert_eq(written.get_value("meta", "version"), SaSettings.SETTINGS_VERSION, "and the file is stamped, so it migrates once")


func test_a_first_run_starts_uncalibrated_rather_than_on_someone_elses_pen() -> void:
    var absent := ProjectSettings.globalize_path(SaDataRoot.path("test_tablet_absent.cfg"))
    DirAccess.remove_absolute(absent)
    SaSettings.tablet_max_pressure = 0.4
    SaSettings.settings_path = absent

    SaSettings.load_settings()

    assert_almost_eq(
        SaSettings.tablet_max_pressure,
        SaTablet.DEFAULT_MAX_PRESSURE,
        0.0001,
        "Nobody has measured this pen, so nothing is assumed"
    )
    DirAccess.remove_absolute(absent)


# --- The brush -----------------------------------------------------------------------


## The regression this whole item exists for. A per-brush copy of the number is
## exactly what was wrong with it, so the brush must hold none and must see a
## change without being rebuilt.
func test_the_brush_reads_the_calibration_rather_than_a_number_of_its_own() -> void:
    var brush := StateBrushScript.new()

    assert_false("max_tablet_pressure" in brush, "The brush must not carry its own maximum again")

    var info: SaStrokeInfo = brush.stroke_info
    var table: PackedFloat32Array = brush.settings.maker_pressure_curve
    SaSettings.tablet_max_pressure = 0.5
    info.feed(Vector2.ZERO, 0.25, Vector2.ZERO, 0.0, 0.0, table)
    assert_almost_eq(info.pressure, SaTablet.correct(0.5, table), 0.0001, "Half of the calibrated maximum is half pressure")

    SaSettings.tablet_max_pressure = 0.25
    info.feed(Vector2.ZERO, 0.25, Vector2.ZERO, 0.0, 0.0, table)
    assert_almost_eq(info.pressure, 1.0, 0.0001, "and recalibrating reaches the brush with no restart")


# --- The page ------------------------------------------------------------------------


## A page nobody can open is the same as no page. Preferences derives its menu
## from this list, so the entry is the whole of "it is reachable".
func test_preferences_offers_the_page() -> void:
    assert_true("Pen and tablet" in SaSettingsWindow.FIXED_PAGES, "Preferences lists the pen's page")


func test_the_page_reports_what_the_pen_is_doing() -> void:
    SaSettings.tablet_max_pressure = 0.8
    var page := SaTabletCalibration.new()

    page.sample_pressure(0.4)

    assert_almost_eq(page.measured_peak(), 0.4, 0.0001, "The hardest reading so far is shown")
    var readout: Label = page.find_child("Readout", true, false)
    assert_true(readout.text.contains("0.40"), "The live reading is on screen: %s" % readout.text)
    assert_true(readout.text.contains("50%"), "and so is what it maps to at this calibration: %s" % readout.text)

    page.free()


## Writing a peak nobody measured would store a maximum near zero, and every
## touch after that would be a full-strength dab.
func test_the_page_refuses_a_measurement_that_was_never_made() -> void:
    SaSettings.tablet_max_pressure = 0.9
    var page := SaTabletCalibration.new()

    assert_false(page.apply_measured(), "There is nothing to apply yet")
    assert_almost_eq(SaSettings.tablet_max_pressure, 0.9, 0.0001, "so the stored calibration is untouched")

    for _i in SaTablet.MIN_SAMPLES:
        page.sample_pressure(0.6)

    assert_true(page.apply_measured(), "A press that reported enough is a measurement")
    assert_almost_eq(SaSettings.tablet_max_pressure, 0.6, 0.0001, "and it becomes the stored maximum")

    var slider: HSlider = page.find_child("MaxPressureSlider", true, false)
    assert_almost_eq(slider.value, 0.6, 0.0001, "with the handle moved to match, rather than left behind")

    page.free()


func test_clearing_a_measurement_leaves_the_stored_calibration_alone() -> void:
    SaSettings.tablet_max_pressure = 0.7
    var page := SaTabletCalibration.new()
    for _i in SaTablet.MIN_SAMPLES:
        page.sample_pressure(0.55)

    page.clear_measurement()

    assert_almost_eq(page.measured_peak(), 0.0, 0.0001, "The measurement is gone")
    assert_false(page.apply_measured(), "and there is nothing left to apply")
    assert_almost_eq(SaSettings.tablet_max_pressure, 0.7, 0.0001, "while what was already calibrated stays")

    page.free()


## The slider is the manual half of the page, for a pen that will not report at
## all. It has to write the same setting the measurement does.
func test_the_slider_writes_the_same_setting_the_measurement_does() -> void:
    var page := SaTabletCalibration.new()
    var slider: HSlider = page.find_child("MaxPressureSlider", true, false)

    # Assigning Range.value is not a drag. Announcing it is what a drag does, and
    # the listener is the only thing that writes the setting.
    slider.value = 0.45
    slider.value_changed.emit(slider.value)

    assert_almost_eq(SaSettings.tablet_max_pressure, 0.45, 0.0001, "Dragging the slider stores the maximum")

    page.free()


## The pad draws two lanes, and the lower one is the pressure the brush gets
## rather than the reading the hardware sent.
##
## The second trace is there because the two numbers are nothing alike
## on a pen whose usable travel ends early: at a maximum of 0.6 a hardware 0.3
## is a stroke pressure of 0.5, and the page said so in words at the bottom
## while the gauge showed only the hardware half.
func test_the_pad_draws_the_pressure_sara_sends_beside_the_hardware_one() -> void:
    SaSettings.tablet_max_pressure = 0.6
    var page := SaTabletCalibration.new()
    var pad := page.find_child("PressurePad", true, false) as SaTabletCalibration.PressurePad

    page.sample_pressure(0.3)
    assert_almost_eq(pad.raw, 0.3, 1e-6, "The hardware lane is the reading itself")
    assert_almost_eq(pad.stroke, 0.5, 1e-6, "and the Sara lane is that reading through the maximum")
    assert_almost_eq(
        pad.stroke, SaTablet.normalize(0.3, 0.6, 1.0), 1e-6, "which is the same maths the brush reads, at a gamma of one"
    )

    page.sample_pressure(0.6)
    assert_almost_eq(pad.stroke, 1.0, 1e-6, "A reading at the maximum is a full-strength dab")
    page.sample_pressure(0.9)
    assert_almost_eq(pad.stroke, 1.0, 1e-6, "and one past it is not more than full")
    page.sample_pressure(0.0)
    assert_almost_eq(pad.stroke, 0.0, 1e-6, "A pen lifted off leaves both lanes empty")

    page.free()


## At a maximum of one the two lanes are the same bar twice, which is why the
## capture step sets the maximum before it feeds a ramp.
func test_an_uncalibrated_pen_draws_the_two_lanes_alike() -> void:
    SaSettings.tablet_max_pressure = 1.0
    var page := SaTabletCalibration.new()
    var pad := page.find_child("PressurePad", true, false) as SaTabletCalibration.PressurePad

    page.sample_pressure(0.42)
    assert_almost_eq(pad.raw, pad.stroke, 1e-6, "Nothing is being rescaled, so nothing differs")

    page.free()


## The two lanes stack rather than overlapping, because an overlay is
## unreadable exactly where the two nearly agree, which is what a painter on
## this page is comparing.
func test_the_two_lanes_stack_and_cover_the_pad_between_them() -> void:
    var page := SaTabletCalibration.new()
    var pad := page.find_child("PressurePad", true, false) as SaTabletCalibration.PressurePad
    pad.size = Vector2(200, 56)

    var lanes: Dictionary = pad.lane_rects()
    var hardware: Rect2 = lanes["hardware"]
    var sara: Rect2 = lanes["sara"]
    assert_eq(hardware.position.y, 0.0, "The hardware lane starts at the top")
    assert_eq(sara.position.y, hardware.end.y, "the Sara lane starts where it ends")
    assert_almost_eq(sara.end.y, 56.0, 1e-6, "and the two fill the pad between them")
    assert_true(hardware.size.y > 0.0 and sara.size.y > 0.0, "with neither of them nothing")
    assert_eq(hardware.size.x, sara.size.x, "Both lanes are the pad's full width")

    page.free()


## Every shipped palette gives the second trace a colour of its own, and one
## the gauge is not: `accent_gauge` is a green in Sara Green, a blue in two of
## the others and a cyan in Solarized, so "a lighter accent" would have been
## telling in none of them.
func test_every_palette_tells_the_two_traces_apart() -> void:
    for theme_id: String in SaTheme.PALETTES:
        var palette := load(SaTheme.PALETTES[theme_id]) as SaPalette
        assert_true(palette != null, "%s loads" % theme_id)
        var gauge: Color = palette.accent_gauge
        var stroke: Color = palette.accent_stroke
        var apart := absf(gauge.h - stroke.h)
        apart = minf(apart, 1.0 - apart)
        assert_true(apart > 0.1, "%s: the two traces are %.2f of the wheel apart" % [theme_id, apart])
        assert_true(stroke.a > 0.9, "%s: and the second one is not nearly transparent" % theme_id)


## Clear with nothing measured threw nothing away. It is dimmed
## until the strip has heard a reading, and a clear dims it again.
func test_clear_is_dimmed_until_something_is_measured() -> void:
    var page := SaTabletCalibration.new()
    var clear := page.find_child("ClearButton", true, false) as Button
    assert_true(clear.disabled, "A page with nothing measured offers no Clear")
    page.sample_pressure(0.4)
    assert_false(clear.disabled, "and one reading lights it")
    page.clear_measurement()
    assert_true(clear.disabled, "Clearing the measurement dims it again")
    page.free()
