## Duplicate, Group, Merge Down and Add Mask stand on the Layers docker's action
## row as buttons, between minus and More.
##
## The More menu had grown to seventeen rows and scrolled under its 520 pixel
## cap, so its last mask rows were read as running off the window, and its order
## was not the Layer menu's. What this suite holds is that the
## four are buttons with their command's chord and sentence on hover, dimmed
## where the command cannot act, one history step a press, folded back into the
## menu from the right on a narrow row. That the menu keeps the Layer menu's
## order and words is `test_the_layer_menu_and_the_more_menu_read_one_list.gd`'s.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document the docker shows.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const FOUR: Array[SaLayerActions.Item] = [
    SaLayerActions.Item.DUPLICATE, SaLayerActions.Item.GROUP, SaLayerActions.Item.MERGE_DOWN, SaLayerActions.Item.MASK_ADD
]

## The node the floor case hangs its row from, freed after every case.
var _host: Node = null


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func _canvas() -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    return canvas


func _docker() -> LayersDocker:
    var canvas := _canvas()
    var docker: LayersDocker = LayersDockerScript.new()
    docker.name = "LayersDocker"
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()
    return docker


## A row of its own in the tree, on *canvas*'s document. In the tree because a
## container lays out only the children that are visible in it, so a docker
## built beside the tree sorts nothing.
func _row_in_tree(canvas: SaCanvas) -> SaLayerActions:
    _host = Control.new()
    _host.name = "OpButtonsHost"
    EventBus.add_child(_host)
    var actions := SaLayerActions.new(null)
    actions.target_canvas = canvas
    _host.add_child(actions)
    return actions


## The row laid out *width* wide, the way the docker's column would lay it out,
## and the four laid out in what it left them.
func _lay_out(actions: SaLayerActions, width: float) -> void:
    actions.size = Vector2(width, float(SaUI.px(SaUI.BASE_BTN_H)))
    actions.notification(Container.NOTIFICATION_SORT_CHILDREN)
    actions.op_buttons.notification(Container.NOTIFICATION_SORT_CHILDREN)


func test_the_four_stand_between_minus_and_more_with_their_chords() -> void:
    var docker := _docker()
    var actions := docker.actions
    var registry: SaCommandRegistry = Fixtures.make_registries().commands
    actions.op_buttons.commands = registry
    actions.sync_buttons()

    var standing := actions.op_buttons.get_children()
    assert_eq(standing.size(), 4, "four buttons in the stretch")
    for index in SaLayerOpButtons.ENTRIES.size():
        var entry: Array = SaLayerOpButtons.ENTRIES[index]
        var btn := actions.op_buttons.button(entry[0])
        assert_true(btn == standing[index], "%s stands %d from the left" % [entry[0], index])
        assert_not_null(btn.icon, "%s draws an icon" % entry[0])
        var chord := registry.chord_text(entry[1], 1)
        assert_false(chord.is_empty(), "%s's command answers to a chord" % entry[1])
        assert_true(btn.tooltip_text.contains("(%s)" % chord), "%s's hover names %s: %s" % [entry[0], chord, btn.tooltip_text])
        var sentence := registry.get_descriptor(entry[1]).sentence
        assert_true(btn.tooltip_text.contains(sentence), "and says the command's sentence: %s" % btn.tooltip_text)
    assert_true(
        actions.op_buttons.button(&"layer_duplicate").tooltip_text.begins_with("Duplicate Layer (Ctrl+Alt+J)"),
        "Ctrl+Alt+J duplicates"
    )
    docker.target_canvas.free()


