## The three cursor modes mean what their labels say.
##
## The hand check found two of them lying. *Never* still drew the ring and its
## crosshair over the OS pointer, and a tool's own picture, which today is the
## eyedropper's, stayed under the pointer wherever it went: the note is an
## eyedropper icon left over the Minimap after an ALT drag of it.
##
## Same fixture note as `test_mirrored_canvas_rect.gd`: the canvas has to be
## a live one in a real window, because everything here walks
## `SaCanvas.live_canvases()` and skips anything not in a tree. The half that
## needs the pointer to physically be somewhere is
## `scenarios/cursor-modes-mean-their-labels.json`, because Wayland will not
## let a capture place it.
##
## A tool's picture is put up only while the pointer is over the canvas, and
## the policy reads that pointer itself, so every canvas here comes with the
## suite's place for it over the canvas. The Windows desktop of 2026-10-01 had
## the live pointer nowhere near, and the eyedropper took no slot.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const RING: float = 12.0
## Over the canvas and clear of the docker below.
const ON_CANVAS := Vector2(100, 60)
## The centre of the embedded docker `_embedded_docker` puts at (400, 400).
const ON_DOCKER := Vector2(500, 500)

var _host: Node = null
var _previous_embedding: bool = true
var _previous_mode: String = "auto"


func before_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    _previous_mode = SaSettings.software_cursor
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "CursorModeTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaPointerDevice.suite_pointer = null
    SaCursorPolicy.clear_tool_cursor()
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


## A live canvas covering the whole of *window*, asking for a ring, with the
## pointer put over it at [constant ON_CANVAS].
func _canvas(window: Window) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    window.add_child(canvas)
    canvas.position = Vector2.ZERO
    canvas.size = Vector2(1920, 1080)
    canvas.cursor_ring_radius = RING
    var to_desktop: Transform2D = SaPointerDevice.desktop_transform(window)
    SaPointerDevice.suite_pointer = to_desktop * ON_CANVAS
    return canvas


## A docker-shaped embedded window over the canvas, 200 by 200 at (400, 400).
func _embedded_docker(window: Window) -> Window:
    var docker := Window.new()
    docker.borderless = true
    docker.position = Vector2i(400, 400)
    docker.size = Vector2i(200, 200)
    window.add_child(docker)
    docker.show()
    return docker


## *Never* is the system pointer and nothing drawn, in every window.
##
## The ring is the largest thing Sara draws and it was asked for whatever the
## setting said, so the painter who turned the software cursor off still got it.
func test_never_draws_nothing_over_a_canvas() -> void:
    var window := _window()
    _canvas(window)

    SaSettings.software_cursor = "auto"
    assert_almost_eq(SaCursorPolicy.canvas_ring_radius_at(window, ON_CANVAS), RING, 0.001, "The canvas asks for a ring")
    assert_eq(SaCursorPolicy.drawn_at(window, ON_CANVAS), &"ring", "and Auto draws it")

    SaSettings.software_cursor = "always"
    assert_eq(SaCursorPolicy.drawn_at(window, ON_CANVAS), &"ring", "Always draws it")

    SaSettings.software_cursor = "never"
    assert_eq(SaCursorPolicy.cursor_ring_radius_at(window, ON_CANVAS), -1.0, "Never asks for no ring at all")
    assert_eq(SaCursorPolicy.drawn_at(window, ON_CANVAS), &"system", "and leaves the OS cursor in charge")
    assert_almost_eq(
        SaCursorPolicy.canvas_ring_radius_at(window, ON_CANVAS),
        RING,
        0.001,
        "The canvas still asks for one, so the mode is what refuses it and nothing has to be put back"
    )


## *Always* is the ring over the canvas and the OS cursor everywhere else. A
## docker is a window over the canvas, not a hole in it, so the pixel belongs to
## the docker.
func test_a_docker_over_the_canvas_is_never_the_ring() -> void:
    var window := _window()
    _canvas(window)
    _embedded_docker(window)

    for mode: String in ["auto", "always", "never"]:
        SaSettings.software_cursor = mode
        assert_eq(SaCursorPolicy.drawn_at(window, ON_DOCKER), &"system", "%s leaves a docker to the OS cursor" % mode)


## A point outside the window is nobody's, which is what stops one window
## answering for another's pointer.
func test_a_point_outside_the_window_is_the_systems() -> void:
    var window := _window()
    _canvas(window)

    SaSettings.software_cursor = "always"
    assert_eq(SaCursorPolicy.drawn_at(window, Vector2(4000, 4000)), &"system", "Outside the window, nothing is drawn")
    assert_eq(SaCursorPolicy.drawn_at(null, ON_CANVAS), &"system", "and with no window there is nothing to draw in")


