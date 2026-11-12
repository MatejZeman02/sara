## An engine is asked whether it converts a preset: the
## converter registry in the door, the store's question of it, and the Convert
## to rows on a preset's menu.
##
## The converters are the engines' own to write, by a painter's flagship
## ruling, so this suite writes one of its own over two engines of its own and
## proves the registry with it. Neither engine is a module's: a stamp script
## and a noise script built here, each declaring its id the way a module's
## settings do, so the suite asks nothing of `modules/`.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")

## Never the real `user://brush_presets`, for `test_brush_presets.gd`'s reason.
static var scratch_dir: String = SaDataRoot.path("test_s2_converters")

var _stamp_script: GDScript = null
var _noise_script: GDScript = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _stamp_script = _engine_script(&"stamp", "@export var radius: float = 0.5\n@export var scatter: float = 0.0\n")
    _noise_script = _engine_script(&"noise", "@export var radius: float = 0.5\n@export var strength: float = 0.0\n")


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


# --- The registry ----------------------------------------------------------


## A converter registered through a module's scoped context is found by its
## pair, owned by that module, and answers yes only for its own direction.
func test_a_converter_registers_through_the_door_and_is_asked_by_pair() -> void:
    var registries := SaRegistries.new()
    registries.build_context(Callable(), Callable())
    var ctx := registries.context.for_module(&"test-converters")
    var found := registries.context.converters
    assert_true(ctx.register_converter(&"stamp", &"noise", _stamp_to_noise), "A module registers a converter through its context")
    assert_true(found.converts(&"stamp", &"noise"), "The pair answers yes")
    assert_false(found.converts(&"noise", &"stamp"), "and the other direction no, it is a pair of its own")
    assert_true(found.converter_for(&"stamp", &"noise").is_valid(), "The converter is found by its pair")
    assert_eq(found.owner_of(&"stamp", &"noise"), &"test-converters", "owned by the module that registered it")
    assert_eq(found.targets_from(&"stamp"), [&"noise"] as Array[StringName], "Stamp can become noise")
    assert_true(found.targets_from(&"noise").is_empty(), "and noise can become nothing yet")


## A second converter of one pair is refused, and unloading the module that
## holds it takes it away.
func test_a_pair_is_held_once_and_goes_with_its_module() -> void:
    var registries := SaRegistries.new()
    registries.build_context(Callable(), Callable())
    var first := registries.context.for_module(&"first")
    var second := registries.context.for_module(&"second")
    assert_true(first.register_converter(&"stamp", &"noise", _stamp_to_noise), "The first module holds the pair")
    assert_false(second.register_converter(&"stamp", &"noise", _stamp_to_noise), "and the second is refused")
    assert_false(first.register_converter(&"stamp", &"stamp", _stamp_to_noise), "An engine does not convert to itself")
    assert_eq(registries.context.converters.owner_of(&"stamp", &"noise"), &"first", "The pair is still the first module's")
    first.remove_all_registrations()
    assert_false(registries.context.converters.converts(&"stamp", &"noise"), "Unloading the module takes its converter with it")


# --- The store --------------------------------------------------------------


## The suite's converter converts a preset: a new preset of the target engine
## beside the original, named after both, and the original untouched on disk.
func test_a_converted_preset_is_a_new_preset_and_the_original_is_untouched() -> void:
    var store := _store()
    var converters := SaConverterRegistry.new()
    converters.register(&"stamp", &"noise", _stamp_to_noise, &"test-converters")
    var original := _stamp_script.new() as Resource
    original.set("radius", 0.2)
    original.set("scatter", 0.8)
    var saved := store.save_preset("Splatter", original, PackedStringArray(["wet", "texture"]))
    assert_eq(saved, "Splatter", "The stamp preset saves")
    var before := _text_of(store, "Splatter")

    var targets := store.conversions_for("Splatter", converters)
    assert_eq(targets, [&"noise"] as Array[StringName], "The store asks: it can become noise")
    var written := store.convert_preset("Splatter", &"noise", converters)
    assert_eq(written, "Splatter (Noise)", "The new preset is named after the original and the engine")
    assert_eq(store.engine_for(written), &"noise", "It is the target engine's")
    var converted := store.load_preset(written)
    assert_eq(SaPresetMeta.engine_of(converted), &"noise", "down to its script")
    assert_almost_eq(float(converted.get("radius")), 0.2, 0.000001, "It carries what the converter carried")
    assert_almost_eq(float(converted.get("strength")), 0.8, 0.000001, "and what the converter made of the rest")
    var tags := Array(store.tags_for(written))
    assert_true(tags.has("wet") and tags.has("texture"), "The original's tags are carried: %s" % [tags])
    assert_true(tags.has("converted"), "beside the one the converter added")

    assert_eq(_text_of(store, "Splatter"), before, "The original's file is byte for byte what it was")
    assert_eq(store.engine_for("Splatter"), &"stamp", "and it is still a stamp preset")
    assert_eq(Array(store.list_names()), ["Splatter", "Splatter (Noise)"], "Two presets, never a replacement")

    var again := store.convert_preset("Splatter", &"noise", converters)
    assert_eq(again, "Splatter (Noise) 2", "A second conversion is a second preset")


