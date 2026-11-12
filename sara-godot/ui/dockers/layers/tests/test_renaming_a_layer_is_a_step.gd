## Renaming a layer is an undo step.
##
## Renaming a layer by a double click and Enter, then pressing
## Ctrl+Z, would lose the duplicate before it, and the Undo docker would list no
## rename if the name were written straight. The row's field and the Rename
## dialog both go through `SaLayerOps.rename`, which records one Rename Layer step.
##
## The Undo docker's rows are the history's action names, which is what each
## case reads, and the row's label is read off the docker after an undo, since
## the label is what the painter sees come back.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document under the docker.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")
const DialogScript = preload("res://ui/dockers/layers/layer_rename_dialog.gd")

## Along a row and past both pictures, so a press there lands on the name.
const NAME_X := 200.0


## A docker on a document of a background, a Layer 1 and a Layer 2 above it,
## readied so a selection rebuilds the rows the way it does in the app.
func _docker() -> LayersDocker:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(128, 128)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var docker: LayersDocker = LayersDockerScript.new()
    docker.name = "LayersDocker"
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()

    var doc := canvas.document
    var ops := SaLayerOps.new(doc)
    ops.layers()[-1].name = "Layer 1"
    ops.add().name = "Layer 2"
    docker.sync_layer_list()
    return docker


func _doc(docker: LayersDocker) -> SaDocument:
    return docker.target_canvas.document


func _layer(docker: LayersDocker, name: String) -> SaLayer:
    for layer in SaLayerOps.new(_doc(docker)).layers():
        if str(layer.name) == name:
            return layer
    return null


## The words on *layer*'s row, which is what the painter reads come back.
func _label(docker: LayersDocker, layer: SaLayer) -> String:
    var list: SaLayerList = docker.item_list
    for i in list.row_count():
        if list.layer_at(i) == layer:
            return (list.rows[i].lbl as Label).text
    return ""


