## Hue and saturation follow the texture.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Design 5 of the noise brush's spec: a texture sensor in the door answers the
## brush's texture at the dab's centre, its second channel or its lightness, and
## the noise brush's Chroma variation row binds Hue and Saturation to it. The
## suite reads the sensor and its binding in the door, holds the CPU reading the
## sensor is fed from to the probe kernel that reads the field on the GPU, texel
## for texel in stroke coordinates,
## and paints dabs over a known field and reads their hue and saturation off
## the layer. Both engines, as the sensor suite does, because the sensor list is theirs
## alike and the stamp has to paint a preset that ticks it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const NoiseFieldReadingScript = preload("res://modules/sara-noise-brush-engine/noise_field_reading.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## A strong orange, so a turn of hue and a fall in chroma are both large
## enough to read.
const ORANGE: Color = Color(0.85, 0.4, 0.15, 1.0)
const RADIUS: float = 4.0
## The spots one dab each is laid on, far enough apart that no two dabs meet.
const SPOTS: Array[Vector2] = [
    Vector2(24, 24),
    Vector2(72, 24),
    Vector2(120, 24),
    Vector2(168, 24),
    Vector2(216, 24),
    Vector2(24, 80),
    Vector2(72, 80),
    Vector2(120, 80),
    Vector2(168, 80),
    Vector2(216, 80),
    Vector2(24, 136),
    Vector2(72, 136),
    Vector2(120, 136),
    Vector2(168, 136),
    Vector2(216, 136),
    Vector2(24, 192),
    Vector2(72, 192),
    Vector2(120, 192),
    Vector2(168, 192),
    Vector2(216, 192),
]

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = ORANGE
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    # No shift, so a press at full pressure paints every texel of the dab and
    # its centre is the dab's colour at full.
    _brush.settings.strength = 0.0
    _brush.settings.strength_option.enabled = false
    _brush.settings.radius = RADIUS / 256.0
    _brush.settings.texture_field = "grain"
    _brush.settings.texture_channels = 2
    _brush.settings.texture_relief = 1.0


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


# --- The sensor, in the door -----------------------------------------------------


func test_the_sensor_is_the_doors_after_lift_up_and_the_list_offers_it() -> void:
    assert_eq(SaSensor.id_of("texture"), int(SaSensor.Id.TEXTURE), "The key names the id")
    assert_eq(int(SaSensor.Id.TEXTURE), int(SaSensor.Id.LIFT_UP) + 1, "and it comes after lift-up")
    assert_true(SaSensor.is_available(SaSensor.Id.TEXTURE), "and it is not greyed")
    assert_eq(SaSensorList.LABELS.get("texture", ""), "Texture", "The sensor list both engines' pages use has a row")
    var list := SaSensorList.new()
    assert_not_null(list.find_child("Row_texture", true, false), "and builds it")
    list.free()


func test_it_reads_what_the_engine_wrote_and_a_middle_grey_otherwise() -> void:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 7)
    var sensor := SaSensor.create(SaSensor.Id.TEXTURE, true)
    assert_almost_eq(sensor.value(info), 0.5, 1e-6, "A press starts at a middle grey")
    info.texture = 0.2
    assert_almost_eq(sensor.value(info), 0.2, 1e-6, "and the sensor answers what the engine wrote")
    info.hovering = true
    assert_almost_eq(sensor.value(info), 0.5, 1e-6, "and a middle grey while hovering")
    info.begin(Vector2.ZERO, 8)
    assert_almost_eq(info.texture, 0.5, 1e-6, "and the next press puts it back")


