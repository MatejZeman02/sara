## The layers docker's row, and the picture in it.
##
## A row reads like Krita's: eye icon, thumbnail, name, then empty space and the
## three locks aligned from the right. A lock that is off is still drawn, so it
## is not invisible and a lock that is on does not arrive from nowhere.
extends "res://tests/test_framework.gd"

## The thumbnail is a compute dispatch over the layer's chunks.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)


func _easel(size: Vector2i = Vector2i(512, 256)) -> SaEasel:
    var easel := SaEasel.create_default(size)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


## Half floats, because that is what a thumbnail is kept in.
func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (y * texture.size.x + x) * 8
    return Color(data.decode_half(at), data.decode_half(at + 2), data.decode_half(at + 4), data.decode_half(at + 6))


func test_the_thumbnail_keeps_the_documents_shape() -> void:
    assert_eq(SaLayerThumbnail.thumbnail_size(Vector2i(512, 256)), Vector2i(32, 16), "A wide document gives a wide picture")
    assert_eq(SaLayerThumbnail.thumbnail_size(Vector2i(256, 512)), Vector2i(16, 32), "and a tall one a tall picture")
    assert_eq(SaLayerThumbnail.thumbnail_size(Vector2i(300, 300)), Vector2i(32, 32), "a square is square")
    assert_eq(SaLayerThumbnail.thumbnail_size(Vector2i(8, 4)), Vector2i(8, 4), "and a document smaller than the box is itself")
    assert_eq(SaLayerThumbnail.thumbnail_size(Vector2i.ZERO), Vector2i.ZERO, "A document with no size has no picture")


## The whole point: the paint reaches the row without a readback.
func test_a_painted_layer_shows_in_its_thumbnail() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer
    doc.fill_layer(RED, layer)

    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(layer, doc)
    thumb.refresh()

    var picture: SaTexture = thumb._texture
    assert_not_null(picture, "the thumbnail allocated a texture")
    if picture != null:
        assert_eq(picture.size, Vector2i(32, 16), "at the document's aspect")
        var middle := _texel(picture, 16, 8)
        assert_almost_eq(middle.r, 1.0, 0.02, "and the middle of it is the red that was painted")
        assert_almost_eq(middle.g, 0.0, 0.02, "with nothing in green")
        assert_almost_eq(middle.a, 1.0, 0.02, "opaque")
    thumb.free()
    easel.free()


## A layer nobody has painted on holds no chunks, so there is nothing to draw
## and nothing to allocate.
func test_an_empty_layer_costs_no_texture() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := SaLayerOps.new(doc).add()

    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(layer, doc)
    thumb.refresh()

    assert_null(thumb._texture, "nothing painted, nothing allocated")
    assert_null(thumb.texture, "and nothing drawn")
    thumb.free()
    easel.free()


## A group holds no chunks of its own, so its row takes a folder mark instead
## and stops asking the GPU anything.
func test_a_group_row_shows_a_mark_rather_than_a_picture() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.fill_layer(RED, doc.active_layer)
    var group := SaLayerOps.new(doc).group_active()
    assert_not_null(group, "the document has a group")

    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(group, doc)
    thumb.refresh()

    assert_null(thumb._texture, "a group allocates no picture")
    assert_true(thumb.is_processing() == false, "and stops polling for one")
    thumb.free()
    easel.free()


func _row_of(list: SaLayerList, idx: int) -> SaRowFrame:
    return list.rows[idx]


## Every one of the three is drawn on every row, at full strength, and says
## which state it is in by being pressed or not rather than by being there at
## all. An off lock is not dimmed, because one at 30 per cent reads as
## one that cannot be pressed.
func test_a_row_draws_all_three_toggles_and_presses_the_ones_that_are_on() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer

    var list := SaLayerList.new()
    var idx := list.add_item("Layer 1", 0, false, layer)

    var toggles: Dictionary = _row_of(list, idx).toggles
    assert_eq(toggles.size(), 3, "three toggles, whatever the layer's flags are")
    for which: StringName in toggles:
        var btn: Button = toggles[which]
        assert_true(btn.visible, "%s is drawn" % which)
        assert_false(btn.button_pressed, "%s is off" % which)
        assert_almost_eq(btn.modulate.a, 1.0, 0.001, "%s is at full strength while it is off" % which)

    layer.is_locked = true
    layer.clip_to_below = true
    list.refresh_all()
    assert_true(toggles[&"paint"].button_pressed, "the paint lock lights up")
    assert_true(toggles[&"clip"].button_pressed, "and so does the clip")
    assert_false(toggles[&"alpha"].button_pressed, "the alpha lock is still off")

    list.free()
    easel.free()


