## A layer row that cannot act is
## dimmed, and dimmed means it takes no press. Merge Down, Move Up and Move
## Down ask the `can_` function beside their operation in `SaLayerOps`, in the
## Layer menu and in the Layers docker's More menu alike, and Delete Layer dims
## only on the one press that does nothing, the only layer locked.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the documents both menus act on.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")

const MORE_ROWS := {
    "Merge Down": SaLayerActions.Item.MERGE_DOWN,
    "Move Up": SaLayerActions.Item.MOVE_UP,
    "Move Down": SaLayerActions.Item.MOVE_DOWN,
}

## Each row's command, whose number in the Layer menu `SaLayerMenuRows` holds.
const LAYER_ROWS := {
    "Merge Down": &"layer_merge_down",
    "Move Up": &"layer_move_up",
    "Move Down": &"layer_move_down",
    "Delete Layer": &"layer_delete",
}


## The real Layer menu, bound to the commands of a registry whose context sees
## *surface*, the way the app binds it, and drawn for *surface*'s document,
## which a detached bar has no Main to ask for.
func _layer_menu(surface: SaSurface) -> Array:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(Fixtures.make_registries(surface).commands)
    var menu := bar.menu("Layer") as SaLayerMenu
    menu.document = surface.easel.document
    return [bar, menu]


## The Layer menu's row key for the row *label* names.
func _key(label: String) -> StringName:
    return SaMenu.key(SaLayerMenuRows.number_of(LAYER_ROWS[label]))


func _docker() -> LayersDocker:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var docker: LayersDocker = LayersDockerScript.new()
    docker.name = "LayersDocker"
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()
    return docker


## A new document holds a background and a layer, so the top one goes and the
## document is the one-layer case.
func _one_layer(doc: SaDocument) -> void:
    var ops := SaLayerOps.new(doc)
    ops.remove(ops.layers()[-1])
    doc.set_active_layer(ops.layers()[0])


## The stack as names, bottom first, which is what a refused press must leave.
func _order(doc: SaDocument) -> Array:
    return SaLayerOps.new(doc).layers().map(func(layer: SaLayer) -> String: return layer.name)


## Every row of *rows* whose dimness is not *dimmed*, pressed or not.
func _layer_rows_not(menu: SaLayerMenu, rows: Array, dimmed: bool) -> Array:
    menu.populate()
    var wrong := []
    for label: String in rows:
        if SaMenu.list_holding(menu.popup, _key(label)).is_disabled(_key(label)) != dimmed:
            wrong.append(label)
    return wrong


## The same for the docker's row, where Merge Down is a button and the moves
## are rows of the More menu. A button is dimmed by the same `can_` function its
## folded row would be.
func _more_rows_not(docker: LayersDocker, rows: Array, dimmed: bool) -> Array:
    docker.actions.sync_from_active_layer()
    var wrong := []
    for label: String in rows:
        var item: SaLayerActions.Item = MORE_ROWS[label]
        var button := docker.actions.on_row(item)
        var is_dim := button.disabled if button != null else docker.actions.menu.is_disabled(docker.actions.row_id_of(item))
        if is_dim != dimmed:
            wrong.append(label)
    return wrong


func test_one_layer_dims_merge_and_both_moves_in_the_layer_menu_and_refuses_them() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    var held := _layer_menu(surface)
    var menu: SaLayerMenu = held[1]
    _one_layer(doc)
    assert_eq(SaLayerOps.new(doc).layers().size(), 1, "the document has one layer")
    assert_eq(_layer_rows_not(menu, ["Merge Down", "Move Up", "Move Down"], true), [], "all three dimmed")
    assert_eq(_layer_rows_not(menu, ["Delete Layer"], false), [], "and Delete Layer live, it empties the layer")
    var before := _order(doc)
    for label: String in ["Merge Down", "Move Up", "Move Down"]:
        assert_false(SaMenu.list_holding(menu.popup, _key(label)).press_row(_key(label)), "%s refuses a press" % label)
    assert_eq(_order(doc), before, "and the stack is as it was")
    held[0].free()
    Fixtures.teardown(surface)


