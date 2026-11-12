## A click on the reference board's empty space unselects the picture,
## and so does Escape.
##
## Built outside the tree as the other suites here are, because a `Window` in
## the tree hangs a headless run. The running app's side, the handles before
## and after the click, is `scenarios/a-click-on-the-reference-board-s-empty-space-unselects-the-picture.json`.
extends "res://tests/test_framework.gd"

const REFERENCE_IMAGE := "res://ui/icon.png"


## One picture in the middle of a board with room around it, selected, so the
## corners of the view are empty board.
func _docker() -> ReferenceDocker:
    var docker := ReferenceDocker.new()
    docker.board_view.size = Vector2(400, 300)
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE, REFERENCE_IMAGE]))
    var board := docker.board()
    board.zoom = 0.25
    board.offset = Vector2(150, 100)
    docker.board_view.select_picture(board.pictures[0])
    return docker


func _button(docker: ReferenceDocker, at: Vector2, pressed: bool, shift: bool = false) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.shift_pressed = shift
    event.position = at
    docker.board_view.input(event)


func _move(docker: ReferenceDocker, at: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    docker.board_view.input(event)


func _escape() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_ESCAPE
    event.pressed = true
    return event


## An empty spot of the view: the top left corner, off every picture.
func _empty(docker: ReferenceDocker) -> Vector2:
    var at := Vector2(5, 5)
    assert_null(docker.board().picture_at(docker.board().to_board(at)), "The corner is empty board")
    return at


## The handle of the selected picture's top left corner answers a press.
func _handle_shown(docker: ReferenceDocker) -> bool:
    var picture := docker.board_view.selected()
    if picture == null:
        return false
    var at := docker.board().view_rect(picture).position
    return docker.board_view.corner_at(at).x >= 0.0


func test_a_click_on_the_empty_board_unselects() -> void:
    var docker := _docker()
    var picture := docker.board_view.selected()
    assert_not_null(picture, "The picture starts selected")
    assert_true(_handle_shown(docker), "with its handles")
    var at := _empty(docker)
    var offset := docker.board().offset
    _button(docker, at, true)
    _move(docker, at + Vector2(1, 1))
    _button(docker, at + Vector2(1, 1), false)
    assert_null(docker.board_view.selected(), "A click off every picture unselects")
    assert_eq(
        docker.board_view.corner_at(docker.board().view_rect(picture).position), Vector2(-1, -1), "and the handles are gone"
    )
    assert_true(docker.board().offset.distance_to(offset) < 2.0, "and the board barely moved")
    docker.free()


## A plain drag there draws the selection's box and a Shift drag is
## the pan, which keeps the selection.
func test_a_shift_drag_from_the_empty_board_pans_and_keeps_the_selection() -> void:
    var docker := _docker()
    var picture := docker.board_view.selected()
    var at := _empty(docker)
    var offset := docker.board().offset
    _button(docker, at, true, true)
    _move(docker, at + Vector2(20, 0))
    _move(docker, at + Vector2(40, 10))
    _button(docker, at + Vector2(40, 10), false, true)
    assert_true(docker.board().offset.is_equal_approx(offset + Vector2(40, 10)), "The drag panned")
    assert_eq(docker.board_view.selected(), picture, "and kept the selection")
    assert_true(_handle_shown(docker), "and its handles")
    docker.free()


func test_escape_unselects() -> void:
    var docker := _docker()
    assert_true(docker.board_view.escape(_escape()), "Escape is taken")
    assert_null(docker.board_view.selected(), "and unselects")
    assert_false(docker.board_view.escape(_escape()), "and a second has nothing left to do")
    docker.free()


func test_with_a_picture_soloed_escape_leaves_solo_first() -> void:
    var docker := _docker()
    var board := docker.board()
    var picture := docker.board_view.selected()
    assert_true(docker.board_view.toggle_solo(picture), "Solo takes")
    assert_true(docker.board_view.escape(_escape()), "The first Escape is taken")
    assert_null(board.soloed(), "and leaves solo")
    assert_eq(docker.board_view.selected(), picture, "with the picture still selected")
    assert_true(docker.board_view.escape(_escape()), "The second Escape is taken")
    assert_null(docker.board_view.selected(), "and unselects")
    docker.free()
