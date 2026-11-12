## The reference board zooms without a scroll wheel.
##
## The quick zoom chord held with a left drag, the zoom in chord and a pinch
## each zoom the board, and the canvas's view keeps its zoom through all three.
## Built outside the tree as the other suites here are, because a `Window` in
## the tree hangs a headless run, so the held Space is the gestures' own seam
## rather than a key no headless run can hold. The running app's side is
## `scenarios/the-reference-board-zooms-without-a-scroll-wheel.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REFERENCE_IMAGE := "res://ui/icon.png"


## One picture on a board of 800 by 400 at zoom 1, with the pointer moved onto
## it so the board is the one under the pointer, and Space held when *space*.
func _docker(space: bool = false) -> ReferenceDocker:
    var docker := ReferenceDocker.new()
    docker.board_view.size = Vector2(800, 400)
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE]))
    var board := docker.board()
    board.pictures[0].rect = Rect2(Vector2.ZERO, Vector2(100.0, 100.0))
    board.zoom = 1.0
    board.offset = Vector2(20, 150)
    docker.board_view.deselect()
    var view := docker.board_view
    var keys := func(key: int) -> bool: return space and key == KEY_SPACE
    view.zoom = ReferenceZoomGestures.new(func() -> bool: return view.inside, view.changed.emit.bind(false), keys)
    _move(docker, Vector2(400, 200))
    return docker


