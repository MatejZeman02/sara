## Picking several layers at once.
##
## Several layers can be selected to create a group from.
## The document still has exactly one active layer, so nothing under the UI
## changed shape: the docker keeps the set, and the actions read it.
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


func _list() -> SaLayerList:
    var list := SaLayerList.new()
    for name: String in ["Top", "Middle", "Bottom"]:
        list.add_item(name)
    return list


func _press(ctrl: bool = false, shift: bool = false) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.ctrl_pressed = ctrl
    event.shift_pressed = shift
    return event


## Ctrl adds a row and takes it away again, Shift takes the whole run, and a
## plain press is the one row it always was.
func test_ctrl_adds_a_row_and_shift_takes_the_run() -> void:
    var list := _list()

    list._on_row_gui_input(_press(), 0)
    assert_eq(list.picked.selected_indices(), [0], "a plain press picks one row")

    list._on_row_gui_input(_press(true), 2)
    assert_eq(list.picked.selected_indices(), [0, 2], "Ctrl adds the second")

    list._on_row_gui_input(_press(true), 2)
    assert_eq(list.picked.selected_indices(), [0], "and Ctrl on it again takes it away")

    list._on_row_gui_input(_press(), 0)
    list._on_row_gui_input(_press(false, true), 2)
    assert_eq(list.picked.selected_indices(), [0, 1, 2], "Shift takes everything to the row pressed")

    list._on_row_gui_input(_press(), 1)
    assert_eq(list.picked.selected_indices(), [0, 1, 2], "a plain press on a picked row keeps the set for a drag")
    list.drop()
    assert_eq(list.picked.selected_indices(), [1], "and its release with no drag starts again")
    list.free()


## A second shift click ranges from the row the first click landed on, not
## from the row the shift click before it landed on.
##
## The range is based on the one active layer, not on the last one selected.
func test_a_second_shift_click_still_ranges_from_the_first_click() -> void:
    var list := _list()
    for name: String in ["Fourth", "Fifth"]:
        list.add_item(name)

    list._on_row_gui_input(_press(), 4)
    assert_eq(list.picked.selected_indices(), [4], "the plain click picks the base")

    list._on_row_gui_input(_press(false, true), 1)
    assert_eq(list.picked.selected_indices(), [1, 2, 3, 4], "the first shift click takes the run to it")

    list._on_row_gui_input(_press(false, true), 2)
    assert_eq(list.picked.selected_indices(), [2, 3, 4], "and the second ranges from row 4 again, not from row 1")

    list._on_row_gui_input(_press(false, true), 0)
    assert_eq(list.picked.selected_indices(), [0, 1, 2, 3, 4], "however far it goes the other way")
    list.free()


## A shift click does not move
## the active mark, which would reach the document, rebuild
## the docker, and `select_layers` would put the anchor on whatever was active by
## then, which is the row just clicked.
func test_a_shift_click_leaves_the_active_row_alone() -> void:
    var list := _list()

    list._on_row_gui_input(_press(), 0)
    assert_eq(list.picked.selected_idx, 0, "the plain click is the active row")

    list._on_row_gui_input(_press(false, true), 2)
    assert_eq(list.picked.selected_idx, 0, "and a shift click adds rows without taking the mark")
    assert_eq(list.picked.selected_indices(), [0, 1, 2], "the run is there all the same")

    # The rebuild the docker runs after every selection change, by layer rather
    # than by index. It re-derives the anchor from the active row, which is the
    # loop the old behaviour closed the wrong way round.
    list.select_layers([], null)
    list._on_row_gui_input(_press(), 0)
    list._on_row_gui_input(_press(false, true), 2)
    list._on_row_gui_input(_press(false, true), 1)
    assert_eq(list.picked.selected_indices(), [0, 1], "the base survives a rebuild between clicks")
    list.free()