func test_one_layer_dims_merge_and_both_moves_in_the_more_menu_and_refuses_them() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    _one_layer(doc)
    assert_eq(SaLayerOps.new(doc).layers().size(), 1, "the document has one layer")
    assert_eq(_more_rows_not(docker, ["Merge Down", "Move Up", "Move Down"], true), [], "all three dimmed")
    var before := _order(doc)
    for label: String in MORE_ROWS:
        assert_false(docker.actions.press_item(MORE_ROWS[label]), "%s refuses a press" % label)
    assert_eq(_order(doc), before, "and the stack is as it was")
    docker.target_canvas.free()


func test_the_bottom_of_two_dims_merge_and_move_down_and_leaves_move_up() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    var held := _layer_menu(surface)
    var menu: SaLayerMenu = held[1]
    var ops := SaLayerOps.new(doc)
    assert_eq(ops.layers().size(), 2, "a new document has two layers")
    doc.set_active_layer(ops.layers()[0])
    assert_eq(_layer_rows_not(menu, ["Merge Down", "Move Down"], true), [], "Layer menu: nothing below to reach")
    assert_eq(_layer_rows_not(menu, ["Move Up", "Delete Layer"], false), [], "Layer menu: up and delete live")
    var bottom := doc.active_layer
    assert_true(SaMenu.list_holding(menu.popup, _key("Move Up")).press_row(_key("Move Up")), "Move Up takes the press")
    assert_eq(ops.layers()[1], bottom, "and the bottom layer is now on top")
    assert_eq(_layer_rows_not(menu, ["Merge Down", "Move Down"], false), [], "where Merge Down and Move Down are live")
    assert_eq(_layer_rows_not(menu, ["Move Up"], true), [], "and Move Up is dimmed")
    held[0].free()
    Fixtures.teardown(surface)

    var docker := _docker()
    var docker_doc := docker.target_canvas.document
    var docker_ops := SaLayerOps.new(docker_doc)
    docker_doc.set_active_layer(docker_ops.layers()[0])
    assert_eq(_more_rows_not(docker, ["Merge Down", "Move Down"], true), [], "More menu: nothing below to reach")
    assert_eq(_more_rows_not(docker, ["Move Up"], false), [], "More menu: Move Up live")
    docker.target_canvas.free()


func test_the_only_layer_locked_dims_delete() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    var held := _layer_menu(surface)
    var menu: SaLayerMenu = held[1]
    _one_layer(doc)
    SaLayerOps.new(doc).set_locked(doc.active_layer, true)
    assert_eq(_layer_rows_not(menu, ["Delete Layer"], true), [], "the only layer locked cannot be emptied")
    assert_false(
        SaMenu.list_holding(menu.popup, _key("Delete Layer")).press_row(_key("Delete Layer")), "and Delete Layer refuses a press"
    )
    SaLayerOps.new(doc).add()
    assert_eq(_layer_rows_not(menu, ["Delete Layer"], false), [], "a second layer lets a locked one go")
    held[0].free()
    Fixtures.teardown(surface)


func test_delete_layer_says_it_empties_the_only_layer() -> void:
    var registries := Fixtures.make_registries()
    var sentence: String = registries.commands.get_descriptor(&"layer_delete").sentence
    assert_true(sentence.contains("only layer is emptied"), "the hover sentence says so: %s" % sentence)


## A group at the top of the stack cannot go higher, and the docker's Move Up
## asks `can_place`, so it dims rather than committing a step that moved
## nothing, which `place` now refuses too.
func test_a_group_at_the_top_dims_move_up_in_the_more_menu() -> void:
    var docker := _docker()
    var doc := docker.target_canvas.document
    docker.actions.toggle_group()
    assert_true(doc.active_layer.is_group, "the top layer is wrapped in a group")
    assert_eq(_more_rows_not(docker, ["Move Up"], true), [], "which cannot go higher")
    assert_eq(_more_rows_not(docker, ["Move Down"], false), [], "and can go lower")
    var steps := doc.history.step_count()
    docker.actions.move_layer(1)
    assert_eq(doc.history.step_count(), steps, "a move that goes nowhere commits no step")
    docker.target_canvas.free()
