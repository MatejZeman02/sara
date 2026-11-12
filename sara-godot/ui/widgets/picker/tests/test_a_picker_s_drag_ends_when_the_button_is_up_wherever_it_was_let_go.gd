## The hue picker circle must not keep moving after a mouse release until the
## user clicks.
##
## A drag on the ring, the area, the HSL square's hue bar or the OKHSL disc's
## lightness bar ends at the first event that shows the left button up, a
## motion whose mask has lost the button included, and that event moves
## nothing. A shape hidden or taken out of the tree mid drag ends it the same
## way. Each drag commits the colour it reached once and only once.
extends "res://tests/test_framework.gd"

const SIDE := 200.0

var _committed: Array[Color] = []
var _holder: Control


func before_each() -> void:
    _committed.clear()
    _holder = Control.new()
    # The root is busy setting up the runner, which is its last child and is
    # in the tree, so the holder goes under that.
    var root := (Engine.get_main_loop() as SceneTree).root
    root.get_child(root.get_child_count() - 1).add_child(_holder)


func after_each() -> void:
    if is_instance_valid(_holder):
        _holder.free()


func _shape(kind: int) -> SaPickerShape:
    var shape := SaPickerShape.new()
    _holder.add_child(shape)
    shape.set_kind(kind)
    shape.set_from_color(Color(0.8, 0.3, 0.2))
    shape.frame.size = Vector2(SIDE, SIDE)
    shape._on_frame_resized()
    shape.hue_bar.size = Vector2(18.0, SIDE)
    shape.lightness_bar.size = Vector2(18.0, SIDE)
    shape.color_committed.connect(func(c: Color) -> void: _committed.append(c))
    return shape


