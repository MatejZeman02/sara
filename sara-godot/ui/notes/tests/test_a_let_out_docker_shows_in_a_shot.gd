## A let-out docker shows in a shot.
##
## The shot is the root's readback with the open lists pasted in, so a docker
## that is a window of its own would be skipped without help. `SaNoteImage.paste_windows` now draws
## every window it is handed, the dockers first and the lists above them.
##
## A window of its own maps a real OS window and blocks the run
## (`test_a_dropdown_is_drawn_inside_the_window.gd`), so the windows here are
## embedded and handed over by name, with a window standing in for the main
## one. The arithmetic is the same, since an embedded window's place is
## measured against the window it sits in just as a let-out one's is measured
## on the desktop. The let-out half, where `windows_over` finds the docker for
## itself, is `scenarios/a-let-out-docker-shows-in-a-shot.json`.
extends "res://tests/test_framework.gd"

## Real windows, and the picture pasted is each one's readback.
const REQUIRES_GPU := true

const ROOT_COLOUR := Color(1.0, 0.0, 0.0)
const DOCKER_COLOUR := Color(0.0, 0.0, 1.0)
const LIST_COLOUR := Color(0.0, 1.0, 0.0)
const EDGE_COLOUR := Color(1.0, 0.0, 1.0)

## The stand-in main window, in the tree root's space.
const ROOT_AT := Vector2i(40, 30)
const ROOT_SIZE := Vector2i(120, 90)
## The docker, the list over its corner and a docker over the stand-in's
## top-left edge, each against the stand-in's corner.
const DOCKER_AT := Vector2i(50, 20)
const DOCKER_SIZE := Vector2i(40, 30)
const LIST_AT := Vector2i(70, 35)
const LIST_SIZE := Vector2i(30, 20)
const EDGE_AT := Vector2i(-10, -10)
const EDGE_SIZE := Vector2i(30, 30)

## Eight bits a channel, with room for a readback that went through sRGB.
const NEAR := 0.02

var _host: Node = null
var _root: Window = null
var _docker: Window = null
var _list: Popup = null
var _edge: Window = null
var _was_embedding: bool = true
## The rectangles that fill the windows, freed with them.
var _fills: Array[RID] = []


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "H3LetOutDockerHost"
    EventBus.add_child(_host)
    _root = _window(ROOT_AT, ROOT_SIZE, ROOT_COLOUR)
    _docker = _window(ROOT_AT + DOCKER_AT, DOCKER_SIZE, DOCKER_COLOUR)
    _edge = _window(ROOT_AT + EDGE_AT, EDGE_SIZE, EDGE_COLOUR)
    _list = Popup.new()
    _host.add_child(_list)
    _list.popup(Rect2i(ROOT_AT + LIST_AT, LIST_SIZE))
    _fill(_list, LIST_COLOUR)
    RenderingServer.force_draw(false, 0.0)


func after_each() -> void:
    for fill in _fills:
        RenderingServer.free_rid(fill)
    _fills.clear()
    if _host != null:
        _host.free()
        _host = null
    _root = null
    _docker = null
    _list = null
    _edge = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


## A borderless window at *at* of *size*, filled with *colour*, holding a
## control as large as itself for a note to be about.
func _window(at: Vector2i, size: Vector2i, colour: Color) -> Window:
    var window := Window.new()
    window.borderless = true
    window.position = at
    window.size = size
    var inside := Control.new()
    inside.size = Vector2(size)
    window.add_child(inside)
    _host.add_child(window)
    window.show()
    _fill(window, colour)
    return window


## Fills *window* with *colour* through the rendering server, since a control's
## drawing waits for a frame a suite never yields (an engine limit).
func _fill(window: Window, colour: Color) -> void:
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, window.find_world_2d().canvas)
    RenderingServer.canvas_item_add_rect(item, Rect2(Vector2.ZERO, Vector2(window.size)), colour)
    _fills.append(item)


func _is(shot: Image, at: Vector2i, colour: Color) -> bool:
    var seen := shot.get_pixelv(at)
    return absf(seen.r - colour.r) < NEAR and absf(seen.g - colour.g) < NEAR and absf(seen.b - colour.b) < NEAR


func _shot() -> Image:
    return _root.get_texture().get_image()


