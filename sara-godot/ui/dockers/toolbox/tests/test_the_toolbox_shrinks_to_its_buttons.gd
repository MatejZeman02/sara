## The Toolbox shrinks to its buttons with no spare space at its edges.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A one-column Toolbox once refused to shrink further and left spare space at
## the edges. This suite floats a one-column Toolbox, drags it to its smallest at
## each button size and reads what it came out at.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript := preload("res://ui/dockers/toolbox/toolbox_docker.gd")

var _host: Node = null
var _docker: ToolBoxDocker = null
var _kept_embedding: bool = true


func before_each() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U850Host"
    EventBus.add_child(_host)
    _docker = ToolBoxDockerScript.new() as ToolBoxDocker
    _docker.name = "ToolBoxDocker"
    _host.add_child(_docker)
    _docker.rebuild_from_registry(Fixtures.make_tool_registry())
    await _frames(2)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    _docker = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    SaToolBoxSize.shown_size = SaToolBoxSize.DEFAULT_SIZE


func _frames(count: int) -> void:
    for i in count:
        await (Engine.get_main_loop() as SceneTree).process_frame


func _shrink() -> void:
    _docker.size = Vector2i(1, 1)
    await _frames(3)
    _docker.size = Vector2i(1, 1)
    await _frames(3)


## The margin the grid sits in, either side and above and below.
const MARGIN := 2


func _gap() -> float:
    return float(_docker.grid_container.get_theme_constant(&"v_separation"))


func _bar() -> float:
    return _docker.drag_handle.get_combined_minimum_size().y


## How many whole rows *height* holds under the bar and the margins, or -1 when
## it holds a part of one.
func _whole_rows(height: float, button: float) -> int:
    var rows := (height - _bar() - MARGIN * 2 + _gap()) / (button + _gap())
    return roundi(rows) if is_equal_approx(rows, roundf(rows)) else -1


## What held each axis, printed for the table in the plan's Done paragraph.
func _say(step: int) -> void:
    var row := _docker.drag_handle.get_node("DragBarRow") as Control
    var shown := []
    for child in row.get_children():
        if child is Control and (child as Control).visible:
            shown.append(String(child.name))
    var scroll := _docker.get_node("Control/VBoxContainer/Scroll") as ScrollContainer
    print(
        (
            "%d px: docker %s, bar %s holding %s, scroll %s with its bar %s"
            % [
                step,
                _docker.size,
                _docker.drag_handle.get_combined_minimum_size(),
                shown,
                scroll.get_combined_minimum_size(),
                scroll.get_v_scroll_bar().visible
            ]
        )
    )


func test_the_smallest_one_column_toolbox_is_its_buttons_at_every_size() -> void:
    for step: int in SaToolBoxSize.STEPS:
        _docker.size_controller.show_size(step)
        await _frames(2)
        await _shrink()
        _say(step)
        var button := float(SaUI.px(step))
        assert_eq(_docker.grid_container.columns, 1, "%d px: the toolbox is one column" % step)
        assert_true(
            _docker.size.x <= button + MARGIN * 2,
            "%d px: the docker is %d wide, no wider than the button and its two margins" % [step, _docker.size.x]
        )
        assert_eq(
            _whole_rows(float(_docker.size.y), button),
            1,
            "%d px: the docker is %d tall, the bar, one whole row and the margins" % [step, _docker.size.y]
        )
        var scroll := _docker.get_node("Control/VBoxContainer/Scroll") as ScrollContainer
        assert_true(
            scroll.get_combined_minimum_size().x <= button + MARGIN * 2,
            "%d px: the scroll's bar takes no width beside a column that scrolls in a docker this narrow" % step
        )


## A grip let go of between two rows leaves the docker at the nearer whole row.
func test_a_grip_let_go_between_two_rows_snaps_to_a_whole_row() -> void:
    for step: int in [24, 40, 72]:
        _docker.size_controller.show_size(step)
        await _frames(2)
        await _shrink()
        var button := float(SaUI.px(step))
        var start := Vector2(_docker.position + _docker.size) - Vector2(4, 4)
        # Three rows and a little under half of the fourth.
        var by := Vector2(0.0, 2.0 * (button + _gap()) + 0.4 * (button + _gap()))
        _docker.resizer.capture_drag(start, by)
        await _frames(2)
        assert_eq(
            _whole_rows(float(_docker.size.y), button),
            3,
            "%d px: let go at %d tall, the docker is %d, three whole rows" % [step, int(start.y + by.y), _docker.size.y]
        )
        var further := Vector2(0.0, 0.7 * (button + _gap()))
        _docker.resizer.capture_drag(Vector2(_docker.position + _docker.size) - Vector2(4, 4), further)
        await _frames(2)
        assert_eq(
            _whole_rows(float(_docker.size.y), button), 4, "%d px: past half of the next row, it takes that row whole" % step
        )
        assert_true(_docker.size.x <= button + MARGIN * 2, "%d px: and the width stays the buttons'" % step)


## The bar's narrow form keeps the window buttons a press away, in the menu a
## right press on the wrench opens.
func test_the_narrow_bar_offers_its_folded_buttons_in_the_wrench_s_menu() -> void:
    _docker.size_controller.show_size(24)
    await _frames(2)
    await _shrink()
    assert_false(_docker.hide_button.visible, "the close is folded off a bar 28 wide")
    var menu := _docker.size_controller.fill_menu()
    var row := StringName(SaToolBoxSize.WINDOW_ROW + String(_docker.hide_button.name))
    assert_true(menu.row_ids().has(row), "and the wrench's menu offers it")
    var closed := [false]
    _docker.close_requested.connect(func() -> void: closed[0] = true)
    _docker.size_controller._on_row_chosen(row)
    assert_true(closed[0], "and choosing the row does what the close does")

    _docker.size = Vector2i(120, _docker.size.y)
    await _frames(2)
    assert_true(_docker.hide_button.visible, "a docker wide enough draws the close on its bar again")
    assert_false(_docker.size_controller.fill_menu().row_ids().has(row), "and the menu no longer offers it")
