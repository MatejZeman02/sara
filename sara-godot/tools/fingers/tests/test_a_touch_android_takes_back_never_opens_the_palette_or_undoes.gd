## A touch Android takes back as the pen lands is no tap. Android cancels a
## resting palm or finger it decides was not meant, and Godot hands that on as
## a release with `canceled` set. One such finger must not open the pop-up
## palette and two must not undo, while a plain release still taps as before.
##
## The touches go through the tool machine as the canvas hands them, local to
## its control, as `test_a_two_finger_tap_undoes.gd` sends them, and the
## palette is a stand-in attached where the real one attaches its toggle.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The device the emulator's stylus came as.
const STYLUS := 32
## Longer than a still tap waits for a second one, in seconds.
const PAST_THE_DOUBLE_TAP := SaOneFinger.DOUBLE_TAP_MSEC / 1000.0 + 0.2
## A foreground no pick off the stroke gives back.
const BEFORE := Color(0.1, 0.2, 0.9, 1.0)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _palette: Palette = null
var _toggle_before: Callable = Callable()
var _foreground_was: Color = Color.BLACK


## Stands in for the pop-up palette, counting the points it was opened at.
class Palette:
    extends RefCounted
    var points: Array[Vector2] = []

    func toggle_at(point: Vector2) -> bool:
        points.append(point)
        return true


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 128))
    _surface.easel.compositor.set_registry(Fixtures.make_registries(_surface).blend_modes)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    var settings: SaStampBrushSettings = _machine.get_tool(&"brush").get("settings")
    settings.radius = 0.1
    _stroke(60)
    _foreground_was = SaColors.foreground
    _toggle_before = SaRightClickDocker._toggles.get(SaRightClickDocker.PALETTE, Callable())
    _palette = Palette.new()
    SaRightClickDocker.attach(SaRightClickDocker.PALETTE, _palette.toggle_at)


func after_each() -> void:
    SaColors.foreground = _foreground_was
    SaRightClickDocker.detach(SaRightClickDocker.PALETTE, _palette)
    if _toggle_before.is_valid():
        SaRightClickDocker.attach(SaRightClickDocker.PALETTE, _toggle_before)
    _toggle_before = Callable()
    _palette = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func test_a_finger_taken_back_opens_no_palette() -> void:
    _touch(0, Vector2(100, 60), true)
    _touch(0, Vector2(100, 60), false, true)
    await Engine.get_main_loop().create_timer(PAST_THE_DOUBLE_TAP).timeout
    assert_true(_palette.points.is_empty(), "A cancelled release opened the palette at %s" % [_palette.points])


func test_a_plain_tap_still_opens_the_palette() -> void:
    _touch(0, Vector2(100, 60), true)
    _touch(0, Vector2(100, 60), false)
    await Engine.get_main_loop().create_timer(PAST_THE_DOUBLE_TAP).timeout
    assert_eq(_palette.points, [Vector2(100, 60)] as Array[Vector2], "A plain tap opens the palette where it landed")


func test_a_finger_taken_back_then_a_tap_opens_the_palette_once() -> void:
    _touch(0, Vector2(100, 60), true)
    _touch(0, Vector2(100, 60), false, true)
    _touch(1, Vector2(110, 62), true)
    _touch(1, Vector2(110, 62), false)
    await Engine.get_main_loop().create_timer(PAST_THE_DOUBLE_TAP).timeout
    assert_eq(_palette.points, [Vector2(110, 62)] as Array[Vector2], "The next landing starts fresh, a single tap and no pick")


func test_a_second_tap_taken_back_picks_no_colour() -> void:
    _surface.easel.document.update_caches()
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    SaColors.foreground = BEFORE
    _touch(0, Vector2(100, 60), true)
    _touch(0, Vector2(100, 60), false)
    _touch(0, Vector2(102, 61), true)
    _touch(0, Vector2(102, 61), false, true)
    assert_eq(SaColors.foreground, BEFORE, "A cancelled second tap picked %s off the stroke" % SaColors.foreground)
    await Engine.get_main_loop().create_timer(PAST_THE_DOUBLE_TAP).timeout
    assert_true(_palette.points.is_empty(), "and opened no palette")


func test_two_fingers_taken_back_undo_nothing() -> void:
    var at := _position()
    _touch(0, Vector2(80, 60), true)
    _touch(1, Vector2(160, 60), true)
    _touch(0, Vector2(80, 60), false, true)
    _touch(1, Vector2(160, 60), false, true)
    assert_eq(_position(), at, "Two cancelled fingers undid the stroke, %d to %d" % [at, _position()])
    await Engine.get_main_loop().create_timer(PAST_THE_DOUBLE_TAP).timeout
    assert_true(_palette.points.is_empty(), "and opened no palette")


func test_two_plain_fingers_still_undo() -> void:
    var at := _position()
    _touch(0, Vector2(80, 60), true)
    _touch(1, Vector2(160, 60), true)
    _touch(0, Vector2(80, 60), false)
    _touch(1, Vector2(160, 60), false)
    assert_eq(_position(), at - 1, "A plain two-finger tap undoes once")


func test_three_fingers_taken_back_redo_nothing() -> void:
    _touch(0, Vector2(80, 60), true)
    _touch(1, Vector2(160, 60), true)
    _touch(0, Vector2(80, 60), false)
    _touch(1, Vector2(160, 60), false)
    var at := _position()
    for index in 3:
        _touch(index, Vector2(80 + 40 * index, 60), true)
    for index in 3:
        _touch(index, Vector2(80 + 40 * index, 60), false, true)
    assert_eq(_position(), at, "Three cancelled fingers redid nothing")


func test_a_pan_taken_back_keeps_the_view_where_it_went() -> void:
    _touch(0, Vector2(100, 60), true)
    _drag(0, Vector2(140, 70))
    _touch(0, Vector2(140, 70), false, true)
    assert_eq(_view().pan, Vector2(40, 10), "The pan stays where the finger took it")
    await Engine.get_main_loop().create_timer(PAST_THE_DOUBLE_TAP).timeout
    assert_true(_palette.points.is_empty(), "and no palette opens")


# --- Helpers --------------------------------------------------------------------


func _view() -> SaTestFixtures.FakeView:
    return _surface.view as SaTestFixtures.FakeView


func _position() -> int:
    return _surface.get_document().history.position()


func _touch(index: int, at: Vector2, pressed: bool, canceled: bool = false) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = at
    event.pressed = pressed
    event.canceled = canceled
    _machine.handle_input(event)


func _drag(index: int, at: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = at
    _machine.handle_input(event)


## A pen stroke along the row at *y*, one undo step.
func _stroke(y: float) -> void:
    _pen_motion(Vector2(20, y), 0)
    _pen(true, Vector2(24, y))
    for i in range(1, 11):
        _pen_motion(Vector2(lerpf(24, 232, i / 10.0), y))
    _pen(false, Vector2(232, y))


func _pen(pressed: bool, at: Vector2) -> void:
    _view().mouse_position = at
    var event := InputEventMouseButton.new()
    event.device = STYLUS
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    event.position = at
    event.global_position = at
    _machine.handle_input(event)


func _pen_motion(at: Vector2, mask: int = MOUSE_BUTTON_MASK_LEFT) -> void:
    _view().mouse_position = at
    var event := InputEventMouseMotion.new()
    event.device = STYLUS
    event.position = at
    event.global_position = at
    event.pressure = 0.8
    event.button_mask = mask
    _machine.handle_input(event)
