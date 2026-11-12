## The noise brush's radius follows the pen's pressure when a preset asks.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A Grain Round stroke pressed from 0.2 to 0.85 and back
## thinned its grain at the ends and kept its whole width, so rows of strokes
## read as rows of round caps. A preset's `pressure` block now takes `radius`,
## Grain Round and Bristle Flat ship with it, and `pen_settings` turns it on
## for any noise preset. The stroke below is laid through the tool's own calls
## on a real surface and its width read back column by column, at a Strength of
## minus one so every texel under the tip takes paint and the grain cannot
## thin a column the tip covers.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoisePointScript = preload("res://modules/sara-noise-brush-engine/noise_point.gd")

## The canvas's side, and the Size row's radius on it in pixels.
const SIDE := 256
const RADIUS := 16.0
## The stroke runs along [constant ROW] from [constant FROM] to [constant TO],
## a sample every [constant STEP] pixels, pressed from [constant LIGHTEST] to
## one over its middle third and back. The lightest press is a half, which
## the cut lays whole, since a light press lays specks and a
## column of specks is no width. The radius at a half is still 0.36 of the
## row's, so the taper reads as clearly as from 0.1. A door stroke
## starts from [constant SENT], which the harness pen's table lifts past a half.
const ROW := 128.0
const FROM := 40.0
const TO := 216.0
const STEP := 4.0
const LIGHTEST := 0.5
const SENT := 0.1
## A texel counts as painted from this alpha up, half the stroke's own.
const PAINTED := 0.5
## The presets that ship with the radius on the pen's pressure, the two that
## first took it, Wood Grain, made of Bristle Flat, Wet Into Wet, made of it,
## and the two line makers of the Look style, a pen and a pencil, which taper
## as a drawn line does.
const TAPERING: Array[String] = ["Grain Round", "Bristle Flat", "Wood Grain", "Wet Into Wet", "Ribbon Pen", "Graphite Pencil"]
## The table every door session reads a stroke step's pressure through, one
## number a line, read here as data so the suite names no harness class.
const DOOR_TABLE := "res://harness/drivers/pen_pressure_curve.txt"

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
var _images: Dictionary = {}
## The pen's correction as the suite found it, put back after each case.
var _correction := PackedFloat32Array()


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(SIDE, SIDE))
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    _brush.settings.strength = -1.0
    _brush.settings.thickness = 0.0
    _brush.settings.radius = RADIUS / float(SIDE)
    _images = {}
    _correction = SaTablet.correction


func after_each() -> void:
    SaTablet.correction = _correction
    _brush = null
    _images = {}
    Fixtures.teardown(_surface)
    _surface = null


## The pressure at sample *index* of *count*: *lightest* at both ends,
## rising along a straight line over the first third, held at one over the
## middle third and falling again over the last, the way a hand presses in,
## draws and lets go.
func _pressure_at(index: int, count: int, lightest: float) -> float:
    var share := float(index) / float(count - 1)
    return lerpf(lightest, 1.0, clampf(3.0 * minf(share, 1.0 - share), 0.0, 1.0))


## The stroke, pressed in from *lightest* and let go to it again.
func _taper(lightest: float = LIGHTEST) -> void:
    var count := int((TO - FROM) / STEP) + 1
    _brush.begin_stroke(Vector2(FROM, ROW), _pressure_at(0, count, lightest))
    for index in range(1, count):
        _brush.add_sample(Vector2(FROM + STEP * index, ROW), _pressure_at(index, count, lightest))
    _brush.end_stroke()


## The active layer's alpha at document pixel *at*, each chunk read back once.
func _alpha(at: Vector2i) -> float:
    var layer := _surface.easel.document.active_layer
    var side := 0
    for grid: Vector2i in layer.chunks:
        side = (layer.chunks[grid] as SaChunk).pixel_size()
        break
    if side == 0:
        return 0.0
    var grid := Vector2i(floori(float(at.x) / side), floori(float(at.y) / side))
    if not layer.chunks.has(grid):
        return 0.0
    if not _images.has(grid):
        @warning_ignore("static_called_on_instance")
        _images[grid] = SaExport.get_texture_image_float(layer.get_field(grid))
    return (_images[grid] as Image).get_pixelv(at - grid * side).a


## How many texels of the column at *x* the stroke painted.
func _width_at(x: float) -> int:
    var painted := 0
    for y in SIDE:
        if _alpha(Vector2i(int(x), y)) >= PAINTED:
            painted += 1
    return painted


