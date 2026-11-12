## Tilt and speed press the brush like a real one. A fresh noise
## preset's default bindings stretch the tip along the pen's lean and thin the
## deposit with it, and a fast hand thins the deposit and carries the field
## further, each a sensor binding a painter unbinds in the curve editor.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Done when of the row, a clause a test: the tilt faked at two angles
## gives a wider footprint and a lower height at the steeper, and two speeds a
## lower deposit and a longer drift at the faster. Every footprint and height
## is read off the layer, so it is what the kernel wrote.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoiseTipScript = preload("res://modules/sara-noise-brush-engine/tip/noise_tip.gd")

const RADIUS := 14.0
## The stroke, a straight line along y = 60, twenty samples four pixels apart.
const FROM := Vector2(20.0, 60.0)
const TO := Vector2(100.0, 60.0)
const SAMPLES := 20
## The column the footprint is counted down, well inside the stroke's ends, and
## the rows it is counted over, wider than the flattest tip reaches.
const COLUMN := 60
const ROWS := Vector2i(20, 100)
## The texels the height is averaged over, along the line and away from its
## ends, which every tip of these strokes crosses whole.
const WINDOW := Rect2i(44, 57, 32, 7)
## Two leans across the stroke in degrees, a pen a little off upright and one
## most of the way down.
const SHALLOW := Vector2(0.0, 20.0)
const STEEP := Vector2(0.0, 55.0)
## Milliseconds between two samples: a slow hand of a tenth of a pixel a
## millisecond and a fast one of sixteen.
const SLOW_MS := 40.0
const FAST_MS := 0.25

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _brush = _fresh_brush()


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


## A brush on the defaults a fresh preset carries, with the cut at nought so
## every texel the tip reaches paints and the footprint is the tip's alone.
func _fresh_brush() -> StateNoiseBrushScript:
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 7
    brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    brush.settings.hardness = 1.0
    brush.settings.strength = 0.0
    brush.settings.strength_option.enabled = false
    brush.settings.radius = RADIUS / 256.0
    brush.settings.thickness = 1.0
    return brush


## The bindings a fresh preset carries: Thickness on pressure, the elevation
## and the speed, the stretch on the elevation and Drift on the speed, every
## one a sensor the door already has and every one on a curve page.
func test_a_fresh_preset_binds_tilt_and_speed() -> void:
    var fresh := NoiseBrushSettingsScript.new()
    assert_eq(
        _ids(fresh.thickness_option),
        [SaSensor.Id.PRESSURE, SaSensor.Id.TILT_ELEVATION, SaSensor.Id.SPEED],
        "Thickness reads pressure, elevation and speed"
    )
    assert_eq(_ids(fresh.stretch_option), [SaSensor.Id.TILT_ELEVATION], "the stretch reads the elevation")
    assert_eq(_ids(fresh.drift_option), [SaSensor.Id.SPEED], "and Drift the speed")
    var pages := {}
    for spec: SaOptionSpec in NoiseModuleScript.options():
        if spec.kind == SaOptionSpec.Kind.CURVE_OPTION:
            pages[spec.key] = spec.label
    for key: StringName in [NoiseModuleScript.THICKNESS_OPTION, NoiseModuleScript.STRETCH_OPTION, NoiseModuleScript.DRIFT_OPTION]:
        assert_true(pages.has(key), "%s has a curve page a painter unbinds it on, pages %s" % [key, str(pages)])
    assert_true(
        fresh.options().has("stretch") and fresh.options().has("drift"), "and the door's dynamics prepares both at the press"
    )


## A pen's reported tilt, -1 to 1 an axis, reaches the sensors in degrees: a
## full lean reads as laid flat rather than as one degree off upright.
func test_a_full_lean_reads_as_laid_flat() -> void:
    var degrees: Vector2 = StateNoiseBrushScript.pen_tilt(Vector2(1.0, 0.0))
    assert_almost_eq(SaSensor.tilt_elevation(degrees.x, degrees.y), 0.0, 0.0001, "A full lean is flat")
    assert_almost_eq(SaSensor.tilt_elevation(0.0, 0.0), 1.0, 0.0001, "and no lean upright")


## The stretch leaves a tip alone under no lean or no amount, grows a round
## tip along the lean by the amount, and keeps a tall tip tall.
func test_the_stretch_grows_the_tip_along_the_lean() -> void:
    var same: Vector3 = NoiseTipScript.stretch(Vector2(10.0, 4.0), 0.3, Vector2.ZERO, 1.0)
    assert_true(same.is_equal_approx(Vector3(10.0, 4.0, 0.3)), "No lean, no stretch, %s" % same)
    var tall: Vector3 = NoiseTipScript.stretch(Vector2(4.0, 10.0), 0.3, Vector2(0.001, 0.0), 0.0001)
    assert_true(tall.distance_to(Vector3(4.0, 10.0, 0.3)) < 0.01, "A tall tip under a breath of stretch stays tall, %s" % tall)
    var circle: Vector3 = NoiseTipScript.stretch(Vector2(10.0, 10.0), 0.0, Vector2(0.0, 30.0), 0.5)
    assert_almost_eq(circle.x, 15.0, 0.001, "A round tip half stretched is half as long again")
    assert_almost_eq(circle.y, 10.0, 0.001, "and as wide as it was across")
    assert_almost_eq(absf(sin(circle.z)), 1.0, 0.001, "its long axis down the lean, %s" % circle)


