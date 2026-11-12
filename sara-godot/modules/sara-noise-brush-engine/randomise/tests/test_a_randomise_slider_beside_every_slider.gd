## A randomise slider beside every slider, along the stroke and per stroke.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The binding is read three ways: on the curve option it writes, in the points
## a stroke lays through the tool's own public calls, and through the control
## the page builds. The band a point is laid at is recorded by a brush that
## answers the state's own [method band_for] and remembers the answer, so what
## the suite reads is what the kernel was handed. The first
## clock is the door's smooth noise along the stroke rather than a number per
## dab, and how slowly it changes is held by
## `test_randomness_changes_along_the_stroke_and_the_warp_is_gone.gd`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")


## The noise brush, remembering the band of every point it lays.
class RecordingBrush:
    extends "res://modules/sara-noise-brush-engine/state_noise_brush.gd"

    var bands: Array[float] = []

    func band_for(dab: SaDabParams) -> float:
        var band: float = super(dab)
        bands.append(band)
        return band


var _surface: SaSurface = null
var _brush: RecordingBrush = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _brush = RecordingBrush.new()
    _brush.surface = _surface
    _brush.stroke_seed = 11
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.hardness = 1.0
    _brush.settings.radius = 10.0 / 256.0
    _brush.settings.strength_option.enabled = false
    _brush.settings.strength = 0.4


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


## One fuzzy sensor on the clock asked for, its curve reaching the amount below
## the row, and the control's two numbers read back off it.
func test_the_binding_is_one_fuzzy_sensor_on_the_curve_option() -> void:
    var option := SaCurveOption.new()
    option.enabled = false
    option.bind_random(0.6, SaSensor.Id.FUZZY_ALONG_STROKE, "hardness")
    var roll := option.sensor_for(SaSensor.Id.FUZZY_ALONG_STROKE)
    assert_true(roll != null and roll.active, "Along the stroke binds the fuzzy along the stroke sensor")
    assert_true(option.enabled, "and switches the option on")
    assert_false(option.use_same_curve, "reading the roll through its own curve")
    assert_eq(roll.resource_name, "hardness", "keyed by the option's own name")
    assert_almost_eq(option.random_amount(), 0.6, 0.0001, "The amount reads back")
    assert_eq(option.random_clock(), SaSensor.Id.FUZZY_ALONG_STROKE, "and so does the clock")

    option.bind_random(0.3, SaSensor.Id.FUZZY_PER_STROKE, "hardness")
    assert_null(option.sensor_for(SaSensor.Id.FUZZY_ALONG_STROKE), "Per stroke drops the along the stroke sensor")
    assert_true(option.sensor_for(SaSensor.Id.FUZZY_PER_STROKE).active, "for the per stroke one")
    assert_almost_eq(option.random_amount(), 0.3, 0.0001, "at the new amount")
    assert_eq(option.random_clock(), SaSensor.Id.FUZZY_PER_STROKE, "on the stroke's clock")

    option.bind_random(0.0, SaSensor.Id.FUZZY_PER_STROKE, "hardness")
    assert_true(option.sensors.is_empty(), "Nought drops every clock")
    option.begin_stroke()
    assert_true(option.active_sensors().is_empty(), "and no pressure is revived in their place")
    assert_eq(option.random_amount(), 0.0, "so the amount reads nought")


## Strength follows no pen of its own since the pressure became the cut, so a
## roll on a fresh brush's is its one sensor, and a pressure line a preset
## bound, as the shipped recipes do, stays beside the roll rather than being
## replaced or bent.
func test_a_roll_on_strength_joins_whatever_line_it_has() -> void:
    var settings := NoiseBrushSettingsScript.new()
    settings.strength_option.bind_random(1.0, SaSensor.Id.FUZZY_ALONG_STROKE, "strength")
    assert_null(settings.strength_option.sensor_for(SaSensor.Id.PRESSURE), "A fresh brush's roll binds no pressure")
    assert_eq(settings.strength_option.active_sensors().size(), 1, "and is the option's one sensor")
    var bound := NoiseBrushSettingsScript.new()
    var option: SaCurveOption = bound.strength_option
    var falling := PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
    var line := SaSensor.create(SaSensor.Id.PRESSURE, true)
    line.curve = falling.duplicate()
    option.set_sensor(line)
    option.common_curve = falling.duplicate()
    option.enabled = true
    option.bind_random(1.0, SaSensor.Id.FUZZY_ALONG_STROKE, "strength")
    var pressure := option.sensor_for(SaSensor.Id.PRESSURE)
    assert_true(pressure.active, "A bound pressure line stays on")
    assert_eq(pressure.curve, falling, "along the falling line it was read through")
    assert_eq(option.active_sensors().size(), 2, "beside the roll")


