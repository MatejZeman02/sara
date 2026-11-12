## Unit tests for BrushSettings resource.
extends "res://tests/test_framework.gd"

const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const SaLayerScript = preload("res://core/api/document/sa_layer.gd")


func test_brush_settings_defaults() -> void:
    var bs := BrushSettingsScript.new()
    assert_not_null(bs, "BrushSettings should instantiate")
    assert_almost_eq(bs.radius, 0.02314814815, 0.00001, "Default radius should match expected")
    assert_eq(bs.opacity, 1.0, "Default opacity should be 1.0")
    assert_eq(bs.color, Color(1.0, 1.0, 1.0, 1.0), "Default color should be white")
    assert_false(bs.size_by_pressure, "size_by_pressure should default to false")
    assert_true(bs.opacity_by_pressure, "opacity_by_pressure should default to true")


func test_brush_settings_gammas() -> void:
    var bs := BrushSettingsScript.new()
    assert_not_null(bs.hardness, "Hardness GammaFloat should not be null")
    assert_not_null(bs.flow, "Flow GammaFloat should not be null")
    assert_not_null(bs.size_pressure_gamma, "Size pressure gamma should not be null")
    assert_not_null(bs.opacity_pressure_gamma, "Opacity pressure gamma should not be null")

    assert_eq(bs.flow.raw(), 1.0, "Default flow value should be 1.0")
    assert_eq(bs.flow.gamma(), 2.4, "Default flow gamma should be 2.4")


func test_brush_blend_mode_and_eraser_toggle() -> void:
    var bs := BrushSettingsScript.new()
    assert_eq(bs.blend_mode, SaLayerScript.BLEND_MODE.NORMAL, "Default blend mode should be NORMAL")
    bs.blend_mode = SaLayerScript.BLEND_MODE.ERASE
    assert_eq(bs.blend_mode, SaLayerScript.BLEND_MODE.ERASE, "Blend mode should be settable to ERASE")

    var StateBrushScript := preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
    var brush := StateBrushScript.new()
    assert_false(brush.eraser_toggled, "eraser_toggled should default to false")
    var state := brush.toggle_eraser()
    assert_true(state, "toggle_eraser should return true when toggled on")
    assert_true(brush.eraser_toggled, "eraser_toggled should be true")
    state = brush.toggle_eraser()
    assert_false(state, "toggle_eraser should return false when toggled off")
    assert_false(brush.eraser_toggled, "eraser_toggled should be false")
