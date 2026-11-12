## Move Layer Up and Down step
## past a sibling's whole block, so a layer below a group goes above it in one
## press and the group keeps its child. `move` counted slots, and one slot up
## from under a group is the group's member, so the layer landed between the
## header and its child with no group of its own.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document the commands act on.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


## Background, Layer 1 and Layer 2 bottom first, Layer 2 wrapped in Group 1,
## with Layer 1 active. Returns the group.
func _stack(doc: SaDocument) -> SaLayer:
    var ops := SaLayerOps.new(doc)
    ops.add().name = "Layer 2"
    var group := ops.group_layers([_named(doc, "Layer 2")])
    group.name = "Group 1"
    doc.set_active_layer(_named(doc, "Layer 1"))
    return group


func _named(doc: SaDocument, wanted: String) -> SaLayer:
    for layer in SaLayerOps.new(doc).layers():
        if layer.name == wanted:
            return layer
    return null


func _order(doc: SaDocument) -> Array:
    return SaLayerOps.new(doc).layers().map(func(layer: SaLayer) -> String: return layer.name)


## Whether every member stands inside its group's block, which is the run of
## layers right under the group's own node.
func _blocks_hold(doc: SaDocument) -> bool:
    var ops := SaLayerOps.new(doc)
    for layer in ops.layers():
        var group := SaLayerStack.parent_of(layer)
        if group == null:
            continue
        var top := group.get_index()
        var bottom := top - ops.subtree(group).size() + 1
        if layer.get_index() < bottom or layer.get_index() >= top:
            return false
    return true


func test_ctrl_page_up_puts_the_layer_above_the_group_in_one_press() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    var group := _stack(doc)
    var before := _order(doc)
    var steps := doc.history.step_count()

    assert_true(registries.commands.execute(&"layer_move_up"), "Move Layer Up runs on Layer 1")
    assert_eq(_order(doc), ["Background", "Layer 2", "Group 1", "Layer 1"], "Layer 1 goes above the whole group")
    assert_eq(_named(doc, "Layer 2").group, group, "and the group still holds Layer 2")
    assert_null(_named(doc, "Layer 1").group, "while Layer 1 stays out of it")
    assert_eq(doc.history.step_count(), steps + 1, "one press is one step")
    assert_eq(doc.undo_redo.get_current_action_name(), "Move Layer", "called Move Layer")

    assert_true(registries.commands.execute(&"layer_move_down"), "Move Layer Down runs on it")
    assert_eq(_order(doc), before, "and returns it below the group")
    assert_true(_blocks_hold(doc), "with the group whole")

    assert_true(doc.undo(), "the press down undoes")
    assert_true(doc.undo(), "and so does the press up")
    assert_eq(_order(doc), before, "back where it started")
    Fixtures.teardown(surface)


func test_a_member_at_the_top_leaves_the_group_above_its_header() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    var group := _stack(doc)
    var member := _named(doc, "Layer 2")
    var ops := SaLayerOps.new(doc)

    assert_true(ops.can_move(member, 1), "the top member can move up")
    assert_true(ops.move(member, 1), "and does")
    assert_eq(_order(doc), ["Background", "Layer 1", "Group 1", "Layer 2"], "above the group's header")
    assert_null(member.group, "out of the group")
    assert_true(doc.undo(), "one step")
    assert_eq(member.group, group, "and undo puts it back in")
    assert_eq(_order(doc), ["Background", "Layer 1", "Layer 2", "Group 1"], "under the header")
    Fixtures.teardown(surface)


## Going down, the lowest member steps out of the group where it stands, so
## the press still shows, and the next press takes it past Layer 1.
func test_a_member_at_the_bottom_leaves_the_group_below_it() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    _stack(doc)
    var member := _named(doc, "Layer 2")
    var ops := SaLayerOps.new(doc)

    assert_true(ops.move(member, -1), "the lowest member moves down")
    assert_null(member.group, "out of the group")
    assert_eq(_order(doc), ["Background", "Layer 1", "Layer 2", "Group 1"], "below what is left of it")
    assert_true(ops.move(member, -1), "the next press")
    assert_eq(_order(doc), ["Background", "Layer 2", "Layer 1", "Group 1"], "passes Layer 1")
    Fixtures.teardown(surface)


## Layer 1 walked to the top of the stack and back to the bottom never stands
## where it splits a group from its members, and the ends dim.
func test_no_press_splits_a_group() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    var ops := SaLayerOps.new(doc)
    ops.add().name = "Layer 2"
    ops.add().name = "Layer 3"
    var outer := ops.group_layers([_named(doc, "Layer 2"), _named(doc, "Layer 3")])
    var inner := ops.group_layers([_named(doc, "Layer 3")])
    assert_eq(inner.group, outer, "the inner group stands in the outer one")
    assert_true(_blocks_hold(doc), "and both start whole, %s" % [_order(doc)])
    var layer := _named(doc, "Layer 1")
    var presses := 0
    while ops.can_move(layer, 1) and presses < 20:
        assert_true(ops.move(layer, 1), "every press it is offered moves")
        assert_true(_blocks_hold(doc), "and leaves every group whole, %s" % [_order(doc)])
        presses += 1
    assert_eq(layer.get_index(), ops.layers().size() - 1, "it ends on top")
    assert_eq(presses, 1, "having gone past the outer group's block in one press")
    while ops.can_move(layer, -1) and presses < 40:
        assert_true(ops.move(layer, -1), "every press down moves")
        assert_true(_blocks_hold(doc), "and leaves every group whole, %s" % [_order(doc)])
        presses += 1
    assert_eq(layer.get_index(), 0, "it ends at the bottom")
    assert_eq(_named(doc, "Layer 3").group, inner, "the inner group keeps its member")
    assert_eq(inner.group, outer, "and stays in the outer one")
    Fixtures.teardown(surface)
