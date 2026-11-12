## A fresh install writes the stock presets a painter tuned as the painter
## left them, field by field.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Seven stock presets were tuned in a painter's own store, and the fixtures
## folder holds a byte for byte copy of each changed file, so the run
## never reads or writes a painter's own folder. A fresh folder is offered the
## stamp brush's stock presets and the noise brush's, and each of the seven is
## loaded from it and from its fixture through a store of its own, so both pass
## the same migrations, and every stored field is compared.
##
## Three things are left out of the comparison, and each for a reason. The
## name, tags, bundle and description travel as metadata and stay the recipe's,
## as the recipe has them. `format_version` is the store's own bookkeeping, which the
## load brings to the current number on both sides. `maker_pressure_curve` is
## the pen table of the machine that saved the file, stamped at install from the
## installing painter's table rather than read from a recipe: the tuned
## files carry two tables, a pen table on some and the straight line on the
## others, so no one table is the preset's. The last test pins what is shipped instead, that a
## fresh install stamps the installing painter's own table.
extends "res://tests/test_framework.gd"

const SaShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

## The noise brush engine is a module of its own, so its table and its settings
## are loaded by path and a run without it compares the stamp presets alone.
const NOISE_TABLE: String = "res://modules/sara-noise-brush-engine/presets/noise_presets.gd"
const NOISE_SETTINGS: String = "res://modules/sara-noise-brush-engine/noise_brush_settings.gd"

const FIXTURES: String = "res://modules/sara-base-modules/stamp-brush/tests/fixtures/earlier-presets"

## The stamp presets that were tuned, by the name each ships under.
const STAMP_CHANGED: PackedStringArray = ["Airbrush", "Dry Strokes", "Spatter", "Streaks", "Torn Gouache"]

## The noise presets that were tuned.
const NOISE_CHANGED: PackedStringArray = ["Broken Chalk", "Wet Into Wet"]

## The fields a comparison skips, for the reasons the header gives.
const SKIPPED: PackedStringArray = [
    "format_version",
    "maker_pressure_curve",
    "script",
    "resource_path",
    "resource_name",
    "resource_local_to_scene",
    "resource_scene_unique_id",
]

## How far apart two floats may be and still be the tuned number, the
## rounding a `.tres` file's text gives a float it writes.
const EPSILON: float = 1e-6

static var fresh_dir: String = SaDataRoot.path("test_fresh_install")
static var reference_dir: String = SaDataRoot.path("test_reference_files")

var _correction := PackedFloat32Array()


func before_each() -> void:
    _correction = SaTablet.correction
    _clear(fresh_dir)
    _clear(reference_dir)


func after_each() -> void:
    SaTablet.correction = _correction
    _clear(fresh_dir)
    _clear(reference_dir)


func test_the_stamp_presets_the_painter_changed_are_the_painter_s_field_for_field() -> void:
    var fresh := _fresh_install()
    var authors := _reference_store()
    for name: String in STAMP_CHANGED:
        _assert_same(fresh, authors, name)


func test_the_noise_presets_the_painter_changed_are_the_painter_s_field_for_field() -> void:
    if not ResourceLoader.exists(NOISE_TABLE):
        assert_true(true, "No noise brush engine in this build, so no noise preset to compare")
        return
    var fresh := _fresh_install()
    var authors := _reference_store()
    for name: String in NOISE_CHANGED:
        _assert_same(fresh, authors, name)


func test_a_fresh_install_stamps_the_installing_painter_s_own_pen_table() -> void:
    var authors := _reference_store()
    var airbrush: Resource = authors.load_preset("Airbrush")
    var table: PackedFloat32Array = airbrush.get("maker_pressure_curve")
    assert_true(table.size() > 2, "A painter's Airbrush carries a painter's pen table, %d entries" % table.size())
    SaTablet.correction = table
    var fresh := _fresh_install()
    for name: String in STAMP_CHANGED:
        var ours: Resource = fresh.load_preset(name)
        var stamped: PackedFloat32Array = ours.get("maker_pressure_curve")
        assert_true(SaTablet.same_table(stamped, table), "A fresh %s carries the installing painter's table" % name)