## Merge Down on the bottom layer and Add Mask on a layer that has one, the two
## the note named, and a dimmed button refuses a press the way a dimmed row does.
func test_each_is_dimmed_where_its_command_cannot_act() -> void:
    var docker := _docker()
    var actions := docker.actions
    var doc := docker.target_canvas.document
    actions.sync_buttons()
    for item: SaLayerActions.Item in FOUR:
        assert_false(actions.on_row(item).disabled, "%s is live on the top layer" % actions.row_id_of(item))

    var ops := SaLayerOps.new(doc)
    doc.set_active_layer(ops.layers()[0])
    actions.sync_buttons()
    assert_true(actions.on_row(SaLayerActions.Item.MERGE_DOWN).disabled, "Merge Down is dimmed on the bottom layer")
    var steps := doc.history.step_count()
    assert_false(actions.press_item(SaLayerActions.Item.MERGE_DOWN), "and refuses a press")
    assert_eq(doc.history.step_count(), steps, "which commits nothing")

    doc.set_active_layer(ops.layers()[-1])
    assert_true(actions.press_item(SaLayerActions.Item.MASK_ADD), "Add Mask gives the top layer a mask")
    actions.sync_buttons()
    assert_true(actions.on_row(SaLayerActions.Item.MASK_ADD).disabled, "and is dimmed on a layer that has one")
    assert_false(actions.press_item(SaLayerActions.Item.MASK_ADD), "which refuses a second")
    docker.target_canvas.free()


## A press on each of the four is its command, one step, from the button and
## not from a row.
func test_each_press_is_one_history_step() -> void:
    var docker := _docker()
    var actions := docker.actions
    var doc := docker.target_canvas.document
    for item: SaLayerActions.Item in [
        SaLayerActions.Item.DUPLICATE, SaLayerActions.Item.MERGE_DOWN, SaLayerActions.Item.GROUP, SaLayerActions.Item.MASK_ADD
    ]:
        assert_not_null(actions.on_row(item), "%s is a button on the row" % actions.row_id_of(item))
        var steps := doc.history.step_count()
        assert_true(actions.press_item(item), "%s takes the press" % actions.row_id_of(item))
        assert_eq(doc.history.step_count(), steps + 1, "%s is one step" % actions.row_id_of(item))
    assert_true(doc.active_layer.is_group, "Group left the new group active")
    assert_not_null(doc.active_layer.mask, "and Add Mask masked it")
    docker.target_canvas.free()


## At the docker's floor of 200 pixels, less the column's margins, the row
## keeps plus, the arrow, minus and More whole and folds the four from the
## right into what is left, rather than pushing More off the edge.
func test_the_floor_width_folds_them_from_the_right_and_keeps_more_whole() -> void:
    var canvas := _canvas()
    var actions := _row_in_tree(canvas)
    var width := float(200 - 2 * SaUI.px(SaUI.BASE_MARGIN))
    _lay_out(actions, width)

    var shown := actions.op_buttons.shown
    assert_true(shown > 0 and shown < 4, "some of the four fold at the floor, %d stand" % shown)
    assert_true(
        actions.more_btn.get_rect().end.x <= width, "More ends inside the row at %.0f" % actions.more_btn.get_rect().end.x
    )
    for index in FOUR.size():
        var btn := actions.op_buttons.button(actions.row_id_of(FOUR[index]))
        assert_eq(btn.visible, index < shown, "%s %s" % [btn.name, "stands" if index < shown else "is folded"])
    var last := actions.op_buttons.button(actions.row_id_of(FOUR[shown - 1]))
    assert_true(
        actions.op_buttons.position.x + last.get_rect().end.x <= actions.more_btn.position.x,
        "and the last one standing ends before More begins"
    )

    actions.sync_from_active_layer()
    var titles := Array(actions.menu_titles())
    for index in FOUR.size():
        var item := FOUR[index]
        assert_eq(actions.on_row(item) == null, index >= shown, "%s is on the row or in the menu" % actions.row_id_of(item))
        assert_eq(actions.menu.row_ids().has(actions.row_id_of(item)), index >= shown, "and in the menu only when folded")
    assert_true(titles.has("Add Mask"), "Add Mask, the rightmost, folds first")

    var doc := canvas.document
    var steps := doc.history.step_count()
    assert_true(actions.press_item(SaLayerActions.Item.MASK_ADD), "a folded one presses from its row")
    assert_eq(doc.history.step_count(), steps + 1, "as one step")

    _lay_out(actions, 600.0)
    assert_eq(actions.op_buttons.shown, 4, "a wide row stands all four again")
    assert_true(actions.op_buttons.button(&"layer_mask_add").visible, "and shows the one that folded")
    canvas.free()
