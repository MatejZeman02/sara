## Every brush preset carries a description, kept through
## every write a preset goes through and never copied as a setting.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter, 2026-11-09: "every brush preset should hold a description that
## will show as a tooltip, or inside the brush editor (for user to edit) and for
## scripts via doors to know what they are picking." The description is a fact
## about the preset's own file, so this writes one through the brush editor's
## session, the surface a painter types it in, and reads the same text back
## after a save, a rename, a Save As, a conversion to another engine and a copy
## of the file into another folder, which is how a preset leaves one Sara for
## another. A plain resource of a script made here stands in for an engine's
## settings, so nothing needs a GPU.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")

const SAID: String = "A hard round for clean lines, solid at any press."

static var scratch_dir: String = SaDataRoot.path("test_description")
static var elsewhere_dir: String = SaDataRoot.path("test_description_elsewhere")


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    ScratchFolder.clear(elsewhere_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)
    ScratchFolder.clear(elsewhere_dir)


## Typed in the editor and saved, the text is in the file under its own key and
## the store reads it back.
func test_a_description_typed_in_the_editor_is_written_into_the_file() -> void:
    var store := _store()
    var session := _session_on(store, "Liner")
    session.description = SAID
    assert_true(session.is_dirty(), "A typed description marks the brush changed")
    assert_eq(session.write("Liner"), "Liner", "and Save writes it")
    assert_false(session.is_dirty(), "after which the brush reads saved")
    assert_eq(store.about_for("Liner"), SAID, "The store reads the same text back")
    var text := FileAccess.get_file_as_string(scratch_dir.path_join("Liner" + SaPresetStore.EXTENSION))
    assert_true(text.contains('metadata/description = "%s"' % SAID), "written into the preset's own file")


## A save over the name from a surface that names no description, the top bar's
## Save, keeps the one the file had.
func test_a_save_that_names_none_keeps_the_description() -> void:
    var store := _store()
    _described(store, "Liner")
    var settings := _settings(0.25)
    assert_eq(store.save_preset("Liner", settings), "Liner", "A plain save over the preset lands")
    assert_eq(store.about_for("Liner"), SAID, "and keeps its description")
    assert_eq(SaPresetMeta.description_of(store.load_preset("Liner")), SAID, "on a fresh load as well")


## A rename moves the description with the preset, and a rename that changes
## only case does too.
func test_a_rename_keeps_the_description() -> void:
    var store := _store()
    _described(store, "Liner")
    var session := _session_on(store, "Liner")
    assert_eq(session.description, SAID, "The editor opens on the stored description")
    assert_eq(session.write_named("Fine Liner"), "Fine Liner", "The rename lands")
    assert_false(store.has_preset("Liner"), "the old name is gone")
    assert_eq(store.about_for("Fine Liner"), SAID, "and the renamed preset says the same")
    assert_eq(session.write_named("fine liner"), "fine liner", "A rename in case alone lands")
    assert_eq(store.about_for("fine liner"), SAID, "and keeps it too")


## Save As is the duplicate: the copy says what the original says, and the
## original keeps its own.
func test_save_as_duplicates_the_description() -> void:
    var store := _store()
    _described(store, "Liner")
    var session := _session_on(store, "Liner")
    assert_eq(session.write("Liner Copy"), "Liner Copy", "Save As lands")
    assert_eq(store.about_for("Liner Copy"), SAID, "The copy carries the description")
    assert_eq(store.about_for("Liner"), SAID, "and the original keeps it")


## A conversion to another engine is a new preset of the same brush, and says
## what the one it came from says.
func test_a_conversion_keeps_the_description() -> void:
    var store := _store()
    _described(store, "Liner")
    var converters := SaConverterRegistry.new()
    converters.register(&"probe", &"other", func(source: Resource) -> Resource: return _other_engine(source))
    var converted := store.convert_preset("Liner", &"other", converters)
    assert_false(converted.is_empty(), "The conversion lands")
    assert_eq(store.engine_for(converted), &"other", "on the other engine")
    assert_eq(store.about_for(converted), SAID, "and says what the preset it came from says")


