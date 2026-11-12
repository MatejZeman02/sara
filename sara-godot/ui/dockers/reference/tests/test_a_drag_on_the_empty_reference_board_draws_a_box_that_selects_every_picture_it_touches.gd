## A drag on the empty reference board draws a box that selects every
## picture it touches.
##
## Built outside the tree as the other suites here are, because a `Window` in
## the tree hangs a headless run. The running app's side, the box drawn and the
## two pictures outlined after, is
## `scenarios/a-drag-on-the-empty-reference-board-draws-a-box-that-selects-every-picture-it-touches.json`.
extends "res://tests/test_framework.gd"

const REFERENCE_IMAGE := "res://ui/icon.png"


## Four pictures laid by hand in a row with gaps, at a zoom that leaves empty
## board above and below them, and nothing selected.
func _docker() -> ReferenceDocker:
    var docker := ReferenceDocker.new()
    docker.board_view.size = Vector2(800, 400)
    var path := REFERENCE_IMAGE
    docker.open_paths(PackedStringArray([path, path, path, path]))
    var board := docker.board()
    for index in board.pictures.size():
        board.pictures[index].rect = Rect2(Vector2(index * 200.0, 0.0), Vector2(100.0, 100.0))
    board.zoom = 1.0
    board.offset = Vector2(20, 150)
    docker.board_view.deselect()
    return docker


func _button(docker: ReferenceDocker, at: Vector2, pressed: bool, shift := false, ctrl := false) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.shift_pressed = shift
    event.ctrl_pressed = ctrl
    docker.board_view.input(event)


func _move(docker: ReferenceDocker, at: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    docker.board_view.input(event)


func _drag(docker: ReferenceDocker, from: Vector2, to: Vector2, shift := false) -> void:
    _button(docker, from, true, shift)
    _move(docker, from + (to - from) * 0.5)
    _move(docker, to)
    _button(docker, to, false, shift)


func _centre(docker: ReferenceDocker, picture: SaReferenceBoard.Picture) -> Vector2:
    return docker.board().view_rect(picture).get_center()


func _selected(docker: ReferenceDocker) -> Array:
    var out: Array = []
    for picture in docker.board_view.selection.held(docker.board()):
        out.append(picture)
    return out


func test_a_box_ctrl_click_group_drag_delete_and_empty_click() -> void:
    var docker := _docker()
    var board := docker.board()
    var four := board.pictures.duplicate()
    var empty := Vector2(10, 20)
    assert_null(board.picture_at(board.to_board(empty)), "The box starts on empty board")
    var offset := board.offset

    # From above the first picture to below the second: it touches those two.
    _drag(docker, empty, Vector2(250, 300))
    var held := _selected(docker)
    assert_eq(held.size(), 2, "The box selects the two pictures it touches")
    assert_true(held.has(four[0]) and held.has(four[1]), "the first and the second")
    assert_eq(board.offset, offset, "and the board did not pan")
    assert_eq(docker.board_view.selection.box(), Rect2(), "and the box is gone once lifted")
    assert_null(docker.board_view.selected(), "Several selected is no one picture for the handles")
    assert_null(docker.board_view.hover_target(), "nor for the hover bar")
    assert_true(docker.report()["boards"][0]["pictures"][0]["selected"], "The dump says the first is selected")

    _button(docker, _centre(docker, four[2]), true, false, true)
    _button(docker, _centre(docker, four[2]), false, false, true)
    assert_eq(_selected(docker).size(), 3, "A Ctrl click adds a third")

    var was: Array = []
    for picture: SaReferenceBoard.Picture in four:
        was.append(picture.rect.position)
    var from := _centre(docker, four[1])
    _drag(docker, from, from + Vector2(30, 40))
    for index in 3:
        assert_eq(four[index].rect.position - was[index], Vector2(30, 40), "Picture %d moved with the drag" % index)
    assert_eq(four[3].rect.position, was[3], "and the fourth stayed")
    assert_eq(_selected(docker).size(), 3, "and the three are still selected")

    var delete := InputEventKey.new()
    delete.keycode = KEY_DELETE
    delete.pressed = true
    assert_true(docker.board_view.erase(delete), "Delete is taken")
    assert_eq(board.pictures.size(), 1, "and leaves one picture")
    assert_eq(board.pictures[0], four[3], "the one not selected")

    docker.board_view.select_picture(four[3])
    _button(docker, empty, true)
    _button(docker, empty, false)
    assert_eq(_selected(docker).size(), 0, "A click on the empty board selects none")
    docker.free()


func test_a_shift_drag_from_the_empty_board_pans_and_selects_nothing() -> void:
    var docker := _docker()
    var board := docker.board()
    var offset := board.offset
    _drag(docker, Vector2(10, 20), Vector2(250, 300), true)
    assert_eq(board.offset, offset + Vector2(240, 280), "A Shift drag pans")
    assert_eq(_selected(docker).size(), 0, "and selects nothing")
    docker.free()


func test_a_ctrl_click_takes_a_selected_picture_out() -> void:
    var docker := _docker()
    var board := docker.board()
    _drag(docker, Vector2(10, 20), Vector2(250, 300))
    _button(docker, _centre(docker, board.pictures[0]), true, false, true)
    _button(docker, _centre(docker, board.pictures[0]), false, false, true)
    assert_eq(_selected(docker).size(), 1, "A Ctrl click on a selected picture takes it out")
    assert_not_null(docker.board_view.selected(), "and the one left has its handles back")
    docker.free()


## Several selected is the selection Fit and Normalize act on, and one is not,
## since every picture is selected as it lands.
func test_normalise_and_fit_act_on_the_selection() -> void:
    var docker := _docker()
    var board := docker.board()
    var four := board.pictures.duplicate()
    four[1].rect.size = Vector2(50, 200)
    var untouched := Rect2(four[3].rect)
    _drag(docker, Vector2(10, 20), Vector2(250, 360))
    assert_eq(_selected(docker).size(), 2, "Two selected")
    docker.board_view.normalise("height")
    assert_eq(four[3].rect, untouched, "Normalize leaves a picture out of the selection where it was")
    assert_almost_eq(four[0].rect.size.y, four[1].rect.size.y, 1e-3, "and brings the two selected to one height")
    assert_eq(four[0].rect.position, Vector2.ZERO, "laid where they stood")
    var room := docker.board_view.size
    var two: Rect2 = four[0].rect.merge(four[1].rect)
    var two_zoom := minf(minf(room.x / two.size.x, room.y / two.size.y), 1.0)
    assert_almost_eq(board.zoom, two_zoom, 1e-4, "The fit after it is of the two")
    docker.board_view.deselect()
    docker.board_view.fit()
    var all := board.bounds()
    var all_zoom := minf(minf(room.x / all.size.x, room.y / all.size.y), 1.0)
    assert_almost_eq(board.zoom, all_zoom, 1e-4, "Fit with none selected shows the whole board")
    docker.board_view.select_picture(four[3])
    docker.board_view.fit()
    assert_almost_eq(board.zoom, all_zoom, 1e-4, "and with one selected, the whole board too")
    docker.free()
