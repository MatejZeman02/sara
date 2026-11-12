## A docker dragged by an edge moves that edge alone and stays inside the
## window.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Resizing a docker by its edges must not behave oddly or let it grow too wide,
## as resizing by the corner grip does not. The odd resize was the
## ALT and right button gesture, which grows about the centre, and the window
## system's own once a docker is let out, which knows no host. `SaDockerEdges`
## gives every docker four strips of its own, and this suite holds their
## arithmetic, their attachment and one drag through the handler a hand goes
## through. `scenarios/a-docker-dragged-by-an-edge-moves-that-edge-alone-and-stays-inside-the.json`
## is the same on the running app, embedded and let out.
##
## The numbers below are the scenario's: Layers at (420, 200) 300 by 400, its
## floor 269 by 212, and the host the 1920 by 1048 window below its 79 pixel bar.
## The docker is embedded the way `test_a_sliders_text_follows_the_font_size.gd`
## embeds its own, because a docker that maps an OS window hangs a headless run.
@tool
extends "res://tests/test_framework.gd"

const START := Rect2i(420, 200, 300, 400)
const FLOOR := Vector2i(269, 212)
const HOST := Rect2i(0, 79, 1920, 969)


## A docker that builds what a real one builds before its edges arrive, its
## content, its drag bar and the grip, and nothing else.
class StubDocker:
    extends DockerWindow

    func _init() -> void:
        _init_docker("B7EdgeDocker", "Stub", Vector2i(300, 400))
        var column := VBoxContainer.new()
        column.name = "Column"
        _control_node.add_child(column)
        drag_handle = PanelContainer.new()
        column.add_child(drag_handle)

    func _ready() -> void:
        _setup_docker_ready()


var _host: Node = null
var _kept_embedding: bool = true
var _layout_changes: int = 0


func before_each() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "B7EdgeHost"
    EventBus.add_child(_host)
    _layout_changes = 0
    EventBus.docker_layout_changed.connect(_count_layout_change)


func after_each() -> void:
    EventBus.docker_layout_changed.disconnect(_count_layout_change)
    if _host != null:
        _host.free()
        _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


func _count_layout_change() -> void:
    _layout_changes += 1


func _rect(sides: int, drag: Vector2) -> Rect2i:
    return SaDockerEdges.edge_rect(START, drag, sides, FLOOR, HOST)


func _docker_with_edges() -> Window:
    var docker := StubDocker.new()
    assert_false(SaDockerEdges.attach(docker), "A docker not built yet has no grip to put its edges beside")
    _host.add_child(docker)
    return docker


## Past the host's edge the left edge gives the rest, so a
## drag of 5,000 ends as wide as the host and no edge leaves it.
func test_the_right_edge_moves_the_right_alone_and_stops_at_the_host() -> void:
    var right := SaDockerEdges.RIGHT
    assert_eq(_rect(right, Vector2(200, 37)), Rect2i(420, 200, 500, 400), "200 wider, the left, the top and the height kept")
    assert_eq(_rect(right, Vector2(1200, 0)), Rect2i(420, 200, 1500, 400), "The right edge stops on the host's")
    assert_eq(_rect(right, Vector2(1300, 0)), Rect2i(320, 200, 1600, 400), "and past it the left edge gives the rest")
    assert_eq(_rect(right, Vector2(5000, 0)), Rect2i(0, 200, 1920, 400), "A drag of 5,000 stops at the host's width")
    assert_eq(_rect(right, Vector2(-5000, 0)), Rect2i(420, 200, 269, 400), "Inwards it stops at the floor")


func test_the_left_edge_moves_the_left_alone_and_stops_at_the_host() -> void:
    var left := SaDockerEdges.LEFT
    assert_eq(_rect(left, Vector2(-200, 0)), Rect2i(220, 200, 500, 400), "The left 200 out, the right edge kept at 720")
    assert_eq(_rect(left, Vector2(-500, 0)), Rect2i(0, 200, 800, 400), "Past the host's left edge the right edge gives")
    assert_eq(_rect(left, Vector2(-5000, 0)), Rect2i(0, 200, 1920, 400), "A drag of 5,000 stops at the host's width")
    assert_eq(_rect(left, Vector2(5000, 0)), Rect2i(451, 200, 269, 400), "Inwards the floor holds and the right edge stays")


func test_the_bottom_and_the_top_stop_at_the_host_and_the_floor() -> void:
    var bottom := SaDockerEdges.BOTTOM
    var top := SaDockerEdges.TOP
    assert_eq(_rect(bottom, Vector2(-30, 200)), Rect2i(420, 200, 300, 600), "The bottom 200 down, the rest kept")
    assert_eq(_rect(bottom, Vector2(0, 5000)).end.y, HOST.end.y, "A drag of 5,000 stops on the window's bottom")
    assert_eq(_rect(bottom, Vector2(0, -5000)), Rect2i(420, 200, 300, 212), "Inwards it stops at the floor")
    assert_eq(_rect(top, Vector2(0, -5000)), Rect2i(420, 79, 300, 521), "The top stops below the bar, the bottom kept")
    assert_eq(_rect(top, Vector2(0, 5000)), Rect2i(420, 388, 300, 212), "and inwards at the floor, the bottom kept")