## The widths at the stroke's first sample, its middle and its last.
func _widths() -> Vector3i:
    var middle := FROM + STEP * floorf((TO - FROM) / STEP / 2.0)
    return Vector3i(_width_at(FROM), _width_at(middle), _width_at(TO))


func test_with_the_radius_on_pressure_the_ends_are_under_half_the_middle() -> void:
    _brush.settings.apply_pen_settings({"radius": {"enabled": true, "sensors": ["pressure"]}})
    _taper()
    var widths := _widths()
    assert_true(widths.y >= int(1.8 * RADIUS), "The middle, at a full press, is the whole tip wide, %d px" % widths.y)
    assert_true(widths.x * 2 < widths.y, "The first end is %d px, under half the middle's %d" % [widths.x, widths.y])
    assert_true(widths.z * 2 < widths.y, "and the last is %d px, under half as well" % widths.z)
    assert_true(widths.x > 0 and widths.z > 0, "and each still lays a mark")


## A door stroke reaches the brush through the harness pen's table, which
## lifts a light pressure a long way: 0.1 sent is about 0.6 at the brush. The
## radius's curve is the stamp switch's power, the curve that table was fitted
## to, so the stroke a step sends still comes to a point.
func test_a_door_stroke_read_through_the_harness_table_comes_to_a_point_as_well() -> void:
    var table := PackedFloat32Array()
    for line in FileAccess.get_file_as_string(DOOR_TABLE).split("\n", false):
        if String(line).strip_edges().is_valid_float():
            table.append(String(line).to_float())
    assert_true(table.size() > 2, "The door's table was read, %d entries" % table.size())
    assert_true(SaTablet.correct(SENT, table) > 0.5, "and it lifts %.1f sent to %.2f" % [SENT, SaTablet.correct(SENT, table)])
    SaTablet.correction = table
    _brush.settings.apply_pen_settings({"radius": {"enabled": true, "sensors": ["pressure"]}})
    _taper(SENT)
    var widths := _widths()
    assert_true(widths.x * 2 < widths.y, "The first end is %d px, under half the middle's %d" % [widths.x, widths.y])
    assert_true(widths.z * 2 < widths.y, "and the last %d px" % widths.z)


func test_with_it_off_the_stroke_keeps_its_width() -> void:
    _taper()
    var widths := _widths()
    assert_true(widths.y >= int(1.8 * RADIUS), "The middle is the whole tip wide, %d px" % widths.y)
    assert_true(absi(widths.x - widths.y) <= 2, "The first end is %d px, the middle's %d" % [widths.x, widths.y])
    assert_true(absi(widths.z - widths.y) <= 2, "and so is the last, %d px" % widths.z)


func test_the_radius_falls_to_a_third_at_no_pressure_and_rises_to_the_whole_row() -> void:
    var curve := NoiseBrushSettingsScript.radius_pressure_curve()
    assert_almost_eq(curve[0].y, 1.0 / 3.0, 1e-6, "A third of the row at no pressure")
    assert_almost_eq(curve[curve.size() - 1].y, 1.0, 1e-6, "and the whole row at a full press")
    for index in range(1, curve.size()):
        assert_true(curve[index].y >= curve[index - 1].y, "rising all the way, point %d" % index)


func test_pen_settings_names_the_radius_by_the_field_and_by_size() -> void:
    var by_field: Resource = NoiseBrushSettingsScript.new()
    var by_page: Resource = NoiseBrushSettingsScript.new()
    assert_false(by_field.size_option.enabled, "A fresh noise brush keeps its width")
    by_field.apply_pen_settings({"radius": {"enabled": true, "sensors": ["pressure"]}})
    by_page.apply_pen_settings({"size": {"enabled": true, "sensors": ["pressure"]}})
    for settings: Resource in [by_field, by_page]:
        var option: SaCurveOption = settings.size_option
        assert_true(option.enabled, "The step turns Size's option on")
        var pressure := option.sensor_for(SaSensor.Id.PRESSURE)
        assert_true(pressure != null and pressure.active, "on the pen's pressure")
        assert_eq(option.common_curve, NoiseBrushSettingsScript.radius_pressure_curve(), "along the curve the presets ship")
    by_field.apply_pen_settings({"radius": {"enabled": false}})
    assert_false(by_field.size_option.enabled, "and a step turns it off by the same name")


