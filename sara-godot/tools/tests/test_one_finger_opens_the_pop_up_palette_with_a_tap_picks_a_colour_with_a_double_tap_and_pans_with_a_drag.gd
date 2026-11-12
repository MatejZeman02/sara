## One finger opens the pop-up palette with a tap, picks a colour with a double
## tap and pans with a drag, and never paints. A pen over the
## same canvas still paints.
##
## The touches go through the tool machine as the canvas hands them, local to
## its control, and the pop-up palette is a toggle attached to
## `SaRightClickDocker` the way the palette docker attaches its own, which
## notes where it was asked to open.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

## The device the emulator's stylus came as.
const STYLUS := 32
## The paint the canvas holds, and the foreground before a pick.
const PAINT := Color(0.8, 0.3, 0.1, 1.0)
const BEFORE := Color(0.1, 0.2, 0.9, 1.0)
## Alpha above which a texel counts as painted.
const PAINTED := 0.05
## Longer than a double tap's wait, in seconds.
const PAST_THE_WAIT := 0.45

var _surface: SaSurface = null
var _machine: ToolMachine = null
## Every point the palette was asked to open at.
var _opened: Array[Vector2] = []
var _foreground_was: Color = Color.BLACK


func before_each() -> void:
    _opened.clear()
    SaRightClickDocker.attach(SaRightClickDocker.PALETTE, _toggle)
    _foreground_was = SaColors.foreground
    _surface = Fixtures.make_surface(Vector2i(256, 128))
    _surface.easel.compositor.set_registry(Fixtures.make_registries(_surface).blend_modes)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    var settings: SaStampBrushSettings = _machine.get_tool(&"brush").get("settings")
    settings.radius = 0.1


func after_each() -> void:
    SaRightClickDocker.detach(SaRightClickDocker.PALETTE, self)
    SaColors.foreground = _foreground_was
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func test_a_tap_opens_the_palette_at_the_finger_once_the_double_tap_wait_is_over() -> void:
    var steps := _steps()
    _tap(0, Vector2(120, 60))
    assert_true(_opened.is_empty(), "The tap waits for a second one before it opens anything")
    await _wait()
    assert_eq(_opened.size(), 1, "and then opens the palette once")
    if _opened.size() == 1:
        assert_true(_opened[0].is_equal_approx(Vector2(120, 60)), "at the finger, %s" % _opened[0])
    assert_eq(_view().pan, Vector2.ZERO, "and moves no view")
    assert_eq(_painted(), 0, "and paints nothing")
    assert_eq(_steps(), steps, "and leaves no undo step")


func test_a_double_tap_picks_the_canvas_colour_under_it_and_opens_no_palette() -> void:
    _surface.get_document().fill_layer(PAINT)
    _composite()
    SaColors.foreground = BEFORE
    var at := Vector2(90, 40)
    _tap(0, at)
    _tap(0, at + Vector2(3, 2))
    var under: Color = _reader().pick_color_at_pos(at + Vector2(3, 2))
    var doc := _surface.get_document()
    var wanted := SaColorStore.opaque(doc.color_space.to_display(under) if doc.color_space != null else under)
    var got := SaColors.foreground
    assert_true(got.is_equal_approx(wanted), "The foreground is the canvas under the finger, %s against %s" % [got, wanted])
    assert_false(got.is_equal_approx(BEFORE), "and no longer the colour it was")
    await _wait()
    assert_true(_opened.is_empty(), "The double tap opened no palette, %s" % [_opened])


func test_a_drag_pans_the_view_by_the_drag_and_paints_nothing() -> void:
    var steps := _steps()
    _land(0, Vector2(60, 60), true)
    for i in range(1, 11):
        _drag(0, Vector2(60, 60) + Vector2(10, 4) * i)
    _land(0, Vector2(160, 100), false)
    var moved := _view().pan
    assert_true(moved.is_equal_approx(Vector2(100, 40)), "The view panned by the drag's (100, 40), %s" % moved)
    assert_eq(_painted(), 0, "The layer is unpainted")
    assert_eq(_steps(), steps, "and no undo step was made")
    await _wait()
    assert_true(_opened.is_empty(), "A drag is no tap and opens no palette")


func test_the_last_finger_off_a_pinch_neither_taps_nor_pans() -> void:
    _land(0, Vector2(100, 60), true)
    _land(1, Vector2(160, 60), true)
    _land(1, Vector2(160, 60), false)
    var pan := _view().pan
    _drag(0, Vector2(140, 90))
    _land(0, Vector2(140, 90), false)
    assert_eq(_view().pan, pan, "The finger left behind does not pan")
    await _wait()
    assert_true(_opened.is_empty(), "and its lift is no tap")


func test_a_pen_stroke_still_paints() -> void:
    _pen_motion(Vector2(20, 64), 0)
    _pen(true, Vector2(24, 64))
    for i in range(1, 21):
        _pen_motion(Vector2(lerpf(24, 232, i / 20.0), 64))
    _pen(false, Vector2(232, 64))
    assert_true(_painted() > 0, "The pen laid paint along its row, %d texels" % _painted())
    await _wait()
    assert_true(_opened.is_empty(), "and opened no palette")


# --- Helpers --------------------------------------------------------------------


func _toggle(point: Vector2) -> bool:
    _opened.append(point)
    return true


func _wait() -> void:
    await Engine.get_main_loop().create_timer(PAST_THE_WAIT).timeout


func _view() -> SaTestFixtures.FakeView:
    return _surface.view as SaTestFixtures.FakeView


func _tap(index: int, at: Vector2) -> void:
    _land(index, at, true)
    _land(index, at, false)


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


## How many texels of the row at y 64 hold paint.
func _painted() -> int:
    var reader := _reader()
    reader.sample_from = StateEyedropperScript.SampleFrom.LAYER
    var count := 0
    for x in range(0, 256, 2):
        if reader.pick_color_at_pos(Vector2(x + 0.5, 64.5)).a > PAINTED:
            count += 1
    return count


## The composite brought up to date, which a frame would do in the app.
func _composite() -> void:
    _surface.easel.document.update_caches()
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()


func _reader() -> Object:
    var reader := StateEyedropperScript.new()
    reader.surface = _surface
    return reader


func _steps() -> int:
    var history := _surface.get_document().history
    return history.step_count() if history != null else -1
