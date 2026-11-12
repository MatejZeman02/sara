## A release that ends a tool drag stays handled in the window that took it, so
## the engine never hands it on to a window the drop has taken out of the tree.
##
## The claim: two scenarios each print `Condition
## "!is_inside_tree()" is true.` at `push_input`, from the capture's release. The
## flyout's `_input` marked the release handled and then cancelled the engine's
## drag, and a cancelled drag ends in `Window.update_mouse_cursor_state`, which
## pushes a motion through the root into the focused embedded window. `push_input`
## clears that window's handled flag on its way in, so the release went on to the
## flyout's GUI pass as if nobody had taken it, and since the rebuilt
## buttons out of the grid at once, the flyout hanging off one was out of the tree
## by then.
##
## In the tree and embedded, the way `test_flyout_on_a_maximised_toolbox`
## hosts its window, because the flag is only cleared in the root's focused
## embedded window, and a detached one has no root to push a motion through.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

var _order: Array = []
var _groups_raw: Variant = null
var _saved_override: float = -1.0
var _saved_user: float = 1.0
var _was_embedding: bool = false
var _host: Node = null
var _toolbox: ToolBoxDocker = null
var _button: Button = null
var _released: Array = []


func before_each() -> void:
    _order = SaSettings.get_layout_order(SaToolBoxGrid.CATEGORY)
    _groups_raw = SaSettings.get_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGroups.GROUPS_KEY)
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _released.clear()


## A failed case can leave a drag running and a button out of the tree, so both
## are put right before the host goes, and the profile a release may write too.
func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_cancel_drag()
    if _button != null and not _button.is_inside_tree():
        _button.free()
    _button = null
    if _host != null:
        _host.free()
        _host = null
    if _toolbox != null:
        _toolbox.free()
        _toolbox = null
    tree.root.gui_embed_subwindows = _was_embedding
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user
    SaSettings.set_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGroups.GROUPS_KEY, _groups_raw)
    SaSettings.set_layout_order(SaToolBoxGrid.CATEGORY, _order)


func _host_node() -> Node:
    _host = Node.new()
    _host.name = "D93Host"
    EventBus.add_child(_host)
    return _host


## A window holding one tool button with a flyout under it, the way
## `ToolBoxDocker._flyout_for` parents one, open on the paint group's rows.
func _flyout_scene() -> SaToolFlyout:
    _toolbox = ToolBoxDockerScript.new() as ToolBoxDocker
    _toolbox.rebuild_from_registry(Fixtures.make_tool_registry())
    var members: Array = _toolbox._visible_members(&"paint")
    var labels := PackedStringArray()
    for descriptor: SaToolDescriptor in members:
        labels.append(descriptor.display_name)

    var docker := Window.new()
    docker.title = "Probe Toolbox"
    docker.position = Vector2i(200, 100)
    docker.size = Vector2i(220, 420)
    _host_node().add_child(docker)
    SaUI.apply_to_window(docker)

    _button = Button.new()
    _button.position = Vector2(8.0, 40.0)
    _button.size = Vector2(40.0, 40.0)
    docker.add_child(_button)

    var flyout := SaToolFlyout.new()
    _button.add_child(flyout)
    flyout.open_beside(_button, members, labels, PackedStringArray())
    return flyout


## What the docker's rebuild does to the button a flyout hangs off: out of its
## parent at once, which takes the flyout out of the tree inside the release.
func _take_the_button_out(tool_id: String, _at: Vector2) -> void:
    _released.append(tool_id)
    _button.get_parent().remove_child(_button)


func _release(at: Vector2) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = false
    event.position = at
    event.global_position = at
    return event


## The unit's proof: the flyout takes the release, the drop takes its button out
## of the tree, and the release is still handled in the flyout afterwards, which
## is what keeps `push_input` from the GUI pass that checks the tree.
func test_a_release_on_a_flyout_is_still_handled_once_its_drop_has_taken_it_out_of_the_tree() -> void:
    var flyout := _flyout_scene()
    var tree := Engine.get_main_loop() as SceneTree
    var row := flyout.row_control(0)
    assert_true(row != null and row.is_inside_tree(), "The flyout is open with its rows in the tree")
    flyout.tool_released.connect(_take_the_button_out)
    flyout.grab_focus()
    assert_true(flyout.has_focus(), "and it is the focused embedded window, the one the cancelled drag pushes a motion into")

    row.force_drag({SaToolFlyout.DRAG_KEY: "brush"}, null)
    assert_true(tree.root.gui_is_dragging(), "A tool is in hand")

    flyout.push_input(_release(row.get_rect().get_center()), true)

    assert_eq(_released, ["brush"], "The release named the tool in hand")
    assert_false(flyout.is_inside_tree(), "and the drop took the flyout out of the tree")
    assert_false(tree.root.gui_is_dragging(), "The engine's drag is over")
    assert_true(flyout.is_input_handled(), "and the release is still handled in the window that took it")