## A toggle writes the layer's own flag, which is what the menu and the chord
## write, so the three doors cannot disagree.
func test_pressing_a_toggle_writes_the_layers_flag() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer

    var list := SaLayerList.new()
    list.target_canvas = null
    var idx := list.add_item("Layer 1", 0, false, layer)
    var toggles: Dictionary = _row_of(list, idx).toggles

    assert_false(layer.alpha_locked, "the alpha lock starts off")
    (toggles[&"alpha"] as Button).pressed.emit()
    assert_true(layer.alpha_locked, "and the press turned it on")
    (toggles[&"alpha"] as Button).pressed.emit()
    assert_false(layer.alpha_locked, "and off again")

    list.free()
    easel.free()


## A group's eye hides its children, and each child's own eye is left
## alone, so opening the group again shows the stack as it was. The row says
## both: the eye is the layer's and the dimming is the group's.
func test_a_hidden_group_dims_its_children_without_touching_their_eyes() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.fill_layer(RED, doc.active_layer)
    var child := doc.active_layer
    var group := SaLayerOps.new(doc).group_active()
    assert_not_null(group, "the child is inside a group")
    if group == null:
        easel.free()
        return

    assert_true(SaLayerRowView.shown_by_its_groups(child), "the group is open, so the child is shown")
    group.visible = false
    assert_false(SaLayerRowView.shown_by_its_groups(child), "hiding the group hides the child")
    assert_true(child.visible, "and the child's own eye is untouched")
    assert_false(SaLayerStack.contributes(doc, child), "so the canvas leaves it out")

    group.visible = true
    assert_true(SaLayerRowView.shown_by_its_groups(child), "and opening the group shows it again")
    assert_true(SaLayerStack.contributes(doc, child), "as it was")
    easel.free()


## A rename writes the node's name and announces nothing, so a row that keeps
## the label it was built with shows a stale name until the docker rebuilds the
## list. The capture found it before this test did.
func test_a_renamed_layer_shows_its_new_name_on_the_next_refresh() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer

    var list := SaLayerList.new()
    var idx := list.add_item("Layer 5", 0, false, layer)

    layer.name = "Hidden"
    list.refresh_all()
    var lbl: Label = _row_of(list, idx).lbl
    assert_eq(lbl.text, "Hidden", "the row reads the layer's name again on every refresh")

    # The fold mark is a button of
    # its own, so a group's label is its name and nothing else, and the mark
    # is a control a refresh cannot rewrite away.
    var group := SaLayerOps.new(doc).group_active()
    var g_idx := list.add_item(str(group.name), 0, true, group)
    list.refresh_all()
    var g_row := _row_of(list, g_idx)
    assert_eq((g_row.lbl as Label).text, str(group.name), "and a group's label is its name alone")
    assert_eq(
        (g_row.disclose as Button).icon, SaUI.get_icon(SaLayerRowView.GROUP_MARK), "with the fold mark on a button beside it"
    )

    list.free()
    easel.free()