## Loads *name* from both stores and asserts every stored field equal.
func _assert_same(fresh: SaPresetStore, authors: SaPresetStore, name: String) -> void:
    var ours: Resource = fresh.load_preset(name)
    var theirs: Resource = authors.load_preset(name)
    assert_not_null(ours, "A fresh install holds %s" % name)
    assert_not_null(theirs, "and a painter's %s loads" % name)
    if ours == null or theirs == null:
        return
    var unequal := PackedStringArray()
    _compare(ours, theirs, name, unequal, 0)
    assert_eq(unequal, PackedStringArray(), "%s is a painter's in every field" % name)


## Walks two values side by side and appends the path of each that differs.
func _compare(ours: Variant, theirs: Variant, at: String, unequal: PackedStringArray, depth: int) -> void:
    if depth > 8:
        return
    if ours is Object and theirs is Object:
        var names := {}
        for owner: Object in [ours, theirs]:
            for property: Dictionary in owner.get_property_list():
                var field := String(property.name)
                if int(property.usage) & PROPERTY_USAGE_STORAGE and not field in SKIPPED and not field.begins_with("metadata/"):
                    names[field] = true
        for field: String in names:
            _compare((ours as Object).get(field), (theirs as Object).get(field), at + "." + field, unequal, depth + 1)
        return
    if (ours is float or ours is int) and (theirs is float or theirs is int):
        if absf(float(ours) - float(theirs)) > EPSILON:
            unequal.append("%s: %s, a painter's %s" % [at, var_to_str(ours), var_to_str(theirs)])
        return
    if ours is Array and theirs is Array:
        if (ours as Array).size() != (theirs as Array).size():
            unequal.append("%s: %s, a painter's %s" % [at, var_to_str(ours), var_to_str(theirs)])
            return
        for i in (ours as Array).size():
            _compare(ours[i], theirs[i], "%s[%d]" % [at, i], unequal, depth + 1)
        return
    if ours is Vector2 and theirs is Vector2:
        if not (ours as Vector2).is_equal_approx(theirs as Vector2):
            unequal.append("%s: %s, a painter's %s" % [at, var_to_str(ours), var_to_str(theirs)])
        return
    if (ours is String or ours is StringName) and (theirs is String or theirs is StringName):
        if String(ours) != String(theirs):
            unequal.append("%s: %s, a painter's %s" % [at, ours, theirs])
        return
    if typeof(ours) != typeof(theirs) or var_to_str(ours) != var_to_str(theirs):
        unequal.append("%s: %s, a painter's %s" % [at, var_to_str(ours), var_to_str(theirs)])


## A store in an empty folder, offered the stamp and noise presets as a first
## run is.
func _fresh_install() -> SaPresetStore:
    _clear(fresh_dir)
    DirAccess.make_dir_recursive_absolute(fresh_dir)
    var store := SaPresetStore.new()
    store.dir = fresh_dir
    store.install_shipped(SaStampBrushSettings.new(), SaShippedPresetsScript)
    if ResourceLoader.exists(NOISE_TABLE):
        store.install_shipped(load(NOISE_SETTINGS).new(), load(NOISE_TABLE))
    return store


## A store holding the copies of the tuned files and nothing else.
func _reference_store() -> SaPresetStore:
    DirAccess.make_dir_recursive_absolute(reference_dir)
    for file_name: String in DirAccess.get_files_at(FIXTURES):
        if not file_name.ends_with(".tres"):
            continue
        var bytes := FileAccess.get_file_as_bytes(FIXTURES.path_join(file_name))
        var file := FileAccess.open(reference_dir.path_join(file_name), FileAccess.WRITE)
        file.store_buffer(bytes)
        file.close()
    var store := SaPresetStore.new()
    store.dir = reference_dir
    return store


func _clear(folder: String) -> void:
    if not DirAccess.dir_exists_absolute(folder):
        return
    for file_name: String in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(file_name))
    DirAccess.remove_absolute(folder)
