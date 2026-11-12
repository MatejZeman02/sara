## A list opened from a maximised docker is drawn at the docker's scale, and opens
## off the dropdown it came from rather than over it.
##
## The claim: the maximised Layers docker drew at 1.25
## and its blend list at 1.0, 1528 by 520 at (5, 528), "a fifth narrower than the
## dropdown it came from, and pushed up over the middle of the docker so that it
## covers that dropdown".
##
## The placement is asked of `SaPopupRect.under` without a tree first, because it
## is a question of three rectangles. Then the whole of it on an embedded docker
## maximised through `SaDockerMaximise.toggle`, the chord's own mechanism, with
## the two factors read back rather than a constant written here twice.
##
## Embedded on purpose, the way `test_choice_popup.gd` does it: without embedding
## a Window added to the tree maps a real OS window and the run blocks until the
## watchdog fires.
extends "res://tests/test_framework.gd"

const ROOM := Rect2i(0, 0, 1920, 1048)

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


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


## The ordinary case, which must not move: room below, so the list starts at
## the button's foot at the size it asked for.
func test_a_list_that_fits_below_opens_under_its_button() -> void:
    var at := SaPopupRect.under(Rect2(100.0, 200.0, 300.0, 30.0), Vector2i(300, 520), ROOM)
    assert_eq(at, Rect2i(100, 230, 300, 520), "Room below, so the list starts at the button's foot")


## The claim's own rectangle: a dropdown 1910 wide near the foot of a docker
## filling a 1048-high window, and a list of 520 that has no room under it.
func test_a_list_with_no_room_below_ends_at_the_top_of_its_button() -> void:
    var button := Rect2(5.0, 896.0, 1910.0, 34.0)
    var at := SaPopupRect.under(button, Vector2i(1910, 520), ROOM)
    assert_eq(at.end.y, 896, "The list ends where the button starts")
    assert_eq(at.size, Vector2i(1910, 520), "at its whole size, since there is room above")
    assert_false(Rect2(at).intersects(button), "and it covers none of the button")


## Neither side holds the whole list, so it takes the larger side and scrolls,
## rather than the engine's fit, which lays it over the button.
func test_a_list_that_fits_neither_side_takes_the_larger_one() -> void:
    var room := Rect2i(0, 0, 800, 600)
    var high := SaPopupRect.under(Rect2(0.0, 400.0, 200.0, 30.0), Vector2i(200, 520), room)
    assert_eq(high, Rect2i(0, 0, 200, 400), "More room above, so the list fills it and ends on the button")
    var low := SaPopupRect.under(Rect2(0.0, 150.0, 200.0, 30.0), Vector2i(200, 520), room)
    assert_eq(low, Rect2i(0, 180, 200, 420), "More room below, so the list fills that instead")


## The unit's proof: maximise a docker holding a dropdown, open its list, and
## the two factors are equal, the list is the dropdown's width in the host's
## units, and it lies off the dropdown. Then back, and the list is at 1.0 again.
func test_the_list_on_a_maximised_docker_takes_its_factor_and_its_width() -> void:
    _host = Node.new()
    _host.name = "D66Host"
    EventBus.add_child(_host)

    var docker := Window.new()
    docker.title = "Maximised Docker"
    docker.position = Vector2i(200, 100)
    docker.size = Vector2i(360, 380)
    _host.add_child(docker)
    SaUI.apply_to_window(docker)

    var anchor := Control.new()
    anchor.position = Vector2(8.0, 40.0)
    anchor.size = Vector2(344.0, 24.0)
    docker.add_child(anchor)

    var popup := SaChoicePopup.new()
    popup.clear()
    popup.add_row(&"one", "One")
    popup.add_row(&"two", "Two")
    anchor.add_child(popup)

    SaDockerMaximise.toggle(docker)
    assert_almost_eq(docker.content_scale_factor, SaDockerMaximise.MAXIMISED_SCALE, 0.0001, "The docker is maximised")

    popup.open_under(anchor)
    var span := SaPopupRect.of_anchor(anchor)
    assert_almost_eq(
        popup.content_scale_factor, docker.content_scale_factor, 0.0001, "The list draws at the maximised docker's factor"
    )
    assert_almost_eq(span.size.x, anchor.size.x * SaDockerMaximise.MAXIMISED_SCALE, 0.01, "The dropdown is wider on the host")
    assert_eq(popup.size.x, roundi(span.size.x), "and the list is the dropdown's width on the host, not in the docker's units")
    assert_false(Rect2(Vector2(popup.position), Vector2(popup.size)).intersects(span), "and it lies off the dropdown")
    assert_eq(popup.position.y, ceili(span.end.y), "under it, since a two-row list has room there")
    popup.hide()

    SaDockerMaximise.toggle(docker)
    popup.open_under(anchor)
    assert_almost_eq(popup.content_scale_factor, docker.content_scale_factor, 0.0001, "Back at its size, the list follows")
    assert_almost_eq(popup.content_scale_factor, 1.0, 0.0001, "which is 1.0 on an embedded docker at a base of one")
    assert_eq(popup.size.x, int(anchor.size.x), "and the list is the dropdown's own width again")
    popup.hide()