## A preset leaves one Sara for another as its file. Copied into another folder,
## a store pointed there reads the same description.
func test_the_file_copied_elsewhere_carries_the_description() -> void:
    var store := _store()
    _described(store, "Liner")
    DirAccess.make_dir_recursive_absolute(elsewhere_dir)
    var from := scratch_dir.path_join("Liner" + SaPresetStore.EXTENSION)
    var to := elsewhere_dir.path_join("Liner" + SaPresetStore.EXTENSION)
    assert_eq(DirAccess.copy_absolute(from, to), OK, "The file copies")
    var other := SaPresetStore.new()
    other.dir = elsewhere_dir
    assert_eq(other.about_for("Liner"), SAID, "and the other store reads the same text")


## The description is the file's and not a setting: copying one brush's
## settings onto another leaves the target's description as it was.
func test_copy_settings_leaves_the_target_s_description_alone() -> void:
    var source := _settings(0.1)
    source.set_meta(SaPresetMeta.DESCRIPTION_META, SAID)
    var target := _settings(0.9)
    target.set_meta(SaPresetMeta.DESCRIPTION_META, "The target's own.")
    SaPresetStore.copy_settings(source, target)
    assert_almost_eq(float(target.get("radius")), 0.1, 0.000001, "The setting is copied")
    assert_eq(String(target.get_meta(SaPresetMeta.DESCRIPTION_META)), "The target's own.", "and the description is not")
    var bare := _settings(0.9)
    SaPresetStore.copy_settings(source, bare)
    assert_false(bare.has_meta(SaPresetMeta.DESCRIPTION_META), "A target with none is given none")


## A file an older build wrote says what it is for under the older key, and
## that is its description until a write puts it under the new one.
func test_an_older_file_s_sentence_is_its_description() -> void:
    var store := _store()
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var older := _settings(0.5)
    older.set_meta(SaPresetMeta.ABOUT_META, SAID)
    assert_eq(ResourceSaver.save(older, scratch_dir.path_join("Older" + SaPresetStore.EXTENSION)), OK, "An older file")
    assert_eq(store.about_for("Older"), SAID, "reads its sentence as its description")
    store.save_preset("Older", _settings(0.4))
    var text := FileAccess.get_file_as_string(scratch_dir.path_join("Older" + SaPresetStore.EXTENSION))
    assert_true(text.contains("metadata/description"), "and a save writes it under the new key")


## A stock description goes through the catalogue and a painter's own comes back
## as written.
func test_a_painter_s_own_text_is_shown_as_written() -> void:
    var own := "Mine, for the cat's whiskers."
    assert_eq(SaPresetMeta.description_said(own), own, "A text the catalogue does not hold is shown as typed")
    assert_eq(SaPresetMeta.description_said(""), "", "and none is none")


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


## A preset *preset_name* in *store* carrying [constant SAID].
func _described(store: SaPresetStore, preset_name: String) -> void:
    var stored := store.save_preset(preset_name, _settings(0.5), PackedStringArray(), {SaPresetMeta.DESCRIPTION_META: SAID})
    assert_eq(stored, preset_name, "The described preset saves")


## An editor session on *preset_name*, saving it first when *store* has none.
func _session_on(store: SaPresetStore, preset_name: String) -> SaBrushEditorSession:
    if not store.has_preset(preset_name):
        store.save_preset(preset_name, _settings(0.5))
    var settings := _settings(0.5)
    store.apply_preset(preset_name, settings)
    return SaBrushEditorSession.new(settings, store, preset_name)


## Settings of a made-up engine with one field, at *radius*.
func _settings(radius: float) -> Resource:
    var made := _engine_script(&"probe").new() as Resource
    made.set("radius", radius)
    return made


func _other_engine(source: Resource) -> Resource:
    var made := _engine_script(&"other").new() as Resource
    made.set("radius", source.get("radius"))
    return made


static var _scripts: Dictionary[StringName, GDScript] = {}


func _engine_script(engine: StringName) -> GDScript:
    if not _scripts.has(engine):
        var script := GDScript.new()
        script.source_code = (
            'extends Resource\nconst PRESET_ENGINE: StringName = &"%s"\n@export var radius: float = 0.5\n' % engine
        )
        script.reload()
        _scripts[engine] = script
    return _scripts[engine]
