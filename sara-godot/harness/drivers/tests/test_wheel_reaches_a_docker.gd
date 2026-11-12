## The `wheel` capture step aims its notches at the docker the point is inside.
##
## Forty notches over the toolbox at its floor moved nothing, while a
## press and a drag of the same docker's own scroll bar moved it, and the same
## step at a free point on the canvas took the zoom from 1.0 to 0.512. The root
## forwards a mouse event into an embedded `Window` only once it knows which
## subwindow is in play, a real pointer tells it that by moving, and an injected
## motion does not.
##
## What this suite holds is the arithmetic that picks the window, which is the
## half a scenario cannot show: a point on the canvas has to find nothing, or
## every canvas zoom in every scenario starts pressing a docker. The other half,
## that the notches then land, is `scenarios/wheel-never-reaches-a-docker.json`
## on the running app.
extends "res://tests/test_framework.gd"

const CanvasDriver = preload("res://harness/drivers/sa_canvas_driver.gd")


## Three windows in a row, so "the first one that contains the point" is a claim
## about the point rather than about the order they were built in.
func _dockers(host: Node) -> Array[Window]:
    var out: Array[Window] = []
    for spec: Array in [[Vector2i(60, 120), Vector2i(52, 88)], [Vector2i(600, 400), Vector2i(283, 144)]]:
        var window := Window.new()
        window.position = spec[0]
        window.size = spec[1]
        window.name = "Docker%d" % out.size()
        host.add_child(window)
        out.append(window)
    return out


func test_a_point_inside_a_docker_finds_that_docker() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "this suite needs the real tree to embed a window in")
    if tree == null:
        return
    var embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "WheelReachTestHost"
    EventBus.add_child(host)
    var dockers := _dockers(host)

    var first: Window = CanvasDriver._docker_under(tree.root, Vector2(80, 160))
    assert_eq(first, dockers[0], "a point inside the first docker finds it")
    var second: Window = CanvasDriver._docker_under(tree.root, Vector2(700, 470))
    assert_eq(second, dockers[1], "and a point inside the second finds that one")

    host.free()
    tree.root.gui_embed_subwindows = embedding


## The clause that keeps every canvas zoom in every scenario working. A wheel on
## the canvas must reach nothing, or the step presses a docker's drag bar on the
## way to a zoom.
func test_a_point_on_the_canvas_finds_no_docker() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "this suite needs the real tree to embed a window in")
    if tree == null:
        return
    var embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "WheelReachTestHost"
    EventBus.add_child(host)
    var dockers := _dockers(host)

    assert_null(CanvasDriver._docker_under(tree.root, Vector2(1400, 700)), "a point past every docker finds none")
    assert_null(CanvasDriver._docker_under(tree.root, Vector2(59, 160)), "and one a pixel outside the left edge finds none")

    # A closed docker is not under anything, whatever its rect still says. The
    # Dockers menu leaves five of the ten hidden in a fresh profile.
    dockers[0].visible = false
    assert_null(CanvasDriver._docker_under(tree.root, Vector2(80, 160)), "a hidden docker is not under the point")

    host.free()
    tree.root.gui_embed_subwindows = embedding
