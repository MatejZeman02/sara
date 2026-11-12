## After Alt+Tab back to Sara with the pen over the canvas, only the
## brush ring shows.
##
## The system pointer could show beside the ring after a trip out to
## another program and back. While Sara is out of focus the system shows its
## own pointer over Sara, and Godot's mode still reads hidden, so a policy that
## writes the mode only when it reads differently never hides it again. The
## seat here plays that: it records every write, and on a focus out it shows
## the pointer on its screen while the mode it reports stays where it was.
## The policy forgets on a focus out and writes the mode whole on a focus in.
##
## The canvas is a live one in a real window, the fixture `test_both_cursor_mode.gd`
## uses, because the policy walks `SaCanvas.live_canvases()`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RING: float = 12.0
const ON_CANVAS := Vector2(100, 60)


## A mouse mode as the policy sees it and a screen as the painter does. What
## the screen shows changes on each write and on a focus out, which the system
## does behind Godot's back.
class RecordingSeat:
    extends SaCursorPolicy.MouseModeSeat

    var mode: int = Input.MOUSE_MODE_VISIBLE
    var pointer_on_screen: bool = true
    var writes: Array[int] = []

    func read() -> int:
        return mode

    func write(new_mode: int) -> void:
        writes.append(new_mode)
        mode = new_mode
        pointer_on_screen = new_mode != Input.MOUSE_MODE_HIDDEN

    ## The system taking the pointer back for the program that has the focus.
    func lose_focus() -> void:
        pointer_on_screen = true


var _host: Node = null
var _seat: RecordingSeat = null
var _kept_seat: SaCursorPolicy.MouseModeSeat = null
var _kept_mode: String = "auto"


func before_each() -> void:
    _kept_mode = SaSettings.software_cursor
    _kept_seat = SaCursorPolicy.mouse_mode_seat
    _seat = RecordingSeat.new()
    SaCursorPolicy.mouse_mode_seat = _seat
    _host = Node.new()
    _host.name = "AltTabTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaCursorPolicy.note_focus_in()
    SaCursorPolicy.mouse_mode_seat = _kept_seat
    SaCursorPolicy.unpin_pointer(self)
    SaCursorPolicy.forget_pointer_device()
    SaSettings.software_cursor = _kept_mode
    if _host != null:
        _host.free()
        _host = null


## A window with a live canvas over the whole of it asking for a ring, and the
## pointer pinned over the canvas.
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
    return window


## The whole round trip: hidden over the ring, out, back in.
func test_the_pointer_is_hidden_again_after_the_focus_comes_back() -> void:
    if DisplayServer.get_name() == "headless":
        return
    SaSettings.software_cursor = "always"
    var window := _window_with_a_ring()
    assert_almost_eq(SaCursorPolicy.cursor_ring_radius_at(window, ON_CANVAS), RING, 0.001, "the ring is asked for under the pen")

    SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(_seat.writes, [Input.MOUSE_MODE_HIDDEN] as Array[int], "over the ring the pointer is written hidden")
    assert_false(_seat.pointer_on_screen, "and the screen shows the ring alone")

    _seat.lose_focus()
    SaCursorPolicy.note_focus_out()
    SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(_seat.writes.size(), 1, "a focus out writes nothing, it only forgets")

    SaCursorPolicy.note_focus_in()
    var expected: Array[int] = [Input.MOUSE_MODE_HIDDEN, Input.MOUSE_MODE_VISIBLE, Input.MOUSE_MODE_HIDDEN]
    assert_eq(_seat.writes, expected, "a focus in writes the hidden pointer whole, through visible so no driver skips it")
    assert_false(_seat.pointer_on_screen, "so only the ring shows after the trip out")

    SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(_seat.writes.size(), 3, "and the sync after it is back to writing only a change")


## The fault itself, read without the focus notes: a guard that writes only a
## change sees hidden already standing and leaves the system's pointer on.
func test_without_the_focus_notes_the_guard_would_leave_the_pointer_on() -> void:
    if DisplayServer.get_name() == "headless":
        return
    SaSettings.software_cursor = "always"
    _window_with_a_ring()
    SaCursorPolicy.sync_os_cursor_visibility()
    _seat.lose_focus()
    SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(_seat.writes.size(), 1, "the mode reads hidden, so the guard writes nothing")
    assert_true(_seat.pointer_on_screen, "and the pointer the system showed stays beside the ring")


## A pen that hovers over the ring while another program has the focus gets
## what it got before this unit: the ordinary guard's one write and no more.
func test_a_pen_over_the_ring_out_of_focus_changes_nothing() -> void:
    if DisplayServer.get_name() == "headless":
        return
    SaSettings.software_cursor = "always"
    SaCursorPolicy.note_focus_out()
    _window_with_a_ring()
    for _frame in 3:
        SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(_seat.writes, [Input.MOUSE_MODE_HIDDEN] as Array[int], "out of focus the guard writes as it always did")


## A focus in with no focus out before it, as at a start, writes nothing more
## than the guard would.
func test_a_focus_in_without_a_trip_out_writes_nothing_extra() -> void:
    if DisplayServer.get_name() == "headless":
        return
    SaSettings.software_cursor = "always"
    _window_with_a_ring()
    SaCursorPolicy.sync_os_cursor_visibility()
    SaCursorPolicy.note_focus_in()
    assert_eq(_seat.writes, [Input.MOUSE_MODE_HIDDEN] as Array[int], "no trip out, nothing to write again")
