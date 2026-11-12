## A look's name folds case as a brush preset's does, so two names that differ
## only in case are one look on every system.
##
## Windows and macOS keep a folder whose names ignore case, so "warm" saved
## beside "Warm" lands in one file there, and a rename of "Warm" to "warm" that
## wrote the new name and deleted the old one deleted the look it had just
## written. Held here: a second save as "warm" leaves one look, a rename that
## changes only the case moves the file and leaves no other behind, and a
## rename onto another look's name in another case is refused naming it. This
## machine's folder keeps case, so the loss itself cannot show here, and the
## rename is held to the move, which leaves no file under the old name.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const FilterLook = preload("res://ui/dockers/filters/filter_look.gd")
const FilterLooks = preload("res://ui/dockers/filters/filter_looks.gd")

## The layers' records go through the compositor's chain.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const CURVES_VALUES := {"curves": {"master": [[0.0, 0.0], [0.5, 0.62], [1.0, 1.0]], "red": [[0.0, 0.05], [1.0, 1.0]]}}
const HSL_VALUES := {"hue": 12.0, "saturation": 130.0, "lightness": -8.0}

## Where this suite's looks go, never the painter's own.
static var scratch_dir: String = SaDataRoot.path("test_look_name_case")

var _easel: SaEasel = null
var _doc: SaDocument = null
var _registries: SaRegistries = null
var _curves := StringName()
var _hsl := StringName()
var _canvas: SaCanvas = null
var _filters: FiltersDocker = null
var _looks: FilterLooks = null
var _host: Node = null
var _was_embedding := false
var _was_root := ""


## The docker's store is pointed at a scratch folder before the docker is built,
## and embedding is forced as the other Filters docker suites force it.
func before_each() -> void:
    _was_root = FilterLook.root
    FilterLook.root = scratch_dir
    ScratchFolder.clear(scratch_dir)
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _easel = Bench.easel(Vector2i(256, 256))
    _doc = _easel.document
    _registries = Fixtures.make_registries()
    var registry := _easel.compositor.filter_chain.registry
    registry.register(SaCurvesFilter.new(), OWNER)
    registry.register(SaHueSaturationLightnessFilter.new(), OWNER)
    _curves = SaFilterRegistry.key_for(OWNER, SaCurvesFilter.new())
    _hsl = SaFilterRegistry.key_for(OWNER, SaHueSaturationLightnessFilter.new())
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _host = Node.new()
    _host.name = "LookCaseHost"
    EventBus.add_child(_host)
    _filters = FiltersDocker.new()
    _filters.parameters.target_canvas = _canvas
    _filters.parameters.registry = registry
    _looks = _filters.looks
    _looks.target_canvas = _canvas
    _looks.layer_types = _registries.layer_types
    _host.add_child(_filters)
    _filters.show()


func after_each() -> void:
    Teardown.free_nodes([_host, _canvas, _easel])
    _host = null
    _canvas = null
    _easel = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding
    ScratchFolder.clear(scratch_dir)
    FilterLook.root = _was_root


func test_a_second_save_in_another_case_writes_over_the_first_look() -> void:
    _warm_group()
    assert_eq(_looks.save("Warm"), "Warm", "The group saves as Warm")
    assert_eq(_looks.save("warm"), "Warm", "A save as warm lands on Warm")
    assert_eq(_looks.describe()["looks"], ["Warm"], "and one look is listed, where two were")
    assert_eq(_files(), ["Warm.tres"], "and one file is on disk")


func test_a_rename_that_changes_only_the_case_keeps_the_look() -> void:
    _warm_group()
    _looks.save("Warm")
    assert_true(_looks.pick("Warm"), "The look is picked")
    assert_true(_looks.open_rename(), "Rename... opens the field")
    _looks.name_field.text_submitted.emit("warm")
    assert_eq(_looks.describe()["looks"], ["warm"], "One look is listed, under warm")
    assert_eq(_looks.picked(), "warm", "and it stays picked")
    assert_eq(_files(), ["warm.tres"], "No Warm.tres and no passing file is left")
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    var look := store.load_preset("warm") as FilterLook
    assert_not_null(look, "A store opened afresh reads the look back")
    if look != null:
        assert_eq(look.members.size(), 2, "with both its members")


func test_a_rename_onto_another_look_in_another_case_is_refused() -> void:
    _warm_group()
    _looks.save("Warm")
    _looks.save("Cool")
    var warm_bytes := FileAccess.get_file_as_bytes(scratch_dir.path_join("Warm.tres"))
    var cool_bytes := FileAccess.get_file_as_bytes(scratch_dir.path_join("Cool.tres"))
    assert_eq(_looks.rename("Cool", "warm"), "", "Cool to warm is refused")
    assert_true(String(_looks.describe()["said"]).contains("'Warm'"), "in the sentence naming Warm")
    assert_eq(_looks.describe()["looks"], ["Cool", "Warm"], "and both looks are kept")
    assert_eq(FileAccess.get_file_as_bytes(scratch_dir.path_join("Warm.tres")), warm_bytes, "Warm reads back as it was")
    assert_eq(FileAccess.get_file_as_bytes(scratch_dir.path_join("Cool.tres")), cool_bytes, "and so does Cool")


## The files in the scratch folder, sorted, thumbnails and folders aside.
func _files() -> Array[String]:
    var names: Array[String] = []
    for file_name: String in DirAccess.get_files_at(scratch_dir):
        if file_name.ends_with(".tres") or file_name.ends_with(SaPresetNames.PASSING_SUFFIX):
            names.append(file_name)
    names.sort()
    return names


## A group of a Curves layer and a Hue, Saturation and Lightness layer over the
## background, the second switched off, screened at half, and the group active.
func _warm_group() -> SaLayer:
    var ops := SaFilterConversion.new(_doc)
    var curves := ops.add_holding(_curves, CURVES_VALUES, _registries.layer_types, "Curves")
    curves.opacity = 0.8
    var hsl := ops.add_holding(_hsl, HSL_VALUES, _registries.layer_types, "Hue Saturation Lightness")
    hsl.visible = false
    hsl.blend_mode = SaLayer.BLEND_MODE.SCREEN
    hsl.opacity = 0.5
    var group := SaLayerOps.new(_doc).group_layers([curves, hsl])
    _doc.set_active_layer(group)
    return group
