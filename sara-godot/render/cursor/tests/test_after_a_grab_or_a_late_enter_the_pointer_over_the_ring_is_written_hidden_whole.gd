## After a grab or an enter that comes after the focus, the pointer over the
## ring is written hidden whole, and the log says what happened on the way.
##
## The system pointer could still show beside the ring after an Alt+Tab
## once the mode was written whole on a focus in. GNOME Shell's switcher
## grabs the pointer and draws its own, so a quick Alt+Tab back to Sara can
## send no focus change at all, only the pointer leaving Sara and coming back.
## And a focus in that comes before the enter writes while Sara's surface does
## not hold the pointer, where the compositor drops the write. The seat here
## plays both: a grab shows the shell's pointer behind Godot's back, and a
## write made while the surface does not hold the pointer changes nothing on
## the screen.
##
## The canvas is a live one in a real window, the fixture the Alt+Tab suite uses,
## because the policy walks `SaCanvas.live_canvases()`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RING: float = 12.0
const ON_CANVAS := Vector2(100, 60)


## A mouse mode as the policy sees it and a screen as the painter does.
class GrabbingSeat:
    extends SaCursorPolicy.MouseModeSeat

    var mode: int = Input.MOUSE_MODE_VISIBLE
    var pointer_on_screen: bool = true
    var surface_holds_pointer: bool = true
    var writes: Array[int] = []

    func read() -> int:
        return mode

    func write(new_mode: int) -> void:
        writes.append(new_mode)
        mode = new_mode
        if surface_holds_pointer:
            pointer_on_screen = new_mode != Input.MOUSE_MODE_HIDDEN

    ## The shell taking the pointer and drawing its own, with Sara's mode left
    ## as it was.
    func grab() -> void:
        surface_holds_pointer = false
        pointer_on_screen = true

    ## The pointer back on Sara's surface, still showing whatever was drawn last.
    func give_back() -> void:
        surface_holds_pointer = true


## The lines said, kept rather than printed, without the `Sara cursor:` head
## the printing seat puts on.
class KeptLog:
    extends SaCursorTrip.LogSeat

    var lines: Array[String] = []

    func say(line: String) -> void:
        lines.append(line)


var _host: Node = null
var _seat: GrabbingSeat = null
var _log: KeptLog = null
var _kept_seat: SaCursorPolicy.MouseModeSeat = null
var _kept_log: SaCursorTrip.LogSeat = null
var _kept_mode: String = "auto"


func before_each() -> void:
    _kept_mode = SaSettings.software_cursor
    _kept_seat = SaCursorPolicy.mouse_mode_seat
    _kept_log = SaCursorTrip.log_seat
    _seat = GrabbingSeat.new()
    _log = KeptLog.new()
    SaCursorPolicy.mouse_mode_seat = _seat
    SaCursorTrip.log_seat = _log
    _host = Node.new()
    _host.name = "CursorTripTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaCursorPolicy.note_focus_in()
    SaCursorTrip.take_write_whole()
    SaCursorPolicy.mouse_mode_seat = _kept_seat
    SaCursorTrip.log_seat = _kept_log
    SaCursorPolicy.unpin_pointer(self)
    SaCursorPolicy.forget_pointer_device()
    SaSettings.software_cursor = _kept_mode
    if _host != null:
        _host.free()
        _host = null


## A window with a live canvas over the whole of it asking for a ring, the
## pointer pinned over the canvas, and the pointer written hidden over it.
func _window_with_a_ring() -> Window:
    var window := Window.new()
    window.borderless = true
    window.size = Vector2i(1920, 1080)
    _host.add_child(window)
    window.show()
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    window.add_child(canvas)
    canvas.position = Vector2.ZERO
    canvas.size = Vector2(1920, 1080)
    canvas.cursor_ring_radius = RING
    SaCursorPolicy.pin_pointer(self, window, ON_CANVAS)
    SaCursorTrip.take_write_whole()
    SaCursorPolicy.sync_os_cursor_visibility()
    return window