func test_the_docker_is_drawn_where_its_window_stands() -> void:
    var shot := SaNoteImage.paste_windows(_shot(), _root, [_docker])
    assert_true(
        _is(shot, DOCKER_AT + Vector2i(10, 10), DOCKER_COLOUR), "The pixel under the docker's window is the docker's colour"
    )
    assert_true(_is(shot, DOCKER_AT, DOCKER_COLOUR), "and so is its corner")
    assert_true(_is(shot, DOCKER_AT + DOCKER_SIZE - Vector2i.ONE, DOCKER_COLOUR), "and its far corner")
    assert_true(_is(shot, DOCKER_AT + DOCKER_SIZE, ROOT_COLOUR), "Past the docker the main window is left as it was")
    assert_true(_is(shot, Vector2i(10, 70), ROOT_COLOUR), "and away from it too")


## The list is handed over before the docker and still drawn above it, which
## is how the desktop stacks an open list over a docker.
func test_a_list_is_drawn_over_the_docker_it_overlaps() -> void:
    var shot := SaNoteImage.paste_windows(_shot(), _root, [_list, _docker])
    assert_true(_is(shot, Vector2i(80, 45), LIST_COLOUR), "Where the list and the docker overlap the list is on top")
    assert_true(_is(shot, Vector2i(95, 52), LIST_COLOUR), "The list past the docker is the list")
    assert_true(_is(shot, Vector2i(55, 45), DOCKER_COLOUR), "and the docker beside the list is the docker")


func test_a_window_over_the_edge_is_cut_there() -> void:
    var shot := SaNoteImage.paste_windows(_shot(), _root, [_edge])
    assert_eq(shot.get_size(), ROOT_SIZE, "The picture keeps the main window's size")
    assert_true(_is(shot, Vector2i.ZERO, EDGE_COLOUR), "The part of the window inside the main one is drawn from its corner")
    assert_true(_is(shot, EDGE_AT + EDGE_SIZE - Vector2i.ONE, EDGE_COLOUR), "up to its far corner")
    assert_true(_is(shot, EDGE_AT + EDGE_SIZE, ROOT_COLOUR), "and no further")


## A readback at twice the main window's size, which is what a content scale
## of two gives, draws the docker at twice its place and its size.
func test_a_scaled_readback_scales_the_docker_with_it() -> void:
    var shot := _shot()
    shot.resize(ROOT_SIZE.x * 2, ROOT_SIZE.y * 2, Image.INTERPOLATE_NEAREST)
    SaNoteImage.paste_windows(shot, _root, [_list, _docker])
    assert_true(_is(shot, DOCKER_AT * 2 + Vector2i(10, 10), DOCKER_COLOUR), "The docker lands at twice its place")
    assert_true(_is(shot, (DOCKER_AT + DOCKER_SIZE) * 2 - Vector2i(2, 2), LIST_COLOUR), "with the list over its far corner")
    assert_true(_is(shot, Vector2i(105, 95), DOCKER_COLOUR), "and its own far corner beside the list at twice its size")
    assert_true(_is(shot, (DOCKER_AT + DOCKER_SIZE) * 2 + Vector2i(30, 30), ROOT_COLOUR), "and no larger")


func test_a_hidden_window_is_left_out() -> void:
    _docker.hide()
    var shot := SaNoteImage.paste_windows(_shot(), _root, [_docker])
    assert_true(_is(shot, DOCKER_AT + Vector2i(10, 10), ROOT_COLOUR), "A docker that is not shown is not drawn")


## Embedded, the docker is in the tree root's texture already, and the walk
## that finds windows of their own finds nothing to add.
func test_an_embedded_docker_leaves_the_readback_as_it_was() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    assert_eq(SaNoteImage.windows_over(root).has(_docker), false, "An embedded docker is not a window of its own")
    var shot := Image.create(8, 8, false, Image.FORMAT_RGBA8)
    shot.fill(ROOT_COLOUR)
    var before := shot.get_data()
    assert_eq(SaNoteImage.with_windows(shot, root).get_data(), before, "so the shot is left as it was")


## A note on a control in a docker says the control is in the picture while
## its window stands over the main one, and outside it when moved past.
func test_a_note_reads_a_docker_control_in_the_picture_while_it_overlaps() -> void:
    var inside := _docker.get_child(0) as Control
    assert_true(SaNoteImage.shows(inside, _root), "A control in a docker over the main window is in its picture")
    _docker.position = ROOT_AT + ROOT_SIZE + Vector2i(10, 10)
    assert_false(SaNoteImage.shows(inside, _root), "and one in a docker past its edge is not")
