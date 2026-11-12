## A tool dropped on a maximised toolbox is placed by the buttons as they are
## drawn, not by rectangles a fifth smaller.
##
## The claim: `release_target` read a button as
## `Rect2(btn.get_screen_position(), btn.size)` and `drop_area_screen_rect` read
## the scroll the same way, a corner on the host and a size in the docker's units.
## On a maximised toolbox those are four fifths of the drawn size, so a release in
## the last fifth of a button found no button, and the capture step aimed with the
## same sum, so no scenario could show it.
##
## Every rectangle here is measured with `SaPopupRect.of_anchor`, which is what
## the drawn control is on the host, and the docker is maximised through
## `SaDockerMaximise.toggle`, the chord's own mechanism.
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


func before_each() -> void:
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "D68Host"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


## A maximised window holding two tool buttons in a column, the shape
## `release_target` reads with one column.
func _maximised_column() -> Dictionary:
    var docker := Window.new()
    docker.title = "Probe Toolbox"
    docker.position = Vector2i(200, 100)
    docker.size = Vector2i(220, 420)
    _host.add_child(docker)
    SaUI.apply_to_window(docker)
    var buttons := {}
    for i in 2:
        var button := Button.new()
        button.position = Vector2(8.0, 40.0 + 48.0 * i)
        button.size = Vector2(40.0, 40.0)
        docker.add_child(button)
        buttons[StringName("group_%d" % i)] = button
    SaDockerMaximise.toggle(docker)
    return {"docker": docker, "buttons": buttons}


## The unit's proof for the buttons: nine tenths down the first drawn button is
## after that group, and 0.3 of it is a group of its own before it, the thirds
## `button_drop_target` reads.
func test_a_release_is_read_against_the_button_as_drawn() -> void:
    var scene := _maximised_column()
    var docker: Window = scene["docker"]
    var buttons: Dictionary = scene["buttons"]
    assert_almost_eq(docker.content_scale_factor, SaDockerMaximise.MAXIMISED_SCALE, 0.0001, "The toolbox is maximised")

    var groups := [["brush", "eraser"], ["marquee", "lasso"]]
    var names := ["group_0", "group_1"]
    var drawn := SaPopupRect.of_anchor(buttons[&"group_0"])
    assert_almost_eq(drawn.size.y, 40.0 * docker.content_scale_factor, 0.01, "The first button is drawn a quarter taller")

    var low := Vector2(drawn.get_center().x, drawn.position.y + drawn.size.y * 0.9)
    assert_eq(
        SaToolBoxGroups.release_target(low, groups, names, {}, buttons, 1, Rect2()),
        [1, 0, true],
        "Nine tenths down the drawn button is its last third, a group of its own after it"
    )
    var high := Vector2(drawn.get_center().x, drawn.position.y + drawn.size.y * 0.3)
    assert_eq(
        SaToolBoxGroups.release_target(high, groups, names, {}, buttons, 1, Rect2()),
        [0, 0, true],
        "and 0.3 of it is its first third, a group of its own before it"
    )


## The capture aims where the painter would: the centre of the drawn button.
## With the old sum the centre sat at two fifths of the drawn button, and every
## `along` a scenario asked for was four fifths of itself.
##
## The capture holds no Control to measure. It aims at the
## rectangle `toolbox_report` hands it, so the claim is asked of the report and
## of the aim the capture takes from it, on a real toolbox with its tools.
func test_the_capture_aims_at_the_drawn_centre() -> void:
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.name = "D68AimedToolBox"
    docker.size = Vector2i(220, 420)
    _host.add_child(docker)
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    SaDockerMaximise.toggle(docker)
    assert_almost_eq(docker.content_scale_factor, SaDockerMaximise.MAXIMISED_SCALE, 0.0001, "The toolbox is maximised")

    var button := docker.button_for_tool("brush")
    assert_true(button != null, "The brush has a button")
    var drawn := SaPopupRect.of_anchor(button)
    var entry := SaToolBoxCapture._button_entry(docker, &"paint")
    assert_true(entry.has("rect"), "The report says where the paint button is drawn")
    var reported := SaToolBoxCapture._rect_of(entry["rect"])
    assert_true(reported.is_equal_approx(drawn), "and it is the button as drawn on the host")
    assert_true(
        reported.size.is_equal_approx(button.size * docker.content_scale_factor),
        "a quarter larger than the button's own size, not the size in the docker's units"
    )
    assert_true(
        SaToolBoxCapture._aim_at(docker, entry).is_equal_approx(drawn.get_center()), "The aim is the centre of the drawn button"
    )


## The dark area under the buttons is the scroll as drawn, so a release in its
## last fifth is still a group of its own rather than the tool put back.
func test_the_drop_area_is_the_scroll_as_drawn() -> void:
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.name = "D68ToolBox"
    docker.size = Vector2i(220, 420)
    _host.add_child(docker)
    var scroll := docker.get_node_or_null("Control/VBoxContainer/Scroll") as Control
    assert_true(scroll != null, "The toolbox has its scroll")

    SaDockerMaximise.toggle(docker)
    assert_almost_eq(docker.content_scale_factor, SaDockerMaximise.MAXIMISED_SCALE, 0.0001, "The toolbox is maximised")
    var area := docker.drop_area_screen_rect()
    assert_true(area.size.x > 0.0, "and has a drop area")
    assert_true(
        area.size.is_equal_approx(scroll.size * docker.content_scale_factor),
        "a quarter larger than the scroll's own size, which is the scroll as drawn"
    )