## The quick Alt+Tab that lands back on Sara: the shell grabs the pointer and
## gives it back with no focus out or in, and the enter writes hidden whole.
func test_an_enter_after_a_grab_with_no_focus_change_writes_hidden_whole() -> void:
    if DisplayServer.get_name() == "headless":
        return
    SaSettings.software_cursor = "always"
    var window := _window_with_a_ring()
    assert_eq(_seat.writes, [Input.MOUSE_MODE_HIDDEN] as Array[int], "over the ring the pointer is written hidden")

    _seat.grab()
    SaCursorPolicy.note_pointer_left(window)
    SaCursorPolicy.sync_os_cursor_visibility()
    _seat.give_back()
    assert_true(_seat.pointer_on_screen, "the shell's pointer stands over the canvas after the grab")
    assert_eq(_seat.writes.size(), 1, "the mode still reads hidden, so the guard alone writes nothing")

    SaCursorPolicy.note_pointer_entered(window)
    var expected: Array[int] = [Input.MOUSE_MODE_HIDDEN, Input.MOUSE_MODE_VISIBLE, Input.MOUSE_MODE_HIDDEN]
    assert_eq(_seat.writes, expected, "the enter writes hidden whole, through visible")
    assert_false(_seat.pointer_on_screen, "so the ring shows alone")

    SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(_seat.writes.size(), 3, "and the sync after it writes only a change")


## A focus in that comes before the enter: its whole write lands while the
## surface does not hold the pointer, and the enter after it writes again.
func test_a_focus_in_before_the_enter_is_written_whole_again_at_the_enter() -> void:
    if DisplayServer.get_name() == "headless":
        return
    SaSettings.software_cursor = "always"
    var window := _window_with_a_ring()

    _seat.grab()
    SaCursorPolicy.note_focus_out()
    SaCursorPolicy.note_pointer_left(window)
    SaCursorPolicy.note_focus_in()
    assert_eq(_seat.writes.size(), 3, "the focus in writes whole")
    assert_true(_seat.pointer_on_screen, "but the surface does not hold the pointer, so the system's stays")

    _seat.give_back()
    SaCursorPolicy.note_pointer_entered(window)
    var expected: Array[int] = [
        Input.MOUSE_MODE_HIDDEN,
        Input.MOUSE_MODE_VISIBLE,
        Input.MOUSE_MODE_HIDDEN,
        Input.MOUSE_MODE_VISIBLE,
        Input.MOUSE_MODE_HIDDEN,
    ]
    assert_eq(_seat.writes, expected, "the later enter writes hidden whole again")
    assert_false(_seat.pointer_on_screen, "and this time it lands, so the ring shows alone")


## The log of an Alt+Tab trip: a line for each focus change, each leave and
## enter and each write, and none while nothing changes.
func test_the_log_holds_a_line_for_each_step_of_a_trip_and_none_while_nothing_changes() -> void:
    if DisplayServer.get_name() == "headless":
        return
    SaSettings.software_cursor = "always"
    var window := _window_with_a_ring()
    assert_eq(_log.lines.size(), 1, "the first hiding is one line")
    var first := _log.lines[0]
    assert_true(first.begins_with("wrote hidden, it read visible before"), "and says what it read: %s" % first)

    _log.lines.clear()
    for _frame in 5:
        SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(_log.lines.size(), 0, "nothing changes, nothing is said")

    SaCursorPolicy.note_focus_out()
    SaCursorPolicy.note_focus_out()
    SaCursorPolicy.note_pointer_left(window)
    SaCursorPolicy.note_focus_in()
    SaCursorPolicy.note_focus_in()
    SaCursorPolicy.note_pointer_entered(window)
    var said: Array[String] = []
    for line in _log.lines:
        said.append(line.get_slice(" at ", 0))
    var expected: Array[String] = [
        "focus out, the mode reads hidden",
        "pointer left window %s, the mode reads hidden" % window.name,
        "focus in, the mode reads hidden",
        "wrote visible, it read hidden before",
        "wrote hidden, it read visible before",
        "pointer entered window %s, the mode reads hidden" % window.name,
        "wrote visible, it read hidden before",
        "wrote hidden, it read visible before",
    ]
    assert_eq(said, expected, "one line per step, a focus heard by every overlay said once")

    _log.lines.clear()
    for _frame in 5:
        SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(_log.lines.size(), 0, "and quiet again once the trip is over")
