## The stamp presets meant to be crisp ship with a Sharpness.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Crisp stamps get a stock sharpness and keep their hardness. Every crisp drawn
## preset's recipe names a Sharpness above zero and below one, where one would
## make it a pen, and every soft one names none. Each is read three ways: off
## the table, off the settings the table builds, and off the preset a fresh
## profile is offered, through a store of the suite's own and never the real
## `user://brush_presets`.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const DrawnTipPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_drawn_tip_presets.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The presets meant to read as crisp marks. Fir Tree is with the soft ones,
## because its lower branches are drawn light grey and any cut that makes its
## greys solid takes them away. Dry Strokes sets no Sharpness, so it is with the
## soft ones too.
const CRISP: Array[String] = [
    "Torn Block",
    "Scrawled Block",
    "Splattered Block",
    "Dotted Line",
    "Sparse Specks",
    "Scattered Dots",
    "Ridge",
    "Palm Fronds",
    "Leafy Twig",
    "Bush",
    "Grass Tuft",
    "Scribble Marks",
    "Flecks",
]

## The presets whose softness is what they are for.
const SOFT: Array[String] = [
    "Soft Haze",
    "Storm Cloud",
    "Smoky Blot",
    "Cloud Puff",
    "Scumble",
    "Lichen",
    "Dust",
    "Streaks",
    "Fir Tree",
    "Dry Strokes",
]

static var scratch_dir: String = SaDataRoot.path("test_fresh_profile")


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


## The drawn table's recipe named *preset_name*, or an empty one.
func _entry(preset_name: String) -> Dictionary:
    for entry: Dictionary in DrawnTipPresetsScript.ENTRIES:
        if String(entry["name"]) == preset_name:
            return entry
    return {}


## The Sharpness the recipe names, nought when it names none, as the template
## holds it.
func _stock_sharpness(preset_name: String) -> float:
    var settings: Dictionary = _entry(preset_name).get("settings", {})
    return float(settings.get("sharpness", 0.0))


func test_the_two_lists_hold_every_drawn_preset_once() -> void:
    var listed: Array[String] = []
    listed.append_array(CRISP)
    listed.append_array(SOFT)
    listed.sort()
    var table: Array[String] = []
    for entry: Dictionary in DrawnTipPresetsScript.ENTRIES:
        table.append(String(entry["name"]))
    table.sort()
    assert_eq(listed, table, "the crisp and the soft lists are the drawn table, each preset once")


func test_every_crisp_preset_ships_a_sharpness_short_of_a_pen() -> void:
    for preset_name: String in CRISP:
        var sharpness := _stock_sharpness(preset_name)
        assert_true(sharpness > 0.0, "%s ships a Sharpness above nought, read %s" % [preset_name, sharpness])
        assert_true(sharpness < 1.0, "%s ships short of a pen's Sharpness of one, read %s" % [preset_name, sharpness])


func test_every_soft_preset_ships_none() -> void:
    for preset_name: String in SOFT:
        assert_eq(_stock_sharpness(preset_name), 0.0, "%s keeps no Sharpness" % preset_name)


func test_the_built_settings_carry_the_recipe_s_sharpness() -> void:
    for preset_name: String in CRISP + SOFT:
        var built := ShippedPresetsScript.build(StampSettingsScript, _entry(preset_name))
        assert_not_null(built, "%s builds" % preset_name)
        if built == null:
            continue
        var read := float(built.get("sharpness"))
        assert_almost_eq(read, _stock_sharpness(preset_name), 0.0001, "%s's settings read its Sharpness" % preset_name)


func test_a_fresh_profile_is_offered_the_sharpness() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    for preset_name: String in CRISP + SOFT:
        var loaded := store.load_preset(preset_name)
        assert_not_null(loaded, "a fresh profile holds %s" % preset_name)
        if loaded == null:
            continue
        var read := float(loaded.get("sharpness"))
        assert_almost_eq(read, _stock_sharpness(preset_name), 0.0001, "%s loads with its stock Sharpness" % preset_name)
