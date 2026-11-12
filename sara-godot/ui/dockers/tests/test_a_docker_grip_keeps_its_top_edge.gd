## Resizing a docker by its grip keeps its top edge.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The finding: a painter dragged the Brush Presets docker's grip down 260 and
## its top edge rose over the menu bar and the top bar's second row, and a
## shrink of 160 after it took the top 170 down with the bottom and left the
## search box and three buttons with no preset grid. The grip used to grow
## about the centre. The grip now holds the corner opposite it, the ALT-right
## drag keeps the centre, both stop under the bar, and Brush Presets keeps a row
## of its grid at its smallest.
##
## The running app is
## `scenarios/resizing-a-docker-by-its-grip-keeps-its-top-edge.json` and
## its restart pair. Here are the arithmetic at the finding's own numbers, the
## two gestures driven like a hand on a docker embedded under a bar, and the
## floor.
extends "res://tests/test_framework.gd"

## Brush Presets is built for the floor's tests, and its chooser asks for one.
const REQUIRES_GPU := true

const PresetsDockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")

## The row below the bar in the scenario's window, where the docker opens.
const BAR := 79

## Brush Presets where a fresh profile opens it, and its floor on that run.
const AT := Vector2i(70, 79)
const OPENED := Vector2i(310, 370)
const FLOOR := Vector2i(246, 329)

## The scenario's window less the bar.
const HOST := Rect2i(0, BAR, 1920, 1048 - BAR)

var _kept_inset: Callable = Callable()
var _kept_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    _kept_inset = SaDialogWindow.top_inset
    SaDialogWindow.top_inset = func() -> int: return BAR
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A window added outside the screen below would map a real OS window and
    # block the run, so the root embeds as well.
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "S21GripHostTest"
    EventBus.add_child(_host)


func after_each() -> void:
    SaDialogWindow.top_inset = _kept_inset
    DockerDragHandle.capture_pointer = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


## A window embedded in a 1280 by 1024 screen, with the bar above it.
func _embedded(at: Vector2i, size: Vector2i) -> Window:
    var screen := SubViewport.new()
    screen.size = Vector2i(1280, 1024)
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    var window := Window.new()
    window.min_size = Vector2i(80, 60)
    window.position = at
    window.size = size
    screen.add_child(window)
    return window


func test_a_grip_pulled_down_260_moves_the_bottom_and_leaves_the_top() -> void:
    var rect := DockerDragHandle.grip_rect(AT, OPENED, Vector2(0, 260), FLOOR, HOST)
    assert_eq(rect.position, AT, "The top edge is where it was, under the bar")
    assert_eq(rect.size, Vector2i(310, 630), "and the bottom went down by the 260 the hand did")


func test_a_shrink_of_160_after_it_raises_the_bottom_and_leaves_the_top() -> void:
    var rect := DockerDragHandle.grip_rect(AT, Vector2i(310, 630), Vector2(0, -160), FLOOR, HOST)
    assert_eq(rect.position, AT, "The top stays")
    assert_eq(rect.size.y, 470, "and the bottom rose by 160, where the old grip dropped the top 170")


func test_a_grip_pushed_past_the_floor_stops_there_without_moving() -> void:
    var rect := DockerDragHandle.grip_rect(AT, Vector2i(310, 470), Vector2(-600, -600), FLOOR, HOST)
    assert_eq(rect.size, FLOOR, "The floor wins over the pointer")
    assert_eq(rect.position, AT, "and the docker does not walk towards it")


func test_a_grip_stops_at_the_host_s_foot_and_its_right_edge() -> void:
    var down := DockerDragHandle.grip_rect(AT, OPENED, Vector2(0, 2000), FLOOR, HOST)
    assert_eq(down.end.y, HOST.end.y, "The bottom stops at the window's foot")
    var across := DockerDragHandle.grip_rect(AT, OPENED, Vector2(4000, 0), FLOOR, HOST)
    assert_eq(across.end.x, HOST.end.x, "and the right edge at the window's right edge")
    assert_eq(across.size.x, HOST.size.x, "where the left edge gives the rest, up to the host's width")
    assert_eq(across.position.y, AT.y, "with the top still where it was")


## The ALT-right drag still holds the centre, as it always did, and the
## bar now stops its top the way the host's edge always stopped its sides.
func test_the_alt_right_drag_keeps_its_centre_and_its_top_under_the_bar() -> void:
    var start := Vector2i(70, 300)
    var press := Vector2(start + FLOOR)
    var rect := DockerDragHandle.resize_rect(start, FLOOR, Vector2(0, 400), press, FLOOR, HOST)
    assert_eq(rect.position.y, BAR, "The top stops at the bar's row and not over it")
    assert_almost_eq(rect.get_center().y, 300 + FLOOR.y * 0.5, 1.0, "and the centre held while it grew")
    var loose := DockerDragHandle.resize_rect(start, FLOOR, Vector2(0, 400), press, FLOOR, Rect2i(0, 0, 1920, 1048))
    assert_true(loose.position.y < BAR, "A host with the bar left on is what let it rise to %d" % loose.position.y)