func test_the_binding_is_a_line_through_a_middle_grey() -> void:
    var option := SaCurveOption.new()
    option.use_curve = true
    option.bind_texture(0.4)
    var sensor := option.sensor_for(SaSensor.Id.TEXTURE)
    assert_not_null(sensor, "Binding ticks the texture sensor")
    assert_true(sensor.active and option.enabled, "on, with the option on")
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 7)
    for pair: Vector2 in [Vector2(0.0, 0.3), Vector2(0.5, 0.5), Vector2(1.0, 0.7)]:
        info.texture = pair.x
        assert_almost_eq(sensor.parameter(info), pair.y, 1e-3, "a texture of %.1f reads %.1f" % [pair.x, pair.y])
    option.bind_texture(0.4)
    assert_true(option.sensor_for(SaSensor.Id.TEXTURE) == sensor, "The same binding again writes nothing")
    option.bind_texture(0.0)
    assert_null(option.sensor_for(SaSensor.Id.TEXTURE), "and nought drops the sensor")


# --- The reading the sensor is fed from ---------------------------------------------


## The CPU reading is the reading the kernel makes, both channels, texel for
## texel over a patch of a straight stroke, in its stroke coordinates: along
## from where the patch's stroke starts, across over the tip's half-width. For
## each field and channel count and either way a picture reads, a few strokes
## each, a seed apart, each heading its own way with its own length behind it.
## The texture sensor reads the same down the middle of the path.
func test_the_cpu_reading_is_the_kernels_texel_for_texel() -> void:
    var cases := [["grain", 1, false], ["grain", 2, false], ["bristle", 1, false], ["bristle", 2, false]]
    cases.append_array([["picture", 1, false], ["picture", 1, true]])
    for setup: Array in cases:
        _brush.settings.texture_field = setup[0]
        _brush.settings.texture_channels = setup[1]
        _brush.settings.picture_invert = setup[2]
        var worst := Vector2.ZERO
        var low := Vector2.ONE
        var high := Vector2.ZERO
        var sensor_worst := 0.0
        for index in 4:
            _brush.lay_field(7 + index)
            var start := Vector2(SPOTS[index * 5]) + Vector2(index * 3, index * 5)
            var direction := Vector2.from_angle(0.7 * index - 0.4)
            var along := 11.0 * index - 6.0
            var half_width := 6.0 + 2.5 * index
            var region := Rect2i(Vector2i(start) - Vector2i(10, 10), Vector2i(21, 21))
            var kernel := _probe(region, start, direction, along, half_width)
            var normal := Vector2(-direction.y, direction.x)
            for y in region.size.y:
                for x in region.size.x:
                    var offset := Vector2(region.position + Vector2i(x, y)) - start
                    var cpu: Vector2 = NoiseFieldReadingScript.at(
                        _brush.field_binding.values,
                        _brush.field_binding.mask,
                        along + offset.dot(direction),
                        offset.dot(normal) / half_width,
                        half_width
                    )
                    var texel := kernel.get_pixel(x, y)
                    worst = worst.max(Vector2(absf(cpu.x - texel.r), absf(cpu.y - texel.g)))
                    low = low.min(Vector2(texel.r, texel.g))
                    high = high.max(Vector2(texel.r, texel.g))
            var sensor: float = NoiseFieldReadingScript.sensor_reading(
                _brush.field_binding.values, _brush.field_binding.mask, along
            )
            var middle := _probe(Rect2i(Vector2i(start), Vector2i.ONE), Vector2(Vector2i(start)), direction, along, half_width)
            sensor_worst = maxf(sensor_worst, absf(sensor - middle.get_pixel(0, 0).g))
        var label := "%s with %d channel(s)%s" % [setup[0], setup[1], ", inverted" if setup[2] else ""]
        assert_true(
            high.x - low.x > 0.1, "%s: the kernel reads a pressure map that varies, %.3f to %.3f" % [label, low.x, high.x]
        )
        assert_true(high.y - low.y > 0.1, "%s: and a lightness that varies, %.3f to %.3f" % [label, low.y, high.y])
        assert_true(worst.x < 0.01, "%s: the CPU reads the pressure map the kernel reads, %.5f apart at worst" % [label, worst.x])
        assert_true(worst.y < 0.01, "%s: and the lightness, %.5f apart at worst" % [label, worst.y])
        assert_true(sensor_worst < 0.01, "%s: and the sensor reads the middle of the path, %.5f apart" % [label, sensor_worst])