func _move(docker: ReferenceDocker, at: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = at
    docker.board_view.input(event)


func _button(docker: ReferenceDocker, at: Vector2, pressed: bool, ctrl: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.ctrl_pressed = ctrl
    docker.board_view.input(event)


## The canvas's zoom in and out commands on a machine with a fake view, the
## way the router's chords reach them, with the surface, the machine and the
## registry the suite tears down.
func _commands() -> Array:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var registry := SaCommandRegistry.new()
    # Kept in the answer, because a bound handler holds no reference to it.
    var commands := SaShortcutCommands.new(func() -> ToolMachine: return machine, Callable(), Callable(), null)
    commands.register_into(registry)
    return [surface, machine, registry, commands]


func test_the_quick_zoom_chord_with_a_drag_right_zooms_about_the_press() -> void:
    var quick := SaShortcutStore.chords_for(ReferenceZoomGestures.QUICK_ZOOM)
    assert_true(quick.has("Ctrl+Space"), "The profile's quick zoom is Ctrl+Space")
    var docker := _docker(true)
    var view := docker.board_view
    var board := docker.board()
    var held := _commands()
    var canvas_zoom: float = held[0].view.get_zoom()
    var press := Vector2(70, 200)
    var under := board.to_board(press)
    _button(docker, press, true, true)
    assert_true(view.busy(), "The press with Ctrl+Space held starts the zoom drag")
    _move(docker, press + Vector2(50, 0))
    _move(docker, press + Vector2(100, 0))
    _button(docker, press + Vector2(100, 0), false, true)
    assert_true(board.zoom > 1.0, "A drag of 100 pixels right zooms the board in")
    assert_almost_eq(board.zoom, ReferenceZoomGestures.drag_zoom(Vector2(100, 0), view.size), 1e-4, "by the drag's factor")
    assert_true(board.to_board(press).distance_to(under) < 1e-3, "The point under the press stays under it")
    assert_true(view.selection.held(board).is_empty(), "The drag drew no selection box and picked nothing")
    assert_false(view.busy(), "The lift ends it")
    assert_almost_eq(held[0].view.get_zoom(), canvas_zoom, 1e-6, "The canvas keeps its zoom")
    Fixtures.teardown(held[0], held[1])
    docker.free()


func test_a_drag_left_or_down_zooms_out() -> void:
    assert_true(ReferenceZoomGestures.drag_zoom(Vector2(-100, 0), Vector2(800, 400)) < 1.0, "Left is out")
    assert_true(ReferenceZoomGestures.drag_zoom(Vector2(0, 100), Vector2(800, 400)) < 1.0, "Down is out")
    assert_true(ReferenceZoomGestures.drag_zoom(Vector2(0, -100), Vector2(800, 400)) > 1.0, "Up is in")


func test_ctrl_and_a_left_drag_without_space_is_still_the_box() -> void:
    var docker := _docker(false)
    var view := docker.board_view
    _button(docker, Vector2(300, 50), true, true)
    assert_true(view.selection.drawing, "Ctrl with no Space held is the adding box, as the box selection has it")
    _button(docker, Vector2(300, 50), false, true)
    assert_almost_eq(docker.board().zoom, 1.0, 1e-6, "and zooms nothing")
    docker.free()


func test_the_zoom_in_chord_over_the_board_zooms_the_board_and_not_the_canvas() -> void:
    var docker := _docker()
    var board := docker.board()
    var held := _commands()
    var registry: SaCommandRegistry = held[2]
    var canvas_zoom: float = held[0].view.get_zoom()
    registry.get_descriptor(&"view_zoom_in").handler.call()
    assert_almost_eq(board.zoom, ReferencePictureView.ZOOM_STEP, 1e-6, "The board zooms by ZOOM_STEP")
    assert_almost_eq(held[0].view.get_zoom(), canvas_zoom, 1e-6, "and the canvas keeps its zoom")
    registry.get_descriptor(&"view_zoom_out").handler.call()
    assert_almost_eq(board.zoom, 1.0, 1e-6, "Zoom out steps it back")
    docker.board_view.pointer_left()
    registry.get_descriptor(&"view_zoom_in").handler.call()
    assert_almost_eq(board.zoom, 1.0, 1e-6, "With the pointer off the board the chord is the canvas's")
    assert_true(held[0].view.get_zoom() > canvas_zoom, "which zooms")
    Fixtures.teardown(held[0], held[1])
    docker.free()


func test_a_pinch_zooms_about_its_centre() -> void:
    var docker := _docker()
    var view := docker.board_view
    var board := docker.board()
    var held := _commands()
    var canvas_zoom: float = held[0].view.get_zoom()
    var magnify := InputEventMagnifyGesture.new()
    magnify.position = Vector2(400, 200)
    magnify.factor = 1.5
    var under := board.to_board(magnify.position)
    view.input(magnify)
    assert_almost_eq(board.zoom, 1.5, 1e-6, "A touchpad's pinch zooms by its factor")
    assert_true(board.to_board(magnify.position).distance_to(under) < 1e-3, "about its centre")
    for finger in 2:
        var touch := InputEventScreenTouch.new()
        touch.index = finger
        touch.pressed = true
        touch.position = Vector2(350 + finger * 100, 200)
        view.input(touch)
    var drag := InputEventScreenDrag.new()
    drag.index = 1
    drag.position = Vector2(550, 200)
    under = board.to_board(Vector2(450, 200))
    view.input(drag)
    assert_almost_eq(board.zoom, 3.0, 1e-4, "Two fingers spread to twice their distance double it")
    assert_true(board.to_board(Vector2(450, 200)).distance_to(under) < 1e-3, "about their midpoint")
    assert_almost_eq(held[0].view.get_zoom(), canvas_zoom, 1e-6, "The canvas keeps its zoom")
    Fixtures.teardown(held[0], held[1])
    docker.free()


func test_the_maximise_stands_down_over_the_board_while_it_shares_the_chord() -> void:
    var docker := _docker()
    var shares := SaShortcutStore.chords_for(ReferenceZoomGestures.MAXIMISE).has("Ctrl+Space")
    var yields := ReferenceZoomGestures.shares_the_quick_zoom()
    assert_eq(yields, shares, "Over the board, the maximise yields only when the chords meet")
    docker.board_view.pointer_left()
    assert_false(ReferenceZoomGestures.shares_the_quick_zoom(), "Off the board it never yields")
    docker.free()
