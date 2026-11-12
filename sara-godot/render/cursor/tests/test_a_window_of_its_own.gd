## A docker let out of the main window owns the pixels it covers.
##
## With embedded subwindows off, every docker is a window of
## the operating system stacked over the main one, and the brush cursor Sara
## draws is drawn in the main window. So the same pixel is still over the canvas
## underneath the docker, the ring was claimed there and the OS cursor was hidden
## for a cursor the docker covers. The painter had no pointer at all over their
## own docker, which is what the note reports and what the capture reads.
##
## **The half that needs a let-out window is the capture**,
## `scenarios/the-cursor-hides-under-a-window-with-subwindows-off.json`. A
## suite cannot build one: adding a `Window` to the scene tree while the root
## viewport does not embed it maps a real OS window and stalls the run until the
## watchdog fires, which is the rule `render/cursor/tests/test_cursor_modes.gd` states at
## its own fixture. What is here is everything the fixture can reach: the walk
## that finds those windows, the rectangle one of them is placed by, and the
## promise that a painter who has not turned the switch off sees nothing change.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

var _host: Node = null
var _previous_embedding: bool = true
var _previous_mode: String = "auto"


## Adding a Window to the scene tree is only safe while the root viewport embeds
## subwindows, so it is forced here and put back afterwards. The host is parented
## to an autoload rather than to the root, because the runner calls this from its
## own `_ready` and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    _previous_mode = SaSettings.software_cursor
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "WindowOfItsOwnTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaSettings.software_cursor = _previous_mode
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


func _window() -> Window:
    var window := Window.new()
    window.borderless = true
    window.size = Vector2i(1920, 1080)
    _host.add_child(window)
    window.show()
    return window


## The docker the default profile has, 200 by 200 at (400, 400) inside *window*.
func _embedded_docker(window: Window) -> Window:
    var docker := Window.new()
    docker.borderless = true
    docker.position = Vector2i(400, 400)
    docker.size = Vector2i(200, 200)
    window.add_child(docker)
    docker.show()
    return docker


## The default profile draws nothing differently, which is the promise the new
## walk has to keep: with every docker embedded, there is no window of its own in
## the tree at all, so the four rulers above answer exactly as they did.
func test_a_painter_who_embeds_their_dockers_sees_nothing_change() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var window := _window()
    _embedded_docker(window)

    assert_true(
        SaCursorPolicy.windows_of_their_own(tree.root).is_empty(),
        "An embedded docker is not a window of its own, so the walk finds nothing"
    )
    assert_false(
        SaCursorPolicy.pointer_is_over_a_window_of_its_own(tree.root, Vector2(500, 500)),
        "and no point in the root is handed to the system's pointer on its account"
    )


## A `Window` taken out of the tree reports `is_embedded()` false, the way a
## let-out docker does, and the walk is over the tree, so it is not a candidate.
## Windows are found where they are shown rather than by asking every object
## holding one.
func test_a_window_out_of_the_tree_is_not_walked() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var host := Node.new()
    var loner := Window.new()
    loner.borderless = true
    loner.position = Vector2i(1000, 600)
    loner.size = Vector2i(300, 400)
    host.add_child(loner)
    loner.show()

    assert_false(loner.is_embedded(), "A Window outside the tree stands in for one in its own OS window")
    assert_true(
        SaCursorPolicy.windows_of_their_own(tree.root).is_empty(), "and the walk, which is over the tree, does not find it"
    )

    loner.free()
    host.free()


## Asking about a window never answers with that window, and the root window is
## never a candidate for a walk rooted at it: a window is in front of what it
## sits in rather than over it.
func test_the_asked_window_is_never_one_of_its_own() -> void:
    var tree := Engine.get_main_loop() as SceneTree

    assert_true(
        SaCursorPolicy.windows_of_their_own(tree.root, tree.root).is_empty(),
        "The root is the walk's starting point and not a window over itself"
    )
    assert_true(SaCursorPolicy.windows_of_their_own(tree.root, null).is_empty(), "and a walk with nothing asked about finds none")


## Where a window of its own sits, as a rectangle in the asked window's space,
## which is what turns "a docker is over the screen" into "a docker is over this
## point". A window of its own is placed in screen pixels, so both ends of the
## conversion go through the screen transform rather than through `position`
## alone.
##
## The fixture is an embedded docker rather than a let-out one, and that is the
## only shape a suite can build: it is the transform on the far end that is being
## read, and an embedded docker has one that is not the identity.
func test_a_window_is_placed_in_the_asked_windows_space() -> void:
    var window := _window()
    var docker := _embedded_docker(window)
    var rect := SaCursorPolicy.rect_in(window, docker)

    assert_almost_eq(rect.position.x, 400.0, 0.01, "The docker's own corner is read through the transforms")
    assert_almost_eq(rect.position.y, 400.0, 0.01, "on both axes")
    assert_almost_eq(rect.size.x, 200.0, 0.01, "and its size comes out as pixels rather than as a scale")
    assert_almost_eq(rect.size.y, 200.0, 0.01, "on both axes")
    assert_true(rect.has_point(Vector2(500, 500)), "so a point inside it is inside the rectangle")
    assert_false(rect.has_point(Vector2(300, 500)), "and a point beside it is not")
    assert_eq(SaCursorPolicy.rect_in(null, docker), Rect2(), "A missing window has nothing placed in it")
    assert_eq(SaCursorPolicy.rect_in(window, null), Rect2(), "and nothing is placed from a missing one")
