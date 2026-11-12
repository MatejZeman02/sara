## The stock brush presets carry one tag each, from seven words, and a store
## mapped under the ten words before them is brought to the seven once.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter, 2026-11-09: "can you reduce the number of tags we currently
## have? Unify it more." Ten stock words, several on a preset, left most of the
## library on screen under one toggle. Every recipe table of every shipped
## engine is walked as the install reads it, and a scratch store laid out as
## the ten's map left it is started over twice. No case reads or writes the
## painter's real store, only a folder of its own under the data root.
extends "res://tests/test_framework.gd"

const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const FilterPresetsScript = preload("res://modules/sara-base-modules/filter-brush/presets/filter_brush_presets.gd")
const LiquifyPresetsScript = preload("res://modules/sara-base-modules/base/liquify/liquify_presets.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## Writing a stamp preset builds its tip pictures, which needs a RenderingDevice.
const REQUIRES_GPU := true

## The file the ten's map recorded its presets in.
const TENS_DONE_FILE: String = "tags.mapped"

static var scratch_dir: String = SaDataRoot.path("test_seven_tags")


func before_each() -> void:
    _clear()


func after_each() -> void:
    _clear()


func _clear() -> void:
    if not DirAccess.dir_exists_absolute(scratch_dir):
        return
    for file_name: String in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(scratch_dir.path_join(file_name))
    DirAccess.remove_absolute(scratch_dir)


func _stock() -> Array[Dictionary]:
    var all: Array[Dictionary] = []
    all.append_array(ShippedPresetsScript.entries())
    all.append_array(FilterPresetsScript.entries())
    all.append_array(LiquifyPresetsScript.entries())
    all.append_array(NoisePresetsScript.entries())
    return all


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


func _path(preset_name: String) -> String:
    return scratch_dir.path_join(preset_name + SaPresetStore.EXTENSION)


func test_every_stock_preset_carries_exactly_one_of_the_seven() -> void:
    var held: Dictionary[String, PackedStringArray] = {}
    for entry: Dictionary in _stock():
        var tags: Array = entry.get("tags", [])
        var preset_name := String(entry.get("name", ""))
        assert_eq(tags.size(), 1, "%s carries one tag, %s" % [preset_name, str(tags)])
        if tags.size() == 1:
            assert_true(SaPresetTagMap.STOCK_WORDS.has(tags[0]), "%s carries %s, one of the seven" % [preset_name, tags[0]])
            var under: PackedStringArray = held.get(tags[0], PackedStringArray())
            under.append(preset_name)
            held[tags[0]] = under
    var lines := PackedStringArray()
    for word: String in SaPresetTagMap.STOCK_WORDS:
        assert_true(held.has(word), "some stock preset carries %s" % word)
        lines.append(
            "%s %d: %s" % [word, held.get(word, PackedStringArray()).size(), ", ".join(held.get(word, PackedStringArray()))]
        )
    print("the seven:\n  " + "\n  ".join(lines))


## Writes *tags* as *preset_name*'s tags line, in the file's text, as the ten's
## build left it once the painter had touched it. A save would drop the
## bundle's lines, which are what make the preset a stock one.
func _retag(preset_name: String, tags: Array[String]) -> void:
    var text := FileAccess.get_file_as_string(_path(preset_name))
    var found := RegEx.create_from_string("(?m)^metadata/tags = .*$").search(text)
    assert_not_null(found, "%s carries a tags line" % preset_name)
    var quoted := PackedStringArray()
    for tag: String in tags:
        quoted.append('"%s"' % tag)
    var line := "metadata/tags = PackedStringArray(%s)" % ", ".join(quoted)
    var file := FileAccess.open(_path(preset_name), FileAccess.WRITE)
    file.store_string(text.substr(0, found.get_start()) + line + text.substr(found.get_end()))
    file.close()


## The stamp brush's presets as a store mapped under the ten holds them:
## installed, each named one tagged with the ten's words and the painter's
## touch on it, the ten's record of the map written and the seven's absent.
func _a_store_under_the_ten() -> void:
    _store().install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    # Two of the ten's words where the recipe's word is one of them.
    _retag("Wash", ["paint", "soft", "wet"])
    _retag("Spatter", ["hard", "scatter", "soft"])
    # Two where the recipe's word is not among them, which the order settles.
    _retag("Masked Stipple", ["soft", "texture"])
    # A word the seven dropped alone, and one the seven fold into another.
    _retag("Eraser", ["eraser", "hard"])
    _retag("Bush", ["nature", "texture"])
    # The painter's own word beside the ten's.
    _retag("Sketch", ["hard", "lines", "mine"])
    var done := PackedStringArray()
    for stored: String in _store().list_names():
        done.append("%s/%s" % [_store().origin_for(stored)[0], stored])
    var file := FileAccess.open(scratch_dir.path_join(TENS_DONE_FILE), FileAccess.WRITE)
    file.store_string("\n".join(done) + "\n")
    file.close()
    DirAccess.remove_absolute(scratch_dir.path_join(SaPresetTagMap.DONE_FILE))


func test_a_store_under_the_ten_is_mapped_to_one_of_the_seven_once() -> void:
    _a_store_under_the_ten()
    _store().install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    var store := _store()
    assert_eq(store.tags_for("Wash"), PackedStringArray(["paint"]), "Wash keeps its recipe's paint")
    assert_eq(store.tags_for("Spatter"), PackedStringArray(["scatter"]), "Spatter keeps its recipe's scatter")
    assert_eq(store.tags_for("Masked Stipple"), PackedStringArray(["soft"]), "Masked Stipple keeps the first it carried")
    assert_eq(store.tags_for("Eraser"), PackedStringArray(["eraser"]), "Eraser stays an eraser, hard gone")
    assert_eq(store.tags_for("Bush"), PackedStringArray(["scatter"]), "Bush's nature is scatter")
    assert_eq(store.tags_for("Sketch"), PackedStringArray(["lines", "mine"]), "Sketch keeps the painter's mine")
    for entry: Dictionary in ShippedPresetsScript.entries():
        var preset_name := String(entry.get("name", ""))
        var stock := PackedStringArray()
        for tag: String in store.tags_for(preset_name):
            if SaPresetTagMap.STOCK_WORDS.has(tag):
                stock.append(tag)
            else:
                assert_eq(tag, "mine", "%s carries no stock word outside the seven, %s" % [preset_name, tag])
        assert_eq(stock.size(), 1, "%s carries one of the seven, %s" % [preset_name, stock])
    var fingerprints: Dictionary[String, String] = {}
    for stored: String in store.list_names():
        fingerprints[stored] = SaPresetLedger.fingerprint(_path(stored))
    _store().install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    for stored: String in fingerprints:
        assert_eq(SaPresetLedger.fingerprint(_path(stored)), fingerprints[stored], "a second start leaves %s as it was" % stored)
    assert_eq(_store().tags_for("Sketch"), PackedStringArray(["lines", "mine"]), "and Sketch's tags with it")
