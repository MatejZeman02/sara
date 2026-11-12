## The Minimap docker's arithmetic: where the picture sits, where the view's
## outline lands on it, and where a click takes the view.
##
## The docker is a Window, so it is built detached and its static maths tested
## against a fake view. What it draws is the morning's look, in
## scenarios/adjust-inside-a-selection.json.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")


func test_the_picture_is_fitted_and_centred_in_its_box() -> void:
    var rect := MinimapDocker.picture_rect(Vector2(200, 200), Vector2i(1000, 500))
    assert_eq(rect, Rect2(0, 50, 200, 100), "A wide picture fills the width and sits in the middle")
    var tall := MinimapDocker.picture_rect(Vector2(200, 200), Vector2i(500, 1000))
    assert_eq(tall, Rect2(50, 0, 100, 200), "and a tall one fills the height")
    assert_eq(MinimapDocker.picture_rect(Vector2(200, 200), Vector2i.ZERO), Rect2(), "No document, no picture")


func test_map_and_document_coordinates_are_inverses() -> void:
    var rect := Rect2(0, 50, 200, 100)
    var size := Vector2i(1000, 500)
    var on_map := MinimapDocker.document_to_map(Vector2(500, 250), rect, size)
    assert_eq(on_map, Vector2(100, 100), "The document's middle is the picture's middle")
    var back := MinimapDocker.map_to_document(on_map, rect, size)
    assert_eq(back, Vector2(500, 250), "and it maps back")


func test_the_view_outline_is_the_four_corners_through_the_view() -> void:
    var view := SaTestFixtures.FakeView.new()
    view.viewport_size = Vector2(1000, 800)
    view.zoom = 2.0
    view.pan = Vector2(-200, -100)

    var corners := MinimapDocker.view_corners(view)

    assert_eq(corners.size(), 4, "Four corners")
    assert_eq(corners[0], Vector2(100, 50), "The top left of the screen is where the pan and zoom put it")
    assert_eq(corners[2], Vector2(600, 450), "and the bottom right likewise")


func test_a_click_centres_the_view_on_that_document_point() -> void:
    var view := SaTestFixtures.FakeView.new()
    view.viewport_size = Vector2(1000, 800)
    view.zoom = 2.0

    MinimapDocker.centre_view_on(view, Vector2(300, 200))

    var middle := view.screen_to_document(Vector2(500, 400))
    assert_almost_eq(middle.x, 300.0, 1e-4, "The point is under the middle of the view")
    assert_almost_eq(middle.y, 200.0, 1e-4, "on both axes")

    view.rotation = PI / 2.0
    MinimapDocker.centre_view_on(view, Vector2(300, 200))
    var turned := view.screen_to_document(Vector2(500, 400))
    assert_almost_eq(turned.x, 300.0, 1e-3, "and a rotated view centres the same point")


func test_the_docker_builds_detached_with_its_parts() -> void:
    var docker := MinimapDocker.new()
    assert_eq(String(docker.name), "MinimapDocker", "Named for the layout store")
    assert_not_null(docker.find_child("Picture", true, false), "with the picture")
    assert_not_null(docker.find_child("ViewOverlay", true, false), "and the overlay over it")
    docker.free()


## A mirror is a view property, so the maths is the view's and the map's
## job is to agree with it.
func test_a_flip_mirrors_the_picture_about_the_middle_of_the_view() -> void:
    var view := SaTestFixtures.FakeView.new()
    view.viewport_size = Vector2(1000, 800)
    var before := view.document_to_screen(Vector2(100, 200))
    assert_eq(before, Vector2(100, 200), "Unmirrored, a document point is where the pan puts it")

    view.flip_view(true)

    assert_eq(view.get_flip(), Vector2(-1, 1), "The horizontal sign is the flip")
    var after := view.document_to_screen(Vector2(100, 200))
    assert_eq(after, Vector2(900, 200), "and the point lands mirrored about the middle of the view")
    assert_eq(view.screen_to_document(after), Vector2(100, 200), "The way back is the same signs")


## The mirror is on the screen rather than in the document, which is why the
## rotation is negated with it. A turned view mirrors to its own reflection.
func test_a_flip_mirrors_a_turned_view_on_the_screen() -> void:
    var view := SaTestFixtures.FakeView.new()
    view.viewport_size = Vector2(1000, 800)
    view.rotation = PI / 2.0
    var before := view.document_to_screen(Vector2(100, 0))

    view.flip_view(true)

    var after := view.document_to_screen(Vector2(100, 0))
    assert_almost_eq(after.x, 1000.0 - before.x, 1e-3, "The point is mirrored about the middle")
    assert_almost_eq(after.y, before.y, 1e-3, "and nothing moves along the other axis")
    assert_almost_eq(view.get_rotation(), -PI / 2.0, 1e-6, "The turn is reversed, which is what a mirror does to one")


func test_flipping_twice_puts_the_view_back() -> void:
    var view := SaTestFixtures.FakeView.new()
    view.viewport_size = Vector2(1000, 800)
    view.zoom = 3.0
    view.rotation = 0.4
    view.pan = Vector2(120, -60)

    view.flip_view(false)
    view.flip_view(false)

    assert_eq(view.get_flip(), Vector2.ONE, "Both signs are back")
    assert_almost_eq(view.get_rotation(), 0.4, 1e-6, "and so is the turn")
    assert_almost_eq(view.get_pan().x, 120.0, 1e-3, "and the pan, because both flips were about the same point")
    assert_almost_eq(view.get_pan().y, -60.0, 1e-3, "on both axes")


func test_the_map_mirrors_with_the_view() -> void:
    var size := Vector2i(1000, 500)
    var mirrored := MinimapDocker.mirror_point(Vector2(200, 100), size, Vector2(-1, 1))
    assert_eq(mirrored, Vector2(800, 100), "A point 200 from the left draws 200 from the right")
    assert_eq(MinimapDocker.mirror_point(mirrored, size, Vector2(-1, 1)), Vector2(200, 100), "and the mirror is its own inverse")
    assert_eq(
        MinimapDocker.mirror_point(Vector2(200, 100), size, Vector2(1, -1)),
        Vector2(200, 400),
        "The vertical flip is the other axis"
    )
    assert_eq(MinimapDocker.mirror_point(Vector2(200, 100), size, Vector2.ONE), Vector2(200, 100), "and no flip moves nothing")


func test_the_docker_carries_a_button_per_axis() -> void:
    var docker := MinimapDocker.new()
    assert_not_null(docker.find_child("FlipHorizontal", true, false), "One button for the horizontal mirror")
    assert_not_null(docker.find_child("FlipVertical", true, false), "and one for the vertical")
    var report := docker.flip_report()
    assert_false(bool(report["horizontal"]), "With no canvas the report says unmirrored")
    assert_false(bool(report["vertical"]), "on both axes")
    docker.free()
