## The Smudge Dilution migration is checked against numbers written by hand,
## so a migration that forgets to take the dilution from one fails.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The migration turns an old Smudge Dilution into the Colour Rate that lays
## the same paint. The dilution said how much of the dragged paint replaces the brush's
## colour, so the rate is what is left of one. The brush's own suite migrates 0.5,
## which is its own complement, and built its other expected brush with the
## same turn the code makes, so a migration that kept the number as it stood
## passed it. Every expected rate here is a constant worked out by hand from
## the old meaning, at 0.2 and 0.8, which read apart when the turn is lost.
##
## Every stroke goes through the brush's own input over two bands of paint, a
## red chunk and a yellow one, and a saved brush is written into a scratch
## store, never the painter's own. An old file is made the way an old build
## wrote one, as that suite makes it: saved with its dilution at the old
## format, the colour rate line taken out.
extends "res://tests/test_framework.gd"

## Paints and reads back the canvas.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The recorded paint of every shipped stamp recipe, by name.
const SHIPPED_PAINT: String = "res://tests/fixtures/shipped-paint/shipped_paint.json"

## Two chunks across, one band of paint each, as in the brush's own suite.
const CANVAS := Vector2i(512, 256)
const ROW: float = 128.0
const FROM_X: float = 60.0
const TO_X: float = 450.0
const STEPS: int = 60

const RED := Color(0.85, 0.15, 0.1, 1.0)
const YELLOW := Color(0.9, 0.8, 0.1, 1.0)
const INK := Color(0.1, 0.2, 0.8, 1.0)

## The tolerance for two strokes meant to be one, the largest channel
## difference of any texel.
const SAME: float = 2e-3

## The format the stamp's settings had before the colour rate.
const OLD_FORMAT: int = 14

## Two dilutions and the rates they become, written from the old meaning: a
## dilution of 0.2 replaced a fifth of the brush's colour with the carry and
## left four fifths, a dilution of 0.8 left one fifth.
const LOW_DILUTION: float = 0.2
const LOW_RATE: float = 0.8
const HIGH_DILUTION: float = 0.8
const HIGH_RATE: float = 0.2

## A pressure curve bent below the line, with a point at each pressure the
## bent case paints at, so the curve reads the point's height there exactly:
## a monotone cubic passes through its points.
const BENT := [Vector2(0.0, 0.0), Vector2(0.3, 0.1), Vector2(0.6, 0.3), Vector2(0.9, 0.8), Vector2(1.0, 1.0)]
const PRESSURES := [0.3, 0.6, 0.9]

## The rate the dilution of 0.8 on [constant BENT] left at each of
## [constant PRESSURES], worked by hand: the dilution read 0.8 times the
## curve's height, 0.08, 0.24 and 0.64, and the rate is one less that.
const BENT_RATES := [0.92, 0.76, 0.36]

## How far a reading through the sensor's 256 entry table may sit from the
## point it passes through.
const READ: float = 2e-3

static var scratch_dir: String = SaDataRoot.path("test_colour_rate_presets")


func after_each() -> void:
    if DirAccess.dir_exists_absolute(scratch_dir):
        for file_name: String in DirAccess.get_files_at(scratch_dir):
            DirAccess.remove_absolute(scratch_dir.path_join(file_name))
        DirAccess.remove_absolute(scratch_dir)


## Dilutions of 0.2 and 0.8, ticked in a file of
## the old format, load as colour rates reading 0.8 and 0.2 at full pressure,
## and the page turns the unticked ones to the same numbers.
func test_dilutions_of_two_and_eight_tenths_read_rates_of_eight_and_two_tenths() -> void:
    for pair: Array in [[LOW_DILUTION, LOW_RATE], [HIGH_DILUTION, HIGH_RATE]]:
        var dilution: float = pair[0]
        var rate: float = pair[1]
        var loaded := _through_an_old_file("Dilution %d" % roundi(dilution * 10.0), dilution)
        assert_null(loaded.smudge_dilution_option, "The dilution of %.1f is gone once the file loads" % dilution)
        assert_true(loaded.smudge_color_rate_option.enabled, "and its colour rate is ticked")
        var read := _reading(loaded.smudge_color_rate_option, 1.0, loaded)
        assert_almost_eq(read, rate, 1e-4, "A dilution of %.1f reads a colour rate of %.1f, read %.4f" % [dilution, rate, read])
        var unticked := SaSmudgePage.color_rate_of(SaSmudgePage.option(dilution))
        assert_false(unticked.enabled, "Unticked, %.1f stays unticked" % dilution)
        assert_almost_eq(unticked.strength, rate, 1e-6, "and waits at %.1f for the tick" % rate)


