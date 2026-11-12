## Move Layer Up and Move Layer
## Down on a group move the group with its members, from the menu as from the
## docker. The menu's commands called `move`, which shifted the group's own
## node alone, so a group moved down landed below its own member.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document the commands act on.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


## Background, a layer, a group of two and a layer over it, bottom first, with
## the group active. Returns the group.
func _stack(doc: SaDocument) -> SaLayer:
    var ops := SaLayerOps.new(doc)
    var under := ops.add()
    under.name = "Under"
    var top := ops.add()
    top.name = "Top"
    ops.add().name = "Outsider"
    var group := ops.group_layers([under, top])
    group.name = "Group"
    doc.set_active_layer(group)
    return group


func _order(doc: SaDocument) -> Array:
    return SaLayerOps.new(doc).layers().map(func(layer: SaLayer) -> String: return layer.name)


## The order the docker's `move_layer` gives, which is `place` in the group's
## parent at the slot `_group_slot` counts, run on a twin document.
func _docker_order(delta: int) -> Array:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    var group := _stack(doc)
    var ops := SaLayerOps.new(doc)
    ops.place(group, SaLayerStack.parent_of(group), group.get_index() - ops.subtree(group).size() + 1 + delta)
    var order := _order(doc)
    Fixtures.teardown(surface)
    return order


## Whether both members sit in the group, right under its own node.
func _members_under(doc: SaDocument, group: SaLayer) -> bool:
    var at := group.get_index()
    var below := [doc.get_child(at - 1) as SaLayer, doc.get_child(at - 2) as SaLayer]
    return below.all(func(layer: SaLayer) -> bool: return layer.group == group)


func _moved_by_command(command: StringName, delta: int, expected: Array) -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    var group := _stack(doc)
    var before := _order(doc)

    assert_true(registries.commands.execute(command), "%s runs on a group" % command)
    assert_true(_members_under(doc, group), "%s leaves both members under the group" % command)
    assert_eq(_order(doc), expected, "%s gives the docker's order" % command)
    assert_eq(_order(doc), _docker_order(delta), "which is what the docker's move gives")

    assert_true(doc.undo(), "one step")
    assert_eq(_order(doc), before, "and one undo puts the stack back")
    Fixtures.teardown(surface)


func test_move_down_takes_the_members_along() -> void:
    _moved_by_command(&"layer_move_down", -1, ["Background", "Under", "Top", "Group", "Layer 1", "Outsider"])


func test_move_up_takes_the_members_along() -> void:
    _moved_by_command(&"layer_move_up", 1, ["Background", "Layer 1", "Outsider", "Under", "Top", "Group"])


## The dimming asks the same thing, so a group at the top of the stack cannot
## move up and one at the bottom cannot move down.
func test_a_group_at_the_end_cannot_move_past_it() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    var group := _stack(doc)
    var ops := SaLayerOps.new(doc)
    assert_true(ops.move(group, 1), "the group moves up over the outsider")
    assert_false(ops.can_move(group, 1), "and at the top it cannot move up again")
    assert_true(ops.can_move(group, -1), "while it can still move down")
    Fixtures.teardown(surface)