func test_grain_round_and_bristle_flat_ship_with_it_and_the_other_six_without() -> void:
    var tapering: Array[String] = []
    for entry: Dictionary in NoisePresetsScript.entries():
        var settings: Resource = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
        assert_not_null(settings, "%s builds, its `radius` key read as Size's option" % entry["name"])
        if settings == null:
            continue
        # Broken Chalk's size wanders along the stroke and not on the pen, as a
        # painter set it, so a size option on with no
        # pressure on it is not a taper.
        var option: SaCurveOption = settings.size_option
        var pressure := option.sensor_for(SaSensor.Id.PRESSURE)
        if not option.enabled or pressure == null or not pressure.active:
            continue
        tapering.append(String(entry["name"]))
        assert_almost_eq(option.common_curve[0].y, 1.0 / 3.0, 1e-6, "%s falls to a third at no pressure" % entry["name"])
    assert_eq(
        tapering,
        TAPERING,
        # gdlint:ignore=max-line-length
        "Grain Round, Bristle Flat, Wood Grain, Wet Into Wet, Ribbon Pen and Graphite Pencil taper, and the other nine keep their width"
    )


func test_grain_round_comes_to_a_point_as_it_ships() -> void:
    var entry: Dictionary = NoisePresetsScript.entries()[0]
    assert_eq(entry["name"], "Grain Round", "The first recipe is Grain Round")
    var built: Resource = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    _brush.settings.size_option = built.size_option
    _taper()
    var widths := _widths()
    assert_true(widths.x * 2 < widths.y, "Its first end is %d px, under half the middle's %d" % [widths.x, widths.y])
    assert_true(widths.z * 2 < widths.y, "and its last %d px" % widths.z)


## A tip the taper takes under the pixel mode's three pixels
## is taken three quarters of the way back and never past the Size row, so a
## larger Size lays a larger tip, a wide one tapers as before, and a size a
## curve takes to nought stays nought.
func test_the_taper_takes_a_small_tip_most_of_the_way_back_to_three_pixels() -> void:
    assert_almost_eq(NoisePointScript.thinned(1.1, 2.2), 2.2, 1e-6, "A 2.2 px tip pressed to half keeps its 2.2 px")
    assert_almost_eq(
        NoisePointScript.thinned(2.2, 4.4), 2.8, 1e-6, "a 4.4 px one is laid three quarters of the way from 2.2 to three"
    )
    assert_true(NoisePointScript.thinned(1.6, 3.2) < NoisePointScript.thinned(2.2, 4.4), "and a smaller Size lays smaller")
    assert_almost_eq(NoisePointScript.thinned(6.0, 6.0), 6.0, 1e-6, "a full press is whole")
    assert_almost_eq(NoisePointScript.thinned(32.0 / 3.0, 32.0), 32.0 / 3.0, 1e-6, "a 32 px tip at a third tapers as it did")
    assert_almost_eq(NoisePointScript.thinned(0.0, 8.0), 0.0, 1e-6, "and a curve that reads nought lays nothing")


## A painter's grid: Grain Round pressed at 0.75
## laid the same three texels at a Size of 0.8, 1.2, 1.6 and 2.2 px, the taper
## having pushed each into the pixel mode. The paint it lays grows with the
## Size. The door's own stroke, whose pressure goes through the harness pen's
## table, is read in a running Sara by the suite
## `scripts/test_a_brush_preset_at_a_small_radius_lays_the_opacity_asked_or_its_answer_says_what_it_laid.py`.
func test_grain_round_lays_more_paint_at_each_larger_small_size() -> void:
    var entry: Dictionary = NoisePresetsScript.entries()[0]
    var built: Resource = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    _brush.settings.size_option = built.size_option
    var laid: Array[float] = []
    var row := 24.0
    for radius: float in [0.8, 1.2, 1.6, 2.2]:
        _brush.settings.radius = radius / float(SIDE)
        laid.append(_small_stroke(row, 0.75))
        row += 40.0
    for index in range(1, laid.size()):
        assert_true(laid[index] > laid[index - 1], "The paint laid grows with the Size, %s" % str(laid))


## The alpha laid, summed, by a stroke 2 px long on *row* pressed at one and
## then *pressure*, which the press takes as its own.
func _small_stroke(row: float, pressure: float) -> float:
    _brush.begin_stroke(Vector2(60.0, row), 1.0)
    _brush.add_sample(Vector2(62.0, row + 0.6), pressure)
    _brush.end_stroke()
    _images = {}
    var sum := 0.0
    for y in range(int(row) - 8, int(row) + 9):
        for x in range(52, 72):
            sum += _alpha(Vector2i(x, y))
    return sum
