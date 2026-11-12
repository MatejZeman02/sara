## A stock preset's old tags are mapped to the seven, a
## painter's tag is kept, and no auto tag is ever written to a preset's file.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter, 2026-11-01: "Also work on the tags. Currently there is too many
## of them. There will be auto tags (like bundle, brush engine (filter, noise,
## stamp))". A store an earlier build wrote is started over: every tag of the
## old stock vocabularies on a stock preset becomes its new word or goes, a tag
## that was never a stock word stays, a stock preset the map leaves bare takes
## its recipe's, an import's preset and the painter's own are left as they were,
## and the map runs once. The bundle and the engine a preset shows are never a
## stored tag: the map drops them and the store refuses them by hand. the map took
## the ten to seven and left one on a stock preset, which the expectations
## below read.
extends "res://tests/test_framework.gd"

const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## Writing a stamp preset builds its tip pictures, which needs a RenderingDevice.
const REQUIRES_GPU := true

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


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


func _path(preset_name: String) -> String:
    return scratch_dir.path_join(preset_name + SaPresetStore.EXTENSION)


func _recipe(preset_name: String) -> Dictionary:
    for entry: Dictionary in ShippedPresetsScript.entries():
        if entry.get("name", "") == preset_name:
            return entry
    return {}


func _sorted(tags: Array) -> PackedStringArray:
    var out := PackedStringArray(tags)
    out.sort()
    return out


## The `metadata/tags` line of *preset_name*'s file as text, empty when it has none.
func _tags_line(preset_name: String) -> String:
    for line: String in FileAccess.get_file_as_string(_path(preset_name)).split("\n"):
        if line.begins_with("metadata/tags"):
            return line
    return ""


## A folder as an earlier build left it: the stock set installed, then tagged
## with the old words, the record of the map gone so the next start is its first.
func _an_old_store() -> SaPresetStore:
    var first := _store()
    first.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    # Sketch retagged by the painter in the old words, with one of their own and
    # the words an auto tag says now, its bundle and its engine.
    _retag(first, "Sketch", ["ink", "foliage", "drawn", "mine", "Sara Basic", "stamp", "fill"])
    # Pencil with only words an auto tag covers, which the map leaves bare.
    _retag(first, "Pencil", ["drawn", "noise"])
    # Airbrush as the build before shipped it and nobody touched since.
    _retag(first, "Airbrush", ["spray", "air", "soft"])
    var ledger := SaPresetLedger.new(scratch_dir)
    ledger.record_written("Sara Basic", "Airbrush", SaPresetLedger.fingerprint(_path("Airbrush")), AN_EARLIER_BUILD)
    # An import, filed under a bundle no recipe names, and the painter's own.
    first.save_preset(
        "Kit Brush",
        StampSettingsScript.new(),
        PackedStringArray(["ink", "grain"]),
        {SaPresetMeta.BUNDLE_META: "Kit From A Friend"}
    )
    first.save_preset("My Wash", StampSettingsScript.new(), PackedStringArray(["pencil", "wet"]))
    DirAccess.remove_absolute(scratch_dir.path_join(SaPresetTagMap.DONE_FILE))
    return first


## Writes *tags* as *preset_name*'s tags line, in the file's text, the way an
## earlier build's file said them. A save would drop the bundle's lines, which
## are what make the preset a stock one.
func _retag(store: SaPresetStore, preset_name: String, tags: Array[String]) -> void:
    var text := FileAccess.get_file_as_string(_path(preset_name))
    var line := _tags_line(preset_name)
    assert_false(line.is_empty(), "%s carries a tags line" % preset_name)
    var quoted := PackedStringArray()
    for tag: String in tags:
        quoted.append('"%s"' % tag)
    var file := FileAccess.open(_path(preset_name), FileAccess.WRITE)
    file.store_string(text.replace(line, "metadata/tags = PackedStringArray(%s)" % ", ".join(quoted)))
    file.close()
    store.forget_tags()


func test_a_start_maps_each_stock_tag_or_drops_it_and_keeps_the_painters() -> void:
    _an_old_store()
    var kit := SaPresetLedger.fingerprint(_path("Kit Brush"))
    var wash := SaPresetLedger.fingerprint(_path("My Wash"))
    _store().install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    var reread := _store()
    var sketch := reread.tags_for("Sketch")
    print("after a start: Sketch %s, Pencil %s, Airbrush %s" % [sketch, reread.tags_for("Pencil"), reread.tags_for("Airbrush")])
    assert_eq(
        sketch,
        PackedStringArray(["lines", "mine"]),
        "ink kept as its recipe's word, foliage, the auto words and fill dropped, mine kept"
    )
    assert_eq(reread.tags_for("Pencil"), _sorted(_recipe("Pencil")["tags"]), "a stock preset left bare takes its recipe's tags")
    assert_eq(reread.tags_for("Airbrush"), _sorted(_recipe("Airbrush")["tags"]), "the untouched Airbrush is the recipe again")
    assert_eq(reread.tags_for("Kit Brush"), PackedStringArray(["grain", "ink"]), "an import's preset keeps its tags")
    assert_eq(SaPresetLedger.fingerprint(_path("Kit Brush")), kit, "and its file is untouched")
    assert_eq(reread.tags_for("My Wash"), PackedStringArray(["pencil", "wet"]), "the painter's own preset keeps its tags")
    assert_eq(SaPresetLedger.fingerprint(_path("My Wash")), wash, "and its file is untouched")


