## A group of filter layers saves as a look and is added again
## from the Filters docker.
##
## The workflow: "A group of filter layers is a look. Duplicate the
## group, switch one member off, compare. Save the group as a preset the way a
## brush is saved." Held here: a look saved from a group of a Curves layer and a
## Hue, Saturation and Lightness layer reads back from a store opened afresh on
## its folder with every member's key, values, mode, opacity and switch as
## saved, Save Look... on a paint layer is refused in a sentence and writes
## nothing, a group holding a paint layer is refused the same way, a look comes
## back above the active layer as a group of its layers in one history step that
## one undo takes out whole, a look is renamed and deleted, and the docker is
## still as narrow as the place the default layout gives it.
##
## The running app is `scenarios/a-group-of-filter-layers-saves-as-a-look-and-is-added-again-from-the-filters-docker.json`.
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
static var scratch_dir: String = SaDataRoot.path("test_r3_filter_looks")

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
## and embedding is forced as the other filters suites force it.
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
    _host.name = "R3LooksHost"
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


func test_a_saved_look_reads_back_from_disk_as_it_was_saved() -> void:
    var group := _warm_group()
    assert_eq(_looks.save("Warm"), "Warm", "The group saves under the name typed")
    assert_true(_looks.describe()["looks"].has("Warm"), "and the part lists it")

    var store := SaPresetStore.new()
    store.dir = scratch_dir
    assert_eq(Array(store.list_names()), ["Warm"], "A store opened afresh on the folder finds the one look")
    var look := store.load_preset("Warm") as FilterLook
    assert_not_null(look, "and reads it back as a look")
    if look == null:
        return
    assert_eq(look.members.size(), 2, "The look keeps both members")
    var curves: Dictionary = look.members[0]
    var hsl: Dictionary = look.members[1]
    assert_eq(curves["name"], "Curves", "bottom first, Curves under")
    assert_eq(hsl["name"], "Hue Saturation Lightness", "and Hue, Saturation and Lightness over it")
    assert_eq(curves["type"], String(SaBackdropLayer.TYPE_ID), "each a filter layer")
    assert_eq(curves["records"][0]["key"], String(_curves), "Curves keeps its key")
    assert_eq(curves["records"][0]["params"], CURVES_VALUES, "and its points")
    assert_eq(hsl["records"][0]["key"], String(_hsl), "Hue, Saturation and Lightness keeps its key")
    assert_eq(hsl["records"][0]["params"], HSL_VALUES, "and its values")
    assert_eq(curves["blend_mode"], String(SaLayer.BLEND_MODE.NORMAL), "Curves keeps its mode")
    assert_eq(hsl["blend_mode"], String(SaLayer.BLEND_MODE.SCREEN), "and the other keeps its own")
    assert_almost_eq(float(curves["opacity"]), 0.8, 0.0001, "Curves keeps its opacity")
    assert_almost_eq(float(hsl["opacity"]), 0.5, 0.0001, "and the other keeps its own")
    assert_true(bool(curves["visible"]), "Curves is on")
    assert_false(bool(hsl["visible"]), "and the second is still off")
    assert_eq(look.isolated, group.isolated, "The group's isolation comes with it")
    for member: Dictionary in look.members:
        for record: Dictionary in member["records"]:
            assert_false(record.has("mask"), "and no record keeps a mask")


func test_save_look_is_refused_with_a_sentence_on_a_paint_layer() -> void:
    _warm_group()
    var paint := _doc.get_node("Background") as SaLayer
    _doc.set_active_layer(paint)
    assert_false(_looks.open_save(), "Save Look... on a paint layer opens no name field")
    assert_false(_looks.name_field.visible, "and the field stays away")
    var said := String(_looks.describe()["said"])
    assert_true(said.contains("not a group"), "The part says why in a sentence: %s" % said)
    assert_true(said.ends_with("."), "a whole one")
    assert_eq(_looks.save("Paint"), "", "A save typed anyway is refused as well")
    assert_true(_looks.describe()["looks"].is_empty(), "and nothing is written")


