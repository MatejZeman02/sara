## A short pen or finger mark on Android reaches Sara from its first move.
##
## With `input_devices/pointing/android/disable_scroll_deadzone` false, Godot's
## Android input handler drops every move until Android's gesture detector
## has scrolled past its touch slop of 8 dp, so a shorter mark arrived as a
## single dab and a longer one began with a straight jump. A stylus takes the
## same route as a finger. The setting is read once when the app starts, so
## the project file is the only place it can be set, and this suite keeps it
## there.
##
## With the deadzone off, a finger that wanders a few pixels before a second
## one lands now sends those moves too. Godot's scale detector, the one path
## that would cancel such a drag, stays off while
## `pointing/android/enable_pan_and_scale_gestures` is false, so the pinch is
## read by `SaTwoFingers` alone, and the second test plays that order through
## the tool machine as the canvas hands it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 128))
    _surface.easel.compositor.set_registry(Fixtures.make_registries(_surface).blend_modes)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func test_the_android_scroll_deadzone_is_off() -> void:
    assert_true(
        ProjectSettings.get_setting("input_devices/pointing/android/disable_scroll_deadzone", false),
        "the Android scroll deadzone holds back every move under 8 dp",
    )


func test_godot_s_own_pan_and_scale_stays_off_so_it_cancels_no_drag() -> void:
    assert_false(
        ProjectSettings.get_setting("input_devices/pointing/android/enable_pan_and_scale_gestures", false),
        "Godot's scale detector would cancel a first finger's early drag",
    )


func test_a_pinch_whose_first_finger_moved_before_the_second_landed_zooms_by_the_spread() -> void:
    var at := _surface.get_document().history.position()
    _land(0, Vector2(80, 60), true)
    _drag(0, Vector2(75, 60))
    _drag(0, Vector2(70, 60))
    _land(1, Vector2(160, 60), true)
    _drag(0, Vector2(40, 60))
    _drag(1, Vector2(175, 60))
    _land(0, Vector2(40, 60), false)
    _land(1, Vector2(175, 60), false)
    var view := _surface.view as SaTestFixtures.FakeView
    assert_almost_eq(view.zoom, 1.5, 0.001, "the pinch zooms from where both fingers were when it began")
    assert_eq(_surface.get_document().history.position(), at, "and undoes nothing")


func _land(index: int, at: Vector2, pressed: bool) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = at
    event.pressed = pressed
    _machine.handle_input(event)


func _drag(index: int, at: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = at
    _machine.handle_input(event)
