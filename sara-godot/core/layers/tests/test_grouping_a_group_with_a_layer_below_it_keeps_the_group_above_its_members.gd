## Grouping a group with a layer beside it carries the
## group's members along, so every group stands directly above its own
## members in the flat order the Layers docker draws as a tree.
##
## A picked group is moved as its whole block. Grouping a layer under a group,
## a group under a layer, and two groups each leave every group on top of its
## members, the links right and the picture as it was, and undo and redo
## bring back the whole order and every node's group.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

## Half covering paints, so that an order that changed would show.
const GROUND := Color(0.1, 0.3, 0.7, 1.0)
const COLOURS: Array[Color] = [
    Color(0.9, 0.1, 0.1, 0.5),
    Color(0.1, 0.9, 0.2, 0.5),
    Color(0.9, 0.8, 0.1, 0.5),
    Color(0.6, 0.1, 0.9, 0.5),
]
const PROBE := Vector2i(30, 40)

var _easel: SaEasel
var _doc: SaDocument
var _ops: SaLayerOps
var _painted := 0


func before_each() -> void:
    _easel = Bench.easel(Vector2i(256, 256))
    _doc = _easel.document
    _ops = SaLayerOps.new(_doc)
    var bottom: SaLayer = _ops.layers()[0]
    for layer: SaLayer in _ops.layers().slice(1):
        _ops.remove(layer)
    bottom.name = "Ground"
    _doc.set_active_layer(bottom)
    _doc.fill_layer(GROUND, bottom)
    _painted = 0


func after_each() -> void:
    _ops = null
    _doc = null
    _easel.free()
    _easel = null


## A layer called *named*, filled with the next of the colours, on top.
func _layer(named: String) -> SaLayer:
    _doc.set_active_layer(_ops.layers()[-1])
    var layer := _ops.add()
    layer.name = named
    _doc.fill_layer(COLOURS[_painted % COLOURS.size()], layer)
    _painted += 1
    return layer


## A group called *named* holding two new painted layers, on top.
func _group(named: String) -> SaLayer:
    var first := _layer(named + " Member")
    var second := _layer(named + " Top")
    var group := _ops.group_layers([first, second])
    group.name = named
    return group


func _order() -> Array:
    return _ops.layers().map(func(layer: SaLayer) -> String: return layer.name)


func _links() -> Dictionary:
    var links := {}
    for layer in _ops.layers():
        var group_name := ""
        if layer.group != null:
            group_name = layer.group.name
        links[layer.name] = group_name
    return links


func _probe() -> Color:
    Bench.composite(_easel)
    return Bench.texel(_easel.output, PROBE)


## Every group sits directly above all of its members, at any depth, which is
## the order the docker can draw as a tree.
func _every_group_above_its_members(what: String) -> void:
    for layer in _ops.layers():
        if not layer.is_group:
            continue
        var top := layer.get_index()
        var block := _ops.subtree(layer)
        for member in block:
            var at := member.get_index()
            assert_true(
                at <= top and at > top - block.size(),
                "%s: %s stands inside the run under %s, order %s" % [what, member.name, layer.name, _order()]
            )


func _same(was: Color, now: Color, what: String) -> void:
    var moved := maxf(maxf(absf(was.r - now.r), absf(was.g - now.g)), maxf(absf(was.b - now.b), absf(was.a - now.a)))
    assert_true(moved < 0.001, "%s: the probe read %s and now reads %s" % [what, was, now])


## Groups *picks*, checks the rule, the links and the picture, then undoes and
## redoes and reads the whole order and every link as they were. Answers the
## order after the grouping.
func _groups_and_holds(picks: Array, what: String) -> Array:
    var order_before := _order()
    var links_before := _links()
    var picture := _probe()
    var outer := _ops.group_layers(picks)
    assert_not_null(outer, "%s: the grouping makes a group" % what)
    if outer == null:
        return []
    _every_group_above_its_members(what)
    for pick: SaLayer in picks:
        assert_true(SaLayerStack.is_inside(pick, outer), "%s: %s is inside the new group" % [what, pick.name])
    _same(picture, _probe(), what)
    var order_after := _order()
    var links_after := _links()

    assert_true(_doc.undo(), "%s: the grouping undoes" % what)
    assert_eq(_order(), order_before, "%s: undo puts the order back" % what)
    assert_eq(_links(), links_before, "%s: and every node's group" % what)
    _same(picture, _probe(), "%s, undone" % what)

    assert_true(_doc.redo(), "%s: and redoes" % what)
    assert_eq(_order(), order_after, "%s: redo makes the same order again" % what)
    assert_eq(_links(), links_after, "%s: with the same groups" % what)
    _every_group_above_its_members("%s, redone" % what)
    _same(picture, _probe(), "%s, redone" % what)
    return order_after


func test_a_group_and_the_layer_below_it_group_with_the_members_kept_under_their_group() -> void:
    var low := _layer("Low")
    var inner := _group("Inner")
    var order := _groups_and_holds([low, inner], "Low under Inner")
    assert_eq(order, ["Ground", "Low", "Inner Member", "Inner Top", "Inner", "Group 1"], "the order the note asks for")
    assert_eq(_named("Inner Member").group, inner, "Inner still holds its bottom member")
    assert_eq(_named("Inner Top").group, inner, "and its top one")
    assert_eq(inner.group, _named("Group 1"), "and Inner is inside the new group")


func test_a_group_and_the_layer_above_it_group_with_the_members_kept_under_their_group() -> void:
    var inner := _group("Inner")
    var high := _layer("High")
    var order := _groups_and_holds([inner, high], "Inner under High")
    assert_eq(order, ["Ground", "Inner Member", "Inner Top", "Inner", "High", "Group 1"], "the group's block under the layer")


func test_two_groups_group_each_kept_above_its_own_members() -> void:
    var first := _group("First")
    var second := _group("Second")
    var order := _groups_and_holds([second, first], "First and Second")
    assert_eq(
        order,
        ["Ground", "First Member", "First Top", "First", "Second Member", "Second Top", "Second", "Group 1"],
        "both blocks whole, in the order they had"
    )


func test_a_layer_below_a_group_s_member_and_the_group_group_from_a_picked_member_too() -> void:
    var low := _layer("Low")
    var inner := _group("Inner")
    var member := _named("Inner Top")
    _groups_and_holds([member, low, inner], "Low, Inner and its own member")
    assert_eq(member.group, inner, "the member picked with its group stays in its group")


func _named(wanted: String) -> SaLayer:
    for layer in _ops.layers():
        if layer.name == wanted:
            return layer
    return null
