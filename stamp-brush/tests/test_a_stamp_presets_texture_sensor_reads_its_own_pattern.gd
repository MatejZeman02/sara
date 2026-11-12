## A stamp preset's texture sensor reads its own pattern.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The stamp writes the value of its paper at the dab's centre into
## `SaStrokeInfo.texture`, so a preset whose Hue is bound to the texture sensor
## turns with the paper rather than reading a fixed middle grey. The suite holds the reading to the
## texels the dab binds, paints
## single dabs over a paper of four greys and reads their hue off the layer,
## and paints one stroke twice, once with the reading and once without, to show
## a preset not bound to the sensor is not moved by it.
##
## **The paper is four greys, one texel each, written as a PNG**, the way
## `test_pattern_tone.gd` writes its ramp, so it comes in at the door a
## painter's paper does. A tile four texels wide puts a dab's centre on a known
## grey by its column alone.
extends "res://tests/test_framework.gd"

## A readback of the bound paper and a dab are both GPU work.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

static var scratch_dir: String = SaDataRoot.path("test_f2_stamp_texture_sensor")
const PAPER_FILE := "sensor_steps.png"
## What the store calls the file above, its stem made readable.
const PAPER_NAME := "Sensor Steps"
const GREYS: Array[int] = [0, 85, 170, 255]

## A strong orange, so a turn of hue is large enough to read.
const ORANGE: Color = Color(0.85, 0.4, 0.15, 1.0)
## How far the Hue row is bound to the sensor, a clear but moderate amount.
const BINDING: float = 0.3

## One dab each, twenty texels apart so no two meet, and one texel further
## along the tile every time, so the eight read each grey twice.
const SPOTS: Array[Vector2] = [
    Vector2(40, 40),
    Vector2(61, 40),
    Vector2(82, 40),
    Vector2(103, 40),
    Vector2(40, 80),
    Vector2(61, 80),
    Vector2(82, 80),
    Vector2(103, 80),
]

var _surface: SaSurface = null


func before_each() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var image := Image.create_empty(GREYS.size(), 1, false, Image.FORMAT_RGBA8)
    for x in GREYS.size():
        var level := float(GREYS[x]) / 255.0
        image.set_pixel(x, 0, Color(level, level, level, 1.0))
    image.save_png(scratch_dir.path_join(PAPER_FILE))
    _surface = Fixtures.make_surface()


func after_each() -> void:
    Fixtures.teardown(_surface)
    _surface = null
    if DirAccess.dir_exists_absolute(scratch_dir):
        var dir := DirAccess.open(scratch_dir)
        for file in dir.get_files():
            dir.remove(file)
        DirAccess.remove_absolute(scratch_dir)


# --- The reading -------------------------------------------------------------------


## The reading at a dab's centre is the texel the dab binds there, at the
## painter's offset, turned over by the invert, and it costs one readback.
func test_the_reading_is_the_texel_the_dab_binds() -> void:
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    var texels := _texels(dab_pattern, settings)
    assert_eq(texels.size(), GREYS.size(), "The paper binds its four texels")
    var low := 1.0
    var high := 0.0
    for x in range(-6, 10):
        var centre := Vector2(float(x) + 0.7, 3.2)
        var reading := dab_pattern.sensor_reading(settings, centre)
        assert_almost_eq(reading, texels[posmod(x, GREYS.size())], 1e-6, "The centre at %.1f reads its texel" % centre.x)
        low = minf(low, reading)
        high = maxf(high, reading)
    assert_true(high - low > 0.9, "and the four greys span the paper, %.2f to %.2f" % [low, high])
    settings.texture_offset_x = 1
    assert_almost_eq(dab_pattern.sensor_reading(settings, Vector2(2.5, 0.5)), texels[3], 1e-6, "The offset moves the grid")
    settings.texture_offset_x = 0
    settings.texture_invert = true
    var turned := dab_pattern.sensor_reading(settings, Vector2(1.5, 0.5))
    assert_almost_eq(turned, 1.0 - texels[1], 1e-6, "and invert turns it over")
    assert_eq(dab_pattern.reads, 1, "Every reading above came from one readback")
    assert_eq(dab_pattern.builds, 1, "of the one texture the dab binds")


## With no paper named the sensor reads the middle grey it read before, and
## nothing is read back.
func test_no_paper_reads_a_middle_grey() -> void:
    var dab_pattern := _dab_pattern()
    var settings := _settings()
    settings.pattern_name = ""
    var reading := dab_pattern.sensor_reading(settings, Vector2(1.5, 0.5))
    assert_almost_eq(reading, SaSensor.NEUTRAL_TEXTURE, 1e-6, "A middle grey")
    assert_eq(dab_pattern.reads, 0, "and no readback")
    settings.pattern_name = "No Such Paper"
    reading = dab_pattern.sensor_reading(settings, Vector2(1.5, 0.5))
    assert_almost_eq(reading, SaSensor.NEUTRAL_TEXTURE, 1e-6, "and so for a lost name")


# --- Painted -----------------------------------------------------------------------


