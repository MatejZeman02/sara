## While the pointer is over a menu or a popup that covers the canvas, the
## canvas stops asking for the tool's shape, so the I-beam of the Text tool
## does not stay under a menu. Off the menu the tool's shape comes back.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const RING: float = 12.0
## Over the canvas and clear of the docker below.
const ON_CANVAS := Vector2(100, 60)
## The centre of the embedded docker `_embedded_docker` puts at (400, 400).
const ON_DOCKER := Vector2(500, 500)

var _host: Node = null
var _previous_embedding: bool = true
var _previous_mode: String = "auto"


func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    _previous_mode = SaSettings.software_cursor
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "MenuCursorTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaPointerDevice.suite_pointer = null
    SaCursorPolicy.clear_tool_cursor()
    SaSettings.software_cursor = _previous_mode
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


func _window() -> Window:
    var window := Window.new()
    window.borderless = true
    window.size = Vector2i(1920, 1080)
    _host.add_child(window)
    window.show()
    return window


## A live canvas covering the whole of *window*, asking for a ring, with the
## pointer put over it at [constant ON_CANVAS].
func _canvas(window: Window) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    window.add_child(canvas)
    canvas.position = Vector2.ZERO
    canvas.size = Vector2(1920, 1080)
    canvas.cursor_ring_radius = RING
    var to_desktop: Transform2D = SaPointerDevice.desktop_transform(window)
    SaPointerDevice.suite_pointer = to_desktop * ON_CANVAS
    return canvas


## A docker-shaped embedded window over the canvas, 200 by 200 at (400, 400).
func _embedded_docker(window: Window) -> Window:
    var docker := Window.new()
    docker.borderless = true
    docker.position = Vector2i(400, 400)
    docker.size = Vector2i(200, 200)
    window.add_child(docker)
    docker.show()
    return docker


func _point_at(window: Window, at: Vector2) -> void:
    SaPointerDevice.suite_pointer = SaPointerDevice.desktop_transform(window) * at


func test_a_menu_over_the_canvas_has_the_arrow_and_the_canvas_the_tool_s_shape() -> void:
    var window := _window()
    var canvas := _canvas(window)
    _embedded_docker(window)
    var lasso := Fixtures.make_tool_registry().get_descriptor(&"lasso")

    SaCursorPolicy.apply_tool_cursor(canvas, lasso, Control.CURSOR_IBEAM)
    assert_eq(int(canvas.mouse_default_cursor_shape), Control.CURSOR_IBEAM, "Over the canvas the tool's shape shows")

    _point_at(window, ON_DOCKER)
    SaCursorPolicy.sync_tool_cursor()
    assert_eq(int(canvas.mouse_default_cursor_shape), Control.CURSOR_ARROW, "Over a menu it is the arrow")

    _point_at(window, ON_CANVAS)
    SaCursorPolicy.sync_tool_cursor()
    assert_eq(int(canvas.mouse_default_cursor_shape), Control.CURSOR_IBEAM, "and the tool's shape is back off the menu")
