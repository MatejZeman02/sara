## Reordering the layers docker by drag and drop.
##
## Layer items are reorderable by drag and drop, with no new UI element. A press,
## a few pixels of travel and a release already emitted a move. What was missing was
## any sign of where the drop would land, and a way into a group from either
## direction.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so the docker here is built and driven without ever entering the tree.
##
## The gesture itself is not here. Four cases drove it by
## calling `begin_drag`, `drag_over` and `drop` on the list, the three calls
## the mouse path makes, which proved nothing about a drag: a
## press that never reached the row passed them all. They are
## `scenarios/the-suite-through-the-door.json` now, a pointer pressing,
## travelling and releasing over the rows the docker draws, read by
## `LayerDragTest` in `scripts/test_door_replay.py` through the door. What
## stays is what no pointer can reach: the drop index arithmetic, the press
## handing the rest of the gesture to the list, and the eye of an unselected
## row.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _list() -> SaLayerList:
    var list := SaLayerList.new()
    for name: String in ["Top", "Middle", "Bottom"]:
        list.add_item(name)
    return list


## Where `place` is told to put the layer. `move_child` counts the index the
## node ends at, so the answer depends on which side the layer comes from.
func test_the_drop_index_depends_on_which_side_the_layer_comes_from() -> void:
    var easel := _easel()
    var doc := easel.document
    var lower := doc.active_layer
    var upper := SaLayerOps.new(doc).add()
    assert_true(upper.get_index() > lower.get_index(), "the added layer is above")

    var above := SaLayerList.Drop.ABOVE
    var below := SaLayerList.Drop.BELOW
    assert_eq(
        LayersDocker.drop_index(lower, upper, above), upper.get_index(), "coming from below, above is the target's own index"
    )
    assert_eq(LayersDocker.drop_index(upper, lower, above), lower.get_index() + 1, "coming from above it needs one more")
    assert_eq(LayersDocker.drop_index(lower, upper, below), upper.get_index() - 1, "and below is one fewer the other way")
    assert_eq(LayersDocker.drop_index(upper, lower, below), lower.get_index(), "or the target's own index")
    easel.free()


## A group row is a block, and the bottom quarter drops the layer under
## all of it. The branch answered the group's own index less one, which is the
## top of the block, so the layer left the group and was then drawn between the
## group and the members it had just left. The
## `scenarios/the-suite-through-the-door.json`, whose ninth state holds the
## same drop made by the pointer.
func test_a_drop_below_a_group_row_clears_the_whole_block() -> void:
    var easel := _easel()
    var doc := easel.document
    var background := doc.active_layer
    var under := SaLayerOps.new(doc).add()
    var top := SaLayerOps.new(doc).add()
    var outsider := SaLayerOps.new(doc).add()
    var groups := SaLayerOps.new(doc)
    var group := groups.group_layers([under, top])

    assert_eq(groups.subtree(group).size(), 3, "the group holds two layers and itself")
    assert_eq(group.get_index() - 2, under.get_index(), "and its block reaches down to the lower one")
    assert_true(outsider.get_index() > group.get_index(), "the fourth layer is above the whole block")

    var below := SaLayerList.Drop.BELOW
    assert_eq(
        LayersDocker.drop_index(outsider, group, below),
        under.get_index(),
        "a layer from above the block lands under all of it, not under the group's own row"
    )
    assert_eq(
        LayersDocker.drop_index(background, group, below),
        under.get_index() - 1,
        "and one already under the block stays where it is"
    )
    assert_eq(
        LayersDocker.drop_index(top, group, below),
        under.get_index(),
        "a member leaving by the bottom quarter clears its own siblings too"
    )
    assert_eq(
        LayersDocker.drop_index(outsider, group, SaLayerList.Drop.INTO),
        LayersDocker.drop_index(outsider, group, below),
        "which is the slot a drop into the group already used, the two differing in the group and not the index"
    )
    easel.free()


func _docker(easel: SaEasel) -> LayersDocker:
    var canvas := SaCanvas.new()
    canvas.easel = easel
    var docker := LayersDocker.new()
    docker.target_canvas = canvas
    docker.item_list.item_dropped.connect(docker._on_row_dropped)
    docker.sync_layer_list()
    return docker


