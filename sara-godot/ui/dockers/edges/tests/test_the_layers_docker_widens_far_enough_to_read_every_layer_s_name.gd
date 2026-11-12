## The Layers docker widens far enough to read every layer's name.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Layers docker has to widen far enough to read its layers' names. The default layout puts the Layers
## docker 10 from the window's
## right edge, and its right edge and its corner grip stopped where they would
## leave the host, so both ended at 320 wide. Now the left edge gives what the
## right edge has no room for. This suite drags the default's Layers docker to
## 500 on a 1920 by 1048 window, docked under the bar and let out on the screen,
## and fits the layout again over it, twice. The scenario
## `scenarios/the-layers-docker-widens-far-enough-to-read-every-layer-s-name.json`
## does the same on the running app and shoots the rows.
@tool
extends "res://tests/test_framework.gd"

## The Layers docker as a capture's 1920 by 1048 window fits the default
## layout, measured by the scenario, and its floor from `layouts/default.cfg`.
const LAYERS := Rect2i(1600, 485, 310, 524)
const FLOOR := Vector2i(310, 272)
const WINDOW := Vector2i(1920, 1048)
const BAR := 79
const DOCKED := Rect2i(0, BAR, 1920, 1048 - BAR)
const LET_OUT := Rect2i(Vector2i.ZERO, WINDOW)


## A docker that builds a content, a drag bar and a grip, as b7's does.
class StubDocker:
    extends DockerWindow

    func _init() -> void:
        _init_docker("U80WideDocker", "Stub", Vector2i(310, 400))
        var column := VBoxContainer.new()
        column.name = "Column"
        _control_node.add_child(column)
        drag_handle = PanelContainer.new()
        column.add_child(drag_handle)

    func _ready() -> void:
        _setup_docker_ready()


var _host: Node = null
var _kept_embedding: bool = true


func before_each() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    _kept_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U80Host"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


func test_the_right_edge_and_the_grip_widen_the_docked_layers_docker_to_500() -> void:
    for host: Rect2i in [DOCKED, LET_OUT]:
        var by_edge := SaDockerEdges.edge_rect(LAYERS, Vector2(190, 0), SaDockerEdges.RIGHT, FLOOR, host)
        assert_eq(by_edge, Rect2i(1420, 485, 500, 524), "The right edge on %s: 10 by itself, 180 from the left" % host)
        var by_left := SaDockerEdges.edge_rect(LAYERS, Vector2(-190, 0), SaDockerEdges.LEFT, FLOOR, host)
        assert_eq(by_left, Rect2i(1410, 485, 500, 524), "and the left edge on %s, which keeps the right edge at 1910" % host)
        var by_grip := DockerDragHandle.grip_rect(LAYERS.position, LAYERS.size, Vector2(190, 0), FLOOR, host)
        assert_eq(by_grip, Rect2i(1420, 485, 500, 524), "and the corner grip on %s as the right edge does" % host)
    var half := SaDockerEdges.edge_rect(LAYERS, Vector2(650, 0), SaDockerEdges.RIGHT, FLOOR, DOCKED)
    assert_eq(half.size.x, 960, "Half the window's width is in reach")
    assert_eq(half.end.x, DOCKED.end.x, "with the right edge on the window's")


func test_a_hand_on_the_right_edge_widens_a_docker_against_the_host() -> void:
    var docker := StubDocker.new()
    _host.add_child(docker)
    assert_true(SaDockerEdges.attach(docker), "The docker has its four edges")
    var host := DockerDragHandle.resize_host_of(docker)
    if host.size.x < 600:
        skip("The headless root is narrower than 600, so the drag has nowhere to go")
        return
    docker.size = Vector2i(310, 400)
    docker.position = Vector2i(host.end.x - 320, host.position.y + 20)
    var edge := docker.get_node("Control/EdgeRight") as SaDockerEdges.Edge
    edge.capture_drag(Vector2(docker.position.x + 310, docker.position.y + 200), Vector2(190, 0))
    assert_eq(docker.size.x, 500, "The docker is 500 wide after the drag")
    assert_eq(docker.position.x + docker.size.x, host.end.x, "with its right edge on the host's")


func test_the_layout_fit_keeps_the_width_the_painter_chose() -> void:
    var widened := Rect2i(1410, 485, 500, 524)
    var placed := _default_with(widened)
    assert_false(placed.is_empty(), "The default layout reads")
    var room := WINDOW - Vector2i(0, SaDockerLayoutRefit.status_rows_in(1.0))
    var fit := SaDockerLayoutFit.new(room, BAR, WINDOW)
    var once := fit.place(placed)
    assert_eq((once.get("LayersDocker", Rect2i()) as Rect2i).size.x, 500, "The fit leaves the Layers docker 500 wide")
    for section: String in once:
        placed[section]["rect"] = once[section]
    var twice := SaDockerLayoutFit.new(room, BAR, WINDOW).place(placed)
    assert_eq((twice.get("LayersDocker", Rect2i()) as Rect2i).size.x, 500, "and a second fit over its answer too")


## The default layout's open dockers as a painter's fit is handed them, at their
## shipped places, with the Layers docker at *layers*.
func _default_with(layers: Rect2i) -> Dictionary:
    var shipped := ConfigFile.new()
    if shipped.load("res://layouts/default.cfg") != OK:
        return {}
    var placed: Dictionary = {}
    for section: String in shipped.get_sections():
        if not bool(shipped.get_value(section, "visible", false)):
            continue
        var rect := Rect2i(shipped.get_value(section, "position", Vector2i()), shipped.get_value(section, "size", Vector2i()))
        var least: Vector2i = shipped.get_value(section, SaDockerLayoutRefit.FLOOR_SIZE, Vector2i.ONE)
        placed[section] = {"rect": rect, "min": least}
    if not placed.has("LayersDocker"):
        return {}
    placed["LayersDocker"]["rect"] = layers
    return placed
