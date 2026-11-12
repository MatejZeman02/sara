## A stroke asked for an opacity above one lays no alpha above one.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Brush steps whose jitter writes opacities up to 1.074 must not push a layer's
## alpha past one, as a Wash stroke at 1.074 on an empty layer did by laying
## 1.064. The stroke is replayed here on a layer
## already at alpha one and on an empty one, under both painting modes, and the
## layer's largest alpha is reduced on the card.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## Never the real `user://brush_presets`, which is the painter's own folder.
static var scratch_dir: String = SaDataRoot.path("test_presets")
const ASKED: float = 1.074
const SLACK: float = 0.0001

var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    if DirAccess.dir_exists_absolute(scratch_dir):
        for file_name: String in DirAccess.get_files_at(scratch_dir):
            DirAccess.remove_absolute(scratch_dir.path_join(file_name))
        DirAccess.remove_absolute(scratch_dir)


func _brush() -> Object:
    return _machine.active_tool


func _button(pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    _brush().handle_input(event)


func _motion(at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.pressure = 1.0
    _surface.view.mouse_position = at
    _brush().handle_input(motion)


## Three strokes across one row at *mode* with the opacity asked above one,
## and the layer's largest alpha after them.
func _strokes(mode: int) -> float:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(_brush().settings, ShippedPresetsScript)
    assert_true(store.apply_preset("Paint", _brush().settings), "Paint loads")
    var settings: SaStampBrushSettings = _brush().settings
    settings.painting_mode = mode as SaStampBrushSettings.PaintingMode
    settings.opacity_by_pressure = false
    settings.radius = 6.0 / 256.0
    settings.opacity = ASKED
    for row in 3:
        _surface.view.mouse_position = Vector2(30, 100 + row * 2)
        _button(true)
        for step in range(1, 10):
            _motion(Vector2(30 + step * 20, 100 + row * 2))
        _brush()._walk_batch.flush()
        _button(false)
    var layer := _surface.easel.document.active_layer
    var most: Variant = SaReduce.new(layer).reduce(Rect2i(0, 0, 256, 256))["max"]
    return float(most[3]) if most != null else 0.0


func test_the_opacity_holds_zero_to_one_and_says_its_band() -> void:
    var settings := SaStampBrushSettings.new()
    settings.opacity = ASKED
    assert_eq(settings.opacity, 1.0, "An opacity of 1.074 is held at one")
    settings.opacity = -0.5
    assert_eq(settings.opacity, 0.0, "and one below zero at zero")
    var band := ""
    for property: Dictionary in settings.get_property_list():
        if property["name"] == "opacity" and int(property["hint"]) == PROPERTY_HINT_RANGE:
            band = String(property["hint_string"])
    assert_true(
        band.begins_with("0,1") or band.begins_with("0.0,1.0"), "and declares the band the door refuses outside, %s" % band
    )


func test_a_stroke_on_an_empty_layer_lays_no_alpha_above_one() -> void:
    for mode: int in [SaStampBrushSettings.PaintingMode.WASH, SaStampBrushSettings.PaintingMode.BUILD_UP]:
        var most := _strokes(mode)
        assert_true(most > 0.5, "The strokes laid paint, %f" % most)
        assert_true(most <= 1.0 + SLACK, "Mode %d at opacity %.3f holds alpha at most one, %f" % [mode, ASKED, most])


func test_a_stroke_over_paint_at_alpha_one_lays_no_alpha_above_one() -> void:
    _surface.easel.document.active_layer.get_or_create_chunk(Vector2i.ZERO).clear(Color(0.8, 0.3, 0.2, 1.0))
    var most := _strokes(SaStampBrushSettings.PaintingMode.WASH)
    assert_true(most <= 1.0 + SLACK, "Wash over opaque paint holds alpha at most one, %f" % most)