## No converter, no row: a registry holding nothing, or none at all, offers
## nothing and converts nothing.
func test_no_converter_offers_nothing() -> void:
    var store := _store()
    store.save_preset("Round", _stamp_script.new() as Resource)
    assert_true(store.conversions_for("Round", SaConverterRegistry.new()).is_empty(), "An empty registry offers nothing")
    assert_true(store.conversions_for("Round", null).is_empty(), "and no registry offers nothing")
    var written := store.convert_preset("Round", &"noise", SaConverterRegistry.new())
    assert_eq(written, "", "A convert with no converter writes nothing")
    assert_eq(Array(store.list_names()), ["Round"], "and the library is as it was")


## A converter answering a preset of the wrong engine writes nothing, so a
## broken converter cannot put a stamp preset in the library as a noise one.
func test_a_converter_answering_the_wrong_engine_writes_nothing() -> void:
    var store := _store()
    store.save_preset("Round", _stamp_script.new() as Resource)
    var converters := SaConverterRegistry.new()
    converters.register(&"stamp", &"noise", func(source: Resource) -> Resource: return source, &"broken")
    assert_eq(store.convert_preset("Round", &"noise", converters), "", "Nothing is saved")
    assert_eq(Array(store.list_names()), ["Round"], "and the library is as it was")


# --- The menu ---------------------------------------------------------------


## The preset's menu offers Convert to with the engine that answers yes, and
## pressing the row writes the new preset.
func test_the_menu_offers_convert_to_and_the_row_converts() -> void:
    var store := _store()
    store.save_preset("Splatter", _stamp_script.new() as Resource)
    var converters := SaConverterRegistry.new()
    converters.register(&"stamp", &"noise", _stamp_to_noise, &"test-converters")
    var host := Node.new()
    var tags := SaBrushPresetTags.new(store, host, converters)
    var moved: Array = []
    tags.changed.connect(func(follow: String) -> void: moved.append(follow))
    tags.open_menu_for("Splatter", null)
    var row := StringName(SaBrushPresetTags.CONVERT_PREFIX + "noise")
    assert_true(tags.menu.row_ids().has(row), "The menu has a Convert to row for the noise engine")
    assert_true(tags.menu.row_labels().has("Noise"), "labelled with the engine's name")
    assert_eq(tags.menu.row_ids()[1], row, "under New preset... and over the tags, where a long tag list cannot bury it")
    assert_true(tags.menu.press_row(row), "The row presses")
    assert_eq(tags.tags_report()["converted"], "Splatter (Noise)", "and the new preset is written")
    assert_true(store.has_preset("Splatter") and store.has_preset("Splatter (Noise)"), "beside the original")
    assert_eq(moved.size(), 1, "The chooser is told the library moved")
    assert_false(tags.tags_report()["ticked"].has(String(row)), "A convert row is never read as a tag")
    tags.menu.free()
    tags.field.free()
    host.free()


## A menu over a registry holding nothing has the tag rows it always had and
## no Convert to row, which is what a module that registers nothing adds.
func test_a_module_that_registers_nothing_adds_nothing_to_the_menu() -> void:
    var store := _store()
    store.save_preset("Splatter", _stamp_script.new() as Resource)
    var host := Node.new()
    var tags := SaBrushPresetTags.new(store, host, SaConverterRegistry.new())
    tags.open_menu_for("Splatter", null)
    for id: StringName in tags.menu.row_ids():
        assert_false(String(id).begins_with(SaBrushPresetTags.CONVERT_PREFIX), "No Convert to row: %s" % id)
    assert_false(tags.menu.row_labels().has("Noise"), "and no engine named")
    tags.menu.free()
    tags.field.free()
    host.free()


# --- Helpers ----------------------------------------------------------------


## The suite's converter: carries the radius, makes the stamp's scatter the
## noise's strength, and tags what it made so the store's merge is seen.
func _stamp_to_noise(source: Resource) -> Resource:
    var out := _noise_script.new() as Resource
    out.set("radius", source.get("radius"))
    out.set("strength", source.get("scatter"))
    out.set_meta(SaPresetMeta.TAGS_META, PackedStringArray(["converted"]))
    # Written on the handed preset to prove the store handed a fresh copy: the
    # original's file must not see it.
    source.set("radius", 9.0)
    return out


func _engine_script(engine: StringName, fields: String) -> GDScript:
    var script := GDScript.new()
    script.source_code = 'extends Resource\nconst PRESET_ENGINE: StringName = &"%s"\n%s' % [engine, fields]
    script.reload()
    return script


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


func _text_of(store: SaPresetStore, preset_name: String) -> String:
    return FileAccess.get_file_as_string(store.dir.path_join(preset_name + SaPresetStore.EXTENSION))
