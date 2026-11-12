## A layer keeps the name the painter typed, full stops and colons included.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The engine turns each of `.`, `:`, `@`, `/`, `"` and `%` in a node's name
## into an underscore, and a layer's name was its node's, so "Sky v1.2: dusk"
## typed into the Layers docker became "Sky v1_2_ dusk". The layer holds the
## typed name beside its node's now. Each case reads what the painter reads,
## the row's label, the door's layer list and the file after a reopen.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document under the docker and the save.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")
const DialogScript = preload("res://ui/dockers/layers/layer_rename_dialog.gd")
const LayersReport = preload("res://harness/report/sa_layers_report.gd")

const SKY := "Sky v1.2: dusk"
const GLAZE := '50% glaze, Ref: Ana\'s face/2 "warm" @ noon'
## Along a row and past both pictures, so a press there lands on the name.
const NAME_X := 200.0
## A file written before the typed name existed, which holds groups.
const OLD_FILE := "res://tests/data/group_filters_at_density.sad"

static var scratch_saved: String = SaDataRoot.path("test_h303_typed_names.sad")
static var scratch_picture: String = SaDataRoot.path("photo.v2.jpg")


func after_all() -> void:
    for path: String in [scratch_saved, scratch_picture]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## A docker on a document of a background and a Layer 1, with Layer 2 above
## them inside a group, readied so the rows rebuild as in the app.
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
    var ops := SaLayerOps.new(canvas.document)
    var member := ops.add()
    member.name = "Layer 2"
    ops.group_layers([member])
    docker.sync_layer_list()
    return docker


func _layer(doc: SaDocument, shown: String) -> SaLayer:
    for layer in SaLayerOps.new(doc).layers():
        if layer.shown_name() == shown:
            return layer
    return null


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


## A double click on *layer*'s row, *wanted* typed into the field and Enter,
## the docker's own rename.
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


## The Rename window on *layer*, its name written and Rename pressed.
func _rename_by_dialog(doc: SaDocument, layer: SaLayer, wanted: String) -> void:
    var dialog := DialogScript.new()
    dialog.open_for(doc, layer)
    (dialog.find_child("NameEdit", true, false) as LineEdit).text = wanted
    (dialog.find_child("OKButton", true, false) as Button).pressed.emit()
    dialog.free()


## The door's layer list, parsed as `sara.py` parses it.
func _door_list(doc: SaDocument) -> Array:
    var line := LayersReport.capture(doc)
    var parsed: Variant = JSON.parse_string(line.trim_prefix("SaCapture: layers "))
    return parsed if parsed is Array else []


func _door_entry(doc: SaDocument, shown: String) -> Dictionary:
    for entry: Dictionary in _door_list(doc):
        if entry.get("name", "") == shown:
            return entry
    return {}


func test_a_group_and_its_member_renamed_in_the_docker_show_the_typed_names() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    var member := _layer(doc, "Layer 2")
    var group := member.group
    assert_not_null(group, "Layer 2 sits in a group")
    if group == null:
        docker.target_canvas.free()
        return

    _double_click(docker, group, SKY)
    _rename_by_dialog(doc, member, GLAZE)
    docker.sync_layer_list()
    assert_eq(group.shown_name(), SKY, "The group holds the name typed in its row")
    assert_eq(_label(docker, group), SKY, "and its row shows it")
    assert_eq(member.shown_name(), GLAZE, "The member holds the name typed in the Rename window")
    assert_eq(_label(docker, member), GLAZE, "and its row shows it")

    assert_eq(_door_entry(doc, SKY).get("kind", ""), "group", "The door's layer list gives the group its typed name")
    var listed := _door_entry(doc, GLAZE)
    assert_false(listed.is_empty(), "and the member its own")
    assert_eq(listed.get("group", ""), SKY, "naming its group as the painter typed it")
    docker.target_canvas.free()


func test_the_typed_names_read_back_after_a_save_and_a_reopen_with_the_group_intact() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    var member := _layer(doc, "Layer 2")
    SaLayerOps.new(doc).rename(member.group, SKY)
    SaLayerOps.new(doc).rename(member, GLAZE)
    assert_eq(SaExport.save_sad(doc, scratch_saved), OK, "The file saves")
    docker.target_canvas.free()

    var opened := SaDocument.new()
    assert_eq(SaExport.load_sad(opened, scratch_saved, SaCompositor.new()), OK, "and opens")
    var group := _layer(opened, SKY)
    var reopened := _layer(opened, GLAZE)
    assert_not_null(group, "with the group named as typed")
    assert_not_null(reopened, "and the member named as typed")
    if group != null and reopened != null:
        assert_true(group.is_group, "The group is still a group")
        assert_eq(reopened.group, group, "and the member still sits in it")
    var header := SaSadFile.header_at(scratch_saved)
    var names: Array[String] = []
    for entry: Dictionary in header.get("layers", []):
        names.append(str(entry.get("name", "")))
    assert_true(names.has(SKY) and names.has(GLAZE), "The file stores the typed names: %s" % [names])
    opened.free()


