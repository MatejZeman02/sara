## A layer added to a document is numbered from the layers named Layer N it
## already has, and a pasted or placed picture's undo step says Paste or Place
## Picture.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Photoshop hour opened a photograph of two picture layers over a
## background and its first paint layer was "Layer 3", counted from every
## layer the document held, while the Layers docker's own naming pass counted
## from a layer's place in the stack. Both now ask `SaLayerNames`. The paste's
## history row read "Add Layer", the step `SaLayerOps.add` records, and it now
## carries the word for what the painter did.
extends "res://tests/test_framework.gd"

## Real documents, real uploads.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")

## 300 by 200, the size the canvas is made, so no fit is asked about.
const PICTURE := "res://tests/data/import_gradient.png"
const CANVAS := Vector2i(300, 200)

var _canvas: SaCanvas = null
var _docker: LayersDocker = null
var _flow: SaDocumentFiles = null
var _kept_reader: Callable = Callable()
var _kept_fit := ""


func before_each() -> void:
    SaTestFixtures.FrontDocuments.owner_in_the_run().clipboard.clear()
    _kept_reader = SaShortcutCommands.desktop_picture
    _kept_fit = SaSettings.import_fit
    SaSettings.import_fit = "ask"
    _canvas = SaCanvas.new()
    _canvas.canvas_size = CANVAS
    _canvas.easel = SaEasel.create_default(CANVAS)
    _canvas.add_child(_canvas.easel)
    EventBus.add_child(_canvas)
    _docker = LayersDockerScript.new()
    _docker.name = "LayersDocker"
    _canvas.add_child(_docker)
    _docker.target_canvas = _canvas
    _flow = SaDocumentFiles.new(func() -> SaCanvas: return _canvas)
    EventBus.add_child(_flow)


func after_each() -> void:
    SaShortcutCommands.desktop_picture = _kept_reader
    SaSettings.import_fit = _kept_fit
    if _flow != null and is_instance_valid(_flow):
        _flow.free()
    if _canvas != null and is_instance_valid(_canvas):
        _canvas.free()
    _flow = null
    _canvas = null
    _docker = null


func _doc() -> SaDocument:
    return _canvas.easel.document


## The photograph the finding opened: the fresh document's Layer 1 becomes a
## picture called "harbour", and a second picture, "boats", lands over it, so
## the stack is a Background and two picture layers and no Layer N.
func _a_photograph_of_two_pictures() -> void:
    var doc := _doc()
    doc.active_layer.name = "harbour"
    var image := Image.load_from_file(PICTURE)
    SaImageImport.place(doc, image, "boats", SaColorSpace.srgb())
    assert_eq(_names(), ["Background", "harbour", "boats"], "The stack is a Background and two pictures")


func _names() -> Array[String]:
    var out: Array[String] = []
    for child in _doc().get_children():
        if child is SaLayer and child != _doc().stroke_layer and not child.is_queued_for_deletion():
            out.append(str(child.name))
    return out


func _plus() -> SaLayer:
    _docker.actions.add_btn.pressed.emit()
    return _doc().active_layer


func _last_step() -> String:
    return _doc().undo_redo.get_current_action_name()


## The finding's own case, then the highest number and not the count: a gap
## a delete leaves is not filled, so a third layer after Layer 1 went is
## Layer 3, beside the Layer 2 still there.
func test_the_first_paint_layer_on_a_photograph_is_layer_1() -> void:
    _a_photograph_of_two_pictures()
    var first := _plus()
    assert_eq(str(first.name), "Layer 1", "The first plain layer is Layer 1, not Layer 3")
    assert_eq(_last_step(), "Add Layer", "and the plus's step is Add Layer")
    var second := _plus()
    assert_eq(str(second.name), "Layer 2", "The second is Layer 2")
    assert_true(SaLayerOps.new(_doc()).remove(first), "Layer 1 is deleted")
    var third := _plus()
    assert_eq(str(third.name), "Layer 3", "and the next is Layer 3, one more than the highest")
    assert_eq(_last_step(), "Add Layer", "its step Add Layer too")