## Hardness along the stroke: the band each point is laid at moves along the
## stroke, so points of one stroke have bands of their own, and none is past
## the row.
func test_hardness_along_the_stroke_varies_the_band_along_it() -> void:
    _brush.settings.hardness_option.bind_random(1.0, SaSensor.Id.FUZZY_ALONG_STROKE, "hardness")
    _paint_stroke(Vector2(30.0, 60.0))
    var bands := _brush.bands
    assert_true(bands.size() > 30, "The stroke laid its points, %d of them" % bands.size())
    var distinct := {}
    for band in bands:
        distinct[snappedf(band, 0.001)] = true
    assert_true(
        distinct.size() * 2 > bands.size(), "Most points have a band of their own, %d of %d" % [distinct.size(), bands.size()]
    )
    assert_true(bands.min() >= -0.0001, "none harder than the row, %.3f" % bands.min())
    assert_true(bands.max() - bands.min() > 0.1, "and the band moves, %.3f to %.3f" % [bands.min(), bands.max()])


## Hardness per stroke: every point of one stroke has the same band, and
## another stroke rolls another.
func test_hardness_per_stroke_holds_the_band_within_a_stroke() -> void:
    _brush.settings.hardness_option.bind_random(1.0, SaSensor.Id.FUZZY_PER_STROKE, "hardness")
    var per_stroke: Array[float] = []
    for seed_value: int in [11, 12, 13, 14]:
        _brush.stroke_seed = seed_value
        _brush.bands.clear()
        _paint_stroke(Vector2(30.0, 30.0 + 40.0 * per_stroke.size()))
        assert_true(_brush.bands.size() > 30, "Stroke %d laid its points" % seed_value)
        assert_almost_eq(_brush.bands.max() - _brush.bands.min(), 0.0, 0.000001, "and all of them at one band")
        per_stroke.append(_brush.bands[0])
    var distinct := {}
    for band in per_stroke:
        distinct[snappedf(band, 0.001)] = true
    assert_true(distinct.size() >= 3, "Four strokes roll at least three bands, %s" % str(per_stroke))


## Nought is the row as it is: no roll, the band the Hardness row sets.
func test_nought_leaves_the_band_at_the_row() -> void:
    _brush.settings.hardness = 0.7
    _brush.settings.hardness_option.bind_random(0.0, SaSensor.Id.FUZZY_ALONG_STROKE, "hardness")
    _paint_stroke(Vector2(30.0, 60.0))
    assert_almost_eq(_brush.bands.min(), 0.3, 0.0001, "Every point is laid at the row's band")
    assert_almost_eq(_brush.bands.max(), 0.3, 0.0001, "and none other")


## Size, Opacity and Strength roll through the same binding: each along the
## stroke differs between points a pixel apart over a stroke of forty, and
## each reaches no higher than its row. Strength is set off nought, since a
## roll scales the shift and no shift rolls to none. The sample's tip is two
## pixels wide, so forty points a pixel apart cross five of the roll's numbers.
func test_size_opacity_and_strength_roll_along_the_stroke() -> void:
    var settings := NoiseBrushSettingsScript.new()
    settings.strength = 0.6
    for key: String in ["size", "opacity", "strength"]:
        (settings.options()[key] as SaCurveOption).bind_random(1.0, SaSensor.Id.FUZZY_ALONG_STROKE, key)
    var dynamics := SaDynamics.new(settings)
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 5)
    info.tip_diameter = 2.0
    dynamics.begin_stroke()
    var sizes := {}
    var opacities := {}
    var shifts := {}
    var brush := StateNoiseBrushScript.new()
    brush.settings = settings
    for i in 40:
        info.feed(Vector2(float(i), 0.0), 0.5, Vector2.ZERO, 0.0, float(i))
        info.next_dab()
        var dab := dynamics.evaluate(info, 20.0)
        assert_true(dab.size <= 20.0 + 0.0001 and dab.opacity <= 1.0001, "A roll only lowers the row")
        sizes[snappedf(dab.size, 0.001)] = true
        opacities[snappedf(dab.opacity, 0.001)] = true
        var shift := brush.shift_for(info)
        assert_true(shift <= 0.6001, "A roll only lowers the shift")
        shifts[snappedf(shift, 0.001)] = true
    assert_true(sizes.size() > 20, "Size rolls along the stroke, %d sizes in 40 points" % sizes.size())
    assert_true(opacities.size() > 20, "Opacity rolls along the stroke, %d opacities" % opacities.size())
    assert_true(shifts.size() > 20, "Strength rolls along the stroke, %d shifts" % shifts.size())


