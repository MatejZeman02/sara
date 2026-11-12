## The tip grid scrolls in a frame of its own once the tips outgrow
## it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The user list of brush tips can get long over time, so it needs a scroll bar.
## A folder held 37 tips, the grid stood five rows tall and every tip added pushed Load Tip
## and the rows under it further down the docker. The requirement, a clause a test:
## the grid over 200 listed tips is as tall as over the frame's rows plus one,
## over 3 tips it is no taller than a row, and the cell the row holds is inside
## the frame's visible rectangle when it is the last of the 200.
##
## The grid is handed its tips through its listing argument, because the folders
## a suite may write are not 200 pictures wide, and laid out by hand, the way
## `test_a_wheel_over_the_volume_scrolls_the_page.gd` does, because a suite
## cannot await the frame that would lay it out.
extends "res://tests/test_framework.gd"

## Six cells across at the default scale, with a few pixels over that do not make
## a seventh.
const WIDTH := 270.0

var _host: Node = null
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


## *count* tips, `tip_000` to the last, across the folders named in *folders*
## in turn, none of them a file on disk, so every cell is the unreadable mark.
func _tips(count: int, folders: Array[String] = ["res://scratch_a"]) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for index in count:
        var folder := folders[index % folders.size()]
        var path := folder.path_join("tip_%03d.png" % index)
        out.append({"path": path, "label": "Tip %03d" % index, "folder": folder})
    return out


## A grid over *tips* holding *held*, in a window of *width* and laid out.
func _grid(tips: Array[Dictionary], held: String = "", width: float = WIDTH) -> SaTipGrid:
    if _host == null:
        _host = Node.new()
        _host.name = "TipGridHost"
        EventBus.add_child(_host)
    var window := Window.new()
    window.size = Vector2i(int(width) + 40, 600)
    _host.add_child(window)
    var grid := SaTipGrid.new(Callable(), func(_held: String) -> Array[Dictionary]: return tips)
    window.add_child(grid)
    grid.follow(null, func() -> String: return held)
    _lay_out(grid, width)
    return grid


func _lay_out(grid: SaTipGrid, width: float) -> void:
    grid.size = Vector2(width, 0.0)
    for _pass in 4:
        _sort(grid)


func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort(child)
    if node is Control:
        (node as Control).update_minimum_size()


## The height the grid asks of what it stands in.
func _height(grid: SaTipGrid) -> float:
    return grid.get_combined_minimum_size().y


## How many rows the flow really laid *grid*'s shown cells in, by the distinct
## tops they stand at.
func _laid_rows(grid: SaTipGrid) -> int:
    var tops: Dictionary[int, bool] = {}
    for path: String in grid.shown_paths():
        tops[roundi((grid.cells.get_node(NodePath("Cell_" + path.get_file().validate_node_name())) as Control).position.y)] = true
    return tops.size()


func _across() -> int:
    var gap := SaUI.px(4)
    return floori((WIDTH + gap) / float(SaUI.px(SaTipGrid.CELL) + gap))


## The first clause: 200 tips stand as tall as the frame's rows and one more.
func test_two_hundred_tips_are_as_tall_as_the_frames_rows_plus_one() -> void:
    var across := _across()
    assert_eq(across, SaTipGrid.ACROSS, "the suite's width holds the six the grid assumes before it has a width")
    var long := _grid(_tips(200))
    var one_over := _grid(_tips(across * (SaTipGrid.FRAME_ROWS + 1)))
    var exactly := _grid(_tips(across * SaTipGrid.FRAME_ROWS))
    var under := _grid(_tips(across * (SaTipGrid.FRAME_ROWS - 1)))
    assert_eq(_height(long), _height(one_over), "200 tips ask what the frame's rows plus one ask")
    assert_eq(_height(long), _height(exactly), "which is what the frame's own rows ask")
    assert_true(_height(under) < _height(long), "and a row fewer asks less, %s against %s" % [_height(under), _height(long)])
    var same: bool = long.tip_grid_report()["frame_height"] == exactly.tip_grid_report()["frame_height"]
    assert_true(same, "the frame is the same height for both")
    var rows_px := SaTipGrid.FRAME_ROWS * SaUI.px(SaTipGrid.CELL) + (SaTipGrid.FRAME_ROWS - 1) * SaUI.px(4)
    assert_eq(long.frame.size.y, float(rows_px), "and as laid out the frame is the frame's rows of cells tall, %d" % rows_px)


## The flow's own wrapping is what the frame's rows are worked out against.
func test_the_frames_rows_are_the_rows_the_flow_lays() -> void:
    for width: float in [130.0, 270.0, 400.0]:
        for count: int in [1, 5, 13, 40]:
            var grid := _grid(_tips(count), "", width)
            var laid := _laid_rows(grid)
            var rows := mini(laid, SaTipGrid.FRAME_ROWS)
            var side := SaUI.px(SaTipGrid.CELL)
            var expected := float(rows * side + (rows - 1) * SaUI.px(4))
            var said := "%d tips at %d wide lay %d rows and the frame shows %d" % [count, int(width), laid, rows]
            assert_eq(grid.frame.size.y, expected, said)


## Three tips are a row, and the frame is no taller than one.
func test_three_tips_leave_the_frame_one_row_tall() -> void:
    var grid := _grid(_tips(3))
    var side := float(SaUI.px(SaTipGrid.CELL))
    assert_true(grid.frame.size.y <= side, "The frame is no taller than a cell, %s" % grid.frame.size.y)
    assert_eq(_laid_rows(grid), 1, "for the one row the three tips lay")
    assert_false(grid.frame.get_v_scroll_bar().visible, "and has no scroll bar")


