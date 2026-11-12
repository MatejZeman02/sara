## Smudge Dilution becomes Colour Rate, which says how much of
## the brush's own colour a smudge lays.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Ticking Smudge Pickup to paint and smudge at once gave a smudge
## that laid none of the brush's colour, since a dilution left off read as one,
## all carry. The option is Colour Rate now, Krita's name and direction, nought
## the carry alone and one the brush's colour alone, off reads nought, and a
## fresh brush has it ticked at a half. A brush saved with a dilution is turned
## over when it loads, so it lays what it laid.
##
## Every stroke goes through the brush's own input over two bands of paint, a
## red chunk and a yellow one, and a saved brush is written into a scratch
## store, never the painter's own. An old file is made the way an old build
## wrote one: the brush saved with its dilution and the format it carried, and
## the colour rate line taken out of the text, since no old file has one.
extends "res://tests/test_framework.gd"

## Paints and reads back the canvas.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Two chunks across, one band of paint each.
const CANVAS := Vector2i(512, 256)
const ROW: float = 128.0
const FROM_X: float = 60.0
const TO_X: float = 450.0
const STEPS: int = 60

## The two bands and the brush's own colour, far apart in every channel.
const RED := Color(0.85, 0.15, 0.1, 1.0)
const YELLOW := Color(0.9, 0.8, 0.1, 1.0)
const INK := Color(0.1, 0.2, 0.8, 1.0)

## How far two strokes meant to be one may read apart, as the largest channel
## difference of any texel. The two differ by a rounding of one less a number
## taken from one.
const SAME: float = 2e-3

## The format the stamp's settings had before the colour rate.
const OLD_FORMAT: int = 14

## A pressure curve that is not the line, so a turn that kept the line and lost
## the bend would read apart from the dilution it came from.
const BENT := [Vector2(0.0, 0.0), Vector2(0.5, 0.15), Vector2(1.0, 1.0)]

static var scratch_dir: String = SaDataRoot.path("test_colour_rate_presets")


func after_each() -> void:
    if DirAccess.dir_exists_absolute(scratch_dir):
        for file_name: String in DirAccess.get_files_at(scratch_dir):
            DirAccess.remove_absolute(scratch_dir.path_join(file_name))
        DirAccess.remove_absolute(scratch_dir)


## Oil Smudge as it shipped before this row, its dilution at
## 0.5 in a file of the old format, paints the stroke Oil Smudge paints as it
## ships now.
func test_oil_smudge_as_it_shipped_before_paints_as_it_ships_now() -> void:
    var old := _oil_smudge()
    old.smudge_color_rate_option = SaSmudgePage.option(0.5)
    old.smudge_dilution_option = SaSmudgePage.option(0.5, true)
    var loaded := _through_an_old_file("Oil Smudge Before", old)
    assert_null(loaded.smudge_dilution_option, "The dilution is gone once the file loads")
    assert_true(loaded.smudge_color_rate_option.enabled, "and its colour rate is ticked")
    assert_almost_eq(loaded.smudge_color_rate_option.strength, 0.5, 1e-6, "at one less the 0.5 it carried")
    var before := _stroke(loaded, 1.0)
    var after := _stroke(_oil_smudge(), 1.0)
    var apart := _apart(before, after)
    assert_true(apart < SAME, "Oil Smudge before and after read %.5f apart at most" % apart)
    assert_true(_apart(after, _bare()) > 0.1, "and the stroke painted something to compare")


## A dilution of 0.8 read through a bent pressure curve,
## migrated, paints at three pressures what the dilution laid at each. What it
## laid is the same brush with the colour rate held at one less the dilution's
## reading at that pressure, which is the dab the old build painted.
func test_a_dilution_on_a_pressure_curve_lays_the_same_at_three_pressures() -> void:
    var dilution := SaSmudgePage.option(0.8, true)
    dilution.common_curve = PackedVector2Array(BENT)
    var pressure := SaSensor.create(SaSensor.Id.PRESSURE, true)
    pressure.curve = PackedVector2Array(BENT)
    dilution.set_sensor(pressure)
    var old := _oil_smudge()
    old.smudge_dilution_option = dilution.duplicate(true)
    old.smudge_dilution_option.set_sensor(pressure.duplicate())
    var migrated := _through_an_old_file("Bent Dilution", old)
    assert_eq(migrated.smudge_color_rate_option.active_sensors().size(), 1, "The migrated rate still reads the pen")
    for asked: float in [0.3, 0.6, 0.9]:
        var held := migrated.duplicate(true) as SaStampBrushSettings
        held.smudge_color_rate_option = SaSmudgePage.option(1.0 - _old_reading(dilution, asked, held), true)
        var reading := _old_reading(dilution, asked, held)
        var apart := _apart(_stroke(migrated, asked), _stroke(held, asked))
        assert_true(apart < SAME, "At pressure %.1f, a dilution of %.3f, the two read %.5f apart" % [asked, reading, apart])
    # The comparison is not blind: the rate the dilution read at 0.9, held at a
    # pressure of 0.3, paints a stroke the migrated brush does not.
    var low := _old_reading(dilution, 0.3, migrated)
    var high := _old_reading(dilution, 0.9, migrated)
    assert_true(high - low > 0.3, "The bent curve reads %.3f at 0.3 and %.3f at 0.9" % [low, high])
    var wrong := migrated.duplicate(true) as SaStampBrushSettings
    wrong.smudge_color_rate_option = SaSmudgePage.option(1.0 - high, true)
    var off := _apart(_stroke(migrated, 0.3), _stroke(wrong, 0.3))
    assert_true(off > 10.0 * SAME, "and the reading at 0.9 laid at 0.3 reads %.4f apart" % off)


