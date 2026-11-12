## A gradient's end stays where the hand holds it still.
##
## The ramp must not drift while the hand holds the drag still.
## A pen keeps sending its place while it is in range, each reading a pixel or
## a fraction of one off the last, and every reading would move the end and
## dispatch the preview again, so the end would go back and forth under a still hand
## and the release lay the ramp wherever the last reading fell. The tool
## leaves the end where it stands for a reading within
## `STILL_REACH` screen pixels of it, and follows a hand
## past that exactly. The other candidate cause, the ramp re-seeded off
## the pair on every read changing the preview's key, is held here as well: the
## key stands over sixty ticks and changes once when the foreground does.
##
## Driven through `handle_input` with the fixture's view holding the pointer,
## at a zoom the canvas is often shown at, so a screen pixel is
## nearly four document pixels.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const SaGradientScript = preload("res://modules/sara-base-modules/base/gradient/sa_gradient.gd")

const REQUIRES_GPU := true

## A canvas zoom at which a screen pixel is nearly four document pixels.
const ZOOM := 0.27
const FROM := Vector2(40.0, 200.0)
const TO := Vector2(400.0, 260.0)
## The ticks a hold lasts, a second at sixty frames.
const HOLD := 60
## The tick the foreground is picked before, halfway through the hold.
const PICK_AT := 30
const BLUE := Color(0.1, 0.2, 0.9)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _tool: ToolState = null
var _view: Fixtures.FakeView = null
var _was_pair: Array[Color] = []


## The pair is shared with the rest of the run, so it is put back.
func before_each() -> void:
    _was_pair = [SaColors.foreground, SaColors.background]
    SaColors.foreground = Color.BLACK
    SaColors.background = Color.WHITE
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"gradient")
    _tool = _machine.get_tool(&"gradient")
    _view = _surface.view
    _view.zoom = ZOOM


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _tool = null
    _view = null
    SaColors.foreground = _was_pair[0]
    SaColors.background = _was_pair[1]


## The row's second clause: a drag held at one place over sixty ticks, the
## hand read at that place every tick, and the preview's key unchanged after
## the first.
func test_a_drag_held_at_one_place_keeps_its_key_over_sixty_ticks() -> void:
    _press_and_drag()
    var key: Array = _tool._previewed_key
    var previews := _pass().previews

    var changes := _hold([TO])

    assert_eq(changes, 0, "The key stands over %d ticks" % HOLD)
    assert_eq(_tool._previewed_key, key, "and is the first tick's")
    assert_eq(_pass().previews, previews, "Nothing is dispatched while the hand is still")
    assert_eq(_tool._to, TO, "and the end is where the drag left it")


## A pen held still flips between two readings a
## fraction of a pixel apart, and one rounded to whole pixels flips between
## neighbours, straight and diagonal. None of it moves the end.
func test_a_pen_s_jitter_under_a_still_hand_moves_nothing() -> void:
    _press_and_drag()
    var previews := _pass().previews
    var pixel := 1.0 / ZOOM

    var changes := _hold([TO, TO + Vector2(0.05, 0.0) * pixel, TO + Vector2(pixel, 0.0), TO + Vector2(pixel, pixel)])

    assert_eq(changes, 0, "The key stands through the jitter")
    assert_eq(_pass().previews, previews, "and no preview is dispatched for it")
    assert_eq(_tool._to, TO, "The end stays where the hand holds it")


## The row's second clause again: the same hold, with the foreground changed
## halfway, changes the key once, and the ramp follows the picked colour.
func test_a_colour_picked_mid_hold_changes_the_key_once() -> void:
    _press_and_drag()
    var previews := _pass().previews

    var changes := _hold([TO], PICK_AT)

    assert_eq(changes, 1, "The key changes once, on the tick after the pick")
    assert_eq(_pass().previews, previews + 1, "and one preview shows the new colour")
    assert_eq(_tool.ramp.color_of(0.0).to_html(false), BLUE.to_html(false), "The ramp's near end is the picked foreground")
    assert_eq(_tool._previewed_key, _tool._key(), "and the previewed key is the ramp as it is now")
    _tool.handle_input(_button(false))
    assert_eq(_report()["to"], [TO.x, TO.y], "The release lays the ramp at the held end")


## Past the reach the hand is moving, and the end goes to it exactly rather
## than trailing it.
func test_a_hand_past_the_reach_is_followed_exactly() -> void:
    _press_and_drag()
    var previews := _pass().previews
    var away := TO + Vector2(2.0 / ZOOM, 0.0)

    _move(away)
    _tool.tick(0.016)

    assert_eq(_tool._to, away, "The end is where the hand is")
    assert_eq(_pass().previews, previews + 1, "and the preview shows it on the next tick")


## A pen slides a little as it lifts, and the release laid the ramp at the
## lift's reading. Within the reach it is laid at the held end.
func test_a_release_within_the_reach_lays_the_held_end() -> void:
    _press_and_drag()
    _hold([TO, TO + Vector2(1.0 / ZOOM, 0.0)])

    _view.mouse_position = TO + Vector2(1.0 / ZOOM, 1.0 / ZOOM)
    _tool.handle_input(_button(false))

    assert_true(_report()["held"], "The ramp is laid and its ends held")
    assert_eq(_report()["to"], [TO.x, TO.y], "at the end the hand held still")


## A held end grabbed again keeps still the same way, and its release lays the
## ramp where it stood.
func test_a_grabbed_end_held_still_stays() -> void:
    _press_and_drag()
    _tool.handle_input(_button(false))
    _view.mouse_position = TO
    _tool.handle_input(_button(true))
    assert_eq(_report()["grabbed"], "to", "A press on the far end takes it")
    _tool.tick(0.016)
    var previews := _pass().previews

    var changes := _hold([TO + Vector2(1.0 / ZOOM, 0.0), TO])
    _view.mouse_position = TO + Vector2(0.0, 1.0 / ZOOM)
    _tool.handle_input(_button(false))

    assert_eq(changes, 0, "The key stands while the grabbed end is held")
    assert_eq(_pass().previews, previews, "and nothing is dispatched")
    assert_eq(_report()["to"], [TO.x, TO.y], "The release lays it where it stood")


## Presses at FROM, drags to TO and ticks once, the first preview.
func _press_and_drag() -> void:
    _view.mouse_position = FROM
    _tool.handle_input(_button(true))
    _move(TO)
    _tool.tick(0.016)
    assert_eq(_tool._to, TO, "The drag reached its far end")


## Holds the drag over [constant HOLD] ticks with the hand read at *places* in
## turn, one a tick, and the foreground set to blue before tick *pick_at* when
## it is not negative. Answers how many ticks changed the previewed key.
func _hold(places: Array, pick_at: int = -1) -> int:
    var changes := 0
    var key: Array = _tool._previewed_key
    for frame in HOLD:
        if frame == pick_at:
            SaColors.foreground = BLUE
        _move(places[frame % places.size()])
        _tool.tick(0.016)
        if _tool._previewed_key != key:
            changes += 1
            key = _tool._previewed_key
    return changes


func _move(at: Vector2) -> void:
    _view.mouse_position = at
    _tool.handle_input(InputEventMouseMotion.new())


func _pass() -> SaGradientScript:
    return _tool._pass_for(_surface.get_document())


func _report() -> Dictionary:
    return _tool.capture_report(&"gradient", true)["gradient"]


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