## A stamp preset whose Hue is bound to the texture sensor lays
## dabs whose hue follows the paper under their centres.
func test_the_hue_follows_the_pattern() -> void:
    var brush := _brush()
    brush.settings.hue_option.bind_texture(BINDING)
    var readings: Array[float] = []
    var turns: Array[float] = []
    var picked := _polar(ORANGE)
    for spot: Vector2 in SPOTS:
        _dab(brush, spot)
        readings.append(brush.dab_pattern.sensor_reading(brush.settings, spot))
    for index in SPOTS.size():
        var got := _display_at(Vector2i(SPOTS[index]))
        assert_true(got.a > 0.9, "Spot %d painted, alpha %.3f" % [index, got.a])
        turns.append(wrapf(_polar(got).z - picked.z, -PI, PI))
    assert_true(readings.max() - readings.min() > 0.9, "The paper under the spots spans its greys")
    var r := _correlation(readings, turns)
    assert_true(r > 0.95, "The hue turns with the paper, r = %.3f" % r)
    assert_true(turns.max() > 0.05 and turns.min() < -0.05, "both ways round, %.3f to %.3f rad" % [turns.min(), turns.max()])
    for index in 4:
        assert_almost_eq(turns[index], turns[index + 4], 1e-3, "and one grey is one hue, spot %d" % index)
    assert_eq(brush.dab_pattern.reads, 1, "Eight strokes read the paper back once")


## A preset with a paper that is not bound to the
## sensor paints what it painted while the sensor read a middle grey, at a
## tolerance of nought, texture option on so the paper is in the dab.
func test_a_preset_not_bound_to_the_sensor_paints_as_before() -> void:
    var reading := _brush()
    reading.settings.texture_option.enabled = true
    reading.settings.texture_option.strength = 1.0
    _stroke(reading)
    var with_reading := _layer_floats()
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface()
    var grey := _brush(NeutralPattern.new(SaPatternStore.new([scratch_dir])))
    grey.settings.texture_option.enabled = true
    grey.settings.texture_option.strength = 1.0
    _stroke(grey)
    var with_grey := _layer_floats()
    assert_true(with_reading.size() > 0, "The stroke painted")
    assert_eq(with_reading.keys(), with_grey.keys(), "over the same chunks")
    for grid: Vector2i in with_reading:
        assert_true(with_reading[grid] == with_grey[grid], "and chunk %s is the same bytes" % grid)


# --- Helpers -----------------------------------------------------------------------


## The pattern half as it was before F2: the paper bound, the sensor never fed.
class NeutralPattern:
    extends SaDabPattern

    func sensor_reading(_settings: Resource, _centre: Vector2, _info: SaStrokeInfo = null) -> float:
        return SaSensor.NEUTRAL_TEXTURE


func _dab_pattern() -> SaDabPattern:
    return SaDabPattern.new(SaPatternStore.new([scratch_dir]))


func _settings() -> Resource:
    var settings := SettingsScript.new()
    settings.pattern_name = PAPER_NAME
    return settings


## A stamp over the surface with the paper named, its pattern half over the
## scratch folder alone so no shipped paper can answer the name.
func _brush(pattern: SaDabPattern = null) -> StateBrushScript:
    var brush := StateBrushScript.new()
    brush.dab_pattern = pattern if pattern != null else _dab_pattern()
    brush.surface = _surface
    brush.stroke_seed = 7
    brush.settings.color = ORANGE
    brush.settings.radius = 6.0 / 256.0
    brush.settings.hardness = GammaFloat.new(1.0, 1.0)
    brush.settings.opacity_by_pressure = false
    brush.settings.pattern_name = PAPER_NAME
    return brush


func _texels(dab_pattern: SaDabPattern, settings: Resource) -> PackedFloat32Array:
    var texture := dab_pattern.texture(settings)
    if texture == null:
        return PackedFloat32Array()
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()


## One press and release at *at*, which a mouse paints as one dab.
func _dab(brush: StateBrushScript, at: Vector2) -> void:
    _surface.view.mouse_position = at
    brush.handle_input(_button(true))
    brush.handle_input(_button(false))


## A press, eight motions to the right and a release.
func _stroke(brush: StateBrushScript) -> void:
    _surface.view.mouse_position = Vector2(100, 100)
    brush.handle_input(_button(true))
    for step in range(1, 9):
        _surface.view.mouse_position = Vector2(100 + 4 * step, 100)
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = 1.0
        brush.handle_input(motion)
    brush.handle_input(_button(false))


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## Every chunk of the active layer, as its raw bytes.
func _layer_floats() -> Dictionary:
    var layer := _surface.easel.document.active_layer
    var out := {}
    for grid: Vector2i in layer.chunks:
        out[grid] = GlobalShaderCompiler.get_rd().texture_get_data(layer.get_field(grid).rid, 0)
    return out


## The layer's colour at *pixel*, turned back into what a picker shows.
func _display_at(pixel: Vector2i) -> Color:
    var document := _surface.easel.document
    var layer := document.active_layer
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        var here := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
        if not layer.chunks.has(here):
            return Color(0, 0, 0, 0)
        @warning_ignore("static_called_on_instance")
        var image: Image = SaExport.get_texture_image_float(layer.get_field(here))
        var stored := image.get_pixelv(pixel - here * side)
        return document.color_space.to_display(stored) if document.color_space != null else stored
    return Color(0, 0, 0, 0)


## Oklab lightness, chroma and hue of a display colour.
func _polar(color: Color) -> Vector3:
    var curve := SaTransferFunction.srgb()
    var linear := Vector3(curve.decode(color.r), curve.decode(color.g), curve.decode(color.b))
    return SaOklab.to_polar(SaOklab.from_linear_srgb(linear))


func _correlation(xs: Array[float], ys: Array[float]) -> float:
    var n := float(xs.size())
    var mean_x := 0.0
    var mean_y := 0.0
    for i in xs.size():
        mean_x += xs[i] / n
        mean_y += ys[i] / n
    var sxy := 0.0
    var sxx := 0.0
    var syy := 0.0
    for i in xs.size():
        sxy += (xs[i] - mean_x) * (ys[i] - mean_y)
        sxx += (xs[i] - mean_x) * (xs[i] - mean_x)
        syy += (ys[i] - mean_y) * (ys[i] - mean_y)
    return sxy / sqrt(maxf(sxx * syy, 1e-12))