## The press moves the rest of the gesture onto the list, because the press
## itself frees every row.
##
## Selecting a layer announces a new active layer, the docker rebuilds the rows,
## and Godot's mouse grab dies with the row that held it. Motion then wandered to
## whatever row was hovered and the release reached nothing at all, so the drop
## never landed. The delivery itself needs a real viewport, which is what
## `scenarios/layer-row-drag.json` presses with the mouse. What a headless test can hold
## is the mechanism: the gesture is the list's for as long as the button is down.
func test_a_press_moves_the_rest_of_the_drag_onto_the_list() -> void:
    var list := _list()
    assert_false(list.is_processing_input(), "the list watches nothing until a row is pressed")

    list._on_row_gui_input(_button(true, Vector2(10, 40)), 2)
    assert_true(list.is_processing_input(), "the press hands it the travel and the release")

    list._input(_button(false, Vector2(10, 40)))
    assert_false(list.is_processing_input(), "and the release hands them back")
    list.free()


## A one-line runtime error rather than an input one. The
## eye read its rows as `Array[int] = selected_indices() if ... else [idx]`, and
## GDScript refuses an untyped literal there *at runtime*, so the handler died on
## every row outside the set. So the eye of a layer that
## is not selected could not be clicked.
func test_the_eye_of_a_row_outside_the_set_still_toggles_it() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.active_layer.name = "Painted"
    SaLayerOps.new(doc).add().name = "Top"
    var docker := _docker(easel)
    var rows := docker.item_list

    var other := -1
    for i: int in rows.row_count():
        if not rows.picked.selected_indices().has(i):
            other = i
            break
    assert_true(other >= 0, "there is a row outside the set")
    var layer := rows.layer_at(other) as SaLayer
    assert_true(layer.visible, "and it starts visible")

    rows._on_eye_pressed(other)
    assert_false(layer.visible, "one press of its eye hides it")

    rows._on_eye_pressed(other)
    assert_true(layer.visible, "and the next shows it again")

    var canvas := docker.target_canvas
    docker.free()
    canvas.free()
    easel.free()


## A reorder lands at the nearest valid place and does not demand an exact drop
## point. Three rows of twenty pixels
## with two between them, in a docker two hundred pixels tall.
func test_a_point_on_no_row_is_measured_against_the_nearest_one() -> void:
    var rects: Array[Rect2] = [Rect2(0, 40, 100, 20), Rect2(0, 62, 100, 20), Rect2(0, 84, 100, 20)]
    var area := Rect2(0, 0, 120, 200)
    assert_eq(SaLayerList.nearest_row(rects, 2, area, Vector2(50, 70)), 1, "a point on a row is that row")
    assert_eq(SaLayerList.nearest_row(rects, 2, area, Vector2(50, 10)), 0, "above the first row is the first")
    assert_eq(SaLayerList.nearest_row(rects, 1, area, Vector2(50, 180)), 1, "below the last is the bottom of the stack")
    assert_eq(SaLayerList.nearest_row(rects, 2, area, Vector2(50, 60.5)), 0, "between two rows, the upper edge when it is nearer")
    assert_eq(SaLayerList.nearest_row(rects, 2, area, Vector2(50, 61.5)), 1, "and the lower when that one is")
    assert_eq(SaLayerList.nearest_row(rects, 2, area, Vector2(110, 50)), 0, "beside the rows is the row at that height")
    assert_eq(SaLayerList.nearest_row(rects, 2, area, Vector2(50, 220)), -1, "outside the docker is nothing")
    assert_eq(SaLayerList.nearest_row(rects, 2, area, Vector2(-5, 50)), -1, "on either side of it too")
    var none: Array[Rect2] = []
    assert_eq(SaLayerList.nearest_row(none, -1, area, Vector2(50, 50)), -1, "and a list with no rows has nowhere to put anything")


## Below the last row is the bottom of the stack, and the last row can be a
## member of an open group, where a drop below it would stay inside the group.
func test_the_bottom_of_the_stack_is_the_last_row_outside_every_group() -> void:
    var easel := _easel()
    var doc := easel.document
    var under: Array[SaLayer] = []
    for child in doc.get_children():
        if child is SaLayer:
            under.append(child)
    SaLayerOps.new(doc).add().name = "Top"
    var group := SaLayerOps.new(doc).group_layers(under)
    var docker := _docker(easel)
    var rows := docker.item_list

    var last: SaLayer = rows.layer_at(rows.row_count() - 1)
    assert_eq(SaLayerStack.parent_of(last), group, "the last row drawn is a member of the open group")
    assert_eq(rows.layer_at(rows._bottom_row()), group, "and the bottom of the stack is the group's own row")

    var canvas := docker.target_canvas
    docker.free()
    canvas.free()
    easel.free()


## One mouse button event at a point in the list's own space.
func _button(pressed: bool, at: Vector2) -> InputEventMouseButton:
    var ev := InputEventMouseButton.new()
    ev.button_index = MOUSE_BUTTON_LEFT
    ev.pressed = pressed
    ev.position = at
    ev.global_position = at
    return ev
