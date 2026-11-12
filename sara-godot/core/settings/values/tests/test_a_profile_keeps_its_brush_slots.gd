## A fresh profile has ten brush slots filled, and a profile that
## set its own keeps them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The note asked "A profile that already set a slot keeps it", and the load is
## where that is kept or lost: it reads each stored key over the default, so a
## default that filled ten slots must not reach into a profile that holds any.
## Loaded through a file object and a values node of the suite's own, rather
## than the autoload, so the painter's profile and every other suite's settings
## are never touched.
extends "res://tests/test_framework.gd"

static var scratch_path: String = SaDataRoot.path("test_u2_brush_slots.cfg")


func before_each() -> void:
    _clear()


func after_each() -> void:
    _clear()


func _clear() -> void:
    var path := ProjectSettings.globalize_path(scratch_path)
    for suffix: String in ["", ".bak", ".tmp", ".broken"]:
        DirAccess.remove_absolute(path + suffix)


## The profile a load of *config* gives, or a first launch's when *config* is null.
func _loaded(config: ConfigFile) -> SaSettingsValues:
    var path := ProjectSettings.globalize_path(scratch_path)
    if config != null:
        config.save(path)
    var file := SaSettingsFile.new()
    file.settings_path = path
    var values := SaSettingsValues.new()
    file.load_from_disk(values)
    return values


func test_a_fresh_profile_has_the_factory_ten() -> void:
    var values := _loaded(null)
    assert_eq(values.brush_slots.size(), SaSettingsBrushSlots.COUNT, "Ten slots")
    for slot in SaSettingsBrushSlots.COUNT:
        assert_eq(
            String(values.brush_slots[slot]),
            SaSettingsBrushSlots.FACTORY[slot],
            "Slot %d holds the factory preset rather than nothing" % (slot + 1)
        )
    values.free()


func test_a_profile_with_one_slot_set_keeps_it_and_its_empty_ones() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", SaSettingsFile.SETTINGS_VERSION)
    var stored := SaSettingsBrushSlots.empty()
    stored[2] = "Chalk"
    var place: Array = SaSettingsValues.KEYS["brush_slots"]
    config.set_value(String(place[0]), String(place[1]), stored)
    var values := _loaded(config)
    assert_eq(String(values.brush_slots[2]), "Chalk", "The slot the painter set is the one they set")
    for slot in SaSettingsBrushSlots.COUNT:
        if slot != 2:
            assert_eq(String(values.brush_slots[slot]), "", "and slot %d stays empty, not filled from the factory" % (slot + 1))
    values.free()


## A profile from before the slots had a key gets the factory ten, which is
## what the setting's own comment promises.
func test_a_profile_from_before_the_key_gets_the_factory_ten() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", SaSettingsFile.SETTINGS_VERSION)
    config.set_value("ui", "scale", 1.0)
    var values := _loaded(config)
    assert_eq(values.brush_slots, SaSettingsBrushSlots.factory(), "No key reads as the factory list")
    values.free()