func _button(at: Vector2, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    return event


func _motion(at: Vector2, held: bool) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
    return event


## The frame's points on the ring, at nine tenths of the half side.
func _on_ring(angle: float) -> Vector2:
    return Vector2(SIDE, SIDE) * 0.5 + Vector2.from_angle(angle) * SIDE * 0.45


func _same(got: Color, want: Color, what: String) -> void:
    assert_almost_eq(got.r, want.r, 1e-6, "%s: red" % what)
    assert_almost_eq(got.g, want.g, 1e-6, "%s: green" % what)
    assert_almost_eq(got.b, want.b, 1e-6, "%s: blue" % what)


## Sends the path's held motions after its press, then motions with the button up and no
## release, then a motion with the button down again but no press, and reads
## that nothing after the last held motion moved the colour.
func _drag_and_lose_the_release(shape: SaPickerShape, input: Callable, path: Array, what: String) -> void:
    var press_at: Vector2 = path[0]
    var held: Array = path[1]
    var after: Array = path[2]
    input.call(_button(press_at, true))
    for at: Vector2 in held:
        input.call(_motion(at, true))
    var reached := shape.color()
    var reached_hue := shape.hue
    assert_ne_colour(reached, Color(0.8, 0.3, 0.2), what)
    for at: Vector2 in after:
        input.call(_motion(at, false))
    input.call(_motion(after[0], true))
    _same(shape.color(), reached, "%s: the colour stops at the last held motion" % what)
    assert_almost_eq(shape.hue, reached_hue, 1e-6, "%s: and so does the hue" % what)
    assert_eq(_committed.size(), 1, "%s: color_committed fired once" % what)
    if _committed.size() == 1:
        _same(_committed[0], reached, "%s: with the colour the drag reached" % what)


func assert_ne_colour(got: Color, start: Color, what: String) -> void:
    assert_true(not got.is_equal_approx(start), "%s: the held motions moved the colour" % what)


func test_a_ring_drag_ends_at_a_motion_with_the_button_up() -> void:
    var shape := _shape(SaPickerShape.Kind.WHEEL)
    var path := [_on_ring(0.0), [_on_ring(0.6), _on_ring(1.4)], [_on_ring(2.5), _on_ring(3.5)]]
    _drag_and_lose_the_release(shape, shape._on_frame_gui_input, path, "the ring")


func test_an_area_drag_ends_at_a_motion_with_the_button_up() -> void:
    var shape := _shape(SaPickerShape.Kind.WHEEL)
    var centre := Vector2(SIDE, SIDE) * 0.5
    var held := [centre + Vector2(20, -10), centre + Vector2(30, -25)]
    var after := [centre + Vector2(-30, 30), centre + Vector2(-35, 35)]
    _drag_and_lose_the_release(shape, shape._on_frame_gui_input, [centre, held, after], "the area")


func test_the_hsl_square_s_hue_bar_drag_ends_at_a_motion_with_the_button_up() -> void:
    var shape := _shape(SaPickerShape.Kind.HSL_SQUARE)
    var path := [Vector2(9, 20), [Vector2(9, 60), Vector2(9, 110)], [Vector2(9, 170), Vector2(9, 190)]]
    _drag_and_lose_the_release(shape, shape._on_hue_bar_gui_input, path, "the hue bar")


func test_the_okhsl_disc_s_lightness_bar_drag_ends_at_a_motion_with_the_button_up() -> void:
    var shape := _shape(SaPickerShape.Kind.OKHSL)
    var path := [Vector2(9, 100), [Vector2(9, 80), Vector2(9, 40)], [Vector2(9, 170), Vector2(9, 190)]]
    _drag_and_lose_the_release(shape, shape._on_lightness_bar_gui_input, path, "the lightness bar")


## Hidden mid drag, shown again, and a motion with the button up: the colour
## is the one the drag reached, committed once, at the hide.
func test_a_shape_hidden_mid_drag_ends_the_drag() -> void:
    var shape := _shape(SaPickerShape.Kind.WHEEL)
    shape._on_frame_gui_input(_button(_on_ring(0.0), true))
    shape._on_frame_gui_input(_motion(_on_ring(0.8), true))
    var reached := shape.color()
    shape.hide()
    assert_eq(_committed.size(), 1, "the hide ended the drag and committed")
    shape.show()
    shape._on_frame_gui_input(_motion(_on_ring(2.4), false))
    shape._on_frame_gui_input(_motion(_on_ring(3.0), true))
    _same(shape.color(), reached, "after the hide")
    assert_eq(_committed.size(), 1, "and nothing committed again")


func test_a_shape_taken_out_of_the_tree_mid_drag_ends_the_drag() -> void:
    var shape := _shape(SaPickerShape.Kind.HSL_SQUARE)
    shape._on_hue_bar_gui_input(_button(Vector2(9, 20), true))
    shape._on_hue_bar_gui_input(_motion(Vector2(9, 90), true))
    var reached := shape.color()
    assert_true(shape.is_inside_tree(), "the shape was in the tree")
    _holder.remove_child(shape)
    assert_eq(_committed.size(), 1, "leaving the tree ended the drag and committed")
    _holder.add_child(shape)
    shape._on_hue_bar_gui_input(_motion(Vector2(9, 180), true))
    _same(shape.color(), reached, "after the tree")
    assert_eq(_committed.size(), 1, "and nothing committed again")


## A release that does arrive commits once, and the motions after it, held or
## not, neither move the colour nor commit again.
func test_a_drag_whose_release_arrives_commits_once() -> void:
    var cases := [
        [SaPickerShape.Kind.WHEEL, "_on_frame_gui_input", _on_ring(0.0), _on_ring(0.9)],
        [SaPickerShape.Kind.WHEEL, "_on_frame_gui_input", Vector2(100, 100), Vector2(120, 80)],
        [SaPickerShape.Kind.HSL_SQUARE, "_on_hue_bar_gui_input", Vector2(9, 20), Vector2(9, 120)],
        [SaPickerShape.Kind.OKHSL, "_on_lightness_bar_gui_input", Vector2(9, 100), Vector2(9, 40)],
    ]
    for case: Array in cases:
        _committed.clear()
        var shape := _shape(case[0])
        var input := Callable(shape, case[1])
        input.call(_button(case[2], true))
        input.call(_motion(case[3], true))
        var reached := shape.color()
        input.call(_button(case[3], false))
        input.call(_motion(case[2], false))
        input.call(_motion(case[2], true))
        input.call(_button(case[2], false))
        assert_eq(_committed.size(), 1, "%s: committed once and only once" % case[1])
        _same(shape.color(), reached, "%s: the colour the release left" % case[1])
        shape.free()
