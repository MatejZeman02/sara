## Ctrl+Space with a toolbox flyout focused maximises nothing, and never the
## flyout.
##
## The claim, from a capture: after a drop the Navigate flyout stood
## open with the focus, and the chord logged `SaCapture: '' fills (0, 0) 1536 by
## 838 at 1.25`, the list stretched over four fifths of the toolbox.
## `SaDockerMaximise.focused_window` answered the first focused `Window`, and a
## popup is one.
##
## The focus is given with `grab_focus` on embedded windows, which is what an
## embedded popup's own `popup()` does, and `focused_window` is asked the way the
## router asks it.
##
## Embedded on purpose, the way `test_choice_popup.gd` does it: without embedding
## a Window added to the tree maps a real OS window and the run blocks until the
## watchdog fires.
extends "res://tests/test_framework.gd"

var _was_embedding: bool = false
var _host: Node = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "D71Host"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding


## A docker with a button, and a list under the button the way a toolbox parents
## its flyout.
func _docker_with_a_list() -> Dictionary:
    var docker := Window.new()
    docker.title = "Probe Toolbox"
    docker.position = Vector2i(200, 100)
    docker.size = Vector2i(220, 420)
    _host.add_child(docker)
    var button := Button.new()
    button.size = Vector2(40.0, 40.0)
    docker.add_child(button)
    var flyout := SaToolFlyout.new()
    flyout.add_row(&"pan", "Pan")
    flyout.add_row(&"zoom", "Zoom")
    button.add_child(flyout)
    return {"docker": docker, "flyout": flyout}


## What F1 built stays: a focused docker is the window the chord answers for.
func test_a_focused_docker_is_still_the_answer() -> void:
    var scene := _docker_with_a_list()
    var docker: Window = scene["docker"]
    docker.grab_focus()
    var tree := Engine.get_main_loop() as SceneTree
    assert_true(docker.has_focus(), "The docker holds the focus")
    assert_eq(SaDockerMaximise.focused_window(tree), docker, "and the chord answers for it")


## The unit's claim: an open list holding the focus is not an answer, and neither
## is the docker behind it.
func test_an_open_list_with_the_focus_answers_nothing() -> void:
    var scene := _docker_with_a_list()
    var docker: Window = scene["docker"]
    var flyout: SaToolFlyout = scene["flyout"]
    docker.grab_focus()
    flyout.popup(Rect2i(Vector2i(260, 100), Vector2i(120, 90)))
    flyout.grab_focus()
    var tree := Engine.get_main_loop() as SceneTree
    assert_true(flyout.visible and flyout.has_focus(), "The list is open and holds the focus")
    assert_eq(SaDockerMaximise.focused_window(tree), null, "so the chord answers for no window, never the list")
    flyout.hide()
