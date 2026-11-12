## The stock brush presets carry fewer tags, and every one
## carries two or more.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter, 2026-10-28: "Current Presets need better tags. Make less of them
## and make each preset be in multiple so it is easy to filter through." The
## seven recipe tables are read as the install reads them, and the counts are
## held: three presets or more under each tag, so a tag shown only lists a
## handful and a pair of them narrows that.
##
## moved it to the ten stored words of `SaPresetTagMap`, a painter's
## "Currently there is too many of them", and a later pass to seven, one a preset, on
## a painter's "reduce the number of tags we currently have? Unify it more":
## a stock preset carries one stored tag beside its bundle and its engine,
## which it shows as auto tags, and no stored tag says either. A pair of tags
## no longer narrows, so the case that read a tag sharing presets with others
## is gone, and `test_the_stock_brush_presets_carry_one_tag_each_of_seven`
## holds the one.
##
## A profile from an earlier build is started over: a stock preset nobody
## touched takes the new tags the way a changed recipe is given, because the
## tags are in the file the ledger's fingerprint is taken of, and a stock preset
## the painter retagged and one the painter made keep what they had.
extends "res://tests/test_framework.gd"

const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const FilterPresetsScript = preload("res://modules/sara-base-modules/filter-brush/presets/filter_brush_presets.gd")
const LiquifyPresetsScript = preload("res://modules/sara-base-modules/base/liquify/liquify_presets.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## Writing a stamp preset builds its tip pictures, which needs a RenderingDevice.
const REQUIRES_GPU := true

## The fewest stored tags a stock preset carries, beside its two auto tags.
const FEWEST_ON_A_PRESET: int = 1
## The fewest and the most distinct tags the stock set carries, the seven.
const FEWEST_TAGS: int = 7
const MOST_TAGS: int = 7
## The fewest presets a stock tag holds, the eraser's three.
const FEWEST_UNDER_A_TAG: int = 3

## The tags of today's table that name the engine or the table a preset came
## from, which the engine marks and the bundle words already say.
const SOURCE_WORDS: Array[String] = ["drawn", "noise", "liquify", "filter", "stamp"]

## The build an earlier Sara recorded its writes under, never this one's.
const AN_EARLIER_BUILD: String = "0.0.0 an-earlier-build"

static var scratch_dir: String = SaDataRoot.path("test_tags")


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


## Every stock recipe, the stamp brush's four tables through the door the
## install reads, then the filter brush's, liquify's and the noise module's.
func _stock() -> Array[Dictionary]:
    var all: Array[Dictionary] = []
    all.append_array(ShippedPresetsScript.entries())
    all.append_array(FilterPresetsScript.entries())
    all.append_array(LiquifyPresetsScript.entries())
    all.append_array(NoisePresetsScript.entries())
    return all


## Tag to how many stock presets carry it.
func _held() -> Dictionary[String, int]:
    var held: Dictionary[String, int] = {}
    for entry: Dictionary in _stock():
        for tag: String in entry.get("tags", []):
            held[tag] = held.get(tag, 0) + 1
    return held


func test_every_stock_preset_carries_a_stored_tag_or_more() -> void:
    var stock := _stock()
    assert_eq(stock.size(), 74, "the seven tables hold the 74 stock presets")
    for entry: Dictionary in stock:
        var tags: Array = entry.get("tags", [])
        assert_true(tags.size() >= FEWEST_ON_A_PRESET, "%s carries %s" % [entry.get("name", ""), str(tags)])
        var once: Dictionary = {}
        for tag: String in tags:
            once[tag] = true
        assert_eq(once.size(), tags.size(), "and names none of them twice")


func test_the_stock_set_carries_few_tags_each_holding_three_presets_or_more() -> void:
    var held := _held()
    var lines := PackedStringArray()
    for tag: String in held:
        lines.append("%s %d" % [tag, held[tag]])
    print("tags: %d, %s" % [held.size(), ", ".join(lines)])
    assert_true(held.size() >= FEWEST_TAGS and held.size() <= MOST_TAGS, "%d distinct tags" % held.size())
    for tag: String in held:
        assert_true(held[tag] >= FEWEST_UNDER_A_TAG, "%s holds %d presets" % [tag, held[tag]])
        assert_eq(tag, tag.to_lower(), "and is written in lower case")
        assert_true(SaPresetTagMap.STOCK_WORDS.has(tag), "and is one of the seven, %s" % tag)
    for word: String in SOURCE_WORDS:
        assert_false(held.has(word), "no tag names the table or engine, %s" % word)
    for entry: Dictionary in _stock():
        assert_false(held.has(String(entry.get("bundle", "")).to_lower()), "nor the bundle of %s" % entry.get("name", ""))


## The stock recipe named *preset_name*.
func _recipe(preset_name: String) -> Dictionary:
    for entry: Dictionary in ShippedPresetsScript.entries():
        if entry.get("name", "") == preset_name:
            return entry
    return {}


func _path(preset_name: String) -> String:
    return scratch_dir.path_join(preset_name + SaPresetStore.EXTENSION)


## Saves *preset_name* over itself with *tags*, as an earlier build wrote it,
## and records that write as Sara's own under an earlier build.
func _as_an_earlier_build_wrote_it(store: SaPresetStore, preset_name: String, tags: Array[String]) -> void:
    var settings := store.load_preset(preset_name)
    assert_false(store.save_preset(preset_name, settings, PackedStringArray(tags)).is_empty(), "%s is written" % preset_name)
    var ledger := SaPresetLedger.new(scratch_dir)
    var bundle := String(_recipe(preset_name).get("bundle", ""))
    ledger.record_written(bundle, preset_name, SaPresetLedger.fingerprint(_path(preset_name)), AN_EARLIER_BUILD)


func _sorted(tags: Array) -> PackedStringArray:
    var out := PackedStringArray(tags)
    out.sort()
    return out


## The ask's second half: an untouched old copy takes the new tags, a retagged
## stock preset and the painter's own keep theirs.
func test_a_start_retags_only_the_stock_presets_nobody_touched() -> void:
    var first := SaPresetStore.new()
    first.dir = scratch_dir
    first.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    # Sketch as the build before the fix shipped it, untouched since.
    _as_an_earlier_build_wrote_it(first, "Sketch", ["lines", "texture"])
    # Pencil as that build shipped it, then retagged by the painter.
    _as_an_earlier_build_wrote_it(first, "Pencil", ["lines", "texture"])
    assert_true(first.assign_tag("Pencil", "mine"), "the painter adds a tag to Pencil")
    var retagged := SaPresetLedger.fingerprint(_path("Pencil"))
    # And a preset the painter made.
    first.save_preset("My Wash", StampSettingsScript.new(), PackedStringArray(["mine", "wet"]))
    var made := SaPresetLedger.fingerprint(_path("My Wash"))
    # A look at each before the next start, as the presets docker takes one,
    # which writes the scripts' uids into a file the saver left them out of.
    for preset_name: String in ["Sketch", "Pencil", "My Wash"]:
        assert_not_null(first.load_preset(preset_name), "%s loads" % preset_name)
    assert_eq(_sorted(first.tags_for("Sketch")), PackedStringArray(["lines", "texture"]), "Sketch starts with the old tags")

    var started := SaPresetStore.new()
    started.dir = scratch_dir
    started.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)

    var reread := SaPresetStore.new()
    reread.dir = scratch_dir
    var sketch := reread.tags_for("Sketch")
    var pencil := reread.tags_for("Pencil")
    var mine := reread.tags_for("My Wash")
    print("after a start: Sketch %s, Pencil %s, My Wash %s" % [sketch, pencil, mine])
    assert_eq(sketch, _sorted(_recipe("Sketch")["tags"]), "the untouched Sketch carries the new tags")
    assert_eq(pencil, PackedStringArray(["lines", "mine", "texture"]), "the retagged Pencil keeps the painter's tags")
    assert_eq(SaPresetLedger.fingerprint(_path("Pencil")), retagged, "and its file says what it said")
    assert_eq(mine, PackedStringArray(["mine", "wet"]), "the painter's own preset keeps its tags")
    assert_eq(SaPresetLedger.fingerprint(_path("My Wash")), made, "and its file says what it said")