## Smudge Pickup ticked on a brush that never smudged lays
## the brush's colour and the paint under it, both.
func test_ticking_the_pickup_on_a_fresh_brush_paints_and_smudges() -> void:
    var fresh := StateBrushScript.BrushSettingsScript.new() as SaStampBrushSettings
    fresh.color = INK
    fresh.radius = 0.06
    fresh.smudge_pickup_option.enabled = true
    var image := _stroke(fresh, 1.0)
    # Well inside the red band and past where the stroke began, so the carry is
    # the red it has crossed.
    var texel := image.get_pixel(200, int(ROW))
    assert_true(texel.r > INK.r + 0.15, "The stroke carries the red under it, red %.3f" % texel.r)
    assert_true(texel.b > RED.b + 0.15, "and lays the brush's blue beside it, blue %.3f" % texel.b)
    fresh.smudge_color_rate_option.enabled = false
    var pure := _stroke(fresh, 1.0).get_pixel(200, int(ROW))
    assert_true(pure.b < texel.b - 0.1, "Unticked, the colour rate reads nought, a pure smudge, blue %.3f" % pure.b)


## A Krita colour smudge preset at Color Rate 70 per cent
## reads Colour Rate 0.7, straight through.
func test_a_krita_colour_rate_of_seventy_per_cent_reads_seven_tenths() -> void:
    var settings := StateBrushScript.BrushSettingsScript.new() as SaStampBrushSettings
    var options := {
        "PressureColorRate": {"value": "true"},
        "ColorRateValue": {"value": "0.7"},
        "ColorRateUseCurve": {"value": "false"},
    }
    var result := SaKppImport.apply({"name": "Wet Seventy", "engine": SaKppImport.SMUDGE_ENGINE, "options": options}, settings)
    assert_true(settings.smudge_pickup_option.enabled, "The engine ticks the pickup")
    assert_true(settings.smudge_color_rate_option.enabled, "and Krita's ticked Color Rate ticks Colour Rate")
    assert_almost_eq(settings.smudge_color_rate_option.strength, 0.7, 1e-6, "at 0.7, not one less it")
    for name: String in options:
        assert_false((result["unread"] as Array).has(name), "%s was read" % name)


## The noise brush engine turns a dilution over the same way, through the
## page both engines call.
func test_the_page_turns_an_unticked_dilution_into_an_unticked_rate() -> void:
    var turned := SaSmudgePage.color_rate_of(SaSmudgePage.option(0.8))
    assert_false(turned.enabled, "Off stays off, since both offs lay the carry in full")
    assert_almost_eq(turned.strength, 0.2, 1e-6, "with the complement waiting for the tick")


# --- Brushes ------------------------------------------------------------------


func _oil_smudge() -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if String(entry["name"]) == "Oil Smudge":
            var settings := SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry) as SaStampBrushSettings
            settings.color = INK
            return settings
    assert_true(false, "Oil Smudge is a shipped recipe")
    return SaStampBrushSettings.new()


## *settings* written into the scratch store as a build before this row wrote
## them, at the old format and with no colour rate, and read back through the
## store's load, which migrates.
func _through_an_old_file(preset_name: String, settings: SaStampBrushSettings) -> SaStampBrushSettings:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    var stored := store.save_preset(preset_name, settings)
    assert_false(stored.is_empty(), "%s is saved into the scratch store" % preset_name)
    var path := scratch_dir.path_join(stored + SaPresetStore.EXTENSION)
    var lines := FileAccess.get_file_as_string(path).split("\n")
    var kept := PackedStringArray()
    for line: String in lines:
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


## What the dilution *option* read at a pen pressure of *asked*, through the
## table the stroke reads it through, as the old build's dab took it.
func _old_reading(option: SaCurveOption, asked: float, settings: SaStampBrushSettings) -> float:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 0)
    info.pressure = SaTablet.normalize(asked, SaSettings.tablet_max_pressure, 1.0, settings.maker_pressure_curve)
    var fresh := option.duplicate(true) as SaCurveOption
    fresh.set_sensor(option.sensor_for(SaSensor.Id.PRESSURE).duplicate())
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


## The two bands as they stand before any stroke.
func _bare() -> Image:
    var surface := _ground()
    var image := SaExport.get_easel_image_float(surface.easel)
    Fixtures.teardown(surface)
    return image


## One stroke of *settings* across both bands at a pen pressure of *pressure*,
## the pen shown hovering at it first so the press opens at it too, and the
## composite it leaves.
func _stroke(settings: SaStampBrushSettings, pressure: float) -> Image:
    var surface := _ground()
    var brush := StateBrushScript.new()
    brush.surface = surface
    brush.settings = settings
    brush.stroke_seed = 84
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
