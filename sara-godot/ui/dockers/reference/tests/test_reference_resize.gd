## A reference picture can be resized by a corner handle.
##
## The docker is built but never added to the SceneTree, the way the other
## Reference suites build it. What is proved here is the model's `resize` and the
## gesture from press to release, with shift holding the ratio. That the
## handles are drawn where a press finds them, and that the size survives a
## save, is proved on the running app by
## `scenarios/a-reference-picture-can-be-resized.json`.
extends "res://tests/test_framework.gd"

const REFERENCE_IMAGE := "res://ui/icon.png"


func _docker() -> ReferenceDocker:
    var docker := ReferenceDocker.new()
    docker.board_view.size = Vector2(400, 300)
    return docker


func _press(docker: ReferenceDocker, at: Vector2, pressed: bool, shift: bool = false) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.shift_pressed = shift
    docker.board_view.input(event)


func _move(docker: ReferenceDocker, at: Vector2, shift: bool = false) -> void:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    event.shift_pressed = shift
    docker.board_view.input(event)


## The dragged corner lands on the point and the opposite corner stays.
func test_resize_moves_one_corner_and_anchors_the_other() -> void:
    var board := SaReferenceBoard.new()
    var picture := board.add_path(REFERENCE_IMAGE)
    picture.rect = Rect2(100, 50, 200, 100)
    board.resize(picture, Vector2(1, 1), Vector2(400, 250))
    assert_eq(picture.rect, Rect2(100, 50, 300, 200), "Bottom right dragged out, top left stays")
    board.resize(picture, Vector2(0, 0), Vector2(200, 150))
    assert_eq(picture.rect, Rect2(200, 150, 200, 100), "Top left dragged in, bottom right stays")
    board.resize(picture, Vector2(1, 0), Vector2(500, 100))
    assert_eq(picture.rect, Rect2(200, 100, 300, 150), "Top right dragged, bottom left stays")
    board.resize(picture, Vector2(0, 1), Vector2(100, 300))
    assert_eq(picture.rect, Rect2(100, 100, 400, 200), "Bottom left dragged, top right stays")


## A corner pulled past its opposite leaves the smallest picture, never an
## inverted or empty one.
func test_resize_never_goes_under_the_floor() -> void:
    var board := SaReferenceBoard.new()
    var picture := board.add_path(REFERENCE_IMAGE)
    picture.rect = Rect2(100, 50, 200, 100)
    board.resize(picture, Vector2(1, 1), Vector2(0, 0))
    assert_eq(
        picture.rect.size,
        Vector2(SaReferenceBoard.MIN_SIDE, SaReferenceBoard.MIN_SIDE),
        "Pulled past the anchor, the floor holds"
    )
    assert_eq(picture.rect.position, Vector2(100, 50), "and the anchor stays")


## With the aspect kept, the picture follows the axis the drag pulled
## further and keeps its proportions.
func test_resize_with_the_aspect_kept_holds_the_ratio() -> void:
    var board := SaReferenceBoard.new()
    var picture := board.add_path(REFERENCE_IMAGE)
    picture.rect = Rect2(0, 0, 200, 100)
    board.resize(picture, Vector2(1, 1), Vector2(400, 120), true)
    assert_eq(picture.rect.size, Vector2(400, 200), "Pulled twice as wide, it is twice as tall too")
    board.resize(picture, Vector2(1, 1), Vector2(420, 400), true)
    assert_eq(picture.rect.size, Vector2(800, 400), "Pulled further down than out, the height leads")
    assert_eq(picture.rect.position, Vector2.ZERO, "and the top left never moved")


## From the picture Control: a press on the selected picture's bottom right
## handle, two motions and a release resize it in board units, and the
## release counts as a change rather than a sample.
func test_a_drag_on_a_handle_resizes_the_selected_picture() -> void:
    var docker := _docker()
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE, REFERENCE_IMAGE]))
    var board := docker.board()
    var first := board.pictures[0]
    var second := board.pictures[1]
    assert_eq(docker.board_view.selected(), second, "Opened last, the second is selected")
    var was := second.rect
    var rect := board.view_rect(second)
    var handle := rect.end
    assert_eq(docker.board_view.corner_at(handle), Vector2(1, 1), "The bottom right handle is at the corner")
    assert_eq(docker.board_view.corner_at(board.view_rect(first).position), Vector2(-1, -1), "and an unselected picture has none")

    _press(docker, handle, true)
    assert_true(docker.board_view.busy(), "Pressed, the gesture is a resize")
    _move(docker, handle + Vector2(10.0, 5.0))
    _move(docker, handle + Vector2(20.0, 10.0))
    _press(docker, handle + Vector2(20.0, 10.0), false)
    assert_almost_eq(second.rect.size.x, was.size.x + 20.0 / board.zoom, 1e-3, "Wider by the drag in board units")
    assert_almost_eq(second.rect.size.y, was.size.y + 10.0 / board.zoom, 1e-3, "and taller")
    assert_eq(second.rect.position, was.position, "with the top left where it was")
    assert_false(docker.board_view.busy(), "and released")
    assert_eq(docker._sampled_at, Vector2i(-1, -1), "The lift after a resize samples nothing")
    assert_eq(first.rect.size, board.pictures[0].rect.size, "and the other picture is untouched")
    docker.free()


## Shift held during the drag keeps the ratio, and shift on the handle press
## is not a pan.
func test_shift_on_the_handle_keeps_the_ratio() -> void:
    var docker := _docker()
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE]))
    var board := docker.board()
    var picture := board.pictures[0]
    var was := picture.rect
    var ratio := was.size.x / was.size.y
    var handle := board.view_rect(picture).end
    var offset_before := board.offset

    _press(docker, handle, true, true)
    _move(docker, handle + Vector2(30.0, 2.0), true)
    _press(docker, handle + Vector2(30.0, 2.0), false, true)
    assert_eq(board.offset, offset_before, "Shift on a handle did not pan")
    assert_almost_eq(picture.rect.size.x / picture.rect.size.y, ratio, 1e-3, "The ratio held")
    assert_almost_eq(picture.rect.size.x, was.size.x + 30.0 / board.zoom, 1e-3, "along the axis pulled further")
    docker.free()


## The size a resize left is what the header writes and reads back.
func test_the_resized_rectangle_is_saved() -> void:
    var board := SaReferenceBoard.new("Sized")
    var picture := board.add_path(REFERENCE_IMAGE)
    board.resize(picture, Vector2(1, 1), picture.rect.end * 1.5)
    var back := SaReferenceBoard.from_header(board.to_header())
    assert_eq(back.pictures[0].rect, picture.rect, "The rectangle comes back as resized")
