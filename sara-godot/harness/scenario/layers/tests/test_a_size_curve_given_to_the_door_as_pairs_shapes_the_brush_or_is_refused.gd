## A size curve given to the door as pairs shapes the brush, or is refused.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Sending `{"brush": {"preset": "Pointed Mark", "radius_px": 18,
## "pen_settings": {"size": {"common_curve": [[0, 0.02], [1, 1]]}}}}`, the step
## answered that every key took, and every stroke after it laid nothing: a JSON
## list of pairs written onto a `PackedVector2Array` became a curve of zeros, and
## a zero size curve lays no dab. Here the same step, less the preset key, which
## needs the bar this suite has no window for, is sent to `SaCaptureLayers.brush`
## with Pointed Mark built as the bar would load it. The curve reads back as
## (0, 0.02) and (1, 1), the objects form reads the same, a stroke lays paint,
## and each malformed curve is refused by its path with the brush unchanged.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The canvas and the brush need a RenderingDevice.
const REQUIRES_GPU := true

const CANVAS := Vector2i(256, 256)

## The curve, as the door hands it over from JSON.
const PAIRS: Array = [[0, 0.02], [1, 1]]

## What the brush must hold after it.
const WANTED := [Vector2(0.0, 0.02), Vector2(1.0, 1.0)]

## Coverage a texel needs to count as painted.
const PAINTED: float = 0.05

var _host: Node = null
var _canvas: SaCanvas = null
var _machine: ToolMachine = null
var _foreground: Color = Color.BLACK
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _foreground = SaColors.foreground
    _host = Node.new()
    _host.name = "U578CurveHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = CANVAS
    _host.add_child(_canvas)
    _canvas.size = Vector2(CANVAS)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _canvas.add_child(_machine)
    _machine.bind(SaSurface.create(&"main", _canvas.easel, SaCanvasView.for_canvas(_canvas)), Fixtures.make_tool_registry())
    _machine.set_active_tool(&"brush")
    _front = Fixtures.FrontDocuments.over(_canvas)
    _machine.get_tool("brush").settings = _preset("Pointed Mark")


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    SaColors.foreground = _foreground
    if _machine != null:
        _machine.registered_tools.clear()
        _machine.active_tool = null
        _machine.registry = null
    if _host != null:
        _host.free()
    _host = null
    _canvas = null
    _machine = null


func test_the_day_8_step_reads_the_curve_back_as_given_and_its_stroke_lays_paint() -> void:
    var answer := _step({"radius_px": 18, "pen_settings": {"size": {"common_curve": PAIRS}}})
    assert_true(answer.ends_with(", unset {}"), "The step set it all: %s" % answer)
    var settings := _settings()
    assert_eq(Array(settings.size_option.common_curve), WANTED, "The size curve reads (0, 0.02) and (1, 1)")
    var laid := _paint(settings)
    assert_true(laid > 0, "A stroke with the curve lays paint, %d texels" % laid)


func test_the_objects_form_reads_the_same_curve() -> void:
    var objects := [{"x": 0, "y": 0.02}, {"x": 1.0, "y": 1}]
    var answer := _step({"pen_settings": {"size": {"common_curve": objects}}})
    assert_true(answer.ends_with(", unset {}"), "The step set it all: %s" % answer)
    assert_eq(Array(_settings().size_option.common_curve), WANTED, "The objects read (0, 0.02) and (1, 1)")


func test_a_sensors_own_curve_is_read_as_pairs_too() -> void:
    var sensors := [{"id": "pressure", "curve": [[0, 0.1], [0.5, 0.4], [1, 1]]}]
    _step({"pen_settings": {"size": {"use_same_curve": false, "sensors": sensors}}})
    var sensor: SaSensor = _settings().size_option.sensor_for(SaSensor.Id.PRESSURE)
    assert_true(sensor != null, "Pressure is ticked on Size")
    if sensor != null:
        var curve := [Vector2(0.0, 0.1), Vector2(0.5, 0.4), Vector2(1.0, 1.0)]
        assert_eq(Array(sensor.curve), curve, "and its own curve reads as given")