func test_the_floor_wins_where_the_host_has_no_room_and_no_host_is_no_cap() -> void:
    var tight := Rect2i(1800, 200, 100, 400)
    var rect := SaDockerEdges.edge_rect(tight, Vector2(50, 0), SaDockerEdges.RIGHT, FLOOR, HOST)
    assert_eq(rect.size.x, FLOOR.x, "A docker narrower than its floor grows to it, as the grip's does")
    rect = SaDockerEdges.edge_rect(START, Vector2(5000, 0), SaDockerEdges.RIGHT, FLOOR)
    assert_eq(rect, Rect2i(420, 200, 5300, 400), "An empty host is no cap, which a docker out of the tree has")


func test_every_docker_gets_four_edges_under_its_grip_and_no_resize_of_its_own() -> void:
    var docker := _docker_with_edges()
    var content := docker.get_node("Control")
    var grip := content.get_node("Resizer") as Control
    for side: int in SaDockerEdges.NODE_NAMES:
        var edge := content.get_node_or_null(String(SaDockerEdges.NODE_NAMES[side])) as Control
        assert_not_null(edge, "The %s edge arrived once the docker was built" % SaDockerEdges.NODE_NAMES[side])
        if edge == null:
            continue
        assert_true(edge.get_index() < grip.get_index(), "%s lies under the grip, which keeps its corner" % edge.name)
        assert_eq(edge.mouse_filter, Control.MOUSE_FILTER_STOP, "%s takes the press" % edge.name)
        var shape := Control.CURSOR_HSIZE if side & (SaDockerEdges.LEFT | SaDockerEdges.RIGHT) else Control.CURSOR_VSIZE
        assert_eq(edge.mouse_default_cursor_shape, shape, "%s shows its own resize shape" % edge.name)
    assert_true(docker.unresizable, "The engine's and the window system's resize is off")
    var hold := content.get_node_or_null("EdgeHold") as SaDockerEdges.Hold
    assert_not_null(hold, "and the hold that keeps it off under Wayland is there")
    if hold != null:
        assert_false(hold.held(), "An embedded docker has no window of its own to hold")
    var count := content.get_child_count()
    assert_true(SaDockerEdges.attach(docker), "A second attach answers that the edges are there")
    assert_eq(content.get_child_count(), count, "and adds no second set")

    var dialog := Window.new()
    _host.add_child(dialog)
    assert_false(SaDockerEdges.attach(dialog), "A window that is not a docker is left alone")
    assert_false(dialog.unresizable, "and keeps its own resize")


func test_a_drag_on_an_edge_moves_that_edge_alone_and_tells_the_layout() -> void:
    var docker := _docker_with_edges()
    docker.position = START.position
    docker.size = START.size
    var host := DockerDragHandle.resize_host_of(docker)
    var minimum := DockerDragHandle.minimum_size_of(docker)
    var edge := docker.get_node("Control/EdgeRight") as SaDockerEdges.Edge
    edge.capture_drag(Vector2(START.end.x, 400), Vector2(120, 55))
    var expected := SaDockerEdges.edge_rect(START, Vector2(120, 55), SaDockerEdges.RIGHT, minimum, host)
    assert_eq(Rect2i(docker.position, docker.size), expected, "The handler wrote the rectangle the arithmetic asks for")
    assert_eq(docker.position.x, START.position.x, "The left edge stayed")
    assert_eq(docker.size.y, START.size.y, "and the height, though the pointer moved down as well")
    assert_eq(_layout_changes, 1, "The release told the layout store once, as the grip's does")

    edge = docker.get_node("Control/EdgeLeft") as SaDockerEdges.Edge
    var right_edge := docker.position.x + docker.size.x
    edge.capture_drag(Vector2(docker.position.x, 400), Vector2(-60, 0))
    assert_eq(docker.position.x + docker.size.x, right_edge, "A left drag keeps the right edge where it was")
    assert_eq(_layout_changes, 2, "and tells the layout too")


func test_the_step_drags_an_edge_and_says_so() -> void:
    var docker := _docker_with_edges()
    docker.position = START.position
    docker.size = START.size
    var tree := Engine.get_main_loop() as SceneTree
    var line := SaDockerEdges.capture_resize(tree, {"id": "B7EdgeDocker", "by": [0, 40], "edge": "bottom"})
    assert_true(line.contains("edge bottom"), "The step names the edge it dragged: %s" % line)
    assert_true(line.contains("cursor VSIZE"), "and its pointer shape")
    assert_true(line.contains("window system resize off"), "and that no second resize stands beside it")
    assert_eq(docker.size.y, START.size.y + 40, "The bottom came down 40")
    assert_eq(docker.position, START.position, "and the top and the left stayed")
    line = SaDockerEdges.capture_resize(tree, {"id": "B7EdgeDocker", "by": [10, 0], "edge": "middle"})
    assert_true(line.contains("left, top, right or bottom"), "An edge it does not know is named back: %s" % line)
