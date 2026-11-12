## The ring is drawn in the frame its event arrives.
##
## Sara's ring can fall behind the system pointer, under both drivers and with
## the mouse as well as the pen. None of that lag is a frame of Sara's, an event
## read one frame and drawn the next, and this suite keeps it so. A motion the overlay
## sees in `_input` moves the ring's place, the overlay's step in the same frame
## asks for a redraw at that place, and the draw reads it. The frames the
## running app drew in are what the scenario of the same name reads.
##
## A test cannot await a frame, so the three are called in the order the engine
## calls them inside one: the input, then the step, which is also why the whole
## suite reads one frame number.
extends "res://tests/test_framework.gd"

const PEN_ONE := Vector2(311.0, 207.0)
const PEN_TWO := Vector2(402.5, 240.25)

var _host: Node = null
var _previous_cursor: String = "auto"
var _previous_lead: String = "auto"
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func before_each() -> void:
    _previous_cursor = SaSettings.software_cursor
    _previous_lead = SaSettings.cursor_lead
    _previous_mouse_mode = Input.get_mouse_mode()
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "RingInTheEventsFrameTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaSettings.software_cursor = _previous_cursor
    SaSettings.cursor_lead = _previous_lead
    SaCursorPolicy.forget_pointer_device()
    if _host != null:
        _host.free()
        _host = null
    if Input.get_mouse_mode() != _previous_mouse_mode:
        Input.set_mouse_mode(_previous_mouse_mode as Input.MouseMode)


func _overlay() -> CursorOverlay:
    var window := Window.new()
    window.borderless = true
    window.size = Vector2i(640, 480)
    _host.add_child(window)
    window.show()
    return CursorOverlay.attach_to(window)


func _pen_motion(at: Vector2) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.tilt = Vector2(0.2, -0.1)
    motion.position = at
    return motion


## A pen motion is read, stepped and asked to be drawn in one frame, at the
## place the motion named.
func test_a_pen_motion_is_drawn_in_the_frame_it_arrives() -> void:
    if DisplayServer.get_name() == "headless":
        return
    SaSettings.cursor_lead = "off"
    var overlay := _overlay()
    var frame := Engine.get_process_frames()

    overlay._input(_pen_motion(PEN_ONE))
    assert_eq(overlay._event_frame, frame, "The motion is marked in the frame it arrived in")
    overlay._process(0.0)
    assert_eq(overlay._redraw_frame, frame, "and the same frame's step asks for the ring again")
    assert_eq(overlay._last_pos, PEN_ONE, "at the place the motion named")
    assert_eq(overlay.drawn_centre(overlay._pointer_position()), PEN_ONE, "which is where the draw puts the ring")


## A second motion in the same frame moves the ring again rather than waiting
## for the next frame, because the step compares places and not frames.
func test_a_second_motion_in_the_frame_is_the_one_drawn() -> void:
    if DisplayServer.get_name() == "headless":
        return
    SaSettings.cursor_lead = "off"
    var overlay := _overlay()
    overlay._input(_pen_motion(PEN_ONE))
    overlay._process(0.0)
    overlay._input(_pen_motion(PEN_TWO))
    overlay._process(0.0)
    assert_eq(overlay._last_pos, PEN_TWO, "The newest place is the one the step holds")
    assert_eq(overlay._redraw_frame, overlay._event_frame, "asked for in the frame it arrived in")


## A button is not a motion and does not mark a frame, so the reading is the
## pointer's travel alone.
func test_only_a_motion_marks_the_frame() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var overlay := _overlay()
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = PEN_ONE
    overlay._input(press)
    assert_eq(overlay._event_frame, -1, "A press marks no motion frame")


## The dump carries the three readings the scenario compares.
func test_the_dump_carries_the_frames() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var overlay := _overlay()
    overlay._input(_pen_motion(PEN_ONE))
    overlay._process(0.0)
    var found := false
    for entry: Dictionary in CursorOverlay.state_of(overlay.get_window()):
        found = true
        for key: String in ["event_frame", "redraw_frame", "drawn_frame", "ring_drawn_at"]:
            assert_true(entry.has(key), "The dump has %s" % key)
        assert_eq(int(entry["event_frame"]), Engine.get_process_frames(), "and the motion's frame is this one")
    assert_true(found, "The overlay's window has a dump entry")
