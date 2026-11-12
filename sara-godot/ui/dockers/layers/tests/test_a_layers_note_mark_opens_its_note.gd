## The mark before a layer row's three locks opens the layer's note. It must
## answer a press, and a dimmed one must say something on hover. A
## press on it makes its layer the active one, as a press on the row does, and
## opens the note window on that layer with the keyboard in the note.
##
## The docker is readied by hand and never added to a tree, for the reason
## `test_layer_rename_dialog.gd` gives about a `Window` in a headless run. So
## the dialog is built and filled but never shown, and what this suite holds
## about the keyboard is where the dialog will put it. That it lands there in
## the running app is the scenario's,
## `scenarios/a-layers-note-mark-opens-its-note.json`.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")

const NOTE := "the sky, too blue on purpose"


## A docker over Sky, which carries a note and is the active layer, Layer 1
## under it with none, and the Background.
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
    var sky := SaLayerOps.new(doc).add()
    sky.name = "Sky"
    sky.comment = NOTE
    doc.set_active_layer(sky)
    docker.sync_layer_list()
    return docker


func _row_of(docker: LayersDocker, name: String) -> int:
    var list: SaLayerList = docker.item_list
    for i in list.row_count():
        var layer: SaLayer = list.layer_at(i)
        if layer != null and str(layer.name) == name:
            return i
    return -1


func _press_mark(docker: LayersDocker, idx: int) -> void:
    docker.item_list.rows[idx].comment_btn.pressed.emit()


func _dialog(docker: LayersDocker) -> SaLayerRenameDialog:
    return docker.find_child("LayerRenameDialog", true, false) as SaLayerRenameDialog


func _note_field(dialog: SaLayerRenameDialog) -> TextEdit:
    return dialog.find_child("NoteEdit", true, false) as TextEdit


func _free(docker: LayersDocker) -> void:
    docker.target_canvas.free()


## The second row's mark, on a layer with no note: that layer is active after
## the press, the dialog is on it, and the keyboard goes to the note.
func test_the_second_rows_mark_opens_its_layers_note() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    var second := _row_of(docker, "Layer 1")
    assert_eq(second, 1, "Layer 1 is the second row, under Sky")
    var layer: SaLayer = docker.item_list.layer_at(second)
    assert_true(doc.active_layer != layer, "and Sky is the active layer before the press")

    _press_mark(docker, second)

    assert_eq(doc.active_layer, layer, "The press made the mark's layer the active one")
    assert_eq(docker.item_list.selected_layers(), [layer], "and picked its row alone, as a press on the row does")
    var dialog := _dialog(docker)
    assert_not_null(dialog, "Rename Layer was opened")
    assert_eq(dialog._layer, layer, "on the mark's layer")
    var name_field := dialog.find_child("NameEdit", true, false) as LineEdit
    assert_eq(name_field.text, "Layer 1", "with its name in the name field")
    var note := _note_field(dialog)
    assert_eq(note.text, "", "and its empty note in the note box")
    assert_eq(dialog.first_focus, note, "and the keyboard is put in the note, not the name")
    _free(docker)


## A lit mark opens the note it carries, with the caret after the last word so
## what is typed adds to it rather than replacing it.
func test_a_lit_mark_opens_with_the_caret_after_the_note() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    var sky_row := _row_of(docker, "Sky")
    var sky: SaLayer = docker.item_list.layer_at(sky_row)
    _press_mark(docker, _row_of(docker, "Layer 1"))
    _press_mark(docker, _row_of(docker, "Sky"))

    assert_eq(doc.active_layer, sky, "The second press moved the active layer back to Sky")
    var dialog := _dialog(docker)
    assert_eq(dialog._layer, sky, "and the one dialog is on Sky now")
    var note := _note_field(dialog)
    assert_eq(note.text, NOTE, "holding its note")
    assert_eq(note.get_caret_line(), 0, "with the caret on the note's last line")
    assert_eq(note.get_caret_column(), NOTE.length(), "after its last character")
    assert_eq(dialog.first_focus, note, "and the keyboard in the note")
    _free(docker)


