## One Move Up in a large
## painting, 293 layers in groups, froze Sara for seconds and grew it by gigabytes.
## The move put every child of the document back in its slot with `move_child`,
## and every call that moves a node emits `child_order_changed`, which the
## bucket fill's reference choice answered by building a row per layer. So a
## move cost one emit per node it shifted times every listener's work. Here a
## stack of 300 layers in fifteen groups is moved and timed, and the emits each
## move makes are counted, because the count is what a listener pays for.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document the commands act on.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The bound one move of the stack below stays under, in microseconds, the
## move and its undo record together. It measured 2 to 9 ms on a painter's
## machine, and a tenth of a second is the frame the unit allows, so the bound
## leaves the rest of the frame to the docker and the drawing.
const MOVE_USEC := 40000

## Fourteen groups of nineteen layers and their headers, a loose layer between
## each two, and loose layers on top until the stack holds 300.
const GROUPS := 14
const MEMBERS := 19
const LAYERS := 300


## The stack, bottom first: the fixture's own layers, then for each group a
## loose layer and the group with its members, then loose layers to the count.
## Each add goes above the active layer and into its group, so the active layer
## is set to the root's top before each. Answers the groups bottom first.
func _stack(doc: SaDocument) -> Array[SaLayer]:
    var ops := SaLayerOps.new(doc)
    var groups: Array[SaLayer] = []
    for g in GROUPS:
        doc.set_active_layer(ops.layers()[-1])
        if g > 0:
            ops.add().name = "loose %d" % g
        var members: Array = []
        for m in MEMBERS:
            var layer := ops.add()
            layer.name = "g%d m%d" % [g, m]
            members.append(layer)
        var group := ops.group_layers(members)
        group.name = "group %d" % g
        groups.append(group)
    var extra := 0
    while ops.layers().size() < LAYERS and extra < LAYERS:
        doc.set_active_layer(ops.layers()[-1])
        extra += 1
        ops.add().name = "top %d" % extra
    return groups


func _order(doc: SaDocument) -> Array:
    return SaLayerOps.new(doc).layers().map(func(layer: SaLayer) -> String: return layer.name)


## Moves *layer* by *delta* and answers how long it took in microseconds and how
## many times the document's child order changed.
func _timed_move(doc: SaDocument, layer: SaLayer, delta: int) -> Array:
    var emits := [0]
    var count := func() -> void: emits[0] += 1
    doc.child_order_changed.connect(count)
    var began := Time.get_ticks_usec()
    assert_true(SaLayerOps.new(doc).move(layer, delta), "%s moves by %d" % [layer.name, delta])
    var spent := Time.get_ticks_usec() - began
    doc.child_order_changed.disconnect(count)
    return [spent, emits[0]]


func test_the_stack_holds_300_layers() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    _stack(doc)
    assert_eq(SaLayerOps.new(doc).layers().size(), LAYERS, "300 layers, the groups' headers among them")
    Fixtures.teardown(surface)


func test_a_group_moved_up_past_a_loose_layer_shifts_only_that_layer() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    var groups := _stack(doc)
    var before := _order(doc)
    var moved := groups[7]
    var loose := before.find("loose 8")

    var measured := _timed_move(doc, moved, 1)
    print("a group of %d moved up in %d us with %d emits" % [MEMBERS + 1, measured[0], measured[1]])
    assert_true(measured[0] < MOVE_USEC, "the move stays under %d us" % MOVE_USEC)
    assert_eq(measured[1], 1, "one node shifts, the loose layer going below the group, so one emit")
    var after := _order(doc)
    assert_eq(after.find("loose 8"), loose - MEMBERS - 1, "the loose layer now stands under the group")
    assert_eq(after.find("group 7"), loose, "and the group's header where the loose layer was")

    var emits := [0]
    var count := func() -> void: emits[0] += 1
    doc.child_order_changed.connect(count)
    assert_true(doc.undo(), "the move undoes")
    doc.child_order_changed.disconnect(count)
    assert_eq(_order(doc), before, "back where it was")
    assert_eq(emits[0], 1, "and the undo shifts the one layer back")
    Fixtures.teardown(surface)


func test_a_member_moved_out_of_its_group_and_down_inside_one_stay_cheap() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    var groups := _stack(doc)
    var before := _order(doc)
    var top_member: SaLayer = SaLayerOps.new(doc).subtree(groups[3])[-1]

    var out := _timed_move(doc, top_member, 1)
    print("a member moved out of its group in %d us with %d emits" % [out[0], out[1]])
    assert_true(out[0] < MOVE_USEC, "the move out of the group stays under %d us" % MOVE_USEC)
    assert_null(top_member.group, "the member left its group")
    assert_eq(out[1], 1, "and it trades places with the header alone")

    var inside := _timed_move(doc, SaLayerOps.new(doc).subtree(groups[9])[3], -1)
    assert_true(inside[0] < MOVE_USEC, "a step down inside a group stays under %d us" % MOVE_USEC)
    assert_eq(inside[1], 1, "and shifts one node")

    assert_true(doc.undo(), "the step inside undoes")
    assert_true(doc.undo(), "and so does the step out")
    assert_eq(_order(doc), before, "the stack is as it was")
    Fixtures.teardown(surface)


## Down is the way the old walk paid for: putting every child back from the
## bottom moved each of the group's twenty nodes past the loose layer, twenty
## emits, where moving the loose layer above them is one.
func test_a_group_moved_down_past_a_loose_layer_shifts_only_that_layer() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    var groups := _stack(doc)
    var before := _order(doc)
    var loose := before.find("loose 7")

    var measured := _timed_move(doc, groups[7], -1)
    print("a group of %d moved down in %d us with %d emits" % [MEMBERS + 1, measured[0], measured[1]])
    assert_true(measured[0] < MOVE_USEC, "the move stays under %d us" % MOVE_USEC)
    assert_eq(measured[1], 1, "the loose layer goes above the group, one emit")
    assert_eq(_order(doc).find("loose 7"), loose + MEMBERS + 1, "the loose layer now stands over the group")
    assert_true(doc.undo(), "the move undoes")
    assert_eq(_order(doc), before, "back where it was")
    Fixtures.teardown(surface)
