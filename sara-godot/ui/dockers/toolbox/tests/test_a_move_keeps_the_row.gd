## A move on a row-shaped toolbox leaves a column per button, each as wide as
## before and each under its category's name.
##
## The claim, from a scenario: the maximised toolbox read
## `columns` 5 and five buttons 304 wide before lasso moved inside the Select
## group, and `columns` 10 and five buttons 152 wide after, the first of them
## named `@Button@657` rather than `PaintBtn`. The rebuild a move sets off freed
## the old buttons with `queue_free`, which leaves them in the grid until the
## frame ends, so the count `_apply_orientation` took was the old five and the
## new five, and a new button handed its category's name found the old one still
## holding it and was renamed by the engine.
##
## In the tree and embedded, the way `test_flyout_on_a_maximised_toolbox`
## hosts its window, because a `GridContainer` outside the tree sorts nothing and
## every button kept its minimum width whatever the columns said. The whole suite
## runs inside one frame, so a button `queue_free` left behind is still in the
## grid when the assertions read it, which is the frame the grid was counted in.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Wide and short, so the shape the toolbox follows is a row.
const ROW_SIZE := Vector2i(1400, 120)
## The width the layout pass below hands the grid.
const GRID_WIDTH := 1300.0

var _order: Array = []
var _groups_raw: Variant = null
var _orientation_raw: Variant = null
var _saved_override: float = -1.0
var _saved_user: float = 1.0
var _was_embedding: bool = false
var _host: Node = null


func before_each() -> void:
    _order = SaSettings.get_layout_order(SaToolBoxGrid.CATEGORY)
    _groups_raw = SaSettings.get_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGroups.GROUPS_KEY)
    _orientation_raw = SaSettings.get_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGrid.ORIENTATION)
    SaSettings.set_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGrid.ORIENTATION, SaToolBoxGrid.FOLLOW_SHAPE)
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true


## A move writes the profile, so every case puts the order, the groups and the
## orientation back where it found them, and the scale and the embedding too.
func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user
    SaSettings.set_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGrid.ORIENTATION, _orientation_raw)
    SaSettings.set_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGroups.GROUPS_KEY, _groups_raw)
    SaSettings.set_layout_order(SaToolBoxGrid.CATEGORY, _order)


func _row_toolbox() -> ToolBoxDocker:
    _host = Node.new()
    _host.name = "D70Host"
    EventBus.add_child(_host)
    var docker := ToolBoxDocker.new()
    _host.add_child(docker)
    # A docker is built hidden, and a grid in a hidden window sorts none of its
    # buttons, so they all sat at forty whatever the columns said.
    docker.visible = true
    docker.size = ROW_SIZE
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    return docker


## The buttons a painter can see, which leaves out any the rebuild has already
## given up on, so a stale one cannot stand in for the new one it shadows.
func _live_buttons(docker: ToolBoxDocker) -> Array[Control]:
    var out: Array[Control] = []
    for child in docker.grid_container.get_children():
        if child is Control and (child as Control).visible and not child.is_queued_for_deletion():
            out.append(child as Control)
    return out


## The widths the grid gives those buttons at `GRID_WIDTH`, laid out now because
## the runner is synchronous and a frame's layout pass never comes.
func _button_widths(docker: ToolBoxDocker) -> Array:
    var grid := docker.grid_container
    grid.size = Vector2(GRID_WIDTH, grid.size.y)
    grid.notification(Container.NOTIFICATION_SORT_CHILDREN)
    var widths: Array = []
    for button: Control in _live_buttons(docker):
        widths.append(button.size.x)
    return widths


func _button_names(docker: ToolBoxDocker) -> Array:
    var names: Array = []
    for button: Control in _live_buttons(docker):
        names.append(String(button.name))
    return names


func _first_group_of_several(groups: Array) -> int:
    for i in groups.size():
        if (groups[i] as Array).size() > 1:
            return i
    return -1


func test_a_move_inside_a_group_keeps_a_column_per_button() -> void:
    var docker := _row_toolbox()
    var before: Dictionary = docker.toolbox_report()
    assert_eq(before["shape"], "row", "a docker wider than it is tall and wide enough for every button is a row")
    assert_eq(before["columns"], before["visible_buttons"], "a column per button before the move")
    var widths_before := _button_widths(docker)
    var names_before := _button_names(docker)
    assert_true(
        float(widths_before[0]) > float(SaUI.BASE_TOOL_BTN), "the buttons stretch across the row, so a halved column shows"
    )

    var groups: Array = before["groups"]
    var index := _first_group_of_several(groups)
    assert_true(index >= 0, "the fixture registry has a group with more than one tool")
    var group: Array = groups[index]
    assert_true(docker.move_tool(String(group[0]), index, group.size(), false), "the first tool of the group moves to its end")
    assert_false(docker.toolbox_report()["groups"] == groups, "the move changed the order, so the buttons were built again")

    assert_eq(
        docker.grid_container.columns,
        before["visible_buttons"],
        "the rebuilt row has a column per button, not one for each old button as well"
    )
    assert_eq(
        docker.grid_container.get_child_count(),
        before["visible_buttons"],
        "the grid holds the new buttons only, the old ones are out of it before the frame ends"
    )
    assert_eq(_button_widths(docker), widths_before, "each button is as wide as before the move")
    assert_eq(_button_names(docker), names_before, "each new button carries its category's name, so a capture still finds it")