## The rule by itself: one more than the highest Layer N, nought for a name
## that only starts the same way, and Layer 1 for a document with none.
func test_the_rule_reads_only_names_that_are_layer_and_a_number() -> void:
    assert_eq(SaLayerNames.next_in({}), "Layer 1", "None gives Layer 1")
    assert_eq(SaLayerNames.next_in({"Background": true, "harbour": true}), "Layer 1", "nor do pictures count")
    assert_eq(SaLayerNames.next_in({"Layer 2": true, "Layer 7": true}), "Layer 8", "The highest and one more")
    var lookalikes := {"Layer 2 copy": true, "Layer x": true, "Layer -4": true}
    assert_eq(SaLayerNames.next_in(lookalikes), "Layer 1", "a name that is not Layer N is not read")
    assert_eq(SaLayerNames.number_of("Layer 12"), 12, "Layer 12 is twelve")
    assert_eq(SaLayerNames.number_of("Layer"), 0, "and a bare Layer nought")


## The Layers docker's naming pass gives an unnamed layer the number the plus
## would have, on the same photograph with Layer 2 left after the delete.
func test_the_docker_s_naming_pass_numbers_as_the_plus_does() -> void:
    _a_photograph_of_two_pictures()
    var first := _plus()
    _plus()
    SaLayerOps.new(_doc()).remove(first)
    var wanted := SaLayerNames.next_for(_doc())
    assert_eq(wanted, "Layer 3", "The plus would give Layer 3")
    # No name of its own, so the engine gives it an "@" one, as a node gets.
    var lower := SaLayer.new()
    _doc().add_child(lower)
    assert_true(str(lower.name).begins_with("@"), "The lower one carries the engine's name")
    var upper := SaLayer.new()
    upper.name = "Layer"
    _doc().add_child(upper)
    var layers: Array[SaLayer] = []
    for child in _doc().get_children():
        if child is SaLayer and child != _doc().stroke_layer:
            layers.append(child)
    SaLayerListKeeper._name_layers(_doc(), layers)
    assert_eq(str(lower.name), "Layer 3", "The pass names the lower one Layer 3, as the plus would")
    assert_eq(str(upper.name), "Layer 4", "and the one above it Layer 4")
    assert_eq(_names(), ["Background", "harbour", "boats", "Layer 2", "Layer 3", "Layer 4"], "every name unique")


## A picture off the desktop clipboard pasted by Edit > Paste is a Paste step,
## Paste Special the same, and one onto a document of the picture's size
## never asks.
func test_a_pasted_picture_s_step_says_paste() -> void:
    var image := Image.load_from_file(PICTURE)
    var picture := SaDesktopPicture.new(image, "the engine")
    SaShortcutCommands.desktop_picture = func() -> SaDesktopPicture: return picture
    var placed: Array[SaLayer] = []
    SaShortcutCommands.paste(_doc(), null, func(layer: SaLayer) -> void: placed.append(layer))
    assert_eq(placed.size(), 1, "The paste put a layer down")
    assert_eq(_last_step(), "Paste", "and its step is Paste, not Add Layer")
    SaShortcutCommands.paste(_doc(), null, func(layer: SaLayer) -> void: placed.append(layer), true)
    assert_eq(placed.size(), 2, "Paste Special with no window to ask in put one down too")
    assert_eq(_last_step(), "Paste", "its step Paste as well")


## Sara's own copy pasted back is a Paste step too, the same word for the same
## command.
func test_a_paste_of_sara_s_own_copy_says_paste() -> void:
    var held := SaTestFixtures.FrontDocuments.owner_in_the_run().clipboard
    var image := Image.load_from_file(PICTURE)
    var layer := SaImageImport.place(_doc(), image, "harbour", SaColorSpace.srgb())
    held.copy(_doc(), layer)
    assert_false(held.is_empty(), "Copy took the picture's pixels")
    var placed: Array[SaLayer] = []
    SaShortcutCommands.paste(_doc(), null, func(pasted: SaLayer) -> void: placed.append(pasted))
    assert_eq(placed.size(), 1, "The paste put a layer down")
    assert_eq(_last_step(), "Paste", "and its step is Paste")


## A drop and File > Import Picture both arrive at `import_path`, and both are
## Place Picture. The drop is routed the way a drop off the desktop is.
func test_a_dropped_or_imported_picture_s_step_says_place_picture() -> void:
    var path := ProjectSettings.globalize_path(PICTURE)
    var before := _names().size()
    _flow._route_drop(PackedStringArray([path]))
    assert_eq(_names().size(), before + 1, "The drop put a layer down")
    assert_eq(_last_step(), "Place Picture", "and its step is Place Picture")
    _flow.import_path(path)
    assert_eq(_names().size(), before + 2, "File > Import Picture put one down")
    assert_eq(_last_step(), "Place Picture", "its step Place Picture too")
    _plus()
    assert_eq(_last_step(), "Add Layer", "while the plus is still Add Layer")