# --- Painted ---------------------------------------------------------------------


## The case that matters: dabs painted over a known field, each carrying the hue and
## saturation the field under its centre asks for, and the two following it.
func test_dabs_over_a_known_field_follow_it_in_hue_and_saturation() -> void:
    _brush.settings.chroma_variation = 1.0
    var painted := _paint_spots()
    var picked := _polar(ORANGE)
    var readings: Array[float] = []
    var turns: Array[float] = []
    var chromas: Array[float] = []
    var worst := 0.0
    for index in SPOTS.size():
        _brush.lay_field(7 + index)
        var reading := _kernel_reading(SPOTS[index])
        var expected := _expected(reading)
        var got: Color = painted[index]
        worst = maxf(worst, maxf(absf(got.r - expected.r), maxf(absf(got.g - expected.g), absf(got.b - expected.b))))
        var polar := _polar(got)
        readings.append(reading)
        turns.append(wrapf(polar.z - picked.z, -PI, PI))
        chromas.append(polar.y)
    var spread: float = readings.max() - readings.min()
    assert_true(spread > 0.4, "The field under the spots varies, %.2f to %.2f" % [readings.min(), readings.max()])
    assert_true(worst < 0.01, "Each dab is the colour its field asks for, %.4f apart at worst" % worst)
    var hue_r := _correlation(readings, turns)
    var chroma_r := _correlation(readings, chromas)
    assert_true(hue_r > 0.95, "The hue turns with the field, r = %.3f" % hue_r)
    assert_true(chroma_r > 0.95, "and the chroma rises with it, r = %.3f" % chroma_r)
    var swing: float = NoiseSettingsScript.HUE_SWING * PI
    var both: bool = turns.max() > 0.3 * swing and turns.min() < -0.3 * swing
    assert_true(both, "Both ways round, %.3f to %.3f rad" % [turns.min(), turns.max()])


## At nought the row binds nothing and every dab is the picked colour.
func test_at_nought_every_dab_is_the_picked_colour() -> void:
    var painted := _paint_spots()
    for index in SPOTS.size():
        var got: Color = painted[index]
        assert_true(_close(got, ORANGE, 0.002), "Spot %d is the picked colour, %s" % [index, got])
    assert_null(_brush.settings.hue_option.sensor_for(SaSensor.Id.TEXTURE), "and Hue carries no texture sensor")


## The row: after Blend mode on the General page, off the bar, with a Hue page
## beside Saturation, and a texture sensor a painter ticked by hand at nought
## is left theirs.
func test_the_row_binds_hue_and_saturation_and_leaves_a_hand_tick_alone() -> void:
    var keys: Array[StringName] = []
    var pages: Array[String] = []
    var chroma: SaOptionSpec = null
    for spec: SaOptionSpec in NoiseModuleScript.options():
        if spec.page == NoiseModuleScript.PAGE:
            keys.append(spec.key)
        pages.append(spec.label)
        if spec.key == &"chroma_variation":
            chroma = spec
    assert_not_null(chroma, "The page has a Colour variation row")
    assert_eq(keys[keys.size() - 1], &"chroma_variation", "last, after Blend mode as the spec orders it")
    assert_false(chroma.bar, "and off the bar")
    assert_true(pages.has("Hue") and pages.has("Saturation"), "Hue and Saturation have pages of their own")

    var settings := NoiseSettingsScript.new()
    settings.saturation_option.set_sensor(SaSensor.create(SaSensor.Id.TEXTURE, true))
    settings.bind_chroma()
    assert_not_null(settings.saturation_option.sensor_for(SaSensor.Id.TEXTURE), "A hand tick at nought survives a press")
    settings.chroma_variation = 0.5
    settings.bind_chroma()
    var hue: SaSensor = settings.hue_option.sensor_for(SaSensor.Id.TEXTURE)
    var saturation: SaSensor = settings.saturation_option.sensor_for(SaSensor.Id.TEXTURE)
    assert_not_null(hue, "The row binds Hue")
    assert_almost_eq(hue.curve[1].y - hue.curve[0].y, 0.5 * NoiseSettingsScript.HUE_SWING, 1e-6, "at its swing")
    var rise: float = saturation.curve[1].y - saturation.curve[0].y
    assert_almost_eq(rise, 0.5 * NoiseSettingsScript.SATURATION_SWING, 1e-6, "and Saturation at its")
    settings.chroma_variation = 0.0
    settings.bind_chroma()
    assert_null(settings.hue_option.sensor_for(SaSensor.Id.TEXTURE), "and moving it back to nought unbinds both")


