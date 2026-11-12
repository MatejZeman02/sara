## Every shipped stamp preset paints what it painted before the dynamics moved
## into the door, and a preset saved before the move still loads.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## took the sensors, the curve option, the dynamics, the dab parameters, the
## stroke state and the colour dynamics out of the stamp brush's `dynamics/`
## folder and into `core/api/dynamics`, a move and not a rewrite. The requirement is
## that "the stamp brush paints the same afterwards, to the texel", so this
## paints each of the shipped recipes twice, the S a thumbnail draws and one dab
## at full pressure, and holds the float texels of each to a hash recorded on
## the tree before the move. The S runs its pressure from nothing to full and
## back, so every pressure curve a recipe binds is read along it.
##
## **A hash and nothing beside it.** A recorded number no assertion reads rots,
## so the fixture holds one hash per picture and each is asserted. A row that
## means to change what a preset paints records the fixture again with
## `SARA_WRITE_B1_PAINT=1` and says why in its commit, and a row that did not
## mean to finds this red.
##
## **A preset written before the move** names the old folder in its
## `[ext_resource]` lines. Such a file is made here by saving a recipe through a
## store and writing the old folder back into its lines, once with the `uid` a
## saved file carries and once without, which is a preset from before scripts
## had one. The first is Godot's own resolution of the `uid` and the second is
## the store's repair by the file's name, and both have to paint the recipe's
## own hash.
##
## In `tests/` rather than the stamp's own suites, because it paints through
## `SaPresetThumbs`, which a module cannot name past the door.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## One hash per shipped recipe and picture, recorded before the move.
const FIXTURE: String = "res://tests/fixtures/shipped-paint/shipped_paint.json"

## Set to anything to write the fixture from this run instead of reading it.
const WRITE_ENV: String = "SARA_WRITE_B1_PAINT"

## Where the six scripts lived before the fix, which is what a preset saved then
## names in its `[ext_resource]` lines.
const OLD_DIR: String = "res://modules/sara-base-modules/stamp-brush/dynamics/"
const NEW_DIR: String = "res://core/api/dynamics/"

## The strip the S is painted into, twice a thumbnail's side, which is room
## enough for the widest recipe and quick enough for twenty-one of them twice.
const STRIP := Vector2i(256, 128)

## The patterns a recipe cannot be held to the fixture's texels through on
## Windows. this suite runs there on a different card than the fixture was recorded on
## under Linux, and 19 recipes painted their hashes to the bit while Pencil and
## Charcoal, the two drawing through Paper Grain, did not. A tile is one
## rounding away from its hash: Paper Grain's `at * cells / tile` written as
## `at * (cells / tile)` moves both hashes on Linux too, so a last bit that
## another driver's compiler rounds its own way is enough to move them.
##
## Only the comparison with the fixture is given up for them. They still paint
## an S, and a saved preset of theirs still loads and paints what the recipe
## paints on the same machine, which no driver's rounding changes.
const APART_ON_WINDOWS: Array[String] = ["Paper Grain"]

## The one thing a machine that cannot hold the apart recipes says it left out.
const APART_SKIP := (
    "Pencil and Charcoal are not compared with the fixture, since Windows's driver rounds Paper Grain's last bit its own way, "
    + "and their S and round trip run against this machine's own"
)

static var scratch_dir: String = SaDataRoot.path("test_b1_every_shipped_preset")


func after_each() -> void:
    ScratchFolder.empty(scratch_dir)


## The float texels of *settings* painted into a fresh easel, as a SHA-256.
func _hash(settings: Resource, one_dab: bool) -> String:
    var easel := SaEasel.create_default(STRIP, SaPresetThumbs.shared_compositor())
    var view := SaPresetThumbs.ThumbView.new()
    var surface := SaSurface.create(&"preset_thumb", easel, view)
    var painter := StateBrushScript.new() as ToolState
    painter.surface = surface
    painter.stroke_seed = SaPresetThumbs.STROKE_SEED
    var target := painter.get("settings") as Resource
    SaPresetStore.copy_settings(settings, target)
    target.set("color", SaPresetThumbs.INK)
    SaPresetThumbs._stroke(painter, view, STRIP, one_dab)
    easel.document.commit_stroke()
    easel.request_full_composite()
    easel.process_pending_composite()
    var image := SaExport.get_easel_image_float(easel)
    easel.document.free()
    easel.free()
    if image == null:
        return ""
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    context.update(image.get_data())
    return context.finish().hex_encode()


func _recipe(entry: Dictionary) -> Resource:
    return SaShippedPresets.build(SettingsScript, entry)


## Whether *entry*'s hashes cannot be held to the fixture on *os_name*.
func _apart_on(os_name: String, entry: Dictionary) -> bool:
    if os_name != "Windows":
        return false
    var settings: Dictionary = entry.get("settings", {})
    return APART_ON_WINDOWS.has(String(settings.get("pattern_name", "")))


func _pictures(settings: Resource) -> Dictionary:
    return {"stroke": _hash(settings, false), "dab": _hash(settings, true)}


func _read_fixture() -> Dictionary:
    var text := FileAccess.get_file_as_string(FIXTURE)
    var parsed: Variant = JSON.parse_string(text)
    return parsed if parsed is Dictionary else {}


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