## Every tag a stock preset carries after the start is one of the seven or the
## painter's, and the old words are gone from the files.
func test_no_stock_preset_keeps_an_old_word() -> void:
    _an_old_store()
    _store().install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    var reread := _store()
    for entry: Dictionary in ShippedPresetsScript.entries():
        var preset_name := String(entry.get("name", ""))
        if not reread.has_preset(preset_name):
            continue
        var tags := reread.tags_for(preset_name)
        assert_true(tags.size() >= 1, "%s keeps a stored tag" % preset_name)
        for tag: String in tags:
            var stock := SaPresetTagMap.RENAMED.has(tag)
            assert_true(
                not stock or SaPresetTagMap.RENAMED[tag] == tag,
                "%s carries %s, a word of the seven or its own" % [preset_name, tag]
            )


## The map runs once per preset: a stock word typed again by hand after it is
## the painter's and stays across a start.
func test_the_map_runs_once() -> void:
    _an_old_store()
    _store().install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    var store := _store()
    assert_true(store.assign_tag("Sketch", "ink"), "the painter types ink on Sketch again")
    _store().install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    assert_true(_store().tags_for("Sketch").has("ink"), "and a second start keeps it")
    var done := FileAccess.get_file_as_string(scratch_dir.path_join(SaPresetTagMap.DONE_FILE))
    assert_true(done.contains("Sara Basic/Sketch"), "the folder records each preset mapped by its bundle and name")


## One bundle's presets come from the tables of several engines, each installed
## on a call of its own, and the second table's presets are mapped as the
## first's were. A record by bundle skipped them on a painter's store.
func test_a_bundle_two_tables_carry_is_mapped_on_each() -> void:
    _an_old_store()
    _retag(_store(), "Eraser", ["eraser", "edges", "hard"])
    var first: Array = []
    var second: Array = []
    for entry: Dictionary in ShippedPresetsScript.entries():
        if entry.get("name", "") == "Eraser":
            second.append(entry)
        else:
            first.append(entry)
    SaPresetTagMap.carry_over(_store(), SaPresetLedger.new(scratch_dir), first)
    assert_eq(_store().tags_for("Sketch"), PackedStringArray(["lines", "mine"]), "the first table's Sketch is mapped")
    assert_eq(_store().tags_for("Eraser"), PackedStringArray(["edges", "eraser", "hard"]), "and Eraser waits for its own")
    assert_eq(SaPresetTagMap.carry_over(_store(), SaPresetLedger.new(scratch_dir), second), 1, "the second table maps it")
    assert_eq(_store().tags_for("Eraser"), PackedStringArray(["eraser"]), "edges dropped and hard gone into eraser")


## No auto tag reaches a file: the map drops them, and an add or a rename by
## hand of a bundle's title or an engine's id is refused and writes nothing.
func test_no_auto_tag_is_ever_written_to_a_presets_file() -> void:
    _an_old_store()
    _store().install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    var store := _store()
    var auto := SaPresetTagMap.auto_words(store)
    assert_true(auto.has("stamp") and auto.has("Sara Basic") and auto.has("Sara Advanced Paint"), "the store shows %s" % auto)
    var before := SaPresetLedger.fingerprint(_path("Sketch"))
    for word: String in ["Sara Basic", "sara basic", "stamp", "Sara Advanced Paint"]:
        assert_false(store.assign_tag("Sketch", word), "an add of %s is refused" % word)
        assert_eq(store.rename_tag("mine", word), 0, "and a rename onto it")
    assert_eq(SaPresetLedger.fingerprint(_path("Sketch")), before, "and Sketch's file says what it said")
    for stored: String in store.list_names():
        var line := _tags_line(stored).to_lower()
        for word: String in auto:
            assert_false(line.contains('"%s"' % word.to_lower()), "%s stores no auto tag %s" % [stored, word])


## The mapping itself, with no file: each old word to its new one, an auto word
## dropped and an unknown word kept.
func test_the_words_map_as_the_table_says() -> void:
    var auto := PackedStringArray(["stamp", "Sara Basic"])
    var old := PackedStringArray(["pencil", "flat", "spray", "grain", "rework", "warp", "sky", "fill", "adjust", "spatter"])
    assert_eq(
        SaPresetTagMap.mapped(old, auto),
        PackedStringArray(["blend", "lines", "paint", "scatter", "soft", "texture"]),
        "the stamp presets' words"
    )
    assert_eq(
        SaPresetTagMap.mapped(PackedStringArray(["mine", "STAMP", "sara basic"]), auto),
        PackedStringArray(["mine"]),
        "a painter's word kept"
    )
    var seven := PackedStringArray()
    for word: String in SaPresetTagMap.RENAMED:
        var said := SaPresetTagMap.RENAMED[word]
        if not said.is_empty() and not seven.has(said):
            seven.append(said)
    seven.sort()
    var stock := SaPresetTagMap.STOCK_WORDS.duplicate()
    stock.sort()
    assert_eq(seven, stock, "the old words go to the seven")


## A stock preset's copy from before its file named its bundle, which the
## painter changed since, so nothing files it: the ledger records Sara writing
## it, and its stock words are mapped as a filed copy's are while it stays
## unfiled. Fourteen of a painter's presets are such.
func test_an_unfiled_copy_sara_wrote_is_mapped_too() -> void:
    _an_old_store()
    _retag(_store(), "Fill", ["paint", "fill", "corners", "mine"])
    var text := FileAccess.get_file_as_string(_path("Fill"))
    var kept := PackedStringArray()
    for line: String in text.split("\n"):
        if not line.begins_with("metadata/bundle"):
            kept.append(line)
    var file := FileAccess.open(_path("Fill"), FileAccess.WRITE)
    file.store_string("\n".join(kept))
    file.close()
    assert_eq(_store().origin_for("Fill")[0], "", "Fill names no bundle")
    _store().install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    assert_eq(_store().tags_for("Fill"), PackedStringArray(["mine", "paint"]), "fill and corners dropped, mine kept")