# --- The stamp -------------------------------------------------------------------


## The stamp offers the sensor through the same list, and a preset of it that
## ticks the sensor on Hue and Saturation paints. This preset names no paper,
## so the sensor reads a middle grey there and the colour is the picked one.
## The stamp's own paper is read by a suite in the stamp module.
func test_a_stamp_preset_that_uses_it_paints() -> void:
    var stamp := StateBrushScript.new()
    stamp.surface = _surface
    stamp.settings.color = ORANGE
    stamp.settings.radius = 6.0 / 256.0
    stamp.settings.hardness = GammaFloat.new(1.0, 1.0)
    stamp.settings.opacity_by_pressure = false
    stamp.settings.hue_option.bind_texture(0.3)
    stamp.settings.saturation_option.bind_texture(0.3)
    var view := _surface.view
    view.mouse_position = Vector2(100, 100)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    stamp.handle_input(press)
    for step in range(1, 9):
        view.mouse_position = Vector2(100 + 4 * step, 100)
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = 1.0
        stamp.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    stamp.handle_input(release)
    var got := _display_at(Vector2i(112, 100))
    assert_true(got.a > 0.9, "The stamp painted, alpha %.3f" % got.a)
    assert_true(_close(got, ORANGE, 0.01), "in the picked colour, the sensor reading a middle grey there, %s" % got)


# --- Helpers ---------------------------------------------------------------------


## One press on each spot, each with a seed of its own, since a press's centre
## reads its field at along nought wherever it lands, and the display colour
## at each spot's centre afterwards.
func _paint_spots() -> Array[Color]:
    for index in SPOTS.size():
        _brush.stroke_seed = 7 + index
        _brush.begin_stroke(SPOTS[index], 1.0)
        _brush.end_stroke()
    var out: Array[Color] = []
    for spot: Vector2 in SPOTS:
        out.append(_display_at(Vector2i(spot)))
    return out


## The field's lightness at *centre* as the probe kernel reads it on the GPU,
## at the centre of a press, which is along nought on its own path.
func _kernel_reading(centre: Vector2) -> float:
    var region := Rect2i(Vector2i(centre), Vector2i.ONE)
    return _probe(region, centre, Vector2.RIGHT, 0.0, RADIUS).get_pixel(0, 0).g


## Both readings over *region* as the probe kernel makes them for a straight
## stroke through *start* along *direction*, read back for the suite.
func _probe(region: Rect2i, start: Vector2, direction: Vector2, along: float, half_width: float) -> Image:
    var probe: SaTexture = _brush.probe_field(region, start, direction, along, half_width)
    @warning_ignore("static_called_on_instance")
    return SaExport.get_texture_image_float(probe)


## The picked colour moved as a texture of *reading* asks, at the full row.
func _expected(reading: float) -> Color:
    var dab := SaDabParams.new()
    dab.hue_shift = NoiseSettingsScript.HUE_SWING * (2.0 * reading - 1.0)
    dab.saturation_shift = NoiseSettingsScript.SATURATION_SWING * (2.0 * reading - 1.0)
    return SaColorDynamics.apply(ORANGE, dab)


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


func _close(a: Color, b: Color, tolerance: float) -> bool:
    return absf(a.r - b.r) < tolerance and absf(a.g - b.g) < tolerance and absf(a.b - b.b) < tolerance


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
    if sxx <= 0.0 or syy <= 0.0:
        return 0.0
    return sxy / sqrt(sxx * syy)
