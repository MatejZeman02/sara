## A docker that is a window of its own sank behind the main
## window on Windows, and had a taskbar entry of its own.
##
## Godot 4.7 on Windows gives a transient window an owner only when it is
## exclusive as well, so `DockerWindow` asks the display server for that flag
## after every show and leaves `Window.exclusive` alone. What this suite pins
## is the half that holds on every desktop: the docker is held by the window it
## is transient to after a show, let go on a hide and held again by the same
## window on the next show, and it never becomes exclusive in the scene, which
## would stop the canvas under it taking the pen. The owner the display server
## sets from that is Windows' own, and only a run with the real mouse on Windows proves it.
##
## The docker is embedded here, the way `test_cursor_modes.gd` embeds its
## windows, because a docker that maps an OS window hangs a headless run.
@tool
extends "res://tests/test_framework.gd"


class StubDocker:
    extends DockerWindow

    func _init() -> void:
        _init_docker("StubDocker", "Stub", Vector2i(200, 200))


var _host: Node = null
var _previous_embedding: bool = true
var _previous_owner_rule: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    _previous_owner_rule = DockerWindow.owner_needs_exclusive
    tree.root.gui_embed_subwindows = true
    # The Windows path, so a run on any desktop walks the branch the fix added.
    DockerWindow.owner_needs_exclusive = true
    _host = Node.new()
    _host.name = "D6DockerHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    DockerWindow.owner_needs_exclusive = _previous_owner_rule
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


func _docker() -> DockerWindow:
    var docker := StubDocker.new()
    _host.add_child(docker)
    return docker


func test_a_hidden_docker_is_held_by_nothing() -> void:
    var docker := _docker()
    assert_false(docker.visible, "A docker starts hidden")
    assert_null(docker.held_by, "and a hidden docker is held by no window")


func test_a_shown_docker_is_held_by_the_main_window() -> void:
    var docker := _docker()
    var root := (Engine.get_main_loop() as SceneTree).root
    docker.show()
    assert_true(docker.transient, "A docker is transient")
    assert_eq(DockerWindow.transient_parent_window(docker), root, "to the main window")
    assert_eq(docker.held_by, root, "and a shown docker is held above it")


func test_the_hold_comes_back_after_a_hide_and_a_show() -> void:
    var docker := _docker()
    var root := (Engine.get_main_loop() as SceneTree).root
    docker.show()
    docker.hide()
    assert_null(docker.held_by, "A hide lets the docker go, since its OS window is gone")
    docker.show()
    assert_eq(docker.held_by, root, "and the next show holds it above the main window again")
    assert_eq(DockerWindow.transient_parent_window(docker), root, "which is still its transient parent")


func test_the_docker_never_turns_modal() -> void:
    var docker := _docker()
    docker.show()
    docker.hide()
    docker.show()
    assert_false(docker.exclusive, "The docker is not exclusive in the scene, so the main window still takes input")
