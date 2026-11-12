## A stamp preset compared with the noise brush's settings reads as a
## difference and never stops the script.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Opening the brush editor on the noise brush, switching to the
## stamp brush and loading a stamp preset once left the window bound to the
## noise brush, so its session compared the stamp preset with noise settings,
## and `values_match` cast the noise brush's float `hardness` to a `Resource`
## because the stamp's is a `GammaFloat`. The session half is asked here
## directly and the window's half detached, for the reason the F5 suite gives:
## a `Window` added to the tree in a headless run hangs. The door's rebinding on
## a tool change is the running app's, and
## `scenarios/the-brush-editor-throws-comparing-a-stamp-preset-with-noise-settings.json`
## walks it.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")

## The window builds curve controls and a scratchpad with a canvas in it.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_d4_stamp_against_noise")


## A tool that holds whichever settings it is handed, so the window can be
## bound to either engine without the module's tool.
class HeldTool:
    extends ToolState

    var settings: Resource = null

    func _init(with_settings: Resource = null) -> void:
        settings = with_settings


var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


## The one key the two engines share with different kinds, in both orders.
func test_a_gamma_float_against_a_float_is_a_difference() -> void:
    var stamp: Resource = StampSettingsScript.new()
    var noise: Resource = NoiseSettingsScript.new()
    assert_true(stamp.get("hardness") is Resource, "The stamp's hardness is a resource")
    assert_eq(typeof(noise.get("hardness")), TYPE_FLOAT, "and the noise brush's a float")
    assert_false(SaBrushEditorSession.values_match(stamp.get("hardness"), noise.get("hardness")), "stamp first differs")
    assert_false(SaBrushEditorSession.values_match(noise.get("hardness"), stamp.get("hardness")), "noise first differs")


## The walk over whole settings, which is what `is_dirty` runs.
func test_stamp_settings_against_noise_settings_mismatch() -> void:
    var stamp: Resource = StampSettingsScript.new()
    var noise: Resource = NoiseSettingsScript.new()
    assert_false(SaBrushEditorSession.settings_match(stamp, noise), "A stamp brush is not the noise brush")
    assert_false(SaBrushEditorSession.settings_match(noise, stamp), "in either order")


## What the kind check must not break: a number is a number whichever of int
## and float it was written as, a null object differs from an object, and two
## curves still go through the shape comparison.
func test_values_of_one_kind_still_compare() -> void:
    assert_true(SaBrushEditorSession.values_match(1, 1.0), "An int and a float of one value match")
    assert_false(SaBrushEditorSession.values_match(null, StampSettingsScript.new()), "null is not a brush")
    assert_true(SaBrushEditorSession.values_match(null, null), "and null is null")
    assert_false(SaBrushEditorSession.values_match("0.5", 0.5), "A string is not a number")
    assert_false(SaBrushEditorSession.values_match(Curve.new(), GammaFloat.new(0.0, 1.0)), "A curve is not a gamma float")
    assert_true(SaBrushEditorSession.values_match(Curve.new(), Curve.new()), "Two empty curves match")


## The window was bound to the noise brush and a stamp preset was loaded on the
## stamp brush: the window keeps its own preset and its own dirty text.
func test_a_stamp_load_leaves_a_window_on_the_noise_brush_alone() -> void:
    var store := _store()
    var noise: Resource = NoiseSettingsScript.new()
    var noise_name := store.save_preset("Charcoal (Noise)", noise)
    var stamp_name := store.save_preset("Charcoal (Noise) (Stamp)", StampSettingsScript.new())
    assert_false(noise_name.is_empty() or stamp_name.is_empty(), "Both presets were written")
    var window := SaBrushEditorWindow.new()
    window.bind_tool(HeldTool.new(noise), [], store, noise_name)
    assert_eq(window.preset_bar.dirty_text(), SaBrushEditorSession.CLEAN_TEXT, "The noise preset is loaded")

    window._on_preset_loaded(stamp_name)

    assert_eq(window.preset_bar.session.preset_name, noise_name, "The window still names the noise preset")
    assert_eq(window.preset_bar.dirty_text(), SaBrushEditorSession.CLEAN_TEXT, "and still reads Saved")
    window.free()


## What the door does on a tool change, then the load: the window rebound to the
## stamp brush takes the stamp preset and reads it as saved.
func test_a_window_rebound_to_the_stamp_reads_the_stamp_preset() -> void:
    var store := _store()
    var noise: Resource = NoiseSettingsScript.new()
    var noise_name := store.save_preset("Grain (Noise)", noise)
    var stamp: Resource = StampSettingsScript.new()
    stamp.set("radius", 0.3)
    var stamp_name := store.save_preset("Grain (Stamp)", stamp)
    var window := SaBrushEditorWindow.new()
    window.bind_tool(HeldTool.new(noise), [], store, noise_name)

    # The stamp half is the machine's own brush, because a load draws the
    # thumbnail by building the bound tool's script afresh.
    var brush := _machine.get_tool("brush")
    var live: Resource = brush.get("settings")
    window.bind_tool(brush, [], store)
    assert_true(store.apply_preset(stamp_name, live), "The bar applied the stamp preset")
    window._on_preset_loaded(stamp_name)

    assert_eq(window.preset_bar.session.preset_name, stamp_name, "The window names the stamp preset")
    assert_eq(window.preset_bar.dirty_text(), SaBrushEditorSession.CLEAN_TEXT, "and reads Saved")
    live.set("radius", 0.6)
    assert_eq(window.preset_bar.dirty_text(), SaBrushEditorSession.DIRTY_TEXT, "until the brush is moved")
    window.free()