func _press(double: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.double_click = double
    event.position = Vector2(NAME_X, 11.0)
    return event


## A double click on *layer*'s row, *wanted* typed into the field it opens,
## and Enter.
func _double_click(docker: LayersDocker, layer: SaLayer, wanted: String) -> void:
    var list: SaLayerList = docker.item_list
    var row := -1
    for i in list.row_count():
        if list.layer_at(i) == layer:
            row = i
    list._on_row_gui_input(_press(false), row)
    list._on_row_gui_input(_press(true), row)
    var at: int = list.renaming_row()
    assert_true(at >= 0, "The double click opened a field")
    if at < 0:
        return
    var edit: LineEdit = list.rows[at].edit
    edit.text = wanted
    edit.text_submitted.emit(wanted)


## The newest step's name, the last row the Undo docker draws.
func _newest(doc: SaDocument) -> String:
    return doc.undo_redo.get_current_action_name()


## The Rename dialog on *layer*, its two fields written and Rename pressed.
func _rename_by_dialog(doc: SaDocument, layer: SaLayer, wanted: String, note: String) -> void:
    var dialog := DialogScript.new()
    dialog.open_for(doc, layer)
    (dialog.find_child("NameEdit", true, false) as LineEdit).text = wanted
    (dialog.find_child("NoteEdit", true, false) as TextEdit).text = note
    (dialog.find_child("OKButton", true, false) as Button).pressed.emit()
    dialog.free()


func test_a_double_click_and_enter_is_one_rename_layer_step() -> void:
    var docker := _docker()
    var doc := _doc(docker)
    var layer := _layer(docker, "Layer 2")
    var steps := doc.history.step_count()

    _double_click(docker, layer, "Sky")
    assert_eq(str(layer.name), "Sky", "Enter wrote the name")
    assert_eq(doc.history.step_count(), steps + 1, "as one step")
    assert_eq(_newest(doc), "Rename Layer", "which the Undo docker lists as Rename Layer")

    assert_true(doc.undo(), "Ctrl+Z")
    assert_eq(str(layer.name), "Layer 2", "brings the old name back")
    assert_eq(_label(docker, layer), "Layer 2", "on the row")
    assert_true(doc.redo(), "and Ctrl+Shift+Z")
    assert_eq(str(layer.name), "Sky", "the new one")
    assert_eq(_label(docker, layer), "Sky", "on the row too")
    docker.target_canvas.free()


## The step before the rename is where an undo after it stops, which is the
## duplicate.
func test_an_undo_after_a_rename_leaves_the_step_before_it() -> void:
    var docker := _docker()
    var doc := _doc(docker)
    var copy := SaLayerOps.new(doc).duplicate(_layer(docker, "Layer 2"))
    assert_not_null(copy, "The duplicate was made")
    if copy == null:
        docker.target_canvas.free()
        return
    docker.sync_layer_list()
    var count := SaLayerOps.new(doc).layers().size()

    _double_click(docker, copy, "Sky")
    assert_true(doc.undo(), "Ctrl+Z")
    assert_eq(SaLayerOps.new(doc).layers().size(), count, "keeps the duplicate")
    assert_true(is_instance_valid(copy) and copy.get_parent() != null, "in the stack")
    assert_true(str(copy.name) != "Sky", "and undoes the rename alone")
    docker.target_canvas.free()


func test_renaming_to_the_name_it_has_adds_no_step() -> void:
    var docker := _docker()
    var doc := _doc(docker)
    var layer := _layer(docker, "Layer 2")
    var steps := doc.history.step_count()

    _double_click(docker, layer, "Layer 2")
    assert_eq(doc.history.step_count(), steps, "Enter on the same name adds no row")
    _rename_by_dialog(doc, layer, "Layer 2", layer.comment)
    assert_eq(doc.history.step_count(), steps, "and Rename in the dialog with nothing changed adds none either")
    docker.target_canvas.free()


## An empty name cancels before anything is recorded.
func test_an_empty_name_adds_no_step() -> void:
    var docker := _docker()
    var doc := _doc(docker)
    var layer := _layer(docker, "Layer 2")
    var steps := doc.history.step_count()

    _double_click(docker, layer, "   ")
    assert_eq(str(layer.name), "Layer 2", "The name stays")
    assert_eq(doc.history.step_count(), steps, "and no step is added")
    docker.target_canvas.free()


func test_the_dialog_s_name_and_note_are_one_step() -> void:
    var docker := _docker()
    var doc := _doc(docker)
    var layer := _layer(docker, "Layer 2")
    layer.comment = "the sky"
    var steps := doc.history.step_count()

    _rename_by_dialog(doc, layer, "Cloud", "the sky, twice as high")
    assert_eq(doc.history.step_count(), steps + 1, "Rename in the dialog is one step")
    assert_eq(_newest(doc), "Rename Layer", "called Rename Layer")

    assert_true(doc.undo(), "Ctrl+Z")
    assert_eq(str(layer.name), "Layer 2", "brings the old name back")
    assert_eq(layer.comment, "the sky", "and the old note")
    assert_eq(_label(docker, layer), "Layer 2", "on the row")
    assert_true(doc.redo(), "and Ctrl+Shift+Z")
    assert_eq(str(layer.name), "Cloud", "gives the new name")
    assert_eq(layer.comment, "the sky, twice as high", "and the new note")
    assert_eq(_label(docker, layer), "Cloud", "on the row too")
    docker.target_canvas.free()


## A note changed under the same name is still a change, and still a step.
func test_a_note_changed_alone_is_a_step() -> void:
    var docker := _docker()
    var doc := _doc(docker)
    var layer := _layer(docker, "Layer 2")
    var steps := doc.history.step_count()

    _rename_by_dialog(doc, layer, "Layer 2", "for the clouds")
    assert_eq(doc.history.step_count(), steps + 1, "One step")
    assert_true(doc.undo(), "and its undo")
    assert_eq(layer.comment, "", "takes the note away")
    assert_eq(str(layer.name), "Layer 2", "and leaves the name")
    docker.target_canvas.free()


## Godot puts a digit on a name a sibling holds. Both sides of the step write
## the name that landed, so a redo gives the row the name it showed.
func test_a_name_a_sibling_holds_is_recorded_as_it_landed() -> void:
    var docker := _docker()
    var doc := _doc(docker)
    var lower := _layer(docker, "Layer 1")
    var layer := _layer(docker, "Layer 2")
    lower.name = "Sky"
    docker.sync_layer_list()

    _double_click(docker, layer, "Sky")
    var landed := str(layer.name)
    assert_true(landed != "Sky", "The name a sibling holds lands with a digit on it")
    assert_true(landed != "Layer 2", "and is still a new name")
    assert_eq(_label(docker, layer), landed, "which is what the row shows")
    assert_true(doc.undo(), "Ctrl+Z")
    assert_eq(str(layer.name), "Layer 2", "brings the old name back")
    assert_true(doc.redo(), "and Ctrl+Shift+Z")
    assert_eq(str(layer.name), landed, "the name the row showed")
    assert_eq(str(lower.name), "Sky", "while the sibling keeps its own")
    docker.target_canvas.free()


## Godot counts on from the digit a taken name ends in, so Layer 1 typed on
## Layer 2 lands as Layer 2, the name the layer had, and nothing changed.
func test_a_taken_name_that_lands_as_the_old_one_adds_no_step() -> void:
    var docker := _docker()
    var doc := _doc(docker)
    var layer := _layer(docker, "Layer 2")
    var steps := doc.history.step_count()

    _double_click(docker, layer, "Layer 1")
    assert_eq(str(layer.name), "Layer 2", "The name lands as the one it had")
    assert_eq(doc.history.step_count(), steps, "so the Undo docker adds no row")
    docker.target_canvas.free()


## The door the doors share, without a docker: nothing to change is no step,
## and an empty name is not a name.
func test_rename_records_only_a_change() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var doc := easel.document
    var layer := doc.active_layer
    var ops := SaLayerOps.new(doc)
    var steps := doc.history.step_count()
    var before := str(layer.name)

    assert_false(ops.rename(layer, before), "The name it has is no step")
    assert_false(ops.rename(layer, before, layer.comment), "nor with the note it has")
    assert_false(ops.rename(layer, ""), "and an empty name is no name")
    assert_false(ops.rename(null, "Sky"), "nor is a layer that is not there")
    assert_eq(doc.history.step_count(), steps, "so nothing is recorded")
    assert_true(ops.rename(layer, "Sky"), "A new name is a step")
    assert_eq(doc.history.step_count(), steps + 1, "of its own")
    easel.free()