func test_an_undo_and_a_redo_of_a_typed_name_bring_back_each_name_whole() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    var member := _layer(doc, "Layer 2")
    _double_click(docker, member, SKY)
    assert_eq(member.shown_name(), SKY, "Enter wrote the typed name")
    assert_true(doc.undo(), "Ctrl+Z")
    assert_eq(member.shown_name(), "Layer 2", "brings the old name back")
    assert_true(doc.redo(), "and Ctrl+Shift+Z")
    assert_eq(member.shown_name(), SKY, "the typed one, full stop and colon kept")
    assert_eq(_label(docker, member), SKY, "on the row too")
    docker.target_canvas.free()


## Two siblings never show one name: the engine gives the second node a digit
## and the typed name takes the same digit.
func test_a_typed_name_a_sibling_holds_lands_with_a_digit_and_keeps_its_full_stop() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    var ops := SaLayerOps.new(doc)
    var first := ops.add()
    var second := ops.add()
    ops.rename(first, "v1.2")
    ops.rename(second, "v1.2")
    assert_eq(first.shown_name(), "v1.2", "The first holds the name")
    assert_true(second.shown_name() != "v1.2", "the second does not show the same one")
    assert_true(second.shown_name().begins_with("v1."), "and keeps its full stop: %s" % second.shown_name())
    docker.target_canvas.free()


## A duplicate and a merge down carry the typed name on, as they carry any
## other name.
func test_a_duplicate_and_a_merge_down_keep_the_typed_name() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    var ops := SaLayerOps.new(doc)
    var base := ops.add()
    ops.rename(base, SKY)
    var copy := ops.duplicate(base)
    assert_not_null(copy, "The duplicate is made")
    if copy != null:
        assert_eq(copy.shown_name(), SKY + " Copy", "named after the typed name")
        assert_true(ops.merge_down(copy), "The copy merges down")
        assert_not_null(_layer(doc, SKY), "and the layer it lands in keeps the original's typed name")
    docker.target_canvas.free()


## A node renamed by hand, as a duplicate's " copy" is, shows the node's name
## rather than a typed one the node no longer holds.
func test_a_node_renamed_by_hand_shows_its_own_name() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    var member := _layer(doc, "Layer 2")
    SaLayerOps.new(doc).rename(member, SKY)
    member.name = "Plain"
    assert_eq(member.shown_name(), "Plain", "The hand-set name is the one shown")
    docker.target_canvas.free()


func test_a_picture_placed_from_photo_v2_jpg_is_a_layer_named_photo_v2() -> void:
    var picture := Image.create_empty(16, 16, false, Image.FORMAT_RGB8)
    picture.fill(Color(0.8, 0.4, 0.2))
    assert_eq(picture.save_jpg(scratch_picture), OK, "The picture is written as photo.v2.jpg")
    var docker := _docker()
    var doc := docker.target_canvas.document
    var placed := SaImageImport.open_into(doc, scratch_picture)
    assert_not_null(placed, "The picture is placed")
    if placed != null:
        assert_eq(placed.shown_name(), "photo.v2", "as a layer named photo.v2")
        docker.sync_layer_list()
        assert_eq(_label(docker, placed), "photo.v2", "which its row shows")
    docker.target_canvas.free()


## A file from before the typed name stores node names, so each layer opens
## with the name its header gives and in the group its header names.
func test_a_sad_saved_before_the_change_opens_named_and_grouped_as_before() -> void:
    var header := SaSadFile.header_at(ProjectSettings.globalize_path(OLD_FILE))
    var entries: Array = header.get("layers", [])
    assert_true(entries.size() > 1, "The old file has layers")
    var grouped := 0
    var opened := SaDocument.new()
    assert_eq(SaExport.load_sad(opened, ProjectSettings.globalize_path(OLD_FILE), SaCompositor.new()), OK, "and opens")
    for entry: Dictionary in entries:
        var shown := str(entry.get("name", ""))
        var layer := _layer(opened, shown)
        assert_not_null(layer, "'%s' opens under the name it had" % shown)
        if layer == null:
            continue
        assert_eq(str(layer.name), shown, "its node name too")
        if entry.has("group"):
            grouped += 1
            var parent := layer.group
            assert_eq(parent.shown_name() if parent != null else "", str(entry["group"]), "'%s' in its group" % shown)
    assert_true(grouped > 0, "The old file holds at least one grouped layer")
    opened.free()
