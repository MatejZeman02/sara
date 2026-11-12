## A rule written as a pixel function has a slider on the
## simulation's panel per `uniform` line, and the step after a move reads the
## value the slider wrote.
##
## Life comes from the fixture module under `tests/fixtures/life-pixel/modules`, a
## block of four cells at an alpha of 0.6 is the still life it keeps while
## `alive` is 0.5, and moving the slider above 0.6 makes the next step find
## no living cell at all. The follower is driven a frame at a time, as the
## simulation panel's own suite drives it.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const LifeModule = preload("res://tests/fixtures/life-pixel/modules/life-pixel-fixture/module.gd")

const REQUIRES_GPU := true

const FRAME := 1.0 / 60.0

## A two by two block, which Life keeps as it is, at an alpha between the
## uniform's default and the value the slider is moved to.
const BLOCK: Array[Vector2i] = [Vector2i(40, 40), Vector2i(41, 40), Vector2i(40, 41), Vector2i(41, 41)]
const FAINT := Color(0.0, 0.0, 0.0, 0.6)

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _host: Node = null
var _docker: ToolOptionsDocker = null
var _follower: SaSimulationPanel = null


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _surface = Fixtures.make_surface(Vector2i(512, 256))
    _registries = Fixtures.make_registries(_surface)
    var base := BaseModule.new()
    base.register(_registries.context.for_module(base.get_id()))
    var life := LifeModule.new()
    life.register(_registries.context.for_module(life.get_id()))
    _host = Node.new()
    _docker = ToolOptionsDocker.new()
    _host.add_child(_docker)
    _follower = SaSimulationPanel.new(_registries, _docker)
    _host.add_child(_follower)


func after_each() -> void:
    _host.free()
    _surface.get_document().free()
    _surface.easel.free()
    _surface = null
    _registries = null


func _frames(count: int) -> void:
    for _i in count:
        _follower._process(FRAME)


func _panel() -> Control:
    return _docker.find_child("SimulationPanel", true, false) as Control


func _press(button_name: String) -> void:
    var button := _panel().find_child(button_name, true, false) as Button
    assert_not_null(button, "The panel holds %s" % button_name)
    if button != null:
        button.pressed.emit()


## A paint layer of its own, active, carrying *rule* at *values*, with the
## block painted on it.
func _simulated(rule: StringName, values: Dictionary = {}) -> SaLayer:
    var document := _surface.get_document()
    var layer := SaLayerOps.new(document).add(&"")
    document.set_active_layer(layer)
    var texture := layer.get_or_create_chunk(Vector2i(0, 0)).albedo()
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    image.fill(Color(0.0, 0.0, 0.0, 0.0))
    for at: Vector2i in BLOCK:
        image.set_pixelv(at, FAINT)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    SaSimulation.put_on(layer, _registries.simulation_rules.find(rule), values)
    return layer


## How many of the block's cells still hold paint.
func _living(layer: SaLayer) -> int:
    var texture := layer.get_field(Vector2i(0, 0))
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out := 0
    for at: Vector2i in BLOCK:
        if SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x).a > 0.0:
            out += 1
    return out


func _slider() -> FactorSlider:
    return _panel().find_child("SimulationParameter_alive", true, false) as FactorSlider


func test_the_uniform_is_a_slider_over_its_line_and_the_next_step_reads_it() -> void:
    var layer := _simulated(LifeModule.LIFE)
    var record := SaSimulation.record_of(layer)
    _frames(1)
    var slider := _slider()
    assert_not_null(slider, "Life's `uniform float alive` is a slider on the panel")
    if slider == null:
        return
    assert_almost_eq(slider.value, 0.5, 1e-6, "at the default its line declares")
    assert_almost_eq(slider.min_value, 0.05, 1e-6, "from the low end of its hint")
    assert_almost_eq(slider.max_value, 1.0, 1e-6, "to the high end")
    assert_almost_eq(slider.step, 0.05, 1e-6, "in the hint's steps")
    assert_eq(slider.prefix, "Alive: ", "named after the uniform")
    _press("SimulationStep")
    assert_eq(_living(layer), 4, "At 0.5 the faint block is alive, and a block is a still life")
    slider.step_by_units(5.0)
    assert_true(slider.value > FAINT.a, "Moved up, the slider stands above the block's alpha")
    assert_almost_eq(SaTyped.real(record.params.get("alive")), slider.value, 1e-6, "and writes the record's parameter")
    var report: Dictionary = _follower.report().get("panel", {})
    assert_almost_eq(
        SaTyped.real((report.get("parameters", {}) as Dictionary).get("alive")),
        slider.value,
        1e-6,
        "The state dump carries the slider's value"
    )
    _press("SimulationStep")
    assert_eq(_living(layer), 0, "and the next step reads it, so no cell of the block lives")


func test_a_value_outside_the_hint_widens_the_slider_to_it() -> void:
    _simulated(LifeModule.LIFE, {"alive": 0.02})
    _frames(1)
    var slider := _slider()
    assert_not_null(slider, "The slider stands")
    if slider == null:
        return
    assert_almost_eq(slider.value, 0.02, 1e-6, "at the record's value rather than the default")
    assert_almost_eq(slider.min_value, 0.02, 1e-6, "with its range widened to hold it, so the value is not clamped")


func test_a_rule_written_in_gmacs_has_no_parameter_sliders() -> void:
    _simulated(&"spread")
    _frames(1)
    assert_not_null(_panel(), "Spread's panel stands")
    assert_null(_slider(), "with no slider of Life's")
    var report: Dictionary = _follower.report().get("panel", {})
    assert_true((report.get("parameters", {}) as Dictionary).is_empty(), "and no parameter in the state dump")
