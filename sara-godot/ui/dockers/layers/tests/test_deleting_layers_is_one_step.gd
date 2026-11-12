## Deleting several layers is one undo step.
##
## A painter picks Layer 2 and Layer 1 together, presses the minus
## and then Ctrl+Z once, and only one layer came back, because the Undo
## docker held two Delete Layer rows. The minus now hands the whole pick to
## `SaLayerOps.remove_many`, which commits one step.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so nothing here enters the tree.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _docker(easel: SaEasel) -> LayersDocker:
    var canvas := SaCanvas.new()
    canvas.easel = easel
    var docker := LayersDocker.new()
    docker.target_canvas = canvas
    docker.sync_layer_list()
    return docker


func _pick(docker: LayersDocker, layers: Array) -> void:
    docker.sync_layer_list()
    for i: int in layers.size():
        var row := -1
        for r: int in docker.item_list.row_count():
            if docker.item_list.layer_at(r) == layers[i]:
                row = r
        if i == 0:
            docker.item_list.picked.select(row)
        else:
            docker.item_list.picked.select_extra(row)


func _names(doc: SaDocument) -> Array[String]:
    var found: Array[String] = []
    for layer in SaLayerOps.new(doc).layers():
        found.append(str(layer.name))
    return found


func _drop(docker: LayersDocker) -> void:
    var canvas := docker.target_canvas
    docker.free()
    canvas.free()


## The note's own case: two picked layers, the minus, one row in the Undo
## docker, one Ctrl+Z brings both back where they were, and redo takes both.
func test_two_picked_layers_go_as_one_step_and_come_back_together() -> void:
    var easel := _easel()
    var doc := easel.document
    var base := _names(doc)
    var one := SaLayerOps.new(doc).add()
    one.name = "Layer 1"
    var two := SaLayerOps.new(doc).add()
    two.name = "Layer 2"
    var before := _names(doc)
    var docker := _docker(easel)
    _pick(docker, [two, one])
    var steps := doc.history.step_count()

    docker.actions.delete_picked()

    assert_eq(_names(doc), base, "both picked layers are gone")
    assert_eq(doc.history.step_count(), steps + 1, "the Undo docker gains one row")
    assert_eq(doc.undo_redo.get_current_action_name(), "Delete Layers", "named for several")

    assert_true(doc.undo(), "one Ctrl+Z")
    assert_eq(_names(doc), before, "brings both back in their places")

    assert_true(doc.redo(), "Ctrl+Shift+Z")
    assert_eq(_names(doc), base, "deletes both again")

    _drop(docker)
    easel.free()


## A group picked together with a layer inside it is the group's delete,
## one step, and the member is not taken out twice.
func test_a_group_and_a_layer_inside_it_are_one_step() -> void:
    var easel := _easel()
    var doc := easel.document
    var base := _names(doc)
    var ops := SaLayerOps.new(doc)
    var inner := ops.add()
    inner.name = "Inner"
    var group := ops.group_layers([inner])
    group.name = "Group"
    var before := _names(doc)
    var docker := _docker(easel)
    _pick(docker, [group, inner])
    var steps := doc.history.step_count()

    docker.actions.delete_picked()

    assert_eq(_names(doc), base, "the group and its member are gone")
    assert_eq(doc.history.step_count(), steps + 1, "as one step")

    assert_true(doc.undo(), "one Ctrl+Z")
    assert_eq(_names(doc), before, "brings the group and its member back")
    assert_eq(SaLayerStack.parent_of(inner), group, "with the member still inside it")

    _drop(docker)
    easel.free()


## A group, a layer of its own and a layer outside it, picked together, go as
## one Delete Layers step, and undo puts the member back inside the group.
func test_a_group_beside_a_layer_is_one_step() -> void:
    var easel := _easel()
    var doc := easel.document
    var base := _names(doc)
    var ops := SaLayerOps.new(doc)
    var inner := ops.add()
    inner.name = "Inner"
    var group := ops.group_layers([inner])
    group.name = "Group"
    var loose := ops.add()
    loose.name = "Loose"
    var before := _names(doc)
    var steps := doc.history.step_count()

    assert_true(ops.remove_many([loose, group]), "the pick is deleted")
    assert_eq(_names(doc), base, "all three layers are gone")
    assert_eq(doc.history.step_count(), steps + 1, "as one step")

    assert_true(doc.undo(), "one Ctrl+Z")
    assert_eq(_names(doc), before, "brings all three back in their places")
    assert_eq(SaLayerStack.parent_of(inner), group, "the member inside its group")

    easel.free()


## The corner lines a call sends, with the lines earlier suites kept set aside
## and put back.
func _refusals_of(work: Callable) -> Array[String]:
    var lines: Array[String] = []
    var announcing := SaProblems.announce
    SaProblems.announce = false
    var kept_faults := SaProblems.pending
    var kept_refusals := SaProblems.pending_refusals
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: lines.append(line))
    work.call()
    SaProblems.detach_sink()
    SaProblems.pending = kept_faults
    SaProblems.pending_refusals = kept_refusals
    SaProblems.announce = announcing
    return lines


## A pick that is the whole document is refused whole and leaves no step, and a
## pick of several rows says the same corner line a lone group that is the
## whole document says.
func test_a_pick_of_every_layer_is_refused_whole() -> void:
    var easel := _easel()
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var top := ops.add()
    top.name = "Top"
    var before := _names(doc)
    var steps := doc.history.step_count()

    var several := _refusals_of(func() -> void: assert_false(ops.remove_many(ops.layers()), "the pick is refused"))
    assert_eq(_names(doc), before, "every layer stays")
    assert_eq(doc.history.step_count(), steps, "and no step is made")
    assert_eq(several, [SaLayerOps.KEEPS_A_LAYER] as Array[String], "and the corner says why")

    var whole := ops.group_layers(ops.layers().filter(func(l: SaLayer) -> bool: return SaLayerStack.parent_of(l) == null))
    steps = doc.history.step_count()
    var one := _refusals_of(func() -> void: assert_false(ops.remove_many([whole]), "a group that is everything is refused"))
    assert_eq(doc.history.step_count(), steps, "with no step")
    assert_eq(one, several, "and the same line")

    easel.free()


## One picked layer is still `remove`, so its step keeps its name, and the
## only layer is still cleared rather than taken out.
func test_one_layer_is_the_single_delete() -> void:
    var easel := _easel()
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var top := ops.add()
    top.name = "Top"

    assert_true(ops.remove_many([top]), "one layer is deleted")
    assert_eq(doc.undo_redo.get_current_action_name(), "Delete Layer", "under the single name")

    var below := ops.layers()
    var removals := below.size()
    while below.size() > 1 and removals > 0:
        ops.remove(below[0])
        below = ops.layers()
        removals -= 1
    assert_eq(below.size(), 1, "One layer is left")
    assert_true(ops.remove_many(below), "the only layer is answered")
    assert_eq(ops.layers(), below, "by clearing it, not taking it out")

    easel.free()


## `can_remove` answers for a group as `remove_group` acts, so Delete Layer
## dims on a group that holds the whole document and stays lit on one that
## does not.
func test_can_remove_answers_for_a_group() -> void:
    var easel := _easel()
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var inner := ops.add()
    var group := ops.group_layers([inner])
    assert_true(ops.can_remove(group), "a group beside other layers can go")

    var whole := ops.group_layers(ops.layers().filter(func(l: SaLayer) -> bool: return SaLayerStack.parent_of(l) == null))
    assert_not_null(whole, "everything is wrapped in one group")
    assert_false(ops.can_remove(whole), "and a group that is the whole document cannot")

    easel.free()
