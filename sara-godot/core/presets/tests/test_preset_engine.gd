## A preset names the engine it was written for, and a tool of another engine
## refuses it rather than taking the fields whose names happen to match.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const PresetEngineMarks = preload("res://ui/dockers/presets/preset_engine_marks.gd")

## The chooser half renders its thumbnails through the real paint path.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_preset_engine")


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


## Saved from the stamp settings, the file says stamp, and so does the store.
func test_a_saved_preset_names_the_stamp_engine() -> void:
    var store := _store()
    assert_eq(store.save_preset("Ink", StampSettingsScript.new()), "Ink", "The preset saves")
    var preset := store.load_preset("Ink")
    assert_eq(preset.get_meta(SaPresetMeta.ENGINE_META, &""), &"stamp", "Its metadata is the stamp engine's id")
    assert_eq(store.engine_for("Ink"), &"stamp", "and the store reads it back")
    assert_true(_text_of(store, "Ink").contains('metadata/engine = &"stamp"'), "written into the file itself")


## A preset applied to a resource of another engine is refused, and nothing on
## that resource moves.
func test_a_preset_of_another_engine_is_refused() -> void:
    var store := _store()
    var stamp := StampSettingsScript.new()
    stamp.radius = 0.1
    store.save_preset("Ink", stamp)
    var noise := _second_engine()
    assert_eq(SaPresetMeta.engine_of(noise), &"noise", "The fake engine declares its own id")
    assert_false(store.apply_preset("Ink", noise), "A stamp preset is not applied to the noise engine")
    assert_almost_eq(float(noise.get("radius")), 0.5, 0.000001, "and a field both happen to carry is untouched")
    var why := store.refusal("Ink", noise)
    assert_true(why.contains("Stamp") and why.contains("Noise"), "The refusal names both engines: %s" % why)
    var target := StampSettingsScript.new()
    assert_true(store.apply_preset("Ink", target), "The stamp engine still takes it")
    assert_true(store.refusal("Ink", target).is_empty(), "with nothing to say")
    assert_almost_eq(target.radius, 0.1, 0.000001, "and the copy lands")


## A file written before engines were named is given one the first time the store
## reads it, and keeps it.
func test_a_preset_with_no_engine_is_stamped_when_first_read() -> void:
    var store := _store()
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join("Older" + SaPresetStore.EXTENSION)
    assert_eq(ResourceSaver.save(StampSettingsScript.new(), path), OK, "A preset written the way an earlier build wrote one")
    assert_false(_text_of(store, "Older").contains("metadata/engine"), "carries no engine")
    assert_eq(store.engine_for("Older"), &"stamp", "Reading it answers the engine its script declares")
    assert_true(_text_of(store, "Older").contains('metadata/engine = &"stamp"'), "and writes it into the file")


## The brush, the eraser and the fill all take the stamp engine's presets.
func test_the_stamp_tools_declare_the_stamp_engine() -> void:
    var registry := Fixtures.make_tool_registry()
    for tool_id: StringName in [&"brush", &"eraser", &"bucket_fill"]:
        var descriptor := registry.get_descriptor(tool_id)
        assert_not_null(descriptor, "%s is registered" % tool_id)
        if descriptor != null:
            assert_eq(descriptor.preset_engine, &"stamp", "%s takes the stamp engine's presets" % tool_id)


## The docker's cells: the stamp preset live, the noise preset dimmed with a
## tooltip that says why and its engine's name on the cell, which the stamp's
## cell under the stamp leaves off.
func test_a_preset_of_another_engine_is_listed_dimmed() -> void:
    var store := _store()
    store.save_preset("Ink", StampSettingsScript.new())
    store.save_preset("Grain", StampSettingsScript.new(), PackedStringArray(), {SaPresetMeta.ENGINE_META: &"noise"})
    var chooser := SaBrushPresetsChooser.new()
    var marks := PresetEngineMarks.new(chooser, func() -> SaPresetStore: return store, func() -> StringName: return &"stamp")
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return StampSettingsScript.new())
    assert_eq(chooser.visible_names(), ["Grain", "Ink"] as Array[String], "Both are listed, neither is hidden")
    # By hand, because the grid announces a cell when it enters the tree and a
    # chooser built in a suite is in none.
    for cell: Node in chooser.grid.get_children():
        marks.mark(cell)
    var report := marks.report()
    var grain: Dictionary = report["cells"]["Grain"]
    var ink: Dictionary = report["cells"]["Ink"]
    assert_true(bool(grain["dimmed"]), "The noise preset is dimmed")
    assert_false(bool(ink["dimmed"]), "the stamp preset is not")
    var tip := String(grain["tooltip"])
    assert_true(tip.contains("Noise") and tip.contains("Stamp"), "The dimmed cell's tooltip names both engines: %s" % tip)
    chooser.free()


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


func _text_of(store: SaPresetStore, preset_name: String) -> String:
    return FileAccess.get_file_as_string(store.dir.path_join(preset_name + SaPresetStore.EXTENSION))


## A settings resource of an engine that is not the stamp, the way the noise
## engine's will be: a script of its own declaring its own id, and one field
## whose name the stamp settings also carry.
func _second_engine() -> Resource:
    var script := GDScript.new()
    script.source_code = 'extends Resource\nconst PRESET_ENGINE: StringName = &"noise"\n@export var radius: float = 0.5\n'
    script.reload()
    return script.new() as Resource
