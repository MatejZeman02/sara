## The layer rename dialog: what it opens holding, what OK writes, what
## Cancel leaves alone, and what a name the `Node` cannot hold becomes.
##
## The dialog is built and never added to a tree, for the reason
## `test_layer_comment.gd` gives about a docker: a `Window` in a headless run
## hangs the whole suite. Everything the test needs is reachable without one,
## which is why the dialog owns the write and the docker only hosts it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const DialogScript = preload("res://ui/dockers/layers/layer_rename_dialog.gd")

## Needs a RenderingDevice for the document the dialog writes through.
const REQUIRES_GPU := true

const NOTE := "the sky, too blue"


func _easel(size: Vector2i = Vector2i(128, 64)) -> SaEasel:
    var easel := SaEasel.create_default(size)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _field(dialog: SaDialogWindow, node_name: String) -> LineEdit:
    return dialog.find_child(node_name, true, false) as LineEdit


func _note_field(dialog: SaDialogWindow) -> TextEdit:
    return dialog.find_child("NoteEdit", true, false) as TextEdit


func _press(dialog: SaDialogWindow, node_name: String) -> void:
    var button := dialog.find_child(node_name, true, false) as Button
    assert_not_null(button, "the dialog carries a %s" % node_name)
    button.pressed.emit()


## The two fields open on the layer's own name and note, so the painter
## renaming it can see what it was noted as.
func test_the_dialog_opens_on_the_layers_name_and_note() -> void:
    var easel := _easel()
    var layer := easel.document.active_layer
    layer.name = "Sky"
    layer.comment = NOTE

    var dialog := DialogScript.new()
    dialog.open_for(easel.document, layer)
    assert_eq(_field(dialog, "NameEdit").text, "Sky", "the name field holds the layer's name")
    assert_eq(_note_field(dialog).text, NOTE, "and the note box holds its note")
    dialog.free()
    easel.free()


## OK writes both, and the document says it has changed, which is the same pair
## of lines the inline rename's receiver writes.
func test_ok_writes_the_name_and_the_note() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer
    layer.name = "Sky"
    layer.comment = NOTE
    doc.modified = false

    var dialog := DialogScript.new()
    dialog.open_for(doc, layer)
    _field(dialog, "NameEdit").text = "Cloud"
    _note_field(dialog).text = "the same sky, twice as high"
    _press(dialog, "OKButton")

    assert_eq(layer.name, "Cloud", "the layer takes the typed name")
    assert_eq(layer.comment, "the same sky, twice as high", "and the typed note")
    assert_true(doc.modified, "and the document is modified")
    dialog.free()
    easel.free()


## Cancel writes neither, which is the whole difference between it and OK.
func test_cancel_writes_neither() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer
    layer.name = "Sky"
    layer.comment = NOTE

    var dialog := DialogScript.new()
    dialog.open_for(doc, layer)
    _field(dialog, "NameEdit").text = "Cloud"
    _note_field(dialog).text = "something else"
    _press(dialog, "CancelButton")

    assert_eq(layer.name, "Sky", "the name is where it was")
    assert_eq(layer.comment, NOTE, "and so is the note")
    dialog.free()
    easel.free()


## A name goes through the same filter the inline field applies, so the two
## doors agree about what a name may be: a character a node cannot hold is
## kept as typed, and an empty name writes nothing at all.
func test_a_node_s_forbidden_characters_are_kept_and_an_empty_name_is_none() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer
    layer.name = "Sky"
    layer.comment = NOTE

    var dialog := DialogScript.new()
    dialog.open_for(doc, layer)
    _field(dialog, "NameEdit").text = "C:l@o%u/d"
    _press(dialog, "OKButton")
    assert_eq(layer.shown_name(), "C:l@o%u/d", "a name holding a node's forbidden characters keeps them")
    assert_eq(layer.comment, NOTE, "and the note is written with it")

    dialog.open_for(doc, layer)
    _field(dialog, "NameEdit").text = "   "
    _note_field(dialog).text = "nothing should take this"
    _press(dialog, "OKButton")
    assert_eq(layer.shown_name(), "C:l@o%u/d", "an empty name is not a name")
    assert_eq(layer.comment, NOTE, "and it writes no note either")
    dialog.free()
    easel.free()


## The filter is the inline field's own, read rather than restated, so the two
## cannot drift apart.
func test_the_filter_is_the_inline_fields() -> void:
    assert_eq(SaLayerRename.sanitize_name("S:k@y"), "S:k@y", "the dialog keeps what the field keeps")
    assert_eq(SaLayerRename.sanitize_name("  Sky  "), "Sky", "and trims the same edges")


## The row the dialog is opened from is the menu's tenth item, first in the list
## and above Duplicate, keyed on the id `SaLayerMenuRows` gives it, which is where the Layer menu's Rename is keyed too.
func test_the_rename_row_is_the_menus_tenth() -> void:
    assert_eq(SaLayerActions.ROW_IDS.size(), 24, "the actions menu offers 24 items, Rasterize Layer among them")
    assert_eq(SaLayerActions.ROW_IDS[SaLayerActions.Item.RENAME], SaLayerMenuRows.RENAME, "and the tenth is Rename")