## A double click or F2 opens the name, Enter commits and Escape cancels.
## The name goes onto the layer, which is the node the `.sad` writer reads, so
## a committed rename is in the document rather than only on the row.
func test_a_rename_writes_the_layers_own_name_and_the_row_follows() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer
    layer.name = "Layer 5"

    var list := SaLayerList.new()
    var idx := list.add_item("Layer 5", 0, false, layer)
    var item := _row_of(list, idx)
    var edit: LineEdit = item.edit
    var lbl: Label = item.lbl

    assert_false(edit.visible, "the field is not there until something asks for it")
    assert_true(lbl.visible, "and the name is a plain label")

    assert_true(list.begin_rename(idx), "the row opens for editing")
    assert_eq(list.renaming_row(), idx, "and says which row it is on")
    assert_true(edit.visible, "the field is up")
    assert_false(lbl.visible, "in the label's place rather than beside it")
    assert_eq(edit.text, "Layer 5", "holding the name it is about to replace")

    edit.text = "Sky"
    edit.text_submitted.emit("Sky")
    assert_eq(str(layer.name), "Sky", "Enter wrote the name onto the layer")
    assert_eq(lbl.text, "Sky", "the row followed without waiting for a rebuild")
    assert_false(edit.visible, "and the field went away")
    assert_eq(list.renaming_row(), -1, "so no row is being renamed")

    list.free()
    easel.free()


## Escape leaves the name as it was, and the field still closes. Without the
## second half a cancelled rename would leave a text box on the row for good.
func test_escape_leaves_the_name_alone() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer
    layer.name = "Sky"

    var list := SaLayerList.new()
    var idx := list.add_item("Sky", 0, false, layer)
    var item := _row_of(list, idx)
    var edit: LineEdit = item.edit

    list.begin_rename(idx)
    edit.text = "Something else"
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    edit.gui_input.emit(escape)

    assert_eq(str(layer.name), "Sky", "the layer kept the name it had")
    assert_false(edit.visible, "and the field closed")
    assert_true((item.lbl as Label).visible, "with the label back in its place")

    list.free()
    easel.free()


## A name that a `Node` cannot hold keeps its characters, since the layer
## holds the typed name beside its node's, and a name that is nothing at all
## is no name.
func test_a_typed_name_is_trimmed_and_kept_before_it_lands() -> void:
    assert_eq(SaLayerRename.sanitize_name("  Sky  "), "Sky", "the edges are trimmed")
    assert_eq(SaLayerRename.sanitize_name("Sky/Sea"), "Sky/Sea", "a slash stays")
    assert_eq(SaLayerRename.sanitize_name("a.b:c@d%e"), "a.b:c@d%e", "and so does each of the other four")
    assert_eq(SaLayerRename.sanitize_name("   "), "", "and spaces alone are no name")

    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer
    layer.name = "Sky"

    var list := SaLayerList.new()
    var idx := list.add_item("Sky", 0, false, layer)
    var edit: LineEdit = _row_of(list, idx).edit

    list.begin_rename(idx)
    edit.text = "   "
    edit.text_submitted.emit("   ")
    assert_eq(str(layer.name), "Sky", "an empty name cancels rather than clearing the row")

    list.free()
    easel.free()


## A group's label carries the fold mark, and the mark is not part of its name.
## Opening a group's row has to offer the name alone or the mark accumulates.
func test_renaming_a_group_does_not_write_its_fold_mark() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := SaLayerOps.new(doc).group_active()
    assert_not_null(group, "the document has a group")
    if group == null:
        easel.free()
        return
    group.name = "Sketch"

    var list := SaLayerList.new()
    var idx := list.add_item(str(group.name), 0, true, group)
    var item := _row_of(list, idx)
    var edit: LineEdit = item.edit

    list.begin_rename(idx)
    assert_eq(edit.text, "Sketch", "the field holds the name without the mark")
    edit.text = "Lines"
    edit.text_submitted.emit("Lines")
    assert_eq(str(group.name), "Lines", "and the mark stayed out of the document")
    assert_eq((item.lbl as Label).text, "Lines", "while the row draws the new name alone")

    list.free()
    easel.free()


## A rebuild under an open field: the docker clears the list whenever the
## document's tree moves, and a field left connected to a freed row would answer
## with an index naming a different layer.
func test_a_rebuild_closes_an_open_field_without_writing() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer
    layer.name = "Sky"

    var list := SaLayerList.new()
    var idx := list.add_item("Sky", 0, false, layer)
    var edit: LineEdit = _row_of(list, idx).edit

    list.begin_rename(idx)
    edit.text = "Never"
    list.clear()
    assert_eq(list.renaming_row(), -1, "the rebuild closed the field")
    assert_eq(str(layer.name), "Sky", "and wrote nothing on the way out")

    list.free()
    easel.free()