## The rectangle both gestures are kept in is the host less the bar, by the
## rule every dialog keeps, so a docker and a dialog stop on one row.
func test_a_resize_is_kept_in_the_host_less_the_bar() -> void:
    var window := _embedded(Vector2i(100, 200), Vector2i(300, 400))
    assert_eq(DockerDragHandle.resize_host_of(window), Rect2i(0, BAR, 1280, 1024 - BAR), "The bar comes off the top")
    SaDialogWindow.top_inset = Callable()
    assert_eq(DockerDragHandle.resize_host_of(window), Rect2i(0, 0, 1280, 1024), "and with no bar the screen is whole")


func test_the_grip_driven_like_a_hand_keeps_its_top_and_stops_at_the_foot() -> void:
    var window := _embedded(Vector2i(100, 200), Vector2i(300, 400))
    var resizer := DockerResizer.new(window)
    window.add_child(resizer)

    resizer.capture_drag(Vector2(400, 600), Vector2(0, 260))
    assert_eq(window.position, Vector2i(100, 200), "The top-left stayed")
    assert_eq(window.size, Vector2i(300, 660), "and the bottom followed the hand")

    resizer.capture_drag(Vector2(400, 860), Vector2(0, 1000))
    assert_eq(window.position.y + window.size.y, 1024, "The bottom stops at the screen's foot")
    assert_eq(window.position, Vector2i(100, 200), "and the top is still where the hand left it")


func test_the_alt_right_drag_driven_like_a_hand_stops_under_the_bar() -> void:
    var window := _embedded(Vector2i(100, 100), Vector2i(300, 400))
    var bar := Control.new()
    window.add_child(bar)
    var handle := DockerDragHandle.new()
    window.add_child(handle)
    handle.bind(window, bar)

    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_RIGHT
    press.pressed = true
    press.alt_pressed = true
    DockerDragHandle.capture_pointer = Vector2(400, 500)
    assert_true(handle.handle_input(press), "ALT and the right button begin the resize")
    DockerDragHandle.capture_pointer = Vector2(400, 700)
    handle.handle_input(DockerDragHandle.held_motion(MOUSE_BUTTON_MASK_RIGHT))

    assert_eq(window.position.y, BAR, "The top stopped at the bar's row, where the old one went to -100")
    assert_eq(window.position.y + window.size.y * 0.5, 300.0, "and the centre is where it was")


## The floor a drag reads takes a docker's own height floor when it has one.
class FlooredWindow:
    extends Window

    func column_height_floor() -> int:
        return 329


func test_a_drag_reads_a_docker_s_own_height_floor() -> void:
    var floored := FlooredWindow.new()
    floored.min_size = Vector2i(200, 200)
    assert_eq(DockerDragHandle.minimum_size_of(floored), Vector2i(200, 329), "The column's floor is the drag's")
    floored.free()
    var plain := Window.new()
    plain.min_size = Vector2i(200, 200)
    assert_eq(DockerDragHandle.minimum_size_of(plain), Vector2i(200, 200), "and a window with none keeps its own")
    plain.free()


func test_only_brush_presets_floors_its_height() -> void:
    var docker := DockerWindow.new()
    assert_eq(docker.column_height_floor(), 0, "Every other docker keeps the floor it declared, the Recorder among them")
    docker.free()


## One row of the grid, whatever the grid holds: a cell adds its height to the
## floor and a second row adds nothing.
func test_the_presets_scroll_is_floored_at_one_row_of_its_grid() -> void:
    var holder := Node.new()
    var docker: BrushPresetsDocker = PresetsDockerScript.new()
    holder.add_child(docker)
    var grid: GridContainer = docker.chooser.grid
    grid.columns = 1

    var empty := docker.grid_floor.hold()
    assert_true(empty > 0.0, "With no cells the floor is the rows above the grid, %.0f" % empty)

    var cell := Control.new()
    cell.custom_minimum_size = Vector2(100, 108)
    grid.add_child(cell)
    assert_eq(docker.grid_floor.hold(), empty + 108.0, "One cell adds one row")

    var second := Control.new()
    second.custom_minimum_size = Vector2(100, 108)
    grid.add_child(second)
    assert_eq(docker.grid_floor.hold(), empty + 108.0, "and a second row adds nothing")
    holder.free()
