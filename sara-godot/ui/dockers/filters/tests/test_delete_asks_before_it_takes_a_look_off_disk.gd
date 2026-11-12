## Delete in the Filters docker's Looks part asks before it takes a look off
## disk, in Brush Presets' words, and only the painter's Delete deletes.
##
## A look's file has no undo near it, and the button shares a row with
## Rename... in a docker 160 pixels wide, so a press on the wrong one
## removed the look at once. Held here: the press puts up a question naming the
## look while the look stays listed, Cancel and Escape leave it listed and its
## file as it was, and the question's Delete takes it off the list and off disk.
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
static var scratch_dir: String = SaDataRoot.path("test_look_delete_asks")

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
    _host.name = "LookDeleteHost"
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


func test_a_press_of_delete_asks_naming_the_look_and_keeps_it_meanwhile() -> void:
    _warm_group()
    _looks.save("Warm")
    assert_true(_looks.pick("Warm"), "The look is picked")
    _looks.delete_button.pressed.emit()
    var question := _question()
    assert_not_null(question, "Delete puts a question up rather than deleting")
    if question == null:
        return
    assert_eq(question.title, "Delete look", "titled for what it is about to do")
    assert_true(question.text_label.text.contains("'Warm'"), "and it names the look: %s" % question.text_label.text)
    assert_true(question.text_label.text.contains("cannot be undone"), "in Brush Presets' words")
    assert_eq(question.buttons.size(), 2, "Cancel and Delete")
    assert_eq(question.buttons[0].text, "Cancel", "Cancel first")
    assert_eq(question.buttons[1].text, "Delete", "and Delete second")
    assert_eq(_looks.describe()["looks"], ["Warm"], "The look is still listed while the question stands")
    assert_eq(_files(), ["Warm.tres"], "and its file is still on disk")


func test_cancel_leaves_the_look_and_its_file() -> void:
    _warm_group()
    _looks.save("Warm")
    var bytes := FileAccess.get_file_as_bytes(scratch_dir.path_join("Warm.tres"))
    _looks.pick("Warm")
    _looks.delete_button.pressed.emit()
    var question := _question()
    assert_not_null(question, "The question is up")
    if question == null:
        return
    question.buttons[0].pressed.emit()
    assert_eq(_looks.describe()["looks"], ["Warm"], "Cancel leaves the look listed")
    assert_eq(_looks.picked(), "Warm", "and picked")
    assert_eq(FileAccess.get_file_as_bytes(scratch_dir.path_join("Warm.tres")), bytes, "and its file reads back as it was")


func test_escape_leaves_the_look_and_its_file() -> void:
    _warm_group()
    _looks.save("Warm")
    var bytes := FileAccess.get_file_as_bytes(scratch_dir.path_join("Warm.tres"))
    _looks.pick("Warm")
    _looks.delete_button.pressed.emit()
    var question := _question()
    assert_not_null(question, "The question is up")
    if question == null:
        return
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    assert_true(ShortcutRouter.escape_in_a_dialog(escape, question), "Escape reaches the question")
    assert_false(question.visible, "and puts it away")
    assert_eq(_looks.describe()["looks"], ["Warm"], "Escape leaves the look listed")
    assert_eq(FileAccess.get_file_as_bytes(scratch_dir.path_join("Warm.tres")), bytes, "and its file reads back as it was")


func test_the_question_s_delete_takes_the_look_off_the_list_and_off_disk() -> void:
    _warm_group()
    _looks.save("Warm")
    _looks.save("Cool")
    _looks.pick("Warm")
    _looks.delete_button.pressed.emit()
    var question := _question()
    assert_not_null(question, "The question is up")
    if question == null:
        return
    # A pick made while the question stands is not what the answer deletes.
    _looks.pick("Cool")
    question.buttons[1].pressed.emit()
    assert_eq(_looks.describe()["looks"], ["Cool"], "Delete takes the look it named off the list")
    assert_eq(_files(), ["Cool.tres"], "and off disk")
    assert_true(String(_looks.describe()["said"]).contains("Deleted 'Warm'"), "and says so")


func test_delete_with_no_look_picked_asks_nothing() -> void:
    _looks.delete_button.pressed.emit()
    assert_null(_question(), "No pick, no question")


## The question the Looks part put up, or null.
func _question() -> SaMessage:
    for node in _looks.find_children("*", "Window", true, false):
        var found := node as SaMessage
        if found != null and found.visible:
            return found
    return null


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
