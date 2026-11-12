## A tool dragged out of a flyout and released over a maximised toolbox is placed
## by the point as drawn. The docker added the release's position, in its own
## units, to its corner on the host, so on a toolbox drawn a quarter larger the
## release landed short of the button under the pen. The flyout
## already took its release through the final transform.
##
## Embedded, the way `test_toolbox_drop_on_a_maximised_toolbox.gd` is.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

var _saved_override: float = -1.0
var _saved_user: float = 1.0
var _was_embedding: bool = false
var _host: Node = null


func before_each() -> void:
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "B3ToolboxHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


func test_a_release_in_a_buttons_far_part_lands_on_it() -> void:
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.name = "B3ScaledToolBox"
    docker.size = Vector2i(220, 420)
    _host.add_child(docker)
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    SaDockerMaximise.toggle(docker)
    assert_almost_eq(docker.content_scale_factor, SaDockerMaximise.MAXIMISED_SCALE, 0.0001, "The toolbox is maximised")

    var button := docker.button_for_tool("brush")
    assert_true(button != null, "The brush has a button")
    var local := button.get_global_rect()
    var far := local.position + local.size * Vector2(0.5, 0.9)
    var drawn := SaPopupRect.of_anchor(button)
    var landed := docker.release_point(far)
    assert_true(
        drawn.has_point(landed), "A release near the bottom of the button lands on it as drawn: %s in %s" % [landed, drawn]
    )
    assert_true(landed.is_equal_approx(drawn.position + drawn.size * Vector2(0.5, 0.9)), "at the same place along it the pen was")