func test_every_shipped_recipe_paints_the_hash_it_painted_before() -> void:
    var entries := SaShippedPresets.entries()
    assert_true(entries.size() >= 21, "the shipped set was read, %d recipes" % entries.size())
    var painted: Dictionary = {}
    var apart: Array[String] = []
    for entry: Dictionary in entries:
        var settings := _recipe(entry)
        assert_not_null(settings, "%s builds on the stamp's settings" % entry["name"])
        if settings != null:
            painted[entry["name"]] = _pictures(settings)
        if _apart_on(OS.get_name(), entry):
            apart.append(entry["name"])

    if not OS.get_environment(WRITE_ENV).is_empty():
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE.get_base_dir()))
        var file := FileAccess.open(FIXTURE, FileAccess.WRITE)
        file.store_string(JSON.stringify(painted, "  ", true) + "\n")
        file = null
        print("wrote %d recipes to %s" % [painted.size(), FIXTURE])

    var recorded := _read_fixture()
    assert_eq(recorded.keys().size(), painted.size(), "the fixture holds every recipe and no other")
    for preset_name: String in painted:
        var now: Dictionary = painted[preset_name]
        var then: Dictionary = recorded.get(preset_name, {})
        assert_false(String(now["stroke"]).is_empty(), "%s painted its S" % preset_name)
        if apart.has(preset_name):
            skip(APART_SKIP)
            continue
        assert_eq(now["stroke"], then.get("stroke", ""), "%s paints the S it painted before the move" % preset_name)
        assert_eq(now["dab"], then.get("dab", ""), "and the one dab")


## A saved preset whose lines name the old folder, with and without its `uid`,
## loads through the store and paints the recipe's own hash.
func test_a_preset_saved_before_the_move_loads_and_paints_the_same() -> void:
    var recorded := _read_fixture()
    var store := _store()
    var checked := 0
    for entry: Dictionary in SaShippedPresets.entries():
        var settings := _recipe(entry)
        if settings == null or not recorded.has(entry["name"]):
            continue
        var expected: String = recorded[entry["name"]]["stroke"]
        if _apart_on(OS.get_name(), entry):
            skip(APART_SKIP)
            expected = _hash(settings, false)
        checked += _loaded_both_ways(entry["name"], settings, store, expected)
    assert_eq(checked, recorded.size() * 2, "every recipe was loaded both ways")


## The recipes Windows cannot hold to the fixture, held here on any machine to
## what the same machine paints, so the branch a Windows run takes for them is
## read on Linux too. Each paints an S, and a saved copy of it in the old
## folder loads both ways and paints that S again.
func test_the_recipes_windows_cannot_hold_to_the_fixture_still_paint_and_load() -> void:
    var store := _store()
    var names: Array[String] = []
    var checked := 0
    for entry: Dictionary in SaShippedPresets.entries():
        if not _apart_on("Windows", entry):
            continue
        var settings := _recipe(entry)
        assert_not_null(settings, "%s builds on the stamp's settings" % entry["name"])
        if settings == null:
            continue
        names.append(entry["name"])
        var stroke := _hash(settings, false)
        assert_false(stroke.is_empty(), "%s painted its S" % entry["name"])
        checked += _loaded_both_ways(entry["name"], settings, store, stroke)
    assert_true(names.has("Pencil") and names.has("Charcoal"), "Pencil and Charcoal draw through Paper Grain, got %s" % [names])
    assert_eq(checked, names.size() * 2, "each was loaded both ways")


## Saves *settings* as *preset_name* into *store* with its lines in the old
## folder, once with the `uid` and once without, loads each and holds that it
## paints the *expected* S. Answers how many loads it held.
func _loaded_both_ways(preset_name: String, settings: Resource, store: SaPresetStore, expected: String) -> int:
    var checked := 0
    for keep_uid: bool in [true, false]:
        var stored := store.save_preset(preset_name, settings)
        assert_false(stored.is_empty(), "%s saved into the scratch store" % preset_name)
        var path := scratch_dir.path_join(stored + ".tres")
        var rewritten := _as_before_the_move(path, keep_uid)
        assert_true(rewritten > 0, "%s names the dynamics in %d lines, now the old folder's" % [preset_name, rewritten])
        var loaded := store.load_preset(stored)
        assert_not_null(loaded, "%s loads with its lines in the old folder, uid kept %s" % [preset_name, keep_uid])
        if loaded == null:
            continue
        assert_eq(_hash(loaded, false), expected, "and paints the S it painted before, uid kept %s" % keep_uid)
        checked += 1
    return checked


## Writes the old folder into every `[ext_resource]` line of *path* that names
## one of the six scripts, dropping the `uid` unless *keep_uid*. Answers how
## many lines it changed.
func _as_before_the_move(path: String, keep_uid: bool) -> int:
    var text := FileAccess.get_file_as_string(path)
    var out: PackedStringArray = []
    var changed := 0
    for line: String in text.split("\n"):
        var named := line.begins_with("[ext_resource ") and (line.contains(NEW_DIR) or line.contains(OLD_DIR))
        if named:
            line = line.replace(NEW_DIR, OLD_DIR)
            if not keep_uid:
                line = RegEx.create_from_string(' uid="[^"]*"').sub(line, "")
            changed += 1
        out.append(line)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string("\n".join(out))
    return changed
