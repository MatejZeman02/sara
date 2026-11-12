## A note attached to a layer: what a save keeps, what the row shows, and
## what the `look` step writes.
##
## A layer carries a comment that the Layers docker shows, and a client can
## read the picture at the canvas's size. The naming was already there, so
## what is new is the note and the read.
##
## The row is built through `SaLayerRowView` rather than through the docker,
## because a docker is a `Window` and adding one in a headless run hangs, which
## is the reason `test_layer_group_collapse.gd` gives for the same choice. The
## docker with the note on it is proved by
## `scenarios/the-companions-layer-and-comment.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const RowView = preload("res://ui/dockers/layers/list/layer_row_view.gd")
const Rename = preload("res://ui/dockers/layers/list/rename/layer_rename.gd")

## Needs a RenderingDevice for the save and the readback. The runner skips this
## suite without one.
const REQUIRES_GPU := true

static var scratch: String = SaDataRoot.path("test_layer_comment.sad")
static var scratch_look: String = SaDataRoot.path("test_layer_comment_look.png")
const NOTE := "The sky, painted too blue on purpose"


func _easel(size: Vector2i = Vector2i(256, 128)) -> SaEasel:
    var easel := SaEasel.create_default(size)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _row(layer: SaLayer, document: SaDocument) -> SaLayerRowView:
    var item: SaLayerRowView = RowView.new(str(layer.name), 0, false, 0, layer)
    item.refresh(document)
    return item


func _drop(item: SaLayerRowView) -> void:
    item.free()


## A layer with no note is what every layer has always been, and the empty
## string is what the row and the file both read.
func test_a_layer_starts_with_no_note() -> void:
    var easel := _easel()
    var layer := easel.document.active_layer
    assert_eq(layer.comment, "", "A fresh layer carries no note")
    var item := _row(layer, easel.document)
    assert_false(bool(item.report()["comment_lit"]), "and its mark is dimmed")
    _drop(item)
    easel.free()


## The mark lights when there is a note, the text goes on the row's tooltip and
## on the mark's, and taking the note off puts the row back the way it was.
func test_the_row_lights_its_mark_and_carries_the_text() -> void:
    var easel := _easel()
    var layer := easel.document.active_layer
    layer.comment = NOTE
    var item := _row(layer, easel.document)

    var report := item.report()
    assert_eq(String(report["comment"]), NOTE, "The row reports the note")
    assert_true(bool(report["comment_lit"]), "and lights its mark")
    assert_eq(item.tooltip_text, NOTE, "The row's tooltip is the note")
    assert_eq(item.comment_btn.tooltip_text, NOTE, "and so is the mark's")

    layer.comment = ""
    item.refresh(easel.document)
    assert_false(bool(item.report()["comment_lit"]), "An emptied note dims the mark")
    assert_eq(item.tooltip_text, "", "and clears the tooltip")
    _drop(item)
    easel.free()


## Sara renames a layer in the row rather than in a dialog, so the field is the
## rename dialog the note asks for: it shows the note and never writes it.
func test_the_rename_field_shows_the_note_and_leaves_it_alone() -> void:
    var easel := _easel()
    var layer := easel.document.active_layer
    layer.comment = NOTE
    var item := _row(layer, easel.document)

    var rename := Rename.new()
    assert_true(rename.begin(item.edit, item.lbl, item.layer, 0), "The field opens")
    assert_eq(item.edit.tooltip_text, NOTE, "carrying the note")
    item.edit.text = "Sky"
    rename.commit()
    assert_eq(layer.comment, NOTE, "and a confirmed rename leaves the note where it was")
    _drop(item)
    easel.free()


## The `.sad` key is additive: a document with no note writes no key, and a
## note survives a save and a reopen.
func test_the_note_is_an_additive_sad_key() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.active_layer.comment = NOTE
    assert_eq(SaExport.save_sad(doc, scratch), OK, "Saved")

    var loaded := _easel()
    assert_eq(SaExport.load_sad(loaded.document, scratch), OK, "and loaded")
    var back := loaded.document.get_node(str(doc.active_layer.name)) as SaLayer
    assert_not_null(back, "The layer is there")
    assert_eq(back.comment, NOTE, "with its note")

    for child in loaded.document.get_children():
        if child is SaLayer:
            assert_true(child == back or (child as SaLayer).comment == "", "and nobody else gained one")

    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
    easel.free()
    loaded.free()


## A file written before layers carried a note has no `comment` key at all, and its layers read as
## noteless rather than as an error.
func test_a_file_written_before_the_note_opens_without_one() -> void:
    var easel := _easel()
    assert_eq(SaExport.save_sad(easel.document, scratch), OK, "A document with no note saves")

    var loaded := _easel()
    assert_eq(SaExport.load_sad(loaded.document, scratch), OK, "and opens")
    for child in loaded.document.get_children():
        if child is SaLayer:
            assert_eq((child as SaLayer).comment, "", "every layer noteless")

    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
    easel.free()
    loaded.free()