## Each migrated brush paints the stroke a brush
## at the hand-written rate paints, and the two rates paint apart, so a
## migration that kept the dilution would read one stroke for the other.
func test_each_migrated_brush_paints_as_the_literal_rate_does() -> void:
    var literal := {}
    for pair: Array in [[LOW_DILUTION, LOW_RATE], [HIGH_DILUTION, HIGH_RATE]]:
        var dilution: float = pair[0]
        var rate: float = pair[1]
        var migrated := _through_an_old_file("Painted %d" % roundi(dilution * 10.0), dilution)
        var held := _oil_smudge()
        held.smudge_color_rate_option = SaSmudgePage.option(rate, true)
        literal[rate] = _stroke(held, 1.0)
        var apart := _apart(_stroke(migrated, 1.0), literal[rate])
        assert_true(apart < SAME, "A dilution of %.1f paints as a rate of %.1f, %.5f apart" % [dilution, rate, apart])
    var between := _apart(literal[LOW_RATE], literal[HIGH_RATE])
    assert_true(between > 10.0 * SAME, "and rates of 0.8 and 0.2 paint %.4f apart" % between)


## A dilution of 0.8 read through a bent
## pressure curve paints at three pressures what the hand-worked rate at each
## paints, held as a constant on the same brush.
func test_a_bent_dilution_paints_the_hand_worked_rate_at_three_pressures() -> void:
    var dilution := SaSmudgePage.option(HIGH_DILUTION, true)
    dilution.common_curve = PackedVector2Array(BENT)
    var pressure := SaSensor.create(SaSensor.Id.PRESSURE, true)
    pressure.curve = PackedVector2Array(BENT)
    dilution.set_sensor(pressure)
    var migrated := _through_an_old_file("Bent", HIGH_DILUTION, dilution)
    assert_eq(migrated.smudge_color_rate_option.active_sensors().size(), 1, "The migrated rate still reads the pen")
    for i in range(PRESSURES.size()):
        var asked: float = PRESSURES[i]
        var rate: float = BENT_RATES[i]
        var read := _reading(migrated.smudge_color_rate_option, asked, migrated)
        assert_almost_eq(read, rate, READ, "At pressure %.1f the rate reads %.3f, read %.4f" % [asked, rate, read])
        var held := migrated.duplicate(true) as SaStampBrushSettings
        held.smudge_color_rate_option = SaSmudgePage.option(rate, true)
        var apart := _apart(_stroke(migrated, asked), _stroke(held, asked))
        assert_true(apart < SAME, "At pressure %.1f the stroke paints as a rate of %.2f, %.5f apart" % [asked, rate, apart])


## The recorded recipes are still the ground truth for
## the shipped smudges, and Oil Smudge and Blender, the two whose dilution the
## migration turns, are among them.
func test_the_recorded_paint_holds_both_smudge_recipes() -> void:
    var recorded: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED_PAINT))
    assert_true(recorded is Dictionary, "the fixture reads as a table of recipes")
    if not recorded is Dictionary:
        return
    for name: String in ["Oil Smudge", "Blender"]:
        assert_true((recorded as Dictionary).has(name), "%s is among the recorded recipes" % name)
        var entry: Variant = (recorded as Dictionary).get(name)
        assert_true(entry is Dictionary and (entry as Dictionary).has("stroke"), "with a stroke recorded for it")


# --- Brushes ------------------------------------------------------------------


func _oil_smudge() -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == "Oil Smudge":
            var settings := SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry) as SaStampBrushSettings
            settings.color = INK
            return settings
    assert_true(false, "Oil Smudge is a shipped recipe")
    return SaStampBrushSettings.new()


