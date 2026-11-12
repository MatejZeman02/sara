## A drag right round the ring moved the hue from 0.764 to 0.055 and left the
## paint at `#000000`.
##
## Every shape of the ring family, the disc with its own press and the HSL
## square with its hue bar, is set to black and dragged once round with real
## press, motion and release events, and every colour the drag gives has an
## Oklab lightness of at least 0.4. The same drag from a mid grey leaves the
## lightness as it was, and a press at the black corner of the area (the
## disc's lightness bar at its foot) after the drag gives black again, so the
## lift happens at the start of a gesture and never after it.
extends "res://tests/test_framework.gd"

const OkhslConversionsScript = preload("res://utils/okhsl_conversions.gd")

const SIDE := 200.0
const BAR := 18.0
const STEPS := 72
const GREY := Color(0.5, 0.5, 0.5)
const KINDS: Array[int] = [
    SaPickerShape.Kind.WHEEL,
    SaPickerShape.Kind.OKHSL,
    SaPickerShape.Kind.TRIANGLE,
    SaPickerShape.Kind.TRIANGLE_UP,
    SaPickerShape.Kind.HSV_SQUARE,
    SaPickerShape.Kind.HSV_TRIANGLE,
    SaPickerShape.Kind.HSL_SQUARE,
]

var _holder: Control


func before_each() -> void:
    _holder = Control.new()
    var root := (Engine.get_main_loop() as SceneTree).root
    root.get_child(root.get_child_count() - 1).add_child(_holder)


func after_each() -> void:
    if is_instance_valid(_holder):
        _holder.free()


func _shape(kind: int, col: Color, keep: bool) -> SaPickerShape:
    var shape := SaPickerShape.new()
    _holder.add_child(shape)
    shape.set_kind(kind)
    shape.keep_chroma = keep
    shape.frame.size = Vector2(SIDE, SIDE)
    shape._on_frame_resized()
    shape.hue_bar.size = Vector2(BAR, SIDE)
    shape.lightness_bar.size = Vector2(BAR, SIDE)
    shape.set_from_color(col)
    return shape


static func _lightness(col: Color) -> float:
    return OkhslConversionsScript.srgb_to_oklch(col).z


static func _press(at: Vector2, down: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = down
    event.position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
    return event


static func _motion(at: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    return event


## Where step *k* of one turn puts the pointer: round the ring on a ringed
## shape, round inside the rim on the disc, and down the bar on the HSL square.
func _point(shape: SaPickerShape, k: int) -> Vector2:
    var turn := float(k) / STEPS
    if shape.kind == SaPickerShape.Kind.HSL_SQUARE:
        return Vector2(BAR * 0.5, clampf(turn, 0.0, 1.0) * SIDE)
    return Vector2(SIDE, SIDE) * 0.5 + Vector2.from_angle(TAU * turn) * SIDE * 0.45


## One gesture once round, through the shape's own input handlers, with the
## Oklab lightness of the colour after every event.
func _turn(shape: SaPickerShape) -> PackedFloat32Array:
    var seen := PackedFloat32Array()
    var bar := shape.kind == SaPickerShape.Kind.HSL_SQUARE
    for k in range(STEPS + 1):
        var at := _point(shape, k)
        var event: InputEvent = _motion(at)
        if k == 0:
            event = _press(at, true)
        if bar:
            shape._on_hue_bar_gui_input(event)
        else:
            shape._on_frame_gui_input(event)
        seen.append(_lightness(shape.color()))
    var up := _press(_point(shape, STEPS), false)
    if bar:
        shape._on_hue_bar_gui_input(up)
    else:
        shape._on_frame_gui_input(up)
    return seen


## A press and release at the black end of the shape's lightness: the area's
## black corner, or the foot of the disc's lightness bar.
func _to_black(shape: SaPickerShape) -> void:
    if shape.kind == SaPickerShape.Kind.OKHSL:
        var foot := Vector2(BAR * 0.5, SIDE)
        shape._on_lightness_bar_gui_input(_press(foot, true))
        shape._on_lightness_bar_gui_input(_press(foot, false))
        return
    var area := shape.area_rect
    var corner := area.position + Vector2(0.0, area.size.y)
    if shape.kind == SaPickerShape.Kind.HSV_TRIANGLE:
        corner = area.position + SaPickerClassic.triangle_point(0.0, 0.0) * area.size
    shape._on_frame_gui_input(_press(corner, true))
    shape._on_frame_gui_input(_press(corner, false))


func test_a_turn_from_black_gives_a_colour_with_lightness_at_every_hue() -> void:
    for keep: bool in [false, true]:
        for kind: int in KINDS:
            var shape := _shape(kind, Color.BLACK, keep)
            var seen := _turn(shape)
            var least := 1.0
            for value in seen:
                least = minf(least, value)
            var name := "%s, keep chroma %s" % [SaPickerShape.KIND_KEYS[kind], keep]
            var said := "%s: every hue of the turn from black has Oklab lightness 0.4 or more, least %.3f"
            assert_true(least >= 0.4, said % [name, least])
            shape.free()


func test_a_turn_from_a_mid_grey_keeps_its_lightness() -> void:
    for kind: int in KINDS:
        var shape := _shape(kind, GREY, false)
        var before := _lightness(shape.color())
        var seen := _turn(shape)
        var worst := 0.0
        for value in seen:
            worst = maxf(worst, absf(value - before))
        var name := SaPickerShape.KIND_KEYS[kind]
        assert_true(worst < 0.002, "%s: a turn from a mid grey leaves the lightness at %.3f, off by %.4f" % [name, before, worst])
        shape.free()


func test_a_press_at_black_after_the_turn_keeps_black() -> void:
    for kind: int in KINDS:
        var shape := _shape(kind, Color.BLACK, false)
        _turn(shape)
        _to_black(shape)
        var name := SaPickerShape.KIND_KEYS[kind]
        var html := shape.color().to_html(false)
        assert_eq(html, "000000", "%s: black taken after the turn stays black" % name)
        shape.free()


func test_a_dark_colour_over_the_floor_is_not_lifted() -> void:
    var navy := OkhslConversionsScript.oklch_to_srgb(0.73, 0.05, 0.2)
    var shape := _shape(SaPickerShape.Kind.WHEEL, navy, false)
    var most := 0.0
    for value in _turn(shape):
        most = maxf(most, value)
    assert_true(most < 0.3, "a navy at Oklab lightness 0.2 is not lifted by a turn, the lightest step %.3f" % most)
    shape.free()
