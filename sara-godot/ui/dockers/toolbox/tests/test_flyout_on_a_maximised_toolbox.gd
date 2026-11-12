## The toolbox flyout on a maximised toolbox draws at the toolbox's factor and
## stands beside its button rather than over it.
##
## The claim, from a capture: the toolbox maximised at 1.25 and its
## Select flyout "still 190 by 182 at 1.0, at (1458, 47)", lying over the
## right-hand part of the button it came out of. The flyout keeps its own
## `open_beside` rather than `open_under`, so the earlier fix did not reach it.
##
## The same shape as the maximised toolbox suite: an embedded docker holding a button, maximised
## through `SaDockerMaximise.toggle`, the chord's own mechanism, and the factors
## read back rather than a constant written here twice. The rows are the fills'
## group, from the fixture registry a detached toolbox builds.
##
## Embedded on purpose, the way `test_choice_popup.gd` does it: without embedding
## a Window added to the tree maps a real OS window and the run blocks until the
## watchdog fires.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

var _saved_override: float = -1.0
var _saved_user: float = 1.0
var _was_embedding: bool = false
var _host: Node = null
var _toolbox: ToolBoxDocker = null


func before_each() -> void:
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    if _toolbox != null:
        _toolbox.free()
        _toolbox = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


## A docker at its own size holding one tool button with a flyout under it, the
## way `ToolBoxDocker._flyout_for` parents one, and the fills' group's members.
func _scene() -> Dictionary:
    _toolbox = ToolBoxDockerScript.new() as ToolBoxDocker
    _toolbox.rebuild_from_registry(Fixtures.make_tool_registry())
    var members: Array = _toolbox._visible_members(&"fill")
    var labels := PackedStringArray()
    for descriptor: SaToolDescriptor in members:
        labels.append(descriptor.display_name)

    _host = Node.new()
    _host.name = "D67Host"
    EventBus.add_child(_host)

    var docker := Window.new()
    docker.title = "Probe Toolbox"
    docker.position = Vector2i(200, 100)
    docker.size = Vector2i(220, 420)
    _host.add_child(docker)
    SaUI.apply_to_window(docker)

    var button := Button.new()
    button.position = Vector2(8.0, 40.0)
    button.size = Vector2(40.0, 40.0)
    docker.add_child(button)

    var flyout := SaToolFlyout.new()
    button.add_child(flyout)
    return {"docker": docker, "button": button, "flyout": flyout, "members": members, "labels": labels}


## The layout a frame would give the rows, given now, because the runner is
## synchronous and an awaited assertion is a dropped one. Top down, so
## each container sorts inside the rectangle its parent has just handed it.
func _lay_out(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _lay_out(child)


## The unit's proof: the flyout's factor is the maximised toolbox's, it starts at
## the button's right edge on the host and meets none of the button, and it is
## the size its rows want times that factor.
func test_the_flyout_on_a_maximised_toolbox_takes_its_factor_and_stands_beside_its_button() -> void:
    var scene := _scene()
    var docker: Window = scene["docker"]
    var button: Button = scene["button"]
    var flyout: SaToolFlyout = scene["flyout"]
    assert_true((scene["members"] as Array).size() >= 2, "The fills' group is a flyout")

    SaDockerMaximise.toggle(docker)
    assert_almost_eq(docker.content_scale_factor, SaDockerMaximise.MAXIMISED_SCALE, 0.0001, "The toolbox is maximised")

    flyout.open_beside(button, scene["members"], scene["labels"], PackedStringArray())
    var span := SaPopupRect.of_anchor(button)
    assert_almost_eq(
        flyout.content_scale_factor, docker.content_scale_factor, 0.0001, "The flyout draws at the maximised toolbox's factor"
    )
    assert_eq(flyout.position.x, int(span.end.x), "and starts at the button's right edge on the host")
    assert_false(Rect2(Vector2(flyout.position), Vector2(flyout.size)).intersects(span), "so it meets none of the button")
    var wanted := (Vector2(flyout.wanted_size(0.0)) * docker.content_scale_factor).round()
    assert_eq(flyout.size, Vector2i(wanted), "at the size its rows want, drawn at the toolbox's factor")
    flyout.hide()

    SaDockerMaximise.toggle(docker)
    flyout.open_beside(button, scene["members"], scene["labels"], PackedStringArray())
    assert_almost_eq(flyout.content_scale_factor, 1.0, 0.0001, "Back at its size, the flyout is at 1.0 again")
    assert_eq(flyout.position.x, int(button.get_screen_position().x + button.size.x), "beside the button as before")
    flyout.hide()


## A drop lands on the row the painter sees. A row's `size` is in the flyout's
## units, so on a maximised toolbox the rectangle `row_at` built from it was a
## fifth shorter than the row drawn, and a release in the row's lower part landed
## on no row at all.
func test_a_point_in_the_lower_part_of_a_drawn_row_is_on_that_row() -> void:
    var scene := _scene()
    var docker: Window = scene["docker"]
    var flyout: SaToolFlyout = scene["flyout"]

    SaDockerMaximise.toggle(docker)
    flyout.open_beside(scene["button"], scene["members"], scene["labels"], PackedStringArray())
    _lay_out(flyout)

    var row := flyout.row_control(0)
    assert_true(row != null and row.size.y > 0.0, "The first row is laid out")
    var drawn := SaPopupRect.of_anchor(row)
    assert_almost_eq(drawn.size.y, row.size.y * docker.content_scale_factor, 0.01, "and drawn a quarter taller on the host")
    var low := Vector2(drawn.get_center().x, drawn.position.y + row.size.y * 1.1)
    assert_eq(flyout.row_at(low), [0, false], "A point past the row's own height but inside the drawn row is its lower half")
    flyout.hide()