## Oil Smudge with *dilution* in place of its colour rate, ticked, or with the
## option *shaped* when one is given, written as an old build wrote it into
## the scratch store and read back through the store's load, which migrates.
func _through_an_old_file(preset_name: String, dilution: float, shaped: SaCurveOption = null) -> SaStampBrushSettings:
    var old := _oil_smudge()
    if shaped == null:
        old.smudge_dilution_option = SaSmudgePage.option(dilution, true)
    else:
        old.smudge_dilution_option = shaped.duplicate(true)
        old.smudge_dilution_option.set_sensor(shaped.sensor_for(SaSensor.Id.PRESSURE).duplicate())
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    var stored := store.save_preset(preset_name, old)
    assert_false(stored.is_empty(), "%s is saved into the scratch store" % preset_name)
    var path := scratch_dir.path_join(stored + SaPresetStore.EXTENSION)
    var kept := PackedStringArray()
    for line: String in FileAccess.get_file_as_string(path).split("\n"):
        if line.begins_with("smudge_color_rate_option = "):
            continue
        kept.append("format_version = %d" % OLD_FORMAT if line.begins_with("format_version = ") else line)
    var text := "\n".join(kept)
    assert_true(text.contains("smudge_dilution_option = "), "The old file carries its dilution")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(text)
    file.close()
    var loaded := store.load_preset(preset_name) as SaStampBrushSettings
    assert_not_null(loaded, "and loads back")
    loaded.color = INK
    return loaded


## What *option* reads at a pen pressure of *asked*, through the table the
## stroke reads pressure through.
func _reading(option: SaCurveOption, asked: float, settings: SaStampBrushSettings) -> float:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 0)
    info.pressure = SaTablet.normalize(asked, SaSettings.tablet_max_pressure, 1.0, settings.maker_pressure_curve)
    var fresh := option.duplicate(true) as SaCurveOption
    var sensor := option.sensor_for(SaSensor.Id.PRESSURE)
    if sensor != null:
        fresh.set_sensor(sensor.duplicate())
    fresh.begin_stroke()
    return clampf(fresh.size_like(info), 0.0, 1.0)


# --- Painting -----------------------------------------------------------------


## A fresh canvas with its two bands, composited, since the pickup reads the
## composite.
func _ground() -> SaSurface:
    var surface := Fixtures.make_surface(CANVAS)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i.ZERO).clear(RED)
    document.active_layer.get_or_create_chunk(Vector2i(1, 0)).clear(YELLOW)
    document.invalidate_chunks([Vector2i.ZERO, Vector2i(1, 0)])
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    return surface


## One stroke of *settings* across both bands at a pen pressure of *pressure*,
## the pen shown hovering at it first so the press opens at it too, and the
## composite it leaves.
func _stroke(settings: SaStampBrushSettings, pressure: float) -> Image:
    var surface := _ground()
    var brush := StateBrushScript.new()
    brush.surface = surface
    brush.settings = settings
    brush.stroke_seed = 201
    var from := Vector2(FROM_X, ROW)
    var to := Vector2(TO_X, ROW)
    surface.view.mouse_position = from
    var hover := InputEventMouseMotion.new()
    hover.pressure = pressure
    brush.handle_input(hover)
    brush.handle_input(_button(true))
    for i in range(1, STEPS + 1):
        surface.view.mouse_position = from.lerp(to, float(i) / float(STEPS))
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = pressure
        brush.handle_input(motion)
    brush.handle_input(_button(false))
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    var image := SaExport.get_easel_image_float(surface.easel)
    assert_not_null(image, "The canvas reads back")
    Fixtures.teardown(surface)
    return image


func _button(pressed: bool) -> InputEventMouseButton:
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_LEFT
    button.pressed = pressed
    return button


## The largest channel difference of any texel along the stroke's band.
static func _apart(a: Image, b: Image) -> float:
    var most := 0.0
    for y in range(int(ROW) - 40, int(ROW) + 41):
        for x in range(CANVAS.x):
            var left := a.get_pixel(x, y)
            var right := b.get_pixel(x, y)
            most = maxf(most, maxf(maxf(absf(left.r - right.r), absf(left.g - right.g)), absf(left.b - right.b)))
    return most