## The signal carries the row the list made active, not the row under the
## pointer. The docker sets the document's active layer from it, so the two
## disagreeing is how the active mark moved on a shift click at all.
func test_the_signal_names_the_active_row_not_the_clicked_one() -> void:
    var list := _list()
    var announced: Array[int] = []
    list.item_selected.connect(func(index: int) -> void: announced.append(index))

    list._on_row_gui_input(_press(), 0)
    list._on_row_gui_input(_press(false, true), 2)
    assert_eq(announced, [0, 0], "the shift click announces the base, not row 2")

    # Ctrl on the active row of a set of two hands the mark to what is left, and
    # the signal has to say so or the document keeps the row just dropped.
    list._on_row_gui_input(_press(), 0)
    list.drop()
    list._on_row_gui_input(_press(true), 2)
    list._on_row_gui_input(_press(true), 2)
    assert_eq(announced[-1], 0, "and a Ctrl click that removes the active row names its replacement")
    list.free()


## A set of one behaves exactly the way the active layer did, so every action
## that reads `active_layer` reads the set without a branch.
func test_a_set_of_one_is_the_active_row() -> void:
    var list := _list()
    list.picked.select(1)
    assert_eq(list.picked.selected_indices(), [1], "one row")
    list.free()


func _docker(easel: SaEasel) -> LayersDocker:
    var canvas := SaCanvas.new()
    canvas.easel = easel
    var docker := LayersDocker.new()
    docker.target_canvas = canvas
    docker.sync_layer_list()
    return docker


func _row_of(docker: LayersDocker, layer: SaLayer) -> int:
    for i: int in docker.item_list.row_count():
        if docker.item_list.layer_at(i) == layer:
            return i
    return -1


## The case that matters: two picked rows become one group holding both, and
## undo puts them back where they were.
func test_two_picked_layers_become_one_group_and_undo_puts_them_back() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.active_layer.name = "Lower"
    var upper := SaLayerOps.new(doc).add()
    upper.name = "Upper"
    var lower := doc.get_node_or_null("Lower") as SaLayer
    var docker := _docker(easel)

    docker.item_list.picked.select(_row_of(docker, upper))
    docker.item_list.picked.select_extra(_row_of(docker, lower))
    assert_eq(docker.item_list.selected_layers().size(), 2, "two rows are picked")

    docker.actions.toggle_group()

    var group := SaLayerStack.parent_of(upper)
    assert_not_null(group, "the upper layer is inside a group")
    assert_true(group.is_group, "which is a group")
    assert_eq(SaLayerStack.parent_of(lower), group, "and the lower one is inside the same group")

    doc.undo()
    assert_null(SaLayerStack.parent_of(upper), "undo takes the upper layer back out")
    assert_null(SaLayerStack.parent_of(lower), "and the lower one with it")
    assert_true(upper.get_index() > lower.get_index(), "in the order they were in")

    var canvas := docker.target_canvas
    docker.free()
    canvas.free()
    easel.free()


## Delete acts on the set, which is the point of having one.
func test_delete_removes_every_picked_layer() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.active_layer.name = "Keep"
    SaLayerOps.new(doc).add().name = "Drop A"
    SaLayerOps.new(doc).add().name = "Drop B"
    var docker := _docker(easel)

    var a := doc.get_node_or_null("Drop A") as SaLayer
    var b := doc.get_node_or_null("Drop B") as SaLayer
    docker.item_list.picked.select(_row_of(docker, a))
    docker.item_list.picked.select_extra(_row_of(docker, b))
    docker.actions.delete_layer()

    assert_null(doc.get_node_or_null("Drop A"), "the first picked layer is gone")
    assert_null(doc.get_node_or_null("Drop B"), "and the second")
    assert_not_null(doc.get_node_or_null("Keep"), "and the one nobody picked stays")

    var canvas := docker.target_canvas
    docker.free()
    canvas.free()
    easel.free()


