## A crop on the Reference board let go on or past the picture's edge crops to
## that edge, the way a crop that keeps an edge is made, and a crop inside the
## picture or one that never opened out does what it did before.
##
## The docker is built but never added to the SceneTree, as the other Reference suites build
## it, because a `Window` in the tree hangs a headless run.
extends "res://tests/test_framework.gd"

const REFERENCE_IMAGE := "res://ui/icon.png"


func _press(docker: ReferenceDocker, at: Vector2, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    docker.board_view.input(event)


func _move(docker: ReferenceDocker, at: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    docker.board_view.input(event)


## Presses Crop on the one picture, drags from a quarter in to the point
## *to_of* names on the picture's shown rectangle and lets go. Answers the crop,
## the image's size, whether crop mode is still on, the shown rectangle and the
## press point.
func _crop_drag(to_of: Callable) -> Dictionary:
    var docker := ReferenceDocker.new()
    docker.board_view.size = Vector2(200, 200)
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE]))
    var picture := docker.board().pictures[0]
    var shown := docker.board().view_rect(picture)
    docker.board_view.pointer_entered()
    docker.board_view.toggle("crop")
    var from := shown.position + shown.size * 0.25
    var to: Vector2 = to_of.call(shown, from)
    _press(docker, from, true)
    _move(docker, to)
    _press(docker, to, false)
    var out := {
        "crop": picture.crop,
        "size": picture.image.get_size(),
        "crop_mode": docker.board_view.crop_mode,
        "shown": shown,
        "to": to,
    }
    docker.free()
    return out


## The texel a point of the shown rectangle lies on, along one axis.
func _texel(got: Dictionary, axis: int) -> int:
    var shown: Rect2 = got["shown"]
    var size: Vector2i = got["size"]
    var to: Vector2 = got["to"]
    return floori((to[axis] - shown.position[axis]) / shown.size[axis] * float(size[axis]))


func _check_reaches_the_corner(got: Dictionary, what: String) -> void:
    var crop: Rect2i = got["crop"]
    var size: Vector2i = got["size"]
    assert_false(got["crop_mode"], "%s: the lift leaves crop mode" % what)
    assert_almost_eq(float(crop.position.x), size.x * 0.25, 2.0, "%s: the crop starts a quarter in across" % what)
    assert_almost_eq(float(crop.position.y), size.y * 0.25, 2.0, "%s: and a quarter down" % what)
    assert_eq(crop.end.x, size.x, "%s: and runs to the picture's last texel across" % what)
    assert_eq(crop.end.y, size.y, "%s: and to its last texel down" % what)


func test_a_drag_let_go_six_pixels_past_the_corner_crops_to_the_corner() -> void:
    var got := _crop_drag(func(r: Rect2, _from: Vector2) -> Vector2: return r.end + Vector2(6, 6))
    _check_reaches_the_corner(got, "Past the corner")


func test_a_drag_let_go_exactly_on_the_corner_crops_to_the_corner() -> void:
    var got := _crop_drag(func(r: Rect2, _from: Vector2) -> Vector2: return r.end)
    _check_reaches_the_corner(got, "On the corner")


func test_a_drag_let_go_past_the_right_side_crops_to_it_and_down_to_the_release() -> void:
    var got := _crop_drag(func(r: Rect2, _from: Vector2) -> Vector2: return Vector2(r.end.x + 6, r.position.y + r.size.y * 0.75))
    var crop: Rect2i = got["crop"]
    var size: Vector2i = got["size"]
    assert_false(got["crop_mode"], "The lift leaves crop mode")
    assert_eq(crop.end.x, size.x, "The crop runs to the picture's last texel across")
    assert_almost_eq(float(crop.end.y - 1), float(_texel(got, 1)), 1.0, "and its bottom is where the release was")
    assert_true(crop.end.y < size.y, "which is short of the picture's bottom")


func test_a_drag_inside_the_picture_crops_as_before() -> void:
    var got := _crop_drag(func(r: Rect2, _from: Vector2) -> Vector2: return r.position + r.size * 0.75)
    var crop: Rect2i = got["crop"]
    var size: Vector2i = got["size"]
    assert_false(got["crop_mode"], "The lift leaves crop mode")
    assert_almost_eq(float(crop.position.x) / size.x, 0.25, 0.01, "The crop starts a quarter in")
    assert_almost_eq(float(crop.end.x - 1), float(_texel(got, 0)), 1.0, "and ends across where the release was")
    assert_almost_eq(float(crop.end.y - 1), float(_texel(got, 1)), 1.0, "and down where the release was")


func test_a_drag_shorter_than_two_texels_leaves_the_picture_whole() -> void:
    var got := _crop_drag(func(_r: Rect2, from: Vector2) -> Vector2: return from + Vector2(0.1, 0.1))
    assert_eq(got["crop"], Rect2i(), "A drag that never opened out crops nothing")
    assert_false(got["crop_mode"], "and leaves crop mode as before")
