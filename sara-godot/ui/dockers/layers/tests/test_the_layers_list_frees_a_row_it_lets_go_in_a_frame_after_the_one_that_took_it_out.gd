## The rows the Layers list lets go are taken out of it in the call and freed
## a few at a time in the frames after, so a list that lets go of hundreds,
## a large test document's 756 on an open of another, holds no frame for the lot.
## A trace of that open had the rows' freeing in
## a frame of 0.1 s. A list outside the tree frees its rows at the frame's end,
## as before, since it has no frames of its own to spread them over.
extends "res://tests/test_framework.gd"

var _nodes: Array[Node] = []


func after_each() -> void:
    for node in _nodes:
        if is_instance_valid(node):
            node.free()
    _nodes.clear()


func test_a_list_in_the_tree_takes_a_row_out_at_once_and_frees_it_in_a_frame_after() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var list := SaLayerList.new()
    _nodes.append(list)
    tree.root.add_child(list)
    var row := Control.new()
    list.add_child(row)
    SaLayerRowReuse.let_go(list, row)
    assert_null(row.get_parent(), "The row is out of the list in the call")
    assert_true(is_instance_valid(row), "and not yet freed")
    for _i in 3:
        await tree.process_frame
    assert_false(is_instance_valid(row), "A frame after frees it")
    tree.root.remove_child(list)


func test_a_list_outside_the_tree_frees_its_row_at_the_frame_s_end() -> void:
    var list := SaLayerList.new()
    _nodes.append(list)
    var row := Control.new()
    list.add_child(row)
    SaLayerRowReuse.let_go(list, row)
    assert_null(row.get_parent(), "The row is out of the list in the call")
    await (Engine.get_main_loop() as SceneTree).process_frame
    assert_false(is_instance_valid(row), "and freed at the frame's end, as before")
