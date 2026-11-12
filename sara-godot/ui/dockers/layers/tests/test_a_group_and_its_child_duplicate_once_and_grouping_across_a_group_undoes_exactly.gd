## A group and its child duplicate once, and grouping across a group undoes
## exactly.
##
## Duplicating a group with one of its children picked copied the child a
## second time inside the original group. Duplicate now acts on
## `SaLayerStack.roots`, as Delete does. Grouping a group's child with a
## layer outside the group pulled that layer in, and after Ctrl+Z the layer
## stayed in the group. The new group now goes to the deepest group holding
## every member, and undo gives each member back the parent it had.
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


func _drop(docker: LayersDocker) -> void:
    var canvas := docker.target_canvas
    docker.free()
    canvas.free()


## Every layer bottom first, each as its name and the name of its parent group,
## an empty parent for the top level, which is the whole shape of the tree.
func _tree(doc: SaDocument) -> Array[String]:
    var found: Array[String] = []
    for layer in SaLayerOps.new(doc).layers():
        var parent := SaLayerStack.parent_of(layer)
        found.append("%s<%s" % [layer.name, str(parent.name) if parent != null else ""])
    return found


func _named(doc: SaDocument, name: String) -> SaLayer:
    for layer in SaLayerOps.new(doc).layers():
        if str(layer.name) == name:
            return layer
    return null


## A, B and C bottom to top, with B and C grouped into Group 1, A at the root.
func _stack(doc: SaDocument) -> SaLayer:
    var ops := SaLayerOps.new(doc)
    for name: String in ["A", "B", "C"]:
        ops.add().name = name
    var group := ops.group_layers([_named(doc, "B"), _named(doc, "C")])
    group.name = "Group 1"
    return group


## The first case: the group and C picked, Duplicate, and one copy of
## the group holding one copy each of B and C, the original untouched.
func test_a_group_picked_with_its_child_is_copied_once() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _stack(doc)
    var before := _tree(doc)
    var docker := _docker(easel)
    _pick(docker, [group, _named(doc, "C")])

    docker.actions.duplicate_layer()

    var members := SaLayerStack.members(doc, group)
    assert_eq(members.size(), 2, "the original group still holds two layers")
    assert_eq(str(members[0].name), "B", "B is still in the original group")
    assert_eq(str(members[1].name), "C", "and C, with no copy of C beside it")
    var copies: Array[SaLayer] = []
    for layer in SaLayerOps.new(doc).layers():
        if layer.is_group and layer != group:
            copies.append(layer)
    assert_eq(copies.size(), 1, "one copy of the group")
    if copies.size() == 1:
        var held := SaLayerStack.members(doc, copies[0])
        assert_eq(held.size(), 2, "the copy holds two layers")
        if held.size() == 2:
            assert_true(held[0] != _named(doc, "B") and held[1] != _named(doc, "C"), "copies, not the originals")
            assert_true(str(held[0].name).begins_with("B"), "a copy of B first")
            assert_true(str(held[1].name).begins_with("C"), "then a copy of C")
    assert_eq(SaLayerOps.new(doc).layers().size(), before.size() + 3, "three new layers, the group and its two")

    assert_true(doc.undo(), "Ctrl+Z")
    assert_eq(_tree(doc), before, "takes the copy away")
    _drop(docker)
    easel.free()


## The second case: C and A picked, Group, Ctrl+Z, and the stack as it
## was, A at the root. The new group itself goes to the top level, because that
## is the deepest group that holds both, so C leaves Group 1 to join A.
func test_grouping_across_a_group_undoes_to_the_stack_it_was() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _stack(doc)
    var before := _tree(doc)
    var a := _named(doc, "A")
    var c := _named(doc, "C")
    var docker := _docker(easel)
    _pick(docker, [c, a])

    docker.actions.toggle_group()

    var wrapper := SaLayerStack.parent_of(a)
    assert_true(wrapper != null and wrapper != group, "A is in the new group, not in Group 1")
    if wrapper != null:
        assert_eq(SaLayerStack.parent_of(wrapper), null, "the new group is at the top level")
        assert_eq(SaLayerStack.parent_of(c), wrapper, "C joined it")
    assert_eq(SaLayerStack.members(doc, group).size(), 1, "Group 1 keeps B alone")
    _assert_blocks_whole(doc)

    assert_true(doc.undo(), "Ctrl+Z")
    assert_eq(_tree(doc), before, "the stack as it was before the group")
    assert_eq(SaLayerStack.parent_of(a), null, "A at the root")
    assert_eq(SaLayerStack.parent_of(c), group, "C back in Group 1")

    assert_true(doc.redo(), "redo")
    assert_eq(SaLayerStack.parent_of(a), SaLayerStack.parent_of(c), "redo wraps them again")
    _drop(docker)
    easel.free()


## Grouping inside one group still makes the group there, as it always did.
func test_grouping_within_a_group_keeps_the_group_inside_it() -> void:
    var easel := _easel()
    var doc := easel.document
    var group := _stack(doc)
    var before := _tree(doc)
    var ops := SaLayerOps.new(doc)

    var inner := ops.group_layers([_named(doc, "B"), _named(doc, "C")])

    assert_eq(SaLayerStack.parent_of(inner), group, "the new group sits inside Group 1")
    _assert_blocks_whole(doc)
    assert_true(doc.undo(), "Ctrl+Z")
    assert_eq(_tree(doc), before, "the stack as it was")
    easel.free()


## Every layer sits directly below its group's row or below a sibling of its
## own, so no group's run of rows has a stranger in it.
func _assert_blocks_whole(doc: SaDocument) -> void:
    var stack := SaLayerOps.new(doc).layers()
    for i in stack.size():
        var layer := stack[i]
        var parent := SaLayerStack.parent_of(layer)
        if parent == null:
            continue
        var at := stack.find(parent)
        assert_true(at > i, "%s sits below its group's row" % layer.name)
        for j in range(i + 1, at):
            assert_true(SaLayerStack.is_inside(stack[j], parent), "%s is inside %s" % [stack[j].name, parent.name])
