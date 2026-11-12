## Ctrl and a middle drag zoom the view about the press,
## continuously, as Blender and Krita have it. A painter wrote: "bug:
## CTRL + middle click drag should slowly zoom (like in blender)". Up or right
## zooms in and down or left out, by an exponential of the travel that
## `SaViewDrag.PIXELS_PER_DOUBLING` states, and a plain middle drag still pans
## and a Shift one still turns.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Where every press lands, away from the view's origin so a zoom about the
## origin would be seen to slide it.
const PRESS := Vector2(600, 450)

var _stored: Dictionary = {}
var _stored_mouse_middle: String = ""
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _tool: SaTestFixtures.FakeTool = null
var _view: SaTestFixtures.FakeView = null


func before_each() -> void:
    _stored = SaSettings.pen_buttons.duplicate()
    _stored_mouse_middle = SaSettings.mouse_middle
    SaSettings.mouse_middle = SaSettingsPenButtons.PAN
    SaCursorPolicy.forget_pointer_device()
    _surface = Fixtures.make_surface()
    _view = _surface.view as SaTestFixtures.FakeView
    _view.zoom = 2.0
    _view.pan = Vector2(40, -30)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.surface = _surface
    _tool = SaTestFixtures.FakeTool.new()
    _machine.register_tool(&"fake", _tool)


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    SaSettings.pen_buttons = _stored
    SaSettings.mouse_middle = _stored_mouse_middle
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null


## Up by 100 and by 200 grows the zoom by two to the 100 and the 200 over the
## rate, the document point under the press stays under it, and a second drag
## down by 200 takes the zoom back by the same factor.
func test_a_ctrl_middle_drag_up_zooms_in_about_the_press_and_down_zooms_out() -> void:
    var under := _view.screen_to_document(PRESS)
    _machine.handle_input(_middle(true, PRESS, true))
    _machine.handle_input(_motion(PRESS + Vector2(0, -100), true))
    var rate := SaViewDrag.PIXELS_PER_DOUBLING
    assert_almost_eq(_view.zoom, 2.0 * pow(2.0, 100.0 / rate), 1e-6, "Up by 100 zooms in by 2^(100/%d)" % rate)
    _machine.handle_input(_motion(PRESS + Vector2(0, -200), true))
    assert_almost_eq(_view.zoom, 2.0 * pow(2.0, 200.0 / rate), 1e-6, "and up by 200 by 2^(200/%d)" % rate)
    assert_true(_view.document_to_screen(under).distance_to(PRESS) < 1.0, "with the point under the press where it was")
    assert_true(_tool.events.is_empty(), "and the tool saw nothing of it")
    _machine.handle_input(_middle(false, PRESS + Vector2(0, -200), false))

    var zoomed := _view.zoom
    _machine.handle_input(_motion(PRESS + Vector2(0, -400), false))
    assert_almost_eq(_view.zoom, zoomed, 1e-9, "A motion after the release zooms nothing")

    var under_now := _view.screen_to_document(PRESS)
    _machine.handle_input(_middle(true, PRESS, true))
    _machine.handle_input(_motion(PRESS + Vector2(0, 200), true))
    _machine.handle_input(_middle(false, PRESS + Vector2(0, 200), false))
    assert_almost_eq(_view.zoom, zoomed / pow(2.0, 200.0 / rate), 1e-6, "Down by 200 zooms out by the same factor")
    assert_true(_view.document_to_screen(under_now).distance_to(PRESS) < 1.0, "about the press as well")


## Right zooms in as up does, and left out, and a long drag across the canvas,
## a thousand pixels, is a factor of four.
func test_right_zooms_in_and_a_thousand_pixels_is_a_factor_of_four() -> void:
    _machine.handle_input(_middle(true, PRESS, true))
    _machine.handle_input(_motion(PRESS + Vector2(1000, 0), true))
    assert_almost_eq(_view.zoom, 8.0, 1e-6, "A thousand pixels right is four times")
    _machine.handle_input(_motion(PRESS + Vector2(-500, 0), true))
    assert_almost_eq(_view.zoom, 1.0, 1e-6, "and five hundred left of the press halves the zoom it found")
    _machine.handle_input(_middle(false, PRESS, false))


## Ctrl let go midway goes on zooming, as Shift's turn goes on turning: the
## key's release and motions without it still zoom until the button is up.
func test_ctrl_let_go_during_the_drag_goes_on_zooming() -> void:
    _machine.handle_input(_middle(true, PRESS, true))
    _machine.handle_input(_motion(PRESS + Vector2(0, -100), true))
    var key := InputEventKey.new()
    key.keycode = KEY_CTRL
    key.physical_keycode = KEY_CTRL
    key.pressed = false
    _machine.handle_input(key)
    _machine.handle_input(_motion(PRESS + Vector2(0, -500), false))
    assert_almost_eq(_view.zoom, 4.0, 1e-6, "The drag zooms on with Ctrl up")
    _machine.handle_input(_middle(false, PRESS, false))