## The Done when's first half: the steeper lean paints a wider footprint and
## a lower height than the shallow one.
func test_the_steeper_tilt_paints_wider_and_thinner() -> void:
    _stroke(STEEP, 0.0)
    var steep_width := _footprint()
    var steep_height := _mean_height()
    _fresh_surface()
    _stroke(SHALLOW, 0.0)
    var shallow_width := _footprint()
    var shallow_height := _mean_height()
    assert_true(shallow_height > 0.05, "The shallow stroke laid height, %.3f mm" % shallow_height)
    assert_true(steep_width > shallow_width + 8, "The steeper lean paints wider, %d px against %d" % [steep_width, shallow_width])
    assert_true(steep_height < 0.8 * shallow_height, "and thinner, %.3f mm against %.3f" % [steep_height, shallow_height])


## A painter who unbinds the lean gets the upright brush back at any tilt.
func test_unbinding_the_lean_paints_the_upright_brush() -> void:
    _stroke(Vector2.ZERO, 0.0)
    var upright_width := _footprint()
    var upright_height := _mean_height()
    _fresh_surface()
    _brush.settings.stretch_option.enabled = false
    _brush.settings.thickness_option.sensor_for(SaSensor.Id.TILT_ELEVATION).active = false
    _stroke(STEEP, 0.0)
    assert_eq(_footprint(), upright_width, "Unbound, the lean stretches nothing")
    assert_almost_eq(_mean_height(), upright_height, 0.005, "and thins nothing")


## The Done when's second half: the faster stroke lays a lower deposit and
## carries the field further along with it.
func test_the_faster_stroke_lays_less_and_drifts_further() -> void:
    _brush.settings.texture_drift = 0.5
    _stroke(Vector2.ZERO, FAST_MS)
    var fast_height := _mean_height()
    var fast_slide: float = _brush.field_slide
    _fresh_surface()
    _brush.settings.texture_drift = 0.5
    _stroke(Vector2.ZERO, SLOW_MS)
    var slow_height := _mean_height()
    var slow_slide: float = _brush.field_slide
    var length := FROM.distance_to(TO)
    assert_true(slow_height > 0.05, "The slow stroke laid height, %.3f mm" % slow_height)
    assert_true(
        fast_height < 0.85 * slow_height, "The faster stroke lays less, %.3f mm against %.3f" % [fast_height, slow_height]
    )
    assert_almost_eq(slow_slide, 0.5 * length, 0.05 * length, "A slow stroke carries the field by the Drift row")
    assert_true(fast_slide > 1.2 * slow_slide, "and a fast one further, %.1f px against %.1f" % [fast_slide, slow_slide])
    assert_true(fast_slide <= length + 0.001, "never past the pen, %.1f px of %.1f" % [fast_slide, length])


## With Drift at nought nothing drifts, whatever the speed.
func test_no_drift_row_no_drift_at_any_speed() -> void:
    _stroke(Vector2.ZERO, FAST_MS)
    assert_almost_eq(_brush.field_slide, 0.0, 0.0001, "Drift at nought carries nothing")


## The stroke from [constant FROM] to [constant TO] at full pressure with the
## pen leaning *tilt* degrees, its samples *interval* milliseconds apart.
func _stroke(tilt: Vector2, interval: float) -> void:
    var time := 1000.0
    _brush.begin_stroke(FROM, 1.0, tilt, time)
    for i in range(1, SAMPLES + 1):
        time += interval
        _brush.add_sample(FROM.lerp(TO, float(i) / SAMPLES), 1.0, tilt, time)
    _brush.end_stroke()


## A new canvas and a new brush on it, for the second stroke of a pair.
func _fresh_surface() -> void:
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface()
    _brush = _fresh_brush()


func _ids(option: SaCurveOption) -> Array:
    var ids := []
    for sensor: SaSensor in option.active_sensors():
        ids.append(sensor.id)
    return ids


## How many texels down [constant COLUMN] the stroke painted at more than half.
func _footprint() -> int:
    var layer := _surface.easel.document.active_layer
    var count := 0
    for y in range(ROWS.x, ROWS.y):
        if _alpha_at(layer, Vector2i(COLUMN, y)) > 0.5:
            count += 1
    return count


## The layer's mean height over [constant WINDOW], nought where it holds none.
func _mean_height() -> float:
    var layer := _surface.easel.document.active_layer
    var rd := GlobalShaderCompiler.get_rd()
    var read := {}
    var side := _side(layer)
    var sum := 0.0
    for y in WINDOW.size.y:
        for x in WINDOW.size.x:
            var at := WINDOW.position + Vector2i(x, y)
            var grid := Vector2i(floori(float(at.x) / side), floori(float(at.y) / side))
            var texture := layer.get_field(grid, SaFieldSpec.HEIGHT)
            if texture == null:
                continue
            if not read.has(grid):
                read[grid] = rd.texture_get_data(texture.rid, 0)
            var local := at - grid * side
            sum += (read[grid] as PackedByteArray).decode_half((local.y * texture.size.x + local.x) * 2)
    return sum / float(WINDOW.size.x * WINDOW.size.y)


func _alpha_at(layer: SaLayer, pixel: Vector2i) -> float:
    var side := _side(layer)
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return 0.0
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(layer.get_field(grid))
    return image.get_pixelv(pixel - grid * side).a


## The side of the layer's chunks in pixels, asked of a chunk rather than
## assumed, by hard rule 3 (sparse chunks).
func _side(layer: SaLayer) -> int:
    for grid: Vector2i in layer.chunks:
        return (layer.chunks[grid] as SaChunk).pixel_size()
    return 1
