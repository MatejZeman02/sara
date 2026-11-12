## A change sent while Sara's window is hidden is drawn when it
## comes back, and a window left alone draws nothing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `SaRedrawOnReturn` is handed what it asks the canvas and the engine as
## callables, so the cases here count the redraws it asks for while saying
## whether the window may draw and how many composites the document has had.
## The engine's own part, a suspended window's frame rendered and never
## presented, is not here: the driver in the unit's proof folder takes the
## shell's screenshot of it under a nested gnome-shell.
extends "res://tests/test_framework.gd"

## The canvas builds an easel.
const REQUIRES_GPU := true

## What the node is told and what it asked: `can_draw`, `composites` and
## `redraws`. A dictionary, so the lambdas below share it.
var _world: Dictionary = {}
var _host: Node = null


func before_each() -> void:
    _world = {"can_draw": true, "composites": 0, "redraws": 0}
    _host = null


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func _node() -> SaRedrawOnReturn:
    var world := _world
    var node := SaRedrawOnReturn.new(
        func() -> void: world["redraws"] = int(world["redraws"]) + 1,
        func() -> bool: return bool(world["can_draw"]),
        func() -> int: return int(world["composites"])
    )
    node._ready()
    return node


func _frames(node: SaRedrawOnReturn, count: int) -> void:
    for i in count:
        node._process(0.0)


func test_a_window_left_alone_asks_for_nothing() -> void:
    var node := _node()
    _frames(node, 10)
    _world["can_draw"] = false
    _frames(node, 10)
    assert_eq(_world["redraws"], 0, "no change and no focus, so no frame, even once the engine says it may not draw")
    node.free()


func test_the_focus_coming_back_asks_once() -> void:
    var node := _node()
    node._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
    assert_eq(_world["redraws"], 1, "one redraw for the focus coming in")
    _frames(node, 10)
    assert_eq(_world["redraws"], 1, "and nothing after it")
    node._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
    assert_eq(_world["redraws"], 1, "the focus going asks for nothing")
    node.free()


func test_a_door_step_that_changed_the_document_asks_once() -> void:
    var node := _node()
    _world["composites"] = 3
    node.step_answered()
    assert_eq(_world["redraws"], 1, "the step composited, so the window is drawn again")
    node.step_answered()
    assert_eq(_world["redraws"], 1, "a step after it that changed nothing asks for nothing")
    node.free()


func test_a_change_the_window_can_show_asks_nothing_more() -> void:
    var node := _node()
    _world["composites"] = 1
    _frames(node, 5)
    assert_eq(_world["redraws"], 0, "the canvas draws its own composite, and the window may show it")
    node.free()


func test_a_change_while_hidden_is_asked_for_until_the_window_draws() -> void:
    var node := _node()
    _world["can_draw"] = false
    _world["composites"] = 1
    _frames(node, 4)
    assert_eq(_world["redraws"], 4, "asked on every frame the window cannot draw, since the engine eats each")
    _world["can_draw"] = true
    _frames(node, 1)
    assert_eq(_world["redraws"], 4, "the window drew, so the debt is paid")
    _world["can_draw"] = false
    _frames(node, 5)
    assert_eq(_world["redraws"], 4, "and a window resting past the engine's second asks for nothing again")
    node.free()


func test_the_canvas_carries_one() -> void:
    _host = Node.new()
    _host.name = "L6RedrawHost"
    EventBus.add_child(_host)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(320, 240)
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    viewport.add_child(canvas)
    assert_not_null(canvas.get_node_or_null(SaRedrawOnReturn.NODE_NAME), "the canvas listens for its window coming back")