## A drag past the maximum holds the zoom there, and past the minimum too.
func test_a_drag_past_the_limits_holds_the_zoom_there() -> void:
    _machine.handle_input(_middle(true, PRESS, true))
    _machine.handle_input(_motion(PRESS + Vector2(0, -100000), true))
    assert_almost_eq(_view.zoom, SaView.ZOOM_MAX, 1e-6, "Far past the maximum holds it")
    _machine.handle_input(_motion(PRESS + Vector2(0, -100500), true))
    assert_almost_eq(_view.zoom, SaView.ZOOM_MAX, 1e-6, "and further holds it still")
    _machine.handle_input(_motion(PRESS + Vector2(0, 100000), true))
    assert_almost_eq(_view.zoom, SaView.ZOOM_MIN, 1e-9, "Far down holds the minimum")
    _machine.handle_input(_middle(false, PRESS, false))


## A plain middle drag pans as before and a Shift one turns as before.
func test_a_plain_middle_drag_pans_and_a_shift_one_turns() -> void:
    _machine.handle_input(_middle(true, PRESS, false))
    _machine.handle_input(_motion(PRESS + Vector2(30, -20), false, Vector2(30, -20)))
    _machine.handle_input(_middle(false, PRESS, false))
    assert_eq(_view.pan, Vector2(70, -50), "A plain middle drag pans by its travel")
    assert_almost_eq(_view.zoom, 2.0, 1e-9, "and zooms nothing")

    var press := _middle(true, PRESS, false)
    press.shift_pressed = true
    _machine.handle_input(press)
    for at: Vector2 in [PRESS + Vector2(100, 0), PRESS + Vector2(71, 71), PRESS + Vector2(0, 100)]:
        _machine.handle_input(_motion(at, false))
    _machine.handle_input(_middle(false, PRESS, false))
    assert_almost_eq(_view.rotation, PI / 2.0, 1e-6, "A Shift middle drag turns a quarter for a quarter swing")
    assert_almost_eq(_view.zoom, 2.0, 1e-9, "and zooms nothing")

    var both := _middle(true, PRESS, true)
    both.shift_pressed = true
    _machine.handle_input(both)
    _machine.handle_input(_motion(PRESS + Vector2(0, -300), true))
    _machine.handle_input(_middle(false, PRESS, false))
    assert_almost_eq(_view.zoom, 2.0, 1e-9, "Shift and Ctrl together turn, which Shift always did")


## A pen whose middle row pans zooms the same, and a mouse middle row set to
## anything but Pan is left doing what it does.
func test_a_pen_s_pan_button_zooms_and_a_middle_row_off_pan_does_not() -> void:
    var table := SaSettings.pen_buttons.duplicate()
    table["middle"] = SaSettingsPenButtons.PAN
    SaSettings.pen_buttons = table
    SaSettings.mouse_middle = SaSettingsPenButtons.CONTEXT_MENU
    var tilted := _motion(PRESS, false)
    tilted.tilt = Vector2(0.13, -0.08)
    SaCursorPolicy.note_pointer_device(tilted)
    assert_true(SaCursorPolicy.pointer_is_tablet, "The pointer is a pen's")
    _machine.handle_input(_middle(true, PRESS, true))
    _machine.handle_input(_motion(PRESS + Vector2(0, -500), true))
    _machine.handle_input(_middle(false, PRESS, false))
    assert_almost_eq(_view.zoom, 4.0, 1e-6, "The pen's barrel bound to Pan zooms with Ctrl")

    SaCursorPolicy.forget_pointer_device()
    SaSettings.mouse_middle = SaSettingsPenButtons.EYEDROPPER
    _machine.handle_input(_middle(true, PRESS, true))
    _machine.handle_input(_motion(PRESS + Vector2(0, -500), true))
    _machine.handle_input(_middle(false, PRESS, false))
    assert_almost_eq(_view.zoom, 4.0, 1e-6, "A mouse middle row on the eyedropper zooms nothing")


func _middle(pressed: bool, at: Vector2, ctrl: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_MIDDLE
    event.pressed = pressed
    event.ctrl_pressed = ctrl
    event.position = at
    event.global_position = at
    event.button_mask = MOUSE_BUTTON_MASK_MIDDLE if pressed else 0
    return event


func _motion(at: Vector2, ctrl: bool, relative: Vector2 = Vector2.ZERO) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.relative = relative
    event.ctrl_pressed = ctrl
    event.button_mask = MOUSE_BUTTON_MASK_MIDDLE
    return event