## Every slider on the page has a randomise row right under it, bound to its
## curve option and kept off the bar.
func test_every_slider_on_the_page_has_a_randomise_row_under_it() -> void:
    var specs := NoiseModuleScript.options()
    var settings := NoiseBrushSettingsScript.new()
    var sliders := 0
    for index in specs.size():
        var spec: SaOptionSpec = specs[index]
        # The General page's sliders. The Texture page's sliders are read once a
        # stroke into the field's buffer and have no curve option to bind yet.
        if spec.kind != SaOptionSpec.Kind.FLOAT or spec.page != NoiseModuleScript.PAGE:
            continue
        # Randomness is the roll itself, and Chroma variation a swing
        # bound into Hue and Saturation, so neither has one of its own.
        if spec.key in NoiseModuleScript.UNROLLED:
            assert_false(NoiseModuleScript.RANDOMISED.has(spec.key), "%s is left without one" % spec.key)
            continue
        sliders += 1
        assert_true(index + 1 < specs.size(), "%s is not the page's last row" % spec.key)
        var next: SaOptionSpec = specs[index + 1]
        assert_eq(next.key, StringName(String(spec.key) + "_random"), "%s has its randomise row under it" % spec.key)
        assert_eq(next.kind, SaOptionSpec.Kind.CUSTOM, "built through the module's widget door")
        assert_false(next.bar, "and kept off the bar")
        assert_eq(next.page, spec.page, "on the slider's page")
        assert_true(settings.get_indexed(next.property) is SaCurveOption, "bound to a curve option, %s" % next.property)
    assert_eq(sliders, 5, "Size, Opacity, Hardness, Strength and Thickness are the page's rolled sliders")


## The control a page builds writes the binding and reports the write, and
## reads a bound option back.
func test_the_control_writes_the_binding_and_reads_it_back() -> void:
    var spec: SaOptionSpec = null
    for candidate: SaOptionSpec in NoiseModuleScript.options():
        if candidate.key == &"hardness_random":
            spec = candidate
    assert_not_null(spec, "The page declares Hardness's randomise row")
    var writes: Array = []
    var control: SaRandomiseControl = spec.build_control.call(spec, func(value: Variant) -> void: writes.append(value))
    var option := SaCurveOption.new()
    option.enabled = false
    spec.bind_value.call(control, option)
    var amount := control.find_child("HardnessRandomAmount", true, false) as FactorSlider
    var clock := control.find_child("HardnessRandomClock", true, false) as SaChoiceButton
    assert_true(amount != null and clock != null, "The amount and the clock are named after the row")
    assert_eq(amount.value, 0.0, "An untouched option reads nought")
    assert_eq(writes.size(), 0, "and binding it writes nothing")

    amount.set_value_no_signal(0.5)
    amount.value_changed.emit(0.5)
    assert_almost_eq(option.random_amount(), 0.5, 0.0001, "Moving the amount binds the roll")
    assert_eq(option.random_clock(), SaSensor.Id.FUZZY_ALONG_STROKE, "along the stroke by default")
    assert_eq(option.sensor_for(SaSensor.Id.FUZZY_ALONG_STROKE).resource_name, "hardness", "under the option's own name")
    assert_eq(writes.size(), 1, "and the move is reported")

    clock.pick_row(1)
    assert_eq(option.random_clock(), SaSensor.Id.FUZZY_PER_STROKE, "Picking per stroke moves the roll onto the stroke's clock")
    assert_almost_eq(option.random_amount(), 0.5, 0.0001, "at the same amount")

    var bound := SaCurveOption.new()
    bound.bind_random(0.25, SaSensor.Id.FUZZY_PER_STROKE, "hardness")
    spec.bind_value.call(control, bound)
    assert_almost_eq(amount.value, 0.25, 0.0001, "A bound option's roll shows on the amount")
    assert_eq(clock.selected_value(), SaRandomiseControl.PER_STROKE, "and its clock on the clock")
    control.free()


## A stroke from left to right at full pressure through the tool's public calls,
## long enough for more than thirty points.
func _paint_stroke(from: Vector2) -> void:
    _brush.begin_stroke(from, 1.0)
    for i in range(1, 31):
        _brush.add_sample(from + Vector2(6.0 * i, 0.0), 1.0)
    _brush.end_stroke()