## A tool's picture belongs over the canvas and nowhere else. The note is the
## eyedropper's icon left over the Minimap, and an ALT drag is only how the
## painter notices: the pointer ends up over a docker without crossing the
## canvas on the way, so nothing asked the question again.
func test_a_tool_picture_is_over_the_canvas_only() -> void:
    var window := _window()
    var canvas := _canvas(window)
    _embedded_docker(window)
    var registry := Fixtures.make_tool_registry()
    var dropper := registry.get_descriptor(&"eyedropper")
    assert_not_null(dropper.cursor_texture, "the eyedropper names a picture, which is what this is about")

    SaCursorPolicy.apply_tool_cursor(canvas, dropper, dropper.cursor_shape)
    assert_true(SaCursorPolicy.tool_cursor_shows_at(window, ON_CANVAS), "The picture belongs over the canvas")
    assert_false(SaCursorPolicy.tool_cursor_shows_at(window, ON_DOCKER), "and not over a docker")
    assert_false(SaCursorPolicy.tool_cursor_shows_at(window, Vector2(4000, 4000)), "and not outside the window")

    # Never means Sara draws no pointer, and the picture is one Sara drew: the
    # display server only places it.
    # The tool's stock shape is the system's own and stays, which is why the
    # canvas still carries it while the slot is given back.
    SaSettings.software_cursor = "never"
    assert_false(SaCursorPolicy.tool_cursor_shows_at(window, ON_CANVAS), "Never takes the tool's own picture")
    SaCursorPolicy.sync_tool_cursor()
    assert_false(SaCursorPolicy.tool_cursor_state()["custom"], "and the slot is given back")
    assert_eq(int(canvas.mouse_default_cursor_shape), dropper.cursor_shape, "while the canvas keeps the tool's stock shape")
    SaSettings.software_cursor = "auto"
    assert_true(SaCursorPolicy.tool_cursor_shows_at(window, ON_CANVAS), "and Auto gives the picture back")


## A tool that names no picture has nothing to show anywhere, so the question is
## answered without asking where the pointer is.
func test_a_tool_without_a_picture_shows_none() -> void:
    var window := _window()
    var canvas := _canvas(window)
    var registry := Fixtures.make_tool_registry()
    var lasso := registry.get_descriptor(&"lasso")
    assert_null(lasso.cursor_texture, "the lasso names no picture")

    SaCursorPolicy.apply_tool_cursor(canvas, lasso, lasso.cursor_shape)
    assert_false(SaCursorPolicy.tool_cursor_shows_at(window, ON_CANVAS), "so there is nothing to show over the canvas")
    assert_false(SaCursorPolicy.tool_cursor_state()["custom"], "and no slot is held")


## The rectangle test the two above are built on, on its own.
func test_over_a_canvas_is_rectangles_and_nothing_else() -> void:
    var window := _window()
    _canvas(window)
    _embedded_docker(window)

    assert_true(SaCursorPolicy.pointer_is_over_a_canvas(window, ON_CANVAS), "The canvas owns its own pixels")
    assert_false(SaCursorPolicy.pointer_is_over_a_canvas(window, ON_DOCKER), "A docker over it owns the ones it covers")
    assert_false(SaCursorPolicy.pointer_is_over_a_canvas(window, Vector2(4000, 4000)), "Nothing owns a point off the window")
    assert_false(SaCursorPolicy.pointer_is_over_a_canvas(null, ON_CANVAS), "and no window owns anything")


## A freed canvas must not reach the display server.
##
## **A freed Object does not compare unequal to null in GDScript**, so the guard
## that reads `held != null and not is_instance_valid(held)` is false for
## exactly the case it was written for and the dangling reference goes on to the
## call. That cost a run of the whole suite: seventeen thousand assertions
## passed and `run_tests.sh` still exited 1, on one `SCRIPT ERROR` naming an
## argument "previously freed". `is_instance_valid` with nothing in front of it
## is the form that works, and this is what holds it.
func test_a_freed_canvas_is_dropped_rather_than_passed_on() -> void:
    var window := _window()
    var canvas := _canvas(window)
    var registry := Fixtures.make_tool_registry()
    SaCursorPolicy.apply_tool_cursor(canvas, registry.get_descriptor(&"eyedropper"), Control.CURSOR_CROSS)

    canvas.free()
    SaCursorPolicy.sync_tool_cursor()

    assert_null(SaCursorPolicy._tool_cursor_canvas, "The canvas is forgotten rather than passed on freed")
    # A canvas freed is a canvas that left the tree, and `SaCanvas._exit_tree`
    # gives the slot back on the way out, because the app's
    # shutdown is this very path and a picture left standing in a slot at exit
    # is two leaked texture RIDs. The slot stays held only when no canvas was
    # ever named, which `test_tool_cursor_picture` holds with a null one: with
    # no canvas there is no window to ask where the pointer is, and a picture
    # withheld on a guess is a tool whose cursor never appears.
    assert_false(SaCursorPolicy.tool_cursor_state()["custom"], "and the slot went back with the canvas it was over")


## The picture goes when the next tool names none, which is the path a tool
## change takes and the one that has to give the slot back.
##
## A descriptor cannot be freed under the policy the way a canvas can: it is
## `RefCounted`, so holding it keeps it alive. The guard for one is there
## because the field is typed `Object` and nothing stops a caller handing over
## something that is not.
func test_the_slot_goes_back_when_the_next_tool_names_no_picture() -> void:
    var window := _window()
    var canvas := _canvas(window)
    var registry := Fixtures.make_tool_registry()
    SaCursorPolicy.apply_tool_cursor(canvas, registry.get_descriptor(&"eyedropper"), Control.CURSOR_CROSS)
    assert_true(SaCursorPolicy.tool_cursor_state()["custom"], "the eyedropper takes a slot")

    SaCursorPolicy.apply_tool_cursor(canvas, registry.get_descriptor(&"lasso"), Control.CURSOR_CROSS)

    assert_false(SaCursorPolicy.tool_cursor_state()["custom"], "and the lasso, which names none, gives it back")
    assert_eq(canvas.mouse_default_cursor_shape, Control.CURSOR_CROSS, "with the stock shape still written")
