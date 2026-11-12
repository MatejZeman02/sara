## Folding a group's rows away.
##
## A group can be collapsed. Every row was always
## drawn, at whatever depth, and the fold mark on a group row was the first two
## characters of its label rather than anything a press could reach.
##
## What a collapse must not do is the half worth pinning here. The document's
## own order is untouched, so what the file holds and what composites are the
## same whichever way a mark points, and expanding rebuilds from that order
## rather than restoring a remembered arrangement. The button itself is proved
## by `scenarios/layer-group-collapse.json`, because a docker is a `Window`
## and adding one to the tree in a headless run hangs.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


## A document of Background, Sky and Hills, with the last two wrapped in a
## group, and a docker showing it.
func _grouped() -> Array:
    var easel := _easel()
    var doc := easel.document
    doc.active_layer.name = "Background"
    var sky := SaLayerOps.new(doc).add()
    sky.name = "Sky"
    var hills := SaLayerOps.new(doc).add()
    hills.name = "Hills"

    var canvas := SaCanvas.new()
    canvas.easel = easel
    var docker := LayersDocker.new()
    docker.target_canvas = canvas
    docker.sync_layer_list()
    var picked: Array[SaLayer] = [sky, hills]
    docker.item_list.select_layers(picked, hills)
    docker.actions.toggle_group()

    var group := SaLayerStack.parent_of(hills)
    return [easel, canvas, docker, group, sky, hills]


func _names(docker: LayersDocker) -> Array:
    var out: Array = []
    for i: int in docker.item_list.row_count():
        var layer: SaLayer = docker.item_list.layer_at(i)
        out.append(str(layer.name) if layer != null else "")
    return out


func _order(doc: SaDocument) -> Array:
    var out: Array = []
    for child in doc.get_children():
        var layer := child as SaLayer
        if layer != null and layer != doc.stroke_layer and not layer.is_queued_for_deletion():
            out.append(str(layer.name))
    return out


func _row_of(docker: LayersDocker, layer: SaLayer) -> int:
    for i: int in docker.item_list.row_count():
        if docker.item_list.layer_at(i) == layer:
            return i
    return -1


func test_collapsing_hides_the_children_and_expanding_brings_them_back() -> void:
    var parts := _grouped()
    var docker: LayersDocker = parts[2]
    var group: SaLayer = parts[3]
    assert_true(group != null, "the two picked layers are in a group")

    var open_rows := _names(docker)
    assert_true(open_rows.has("Sky") and open_rows.has("Hills"), "both children have rows while the group is open")

    docker._on_group_toggled(_row_of(docker, group))
    var shut := _names(docker)
    assert_false(shut.has("Sky"), "collapsing takes the group's children out of the list")
    assert_false(shut.has("Hills"), "both of them, not only the active one")
    assert_true(shut.has(str(group.name)), "and leaves the group's own row, or nothing could reopen it")

    docker._on_group_toggled(_row_of(docker, group))
    assert_eq(_names(docker), open_rows, "expanding brings them back in the same order")

    (parts[1] as SaCanvas).free()
    docker.free()
    (parts[0] as SaEasel).free()


## A collapse is
## a way of looking at the stack, so nothing about the document moves.
func test_a_collapse_leaves_the_documents_own_order_alone() -> void:
    var parts := _grouped()
    var easel: SaEasel = parts[0]
    var docker: LayersDocker = parts[2]
    var group: SaLayer = parts[3]
    var before := _order(easel.document)

    docker._on_group_toggled(_row_of(docker, group))
    assert_eq(_order(easel.document), before, "the order is what it was while the group is shut")
    docker._on_group_toggled(_row_of(docker, group))
    assert_eq(_order(easel.document), before, "and after it is opened again")

    (parts[1] as SaCanvas).free()
    docker.free()
    easel.free()


## A group's own eye is a different question from its fold mark, and the eye is
## settled already. Collapsing must not touch it, or a painter who folded a
## group away would find it gone from the picture as well as from the list.
func test_a_collapse_does_not_hide_the_layers_it_folds_away() -> void:
    var parts := _grouped()
    var docker: LayersDocker = parts[2]
    var group: SaLayer = parts[3]
    var sky: SaLayer = parts[4]

    docker._on_group_toggled(_row_of(docker, group))
    assert_true(group.visible, "the group is still drawn")
    assert_true(sky.visible, "and so is a child whose row has gone")

    (parts[1] as SaCanvas).free()
    docker.free()
    (parts[0] as SaEasel).free()


## A filter that hides rows changes what an
## index means, and the gap between the row that is active
## and the layer that is active is closed. Folding the active layer away reopens it unless
## the mark moves, so it moves onto the group.
func test_folding_the_active_layer_away_moves_the_mark_onto_the_group() -> void:
    var parts := _grouped()
    var easel: SaEasel = parts[0]
    var docker: LayersDocker = parts[2]
    var group: SaLayer = parts[3]
    var hills: SaLayer = parts[5]

    easel.document.set_active_layer(hills)
    docker.sync_layer_list()
    assert_eq(docker.item_list.picked.selected_idx, _row_of(docker, hills), "a child is the active row")

    docker._on_group_toggled(_row_of(docker, group))
    assert_eq(easel.document.active_layer, group, "shutting the group takes the mark with it")
    assert_eq(
        docker.item_list.picked.selected_idx,
        _row_of(docker, group),
        "so a row is still lit and a shift click still has an anchor"
    )

    (parts[1] as SaCanvas).free()
    docker.free()
    easel.free()