func test_a_group_holding_a_paint_layer_is_no_look() -> void:
    var paint := _doc.get_node("Background") as SaLayer
    var group := SaLayerOps.new(_doc).group_layers([paint])
    _doc.set_active_layer(group)
    assert_false(_looks.open_save(), "A group of a paint layer is not saved")
    assert_true(String(_looks.describe()["said"]).contains("not a filter layer"), "and the sentence says what is wrong")


func test_a_look_is_added_back_above_the_active_layer_in_one_step() -> void:
    var group := _warm_group()
    _looks.save("Warm")
    SaLayerOps.new(_doc).remove_group(group)
    var paint := _doc.get_node("Background") as SaLayer
    _doc.set_active_layer(paint)
    var before := _doc.get_child_count()
    var steps := _doc.undo_redo.get_history_count()

    assert_true(_looks.pick("Warm"), "The look is listed to pick")
    _looks.add_button.pressed.emit()
    var added := _doc.active_layer
    assert_not_null(added, "Add leaves a layer active")
    if added == null:
        return
    assert_true(added.is_group, "and it is a group")
    assert_eq(String(added.name), "Warm", "named after the look")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "The add is one step")
    assert_eq(added.get_index(), paint.get_index() + 3, "above the layer that was active, over its two members")
    var members := FilterLook.members_of(added)
    assert_eq(members.size(), 2, "The group holds two members")
    if members.size() == 2:
        assert_eq(String(members[0].name), "Curves", "Curves first from the bottom")
        assert_eq(String(members[1].name), "Hue Saturation Lightness", "and Hue, Saturation and Lightness over it")
        assert_true(members[0].is_adjustment() and members[1].is_adjustment(), "both filter layers")
        assert_true(members[0].visible, "Curves is on")
        assert_false(members[1].visible, "and the second is still off")
        assert_eq(members[1].blend_mode, SaLayer.BLEND_MODE.SCREEN, "in its mode")
        assert_almost_eq(members[1].opacity, 0.5, 0.0001, "at its opacity")
        assert_eq(members[0].filters[0].key, _curves, "Curves runs its record")
        assert_eq(SaTyped.strings(members[0].filters[0].parameters), CURVES_VALUES, "with its points")

    assert_true(_doc.undo(), "Undo")
    assert_eq(_doc.get_child_count(), before, "One undo takes the whole group out")


func test_a_look_is_renamed_and_deleted() -> void:
    _warm_group()
    _looks.save("Warm")
    assert_true(_looks.pick("Warm"), "The look is picked")
    assert_true(_looks.open_rename(), "Rename... opens the field")
    assert_eq(_looks.name_field.text, "Warm", "holding the look's name")
    _looks.name_field.text_submitted.emit("Warmer")
    assert_eq(_looks.describe()["looks"], ["Warmer"], "Return renames it")
    assert_eq(_looks.picked(), "Warmer", "and keeps it picked")
    assert_false(_looks.name_field.visible, "and the field goes")
    _looks.save("Cool")
    assert_eq(_looks.rename("Warmer", "Cool"), "", "A name another look has is refused")
    assert_eq(_looks.describe()["looks"], ["Cool", "Warmer"], "and both looks are kept")
    _looks.pick("Warmer")
    var question := _looks.ask_delete()
    assert_not_null(question, "Delete asks first")
    assert_eq(_looks.describe()["looks"], ["Cool", "Warmer"], "and keeps the look while it asks")
    if question != null:
        question.buttons[_looks.DELETE_CONFIRM].pressed.emit()
    assert_eq(_looks.describe()["looks"], ["Cool"], "Answering Delete takes the picked look off disk")


func test_the_docker_is_still_as_narrow_as_its_place() -> void:
    _warm_group()
    _looks.save("A look with a name long enough to wrap")
    _looks.open_save()
    var room := float(SaUI.px(FiltersDocker.DEFAULT_SIZE.x))
    var wide := _filters._column.get_combined_minimum_size().x
    assert_true(wide <= room, "The column with the Looks part is %d wide, in a place %d wide" % [wide, room])
    assert_true(String(_looks.describe()["sentence"]).contains("keeps none"), "and the part says a look keeps no mask")


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
