## A right press reaches the docker under it, and the canvas when no docker is
## under it.
##
## The defect was one engine rule. Godot moves the embedded subwindow focus on a
## left press and on nothing else, so every other button is handed to whichever
## docker already holds that focus and, when the point is not inside that one, to
## nobody at all. Measured through `Input.parse_input_event` with the toolbox at
## (700, 200): ten cold right presses on `SelectBtn` opened nothing, and the same
## press after one left press on the docker opened the flyout every time. The
## same rule left the canvas's own right press dead from startup, because a
## docker holds that focus before the painter has touched anything, so the Brush
## Presets docker and the tool context menu both answered nothing until a
## left click on the canvas had cleared it.
##
## The two answers are `MainDockers.docker_under`, which says whose press it is
## before the engine routes it, and `MainCanvas._is_right_button`, which is what
## keeps the copy the engine delivers afterwards from acting a second time. Both
## are asserted here, beside the non-embedded docker the router is right to leave
## alone. The delivery itself is a scenario, because no test can put a Window in
## this suite's tree.
extends "res://tests/test_framework.gd"

const MainDockersScript = preload("res://ui/main/main_dockers.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")


## A detached Window with a rectangle, which is all `docker_under` reads. In the
## tree it would map a real OS window and hang the run.
func _window(at: Vector2i, size: Vector2i) -> Window:
    var window := Window.new()
    window.position = at
    window.size = size
    return window


func test_the_docker_under_the_point_is_the_one_the_press_belongs_to() -> void:
    var toolbox := _window(Vector2i(700, 200), Vector2i(220, 420))
    var layers := _window(Vector2i(1200, 200), Vector2i(300, 400))
    var dockers: Array[Window] = [toolbox, layers]

    assert_eq(MainDockersScript.docker_under(dockers, Vector2(810, 390)), toolbox, "A point inside the toolbox is the toolbox's")
    assert_eq(
        MainDockersScript.docker_under(dockers, Vector2(1300, 300)), layers, "and one inside the layers docker is that one's"
    )
    toolbox.free()
    layers.free()


## Null is the answer that leaves the canvas its own press. Without it the fix
## would focus a docker for a click on the picture, which is the opposite of the
## complaint.
func test_a_point_on_no_docker_belongs_to_nobody() -> void:
    var toolbox := _window(Vector2i(700, 200), Vector2i(220, 420))
    var dockers: Array[Window] = [toolbox]

    assert_null(MainDockersScript.docker_under(dockers, Vector2(400, 700)), "A point on the canvas names no docker")
    assert_null(MainDockersScript.docker_under(dockers, Vector2(921, 390)), "and neither does one a texel past the edge")
    assert_null(MainDockersScript.docker_under([], Vector2(810, 390)), "An empty list answers nothing rather than failing")
    toolbox.free()


## Two dockers over one point, which the tree's order cannot settle: Godot keeps
## the stacking order of embedded subwindows in the embedder's own array and no
## script can ask for it, so the docker most recently focused or opened wins and
## the last of the tree order takes it when none has been.
func test_the_front_docker_wins_an_overlap() -> void:
    var under := _window(Vector2i(700, 200), Vector2i(400, 400))
    var over := _window(Vector2i(800, 300), Vector2i(400, 400))
    var dockers: Array[Window] = [under, over]
    var shared := Vector2(900, 400)

    assert_eq(
        MainDockersScript.docker_under(dockers, shared), over, "With nothing in front, the later of the tree order takes it"
    )
    assert_eq(
        MainDockersScript.docker_under(dockers, shared, under), under, "and the front docker takes it when it holds the point"
    )
    var closed := _window(Vector2i(700, 200), Vector2i(400, 400))
    assert_eq(
        MainDockersScript.docker_under(dockers, shared, closed),
        over,
        "A front docker no longer among the candidates decides nothing, which is the one hidden since it was focused"
    )
    closed.free()
    under.free()
    over.free()


## The docker the desktop owns rather than the host, which is `embed_subwindows`
## off. `SaCursorPolicy.embedded_subwindows` keeps only what `is_embedded()`
## answers true for, so the router is handed an empty list and grabs nothing, and
## the compositor delivers that press to the docker's own window as it already
## did. This is the half the scenario cannot press for, because a popup with
## `embed_subwindows` off crashes the offscreen run.
func test_a_docker_the_desktop_owns_is_no_candidate_for_the_router() -> void:
    var host := Node.new()
    var toolbox := _window(Vector2i(700, 200), Vector2i(220, 420))
    host.add_child(toolbox)

    assert_false(toolbox.is_embedded(), "A docker the host does not embed answers is_embedded false")
    assert_eq(
        SaCursorPolicy.embedded_subwindows(host).size(), 0, "so the walk that feeds the router finds nothing under the pointer"
    )
    assert_null(
        MainDockersScript.docker_under(SaCursorPolicy.embedded_subwindows(host), Vector2(810, 390)),
        "and the router grabs no focus, which leaves the press where the compositor already put it"
    )
    host.free()


## What the canvas skips on its `gui_input`, because it took the same event at
## the window a moment earlier and a window handler cannot mark one handled.
func test_the_canvas_names_a_right_press_and_a_right_release_and_nothing_else() -> void:
    assert_true(MainCanvasScript._is_right_button(_press(MOUSE_BUTTON_RIGHT, true)), "A right press is the gesture")
    assert_true(MainCanvasScript._is_right_button(_press(MOUSE_BUTTON_RIGHT, false)), "and so is the release that ends it")
    assert_false(MainCanvasScript._is_right_button(_press(MOUSE_BUTTON_LEFT, true)), "A left press is not")
    assert_false(MainCanvasScript._is_right_button(_press(MOUSE_BUTTON_MIDDLE, true)), "nor is the middle button, which pans")
    assert_false(
        MainCanvasScript._is_right_button(InputEventMouseMotion.new()),
        "and motion is not, or an ALT right drag over a docker would lose its middle"
    )


func _press(which: MouseButton, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = which
    event.pressed = pressed
    return event