## Every other door to the dialog still opens on the name, which is what
## Rename... in the More menu is for.
func test_rename_from_the_menu_still_opens_on_the_name() -> void:
    var docker := _docker()
    _press_mark(docker, _row_of(docker, "Layer 1"))
    docker.actions.rename_requested.emit()
    var dialog := _dialog(docker)
    assert_eq(dialog.first_focus, dialog.find_child("NameEdit", true, false), "Rename... puts the keyboard in the name")
    _free(docker)


## The empty mark says what its press does, and the lit one is still the note.
func test_the_empty_mark_says_it_adds_a_note() -> void:
    var docker := _docker()
    var list: SaLayerList = docker.item_list
    var empty: SaRowFrame = list.rows[_row_of(docker, "Layer 1")]
    var lit: SaRowFrame = list.rows[_row_of(docker, "Sky")]
    assert_eq(empty.comment_btn.tooltip_text, "Add a note to this layer", "The dimmed mark says what a press on it does")
    assert_false(bool(empty.report()["comment_lit"]), "and stays dimmed, since nothing is behind it")
    assert_eq(empty.tooltip_text, "", "while the row itself says nothing, having no note to show")
    assert_eq(lit.comment_btn.tooltip_text, NOTE, "The lit mark's tooltip is the note")
    assert_true(bool(lit.report()["comment_lit"]), "and it is lit")
    _free(docker)


## A mark pressed on a row inside a picked set picks that row alone, because
## it is a plain press on the row as well as the door to the note.
func test_the_mark_narrows_a_picked_set_to_its_row() -> void:
    var docker := _docker()
    var list: SaLayerList = docker.item_list
    list.picked.select(_row_of(docker, "Sky"))
    list.picked.select_extra(_row_of(docker, "Background"))
    assert_eq(list.selected_layers().size(), 2, "Two rows are picked before the press")
    var layer: SaLayer = list.layer_at(_row_of(docker, "Layer 1"))
    _press_mark(docker, _row_of(docker, "Layer 1"))
    assert_eq(list.selected_layers(), [layer], "and the mark's row alone after it")
    _free(docker)


## The mark aims the brush as a press on the row's name does: another layer's
## mask stops being what the brush paints, and the layer's own mask stays it.
func test_the_mark_aims_the_brush_as_a_press_on_the_row_does() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    var sky: SaLayer = docker.item_list.layer_at(_row_of(docker, "Sky"))
    var mask := sky.add_mask()
    doc.mask_target = mask
    docker.sync_layer_list()
    _press_mark(docker, _row_of(docker, "Sky"))
    assert_eq(doc.mask_target, mask, "A press on Sky's own mark keeps its mask the brush's")
    _press_mark(docker, _row_of(docker, "Layer 1"))
    assert_null(doc.mask_target, "and a press on Layer 1's gives the brush back to the paint")
    _free(docker)


## The mark must not open a window titled Rename
## Layer with a Rename button, as it is a note being written. Opened for the
## note it says Layer Note and Save, and opened for the name again it says
## Rename Layer and Rename, because the window is one and kept.
func test_the_mark_opens_a_window_named_for_the_note() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    _press_mark(docker, _row_of(docker, "Sky"))
    var dialog := _dialog(docker)
    var ok := dialog.find_child("OKButton", true, false) as Button
    var strip := dialog.find_child("TitleLabel", true, false) as Label
    assert_eq(dialog.title, "Layer Note", "the mark's window is titled for the note")
    assert_eq(strip.text, "Layer Note", "and its title strip says so too")
    assert_eq(ok.text, "Save", "and its button saves rather than renames")

    dialog.open_for(doc, doc.active_layer)
    assert_eq(dialog.title, "Rename Layer", "opened for the name, it is Rename Layer again")
    assert_eq(strip.text, "Rename Layer", "on its title strip as well")
    assert_eq(ok.text, "Rename", "with its Rename button")
    _free(docker)