## Past the frame's rows the bar shows, and exactly at them it does not.
func test_the_scroll_bar_shows_only_once_the_tips_outgrow_the_frame() -> void:
    var across := _across()
    var exactly := _grid(_tips(across * SaTipGrid.FRAME_ROWS))
    assert_false(exactly.frame.get_v_scroll_bar().visible, "The frame's rows full leave no bar")
    var over := _grid(_tips(across * SaTipGrid.FRAME_ROWS + 1))
    assert_true(over.frame.get_v_scroll_bar().visible, "and one tip more has one")


## The last of 200 held: its cell is inside the frame, and the frame scrolls back
## to the first when a preset holds that one.
func test_the_held_cell_is_scrolled_into_the_frame() -> void:
    var tips := _tips(200)
    var last := String(tips[199]["path"])
    var grid := _grid(tips, last)
    var cell := grid.cells.get_node(NodePath("Cell_" + last.get_file().validate_node_name())) as Control
    assert_true(grid.frame.scroll_vertical > 0, "The frame scrolled, %d" % grid.frame.scroll_vertical)
    var said := "The last tip's cell %s is inside the frame %s" % [cell.get_global_rect(), grid.frame.get_global_rect()]
    assert_true(grid.frame.get_global_rect().encloses(cell.get_global_rect()), said)

    var first := String(tips[0]["path"])
    grid.show_tip(first)
    _lay_out(grid, WIDTH)
    var top := grid.cells.get_node(NodePath("Cell_" + first.get_file().validate_node_name())) as Control
    assert_eq(grid.frame.scroll_vertical, 0, "A preset that holds the first tip scrolls back to it")
    assert_true(grid.frame.get_global_rect().encloses(top.get_global_rect()), "so its cell is inside the frame")


## A cell already in view is left where it is, so a press does not move the
## tips under the pointer, and a painter's own scroll survives a sync.
func test_a_press_and_a_sync_leave_the_scroll_alone() -> void:
    var tips := _tips(200)
    var grid := _grid(tips, String(tips[0]["path"]))
    grid.frame.scroll_vertical = 100
    _lay_out(grid, WIDTH)
    assert_eq(grid.frame.scroll_vertical, 100, "The painter scrolled the tips")
    grid.relist()
    _lay_out(grid, WIDTH)
    assert_eq(grid.frame.scroll_vertical, 100, "and a sync of the docker leaves them there")
    var in_view := String(tips[13]["path"])
    assert_true(grid.pick(in_view), "A press on a tip in view")
    _lay_out(grid, WIDTH)
    assert_eq(grid.frame.scroll_vertical, 100, "leaves them there too")


## A folder that holds fewer tips shrinks the frame to its rows, and All grows it
## to the rows again.
func test_a_folder_of_few_tips_shrinks_the_frame() -> void:
    var folders: Array[String] = []
    for letter in "abcdefghijklmnopqrst":
        folders.append("res://scratch_" + letter)
    var tips := _tips(60, folders)
    var grid := _grid(tips)
    var all := grid.tip_grid_report()["frame_height"] as int
    grid.choose_folder("res://scratch_b")
    _lay_out(grid, WIDTH)
    var side := SaUI.px(SaTipGrid.CELL)
    assert_eq(grid.shown_paths().size(), 3, "The folder holds three of the 60")
    assert_eq(grid.tip_grid_report()["frame_height"], side, "and the frame is a row tall")
    assert_eq(grid.frame.size.y, float(side), "as laid out as well")
    grid.choose_folder("")
    _lay_out(grid, WIDTH)
    assert_eq(grid.tip_grid_report()["frame_height"], all, "All brings the frame's rows back")


## A folder that hides the held cell shows its tips from the top, and All puts
## the held cell back in the frame.
func test_a_folder_change_moves_the_scroll_with_the_held_cell() -> void:
    var folders: Array[String] = ["res://scratch_a", "res://scratch_b"]
    var tips := _tips(200, folders)
    var last := String(tips[199]["path"])
    var grid := _grid(tips, last)
    assert_true(grid.frame.scroll_vertical > 0, "The held tip is down the 100 of its folder")
    grid.choose_folder("res://scratch_a")
    _lay_out(grid, WIDTH)
    assert_eq(grid.frame.scroll_vertical, 0, "A folder that does not hold it shows from the top")
    grid.choose_folder("")
    _lay_out(grid, WIDTH)
    var cell := grid.cells.get_node(NodePath("Cell_" + last.get_file().validate_node_name())) as Control
    var said := "All brings the held tip's cell %s into the frame %s" % [cell.get_global_rect(), grid.frame.get_global_rect()]
    assert_true(grid.frame.get_global_rect().encloses(cell.get_global_rect()), said)


## The wheel the pointer turns over a cell scrolls the tips, which is the point
## of the frame, through the window's GUI pass as the pointer takes it.
func test_a_wheel_over_the_frame_scrolls_the_tips() -> void:
    var grid := _grid(_tips(200))
    var window := grid.get_window()
    var before := grid.frame.scroll_vertical
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_WHEEL_DOWN
    event.pressed = true
    event.factor = 1.0
    var centre := grid.frame.get_global_rect().get_center()
    event.position = centre
    event.global_position = centre
    window.push_input(event, true)
    var release := event.duplicate() as InputEventMouseButton
    release.pressed = false
    window.push_input(release, true)
    var said := "A wheel down over the frame scrolled it, %d then %d" % [before, grid.frame.scroll_vertical]
    assert_true(grid.frame.scroll_vertical > before, said)
