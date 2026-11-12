## A canvas that leaves the tree lets go of its viewport's `size_changed`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `_ready` connects `_on_viewport_resized`, and `_exit_tree` disconnected
## `_center_canvas`, the method the connection named before a window
## drag stopped refitting the view. The disconnect never matched, so a canvas
## that had left went on being called on every resize of the viewport it left.
extends "res://tests/test_framework.gd"

## A canvas builds an easel.
const REQUIRES_GPU := true

var _host: Node = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "B2CanvasLeavesHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func test_a_canvas_that_leaves_is_not_called_on_a_resize() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(320, 240)
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    viewport.add_child(canvas)
    assert_true(viewport.size_changed.is_connected(canvas._on_viewport_resized), "connected while it is in the tree")

    viewport.remove_child(canvas)

    assert_false(viewport.size_changed.is_connected(canvas._on_viewport_resized), "and let go once it has left")
    canvas.free()
