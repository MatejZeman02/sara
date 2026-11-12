## Two fingers on the canvas pan, pinch and turn the view, and one finger pans
## and never paints, so a palm never paints.
##
## The gestures go through ToolMachine against the fake view, which needs a
## surface with an easel, so the suite as a whole wants a GPU. The check on a
## real screen is a separate check.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


func _machine(surface: SaSurface) -> Array:
    var tm := ToolMachine.new()
    tm.name = "ToolMachine"
    tm._ready()
    tm.surface = surface
    var tool := SaTestFixtures.FakeTool.new()
    tm.register_tool(&"fake", tool)
    return [tm, tool]


func _land(tm: ToolMachine, index: int, at: Vector2, pressed: bool = true) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = at
    event.pressed = pressed
    tm.handle_input(event)


func _drag(tm: ToolMachine, index: int, at: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = at
    tm.handle_input(event)


## Where the document point that began under *screen* is on screen now.
func _follows(view: SaView, document_point: Vector2) -> Vector2:
    return view.document_to_screen(document_point)


func test_two_fingers_dragged_together_pan_the_view_their_way() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var pair := _machine(surface)
    var tm: ToolMachine = pair[0]
    var tool: SaTestFixtures.FakeTool = pair[1]

    _land(tm, 0, Vector2(400, 400))
    _land(tm, 1, Vector2(600, 400))
    _drag(tm, 0, Vector2(430, 420))
    _drag(tm, 1, Vector2(630, 420))

    assert_almost_eq(view.pan.x, 30.0, 1e-4, "The midpoint's thirty to the right pans thirty to the right")
    assert_almost_eq(view.pan.y, 20.0, 1e-4, "and its twenty down pans twenty down")
    assert_almost_eq(view.zoom, 1.0, 1e-6, "The distance kept, the zoom is kept")
    assert_almost_eq(view.rotation, 0.0, 1e-6, "and the angle kept, the turn is kept")
    assert_true(tool.events.is_empty(), "The tool saw none of it")

    Fixtures.teardown(surface, tm)


func test_two_fingers_spreading_zoom_about_their_midpoint() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var pair := _machine(surface)
    var tm: ToolMachine = pair[0]

    var middle := Vector2(500, 400)
    var under := view.screen_to_document(middle)
    _land(tm, 0, Vector2(450, 400))
    _land(tm, 1, Vector2(550, 400))
    _drag(tm, 0, Vector2(400, 400))
    _drag(tm, 1, Vector2(600, 400))

    assert_almost_eq(view.zoom, 2.0, 1e-6, "Twice the distance is twice the zoom")
    assert_true(_follows(view, under).distance_to(middle) < 1e-3, "about the midpoint, which stays put")
    assert_almost_eq(view.rotation, 0.0, 1e-6, "and a straight spread does not turn")

    Fixtures.teardown(surface, tm)


func test_two_fingers_turning_rotate_the_view_about_their_midpoint() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var pair := _machine(surface)
    var tm: ToolMachine = pair[0]

    var middle := Vector2(500, 400)
    var under := view.screen_to_document(middle)
    _land(tm, 0, Vector2(400, 400))
    _land(tm, 1, Vector2(600, 400))
    # Thirty degrees clockwise on screen, y down, the arm keeping its length.
    var arm := Vector2(100, 0).rotated(deg_to_rad(30.0))
    _drag(tm, 0, middle - arm)
    _drag(tm, 1, middle + arm)

    assert_almost_eq(view.rotation, deg_to_rad(30.0), 1e-5, "The view turns the thirty degrees the fingers did")
    assert_almost_eq(view.zoom, 1.0, 1e-5, "and the kept distance keeps the zoom")
    assert_true(_follows(view, under).distance_to(middle) < 1e-3, "about the midpoint")

    Fixtures.teardown(surface, tm)


## A turn of two degrees while pinching is a hand's wobble, not a request, so
## it snaps back to square as the Shift middle drag does.
func test_a_small_wobble_while_pinching_leaves_the_view_square() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var pair := _machine(surface)
    var tm: ToolMachine = pair[0]

    _land(tm, 0, Vector2(450, 400))
    _land(tm, 1, Vector2(550, 400))
    var arm := Vector2(100, 0).rotated(deg_to_rad(2.0))
    _drag(tm, 0, Vector2(500, 400) - arm)
    _drag(tm, 1, Vector2(500, 400) + arm)

    assert_almost_eq(view.rotation, 0.0, 1e-6, "Two degrees snaps to none")
    assert_almost_eq(view.zoom, 2.0, 1e-4, "and the pinch still zooms")

    Fixtures.teardown(surface, tm)


func test_the_gesture_ends_when_either_finger_lifts() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var pair := _machine(surface)
    var tm: ToolMachine = pair[0]
    var tool: SaTestFixtures.FakeTool = pair[1]

    _land(tm, 0, Vector2(400, 400))
    _land(tm, 1, Vector2(600, 400))
    _drag(tm, 1, Vector2(620, 400))
    var pan := view.pan
    var zoom := view.zoom
    _land(tm, 0, Vector2(400, 400), false)
    _drag(tm, 1, Vector2(800, 600))

    assert_eq(view.pan, pan, "The finger left behind does not pan")
    assert_almost_eq(view.zoom, zoom, 1e-6, "nor zoom")
    assert_true(tool.events.is_empty(), "nor paint")

    Fixtures.teardown(surface, tm)


## One finger never paints on the canvas, so a palm never paints, and
## now its drag pans. Godot also hands the finger over as an
## emulated mouse press and drag, and that copy is refused as well.
func test_one_finger_pans_and_paints_nothing() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var pair := _machine(surface)
    var tm: ToolMachine = pair[0]
    var tool: SaTestFixtures.FakeTool = pair[1]

    _land(tm, 0, Vector2(400, 400))
    _drag(tm, 0, Vector2(500, 450))
    _drag(tm, 0, Vector2(600, 500))
    _land(tm, 0, Vector2(600, 500), false)

    var press := InputEventMouseButton.new()
    press.device = InputEvent.DEVICE_ID_EMULATION
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = Vector2(400, 400)
    tm.handle_input(press)
    var motion := InputEventMouseMotion.new()
    motion.device = InputEvent.DEVICE_ID_EMULATION
    motion.position = Vector2(600, 500)
    motion.relative = Vector2(200, 100)
    tm.handle_input(motion)

    assert_eq(view.pan, Vector2(200, 100), "One finger pans by its drag")
    assert_almost_eq(view.zoom, 1.0, 1e-6, "nor zoom")
    assert_almost_eq(view.rotation, 0.0, 1e-6, "nor turn")
    assert_true(tool.events.is_empty(), "and neither it nor its mouse copy reached the tool")

    # A real mouse, device 0, still paints.
    press.device = 0
    tm.handle_input(press)
    assert_eq(tool.events.size(), 1, "A press from the mouse itself still reaches the tool")

    Fixtures.teardown(surface, tm)


## The sign the tool machine's comment names: Godot's delta is a scroll
## distance, against the fingers, so fingers moving right and down hand over a
## delta pointing left and up, and the picture moves right and down with them.
func test_a_trackpad_pan_moves_the_picture_the_way_the_fingers_go() -> void:
    var surface := Fixtures.make_surface()
    var view := surface.view as SaTestFixtures.FakeView
    var pair := _machine(surface)
    var tm: ToolMachine = pair[0]
    var tool: SaTestFixtures.FakeTool = pair[1]

    var pan := InputEventPanGesture.new()
    pan.delta = Vector2(-12, -5)
    pan.position = Vector2(500, 400)
    tm.handle_input(pan)

    assert_almost_eq(view.pan.x, 12.0, 1e-6, "Fingers going right carry the picture right")
    assert_almost_eq(view.pan.y, 5.0, 1e-6, "and going down carry it down")
    assert_true(tool.events.is_empty(), "and the tool never saw it")

    Fixtures.teardown(surface, tm)


## The canvas takes touch at the window as a view gesture, and so skips it on
## its own gui_input, where the same event would otherwise arrive twice.
func test_the_canvas_counts_a_touch_among_the_view_gestures() -> void:
    var canvas_script := load("res://render/main_canvas.gd")
    assert_true(canvas_script._is_view_gesture(InputEventScreenTouch.new()), "A landing finger is the view's")
    assert_true(canvas_script._is_view_gesture(InputEventScreenDrag.new()), "and so is a moving one")
