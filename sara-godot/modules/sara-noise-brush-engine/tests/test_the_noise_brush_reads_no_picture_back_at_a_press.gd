## The noise brush reads no picture back at a press.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Hard rule 1 keeps every readback out of a stroke, and the Picture field's
## grey mask, which the texture sensor reads on the CPU, was read back from
## a generated pattern's tile at the first press after a pick. The settings make
## it now, when a row or a preset names the pattern, and the press binds what
## was made. The reads are counted where they are made, in
## `SaPatternKernel.picture`, and the sensor is held to the kernel at a dab's
## centre as the texture sensor's suite holds it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoiseFieldReadingScript = preload("res://modules/sara-noise-brush-engine/noise_field_reading.gd")

## A generated pattern Sara ships and not the settings' default, so the name
## is a choice.
const PATTERN: String = "Dot Screen"
const RADIUS: float = 6.0
## The spots one press each is laid on, far enough apart that no two dabs meet.
const SPOTS: Array[Vector2] = [
    Vector2(24, 24),
    Vector2(80, 30),
    Vector2(140, 36),
    Vector2(200, 44),
    Vector2(36, 120),
    Vector2(96, 132),
    Vector2(160, 140),
    Vector2(220, 150),
]

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.radius = RADIUS / 256.0
    _brush.settings.texture_drift = 0.0


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


## The Done when: a generated pattern chosen for the Picture field of a brush
## no stroke has used is read when it is chosen, the presses after read
## nothing, and the texture sensor still reads the mask at every dab's centre.
func test_choosing_reads_the_pattern_and_a_press_reads_nothing() -> void:
    assert_true(SaPatternStore.new().has(PATTERN), "Sara ships %s" % PATTERN)
    var before := SaPatternKernel.reads
    _brush.settings.texture_field = "picture"
    assert_eq(SaPatternKernel.reads - before, 1, "Turning to the Picture field reads the pattern the settings name")
    _brush.settings.picture_name = PATTERN
    var chosen := SaPatternKernel.reads
    assert_eq(chosen - before, 2, "and choosing another reads its tile back once")
    _brush.settings.picture_name = PATTERN
    assert_eq(SaPatternKernel.reads, chosen, "and naming it again reads nothing")
    var low := 1.0
    var high := 0.0
    var worst := 0.0
    for index in SPOTS.size():
        _brush.stroke_seed = 7 + index
        _brush.begin_stroke(SPOTS[index], 1.0)
        assert_eq(SaPatternKernel.reads, chosen, "Press %d reads nothing back" % index)
        var sensor: float = _brush.stroke_info.texture
        var kernel := _kernel_reading(SPOTS[index])
        worst = maxf(worst, absf(sensor - kernel))
        low = minf(low, kernel)
        high = maxf(high, kernel)
        _brush.end_stroke()
    assert_not_null(_brush.field_binding.mask, "The press bound the mask the settings made")
    assert_true(high - low > 0.1, "The pattern under the spots varies, %.3f to %.3f" % [low, high])
    assert_true(worst < 0.01, "and the sensor reads the kernel at each dab's centre, %.5f apart at worst" % worst)
    assert_eq(SaPatternKernel.reads, chosen, "and the strokes read nothing either")


## A preset loaded onto the brush names the pattern through the same writes, so
## its read is at the load. The preset off disk has no store and reads nothing,
## which is every preset a listing or a thumbnail opens.
func test_a_preset_makes_the_mask_at_the_load() -> void:
    var before := SaPatternKernel.reads
    var preset := NoiseSettingsScript.new()
    preset.texture_field = "picture"
    preset.picture_name = PATTERN
    assert_eq(SaPatternKernel.reads, before, "Settings with no store read nothing")
    SaPresetStore.copy_settings(preset, _brush.settings)
    assert_eq(SaPatternKernel.reads, before + 1, "The load reads the tile once")
    assert_not_null(_brush.settings.chosen_picture.mask, "and makes the mask")
    _brush.begin_stroke(SPOTS[0], 1.0)
    assert_eq(SaPatternKernel.reads, before + 1, "and the press reads nothing")
    assert_true(_brush.field_binding.mask == _brush.settings.chosen_picture.mask, "The press binds the mask the load made")
    _brush.end_stroke()


## A field that is not a picture makes nothing, whatever the name says.
func test_another_field_reads_nothing() -> void:
    var before := SaPatternKernel.reads
    _brush.settings.texture_field = "grain"
    _brush.settings.picture_name = PATTERN
    assert_eq(SaPatternKernel.reads, before, "A grain brush naming a pattern reads nothing")
    _brush.begin_stroke(SPOTS[0], 1.0)
    _brush.end_stroke()
    assert_eq(SaPatternKernel.reads, before, "and neither does its stroke")
    assert_null(_brush.field_binding.mask, "and binds no mask")


## Settings handed to the brush without a store never made the pattern, and
## the press does not make it either: it paints as if solid and says why.
func test_settings_with_no_store_paint_solid_rather_than_read() -> void:
    var bare := NoiseSettingsScript.new()
    bare.radius = RADIUS / 256.0
    bare.texture_field = "picture"
    bare.picture_name = PATTERN
    _brush.settings = bare
    var before := SaPatternKernel.reads
    _brush.begin_stroke(SPOTS[0], 1.0)
    _brush.end_stroke()
    assert_eq(SaPatternKernel.reads, before, "The press reads nothing")
    assert_null(_brush.field_binding.picture, "and binds no picture")
    assert_true(_brush.field_binding.error.contains("never chosen"), "and says why: %s" % _brush.field_binding.error)


## The lightness the probe kernel reads at *centre* for the field the last
## press laid, at along nought and in the middle of the path, which is where a
## press's centre is.
func _kernel_reading(centre: Vector2) -> float:
    var region := Rect2i(Vector2i(centre), Vector2i.ONE)
    var probe: SaTexture = _brush.probe_field(region, centre, Vector2.RIGHT, 0.0, RADIUS)
    @warning_ignore("static_called_on_instance")
    var image: Image = SaExport.get_texture_image_float(probe)
    return image.get_pixel(0, 0).g
