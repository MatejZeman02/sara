## A fresh session starts on a shipped preset, and the ten brush
## slots name shipped presets that load.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The first brush was "Unsaved brush" with "No
## preset" and no cell marked, and every slot read "Nothing". The boot's scan
## is where the pick happens, so the bar here is held and scanned the way
## `MainDockers` does it. The docker is built detached from any window, as the
## other presets suites build it, because the runner blocks on a `Window`.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## The bar builds against a tool machine, which needs a RenderingDevice.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_u2_first_brush")

var _slots_before: Array = []


func before_each() -> void:
    ScratchFolder.empty(scratch_dir)
    _slots_before = SaSettings.brush_slots.duplicate()


func after_each() -> void:
    SaSettings.brush_slots = _slots_before
    ScratchFolder.empty(scratch_dir)


func _shipped_names() -> Array[String]:
    var out: Array[String] = []
    for entry: Dictionary in ShippedPresetsScript.entries():
        out.append(String(entry["name"]))
    return out


## Every factory slot is a shipped name, and each one loads into the stamp
## brush's settings, which is the tool a fresh session starts on.
func test_every_factory_slot_names_a_shipped_preset_that_loads() -> void:
    var shipped := _shipped_names()
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    assert_eq(SaSettingsBrushSlots.FACTORY.size(), SaSettingsBrushSlots.COUNT, "Ten factory names")
    var seen: Array[String] = []
    for preset_name: String in SaSettingsBrushSlots.FACTORY:
        assert_true(shipped.has(preset_name), "'%s' is a shipped preset" % preset_name)
        assert_false(seen.has(preset_name), "and is in one slot only")
        seen.append(preset_name)
        assert_true(store.apply_preset(preset_name, StampSettingsScript.new()), "'%s' loads into the stamp brush" % preset_name)


## After the boot's scan the bar shows slot 1's preset, the
## docker marks its cell, and the brush has a name.
func test_the_scan_picks_the_first_slot_and_the_cell_is_marked() -> void:
    SaSettings.brush_slots = SaSettingsBrushSlots.factory()
    var host := Node.new()
    EventBus.add_child(host)
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")

    var bar := ToolOptionsBar.new()
    bar.name = "ToolOptionsBar"
    host.add_child(bar)
    var presets := bar.preset_box
    presets.hold_scan()
    bar.preset_store.dir = scratch_dir
    bar.preset_store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    bar.target_tool_machine = machine
    var docker := BrushPresetsDocker.new()
    host.add_child(docker)
    docker.rebind()
    var loaded: Array[String] = []
    var on_loaded := func(stored_name: String) -> void: loaded.append(stored_name)
    EventBus.preset_loaded.connect(on_loaded)

    assert_eq(presets.selected_preset, "", "Before the scan nothing is loaded")
    presets.scan()

    var first := SaSettingsBrushSlots.FACTORY[0]
    assert_eq(presets.selected_preset, first, "The scan loads slot 1's preset")
    var tip := presets.preset_menu.tooltip_text
    assert_eq(tip, "%s. Shows or hides Brush Presets." % first, "and the bar's button names it in its tooltip")
    assert_eq(loaded, [first] as Array[String], "through the pick path, which announces the load once")
    assert_eq(String(docker.chooser.chooser_report()["marked"]), first, "and the docker marks its cell")

    EventBus.preset_loaded.disconnect(on_loaded)
    EventBus.remove_child(host)
    host.free()
    Fixtures.teardown(surface, machine)


## A preset already loaded is the painter's, and a slot that cannot load is
## passed over for the next one rather than stopping the pick.
func test_the_pick_leaves_a_loaded_preset_and_passes_over_a_missing_one() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var host := Node.new()
    EventBus.add_child(host)
    var bar := ToolOptionsBar.new()
    bar.name = "ToolOptionsBar"
    host.add_child(bar)
    var presets := bar.preset_box
    bar.preset_store.dir = scratch_dir
    bar.preset_store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    bar.target_tool_machine = machine

    assert_eq(presets.pick_first_brush(["", "Departed", "Pencil", "Paint"]), "Pencil", "Empty and missing slots are passed over")
    assert_eq(presets.selected_preset, "Pencil", "and the first that loads is loaded")
    assert_eq(presets.pick_first_brush(["Paint"]), "", "With a preset loaded the pick does nothing")
    assert_eq(presets.selected_preset, "Pencil", "and the loaded one stays")

    EventBus.remove_child(host)
    host.free()
    Fixtures.teardown(surface, machine)