## The eye takes the whole set to the state the row it belongs to is going to,
## rather than flipping each, or a mixed set only ever gets more mixed.
func test_the_eye_takes_the_whole_set_to_one_state() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.active_layer.name = "One"
    SaLayerOps.new(doc).add().name = "Two"
    var docker := _docker(easel)
    var one := doc.get_node_or_null("One") as SaLayer
    var two := doc.get_node_or_null("Two") as SaLayer
    SaLayerOps.new(doc).set_visible(two, false)

    var row_one := _row_of(docker, one)
    docker.item_list.picked.select(row_one)
    docker.item_list.picked.select_extra(_row_of(docker, two))
    docker.item_list._on_eye_pressed(row_one)

    assert_false(one.visible, "the row the eye belongs to is hidden")
    assert_false(two.visible, "and the rest of the set followed it rather than flipping")

    var canvas := docker.target_canvas
    docker.free()
    canvas.free()
    easel.free()


## A rebuild that replaced what was picked collapses the set to the active row.
## Keeping the old set and adding the new active layer to it made Duplicate
## duplicate twice, then three times, and Delete take the document apart.
func test_a_rebuild_that_replaced_the_set_collapses_it() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.active_layer.name = "Only"
    var docker := _docker(easel)
    var before := doc.get_child_count()

    docker.actions.duplicate_layer()
    assert_eq(doc.get_child_count(), before + 1, "one press, one copy")
    docker.actions.duplicate_layer()
    assert_eq(doc.get_child_count(), before + 2, "and the second press makes one more, not two")

    var canvas := docker.target_canvas
    docker.free()
    canvas.free()
    easel.free()


## A selection with a gap in it collects at the topmost row's place, and the
## members sit together under the group. Leaving them where they were drew the
## group's header between its own two members, because the docker builds one
## row per child in the document's order and indents by depth.
func test_a_gapped_selection_collects_at_the_topmost_place() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.active_layer.name = "A"
    SaLayerOps.new(doc).add().name = "B"
    SaLayerOps.new(doc).add().name = "C"
    var docker := _docker(easel)
    var a := doc.get_node_or_null("A") as SaLayer
    var b := doc.get_node_or_null("B") as SaLayer
    var c := doc.get_node_or_null("C") as SaLayer

    docker.item_list.picked.select(_row_of(docker, c))
    docker.item_list.picked.select_extra(_row_of(docker, a))
    docker.actions.toggle_group()

    var group := SaLayerStack.parent_of(a)
    assert_not_null(group, "the bottom layer is inside the new group")
    assert_eq(SaLayerStack.parent_of(c), group, "and the top one with it")
    assert_null(SaLayerStack.parent_of(b), "the layer in the gap is not a member")
    assert_true(group.get_index() > b.get_index(), "and the group sits above it")
    assert_eq(c.get_index(), group.get_index() - 1, "the upper member sits straight under the group")
    assert_eq(a.get_index(), group.get_index() - 2, "and the lower one under that, in their own order")

    doc.undo()
    assert_true(a.get_index() < b.get_index(), "undo puts the bottom layer back under the one in the gap")
    assert_true(b.get_index() < c.get_index(), "and the top one back above it")

    var canvas := docker.target_canvas
    docker.free()
    canvas.free()
    easel.free()


func _order(doc: SaDocument) -> Array[String]:
    var out: Array[String] = []
    for layer in SaLayerOps.new(doc).layers():
        out.append(str(layer.name))
    return out


## The up and down buttons carry a group's whole block, and the group's own
## row stays on top of it. The buttons count from the bottom of the block for
## that reason: the group's index is the top of it, not the place it starts.
func test_the_buttons_move_a_group_with_everything_inside_it() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.active_layer.name = "Wrapped"
    SaLayerOps.new(doc).add().name = "Above"
    var docker := _docker(easel)
    var wrapped := doc.get_node_or_null("Wrapped") as SaLayer

    docker.item_list.picked.select(_row_of(docker, wrapped))
    docker.actions.toggle_group()
    assert_eq(_order(doc), ["Background", "Wrapped", "Group 1", "Above"], "the group closes over its one member")

    docker.actions.move_layer(1)
    assert_eq(_order(doc), ["Background", "Above", "Wrapped", "Group 1"], "up takes the member with it")
    docker.actions.move_layer(-1)
    assert_eq(_order(doc), ["Background", "Wrapped", "Group 1", "Above"], "and down puts the block back")

    var canvas := docker.target_canvas
    docker.free()
    canvas.free()
    easel.free()