func test_a_malformed_curve_is_refused_by_name_and_the_brush_is_left_as_it_was() -> void:
    var malformed: Array = [
        ["size:common_curve", {"size": {"common_curve": [0, 1]}}],
        ["size:common_curve", {"size": {"common_curve": [[0, 0.02]]}}],
        ["size:common_curve", {"size": {"common_curve": [[0, "a"], [1, 1]]}}],
        ["size:common_curve", {"size": {"common_curve": [[0, 0, 1], [1, 1]]}}],
        ["size:common_curve", {"size": {"common_curve": [{"x": 0}, {"x": 1, "y": 1}]}}],
        ["size:common_curve", {"size": {"common_curve": [[1, 1], [0, 0]]}}],
        ["size:common_curve", {"size": {"common_curve": [[0, 0], [2, 1]]}}],
        ["size:common_curve", {"size": {"common_curve": "0 0.02 1 1"}}],
        ["size:sensors:0:curve", {"size": {"sensors": [{"id": "pressure", "curve": [[0.5, 1]]}]}}],
    ]
    var before := _settings().size_option.common_curve
    var radius := float(_settings().radius)
    for pair: Array in malformed:
        var answer := _step({"radius_px": 40, "pen_settings": pair[1]})
        var named := "could not read the curve pen_settings:%s " % pair[0]
        assert_true(answer.contains(named), "%s is refused by name: %s" % [JSON.stringify(pair[1]), answer])
        assert_true(answer.contains("a curve is a list of at least two pairs"), "with the form it takes: %s" % answer)
        assert_true(answer.ends_with("and set nothing"), "and says it set nothing: %s" % answer)
        assert_eq(_settings().size_option.common_curve, before, "The size curve is left as it was")
        assert_eq(float(_settings().radius), radius, "and so is the radius beside it")


func _step(spec: Dictionary) -> String:
    return SaCaptureLayers.brush(Engine.get_main_loop() as SceneTree, spec)


func _settings() -> SaStampBrushSettings:
    return _machine.get_tool("brush").settings as SaStampBrushSettings


static func _preset(name: String) -> SaStampBrushSettings:
    for entry: Dictionary in SaShippedPresets.entries():
        if entry["name"] == name:
            return SaShippedPresets.build(StampSettingsScript, entry) as SaStampBrushSettings
    return null


## How many texels a stroke across the middle at full pressure covers past
## [constant PAINTED], painted with *settings* on a white layer.
func _paint(settings: SaStampBrushSettings) -> int:
    var surface := Fixtures.make_surface(CANVAS)
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var document := surface.easel.document
    document.fill_layer(Color.WHITE, document.active_layer)
    var brush: Object = machine.active_tool
    brush.settings = settings
    brush.settings.color = Color.BLACK
    _send(brush, surface, _button(true), Vector2(60, 128))
    var x := 60.0
    while x < 196.0:
        x += 4.0
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = 1.0
        _send(brush, surface, motion, Vector2(x, 128))
    _send(brush, surface, _button(false), Vector2(x, 128))
    var painted := _painted(document.active_layer)
    Fixtures.teardown(surface, machine)
    return painted


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


static func _send(brush: Object, surface: SaSurface, event: InputEventMouse, at: Vector2) -> void:
    surface.view.mouse_position = at
    event.position = at
    brush.handle_input(event)


static func _painted(layer: SaLayer) -> int:
    var count := 0
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
        var image := Image.create_from_data(
            edge,
            edge,
            false,
            Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF,
            GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        )
        for y in range(edge):
            for x in range(edge):
                if 1.0 - image.get_pixel(x, y).r > PAINTED:
                    count += 1
    return count
