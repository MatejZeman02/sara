## A mouse mode whose write does not read back is written once and said once,
## and written again only when the mode wanted changes.
##
## On the tablet Godot's Android display server keeps the asked mode but
## reports visible while its view can neither change the pointer's icon nor
## capture it, and the policy wrote hidden on every tick, 2391 lines of
## `wrote hidden, it read visible before` in a minute of painting. The seat
## here plays that display server, always reading visible.
##
## The canvas is a live one in a real window, the fixture the cursor-trip suite uses,
## because the policy walks `SaCanvas.live_canvases()`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RING: float = 12.0
const ON_CANVAS := Vector2(100, 60)


## A seat that records each write and always reads visible.
class StuckSeat:
    extends SaCursorPolicy.MouseModeSeat

    var writes: Array[int] = []

    func read() -> int:
        return Input.MOUSE_MODE_VISIBLE

    func write(new_mode: int) -> void:
        writes.append(new_mode)


## The lines said, kept rather than printed.
class KeptLog:
    extends SaCursorTrip.LogSeat

    var lines: Array[String] = []

    func say(line: String) -> void:
        lines.append(line)


var _host: Node = null
var _seat: StuckSeat = null
var _log: KeptLog = null
var _canvas: SaCanvas = null
var _kept_seat: SaCursorPolicy.MouseModeSeat = null
var _kept_log: SaCursorTrip.LogSeat = null
var _kept_mode: String = "auto"


func before_each() -> void:
    _kept_mode = SaSettings.software_cursor
    _kept_seat = SaCursorPolicy.mouse_mode_seat
    _kept_log = SaCursorTrip.log_seat
    _seat = StuckSeat.new()
    _log = KeptLog.new()
    SaCursorPolicy.mouse_mode_seat = _seat
    SaCursorTrip.log_seat = _log
    SaCursorTrip.take_write_whole()
    _host = Node.new()
    _host.name = "U815TestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    # Visible reads back on this seat, so the last write is forgotten and the
    # next suite starts with no memory of an unread one.
    if _canvas != null:
        _canvas.cursor_ring_radius = -1.0
        SaCursorPolicy.sync_os_cursor_visibility()
    _canvas = null
    SaCursorTrip.take_write_whole()
    SaCursorPolicy.mouse_mode_seat = _kept_seat
    SaCursorTrip.log_seat = _kept_log
    SaCursorPolicy.unpin_pointer(self)
    SaCursorPolicy.forget_pointer_device()
    SaSettings.software_cursor = _kept_mode
    if _host != null:
        _host.free()
        _host = null


## A window with a live canvas over the whole of it asking for a ring, and the
## pointer pinned over the canvas, so the policy wants hidden.
func _canvas_with_a_ring() -> SaCanvas:
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
    return canvas


func _ticks(count: int) -> void:
    for _tick in count:
        SaCursorPolicy.sync_os_cursor_visibility()


func test_a_hundred_ticks_wanting_hidden_write_it_once_and_say_it_once() -> void:
    if DisplayServer.get_name() == "headless":
        return
    SaSettings.software_cursor = "always"
    _canvas = _canvas_with_a_ring()
    _ticks(100)
    assert_eq(_seat.writes, [Input.MOUSE_MODE_HIDDEN] as Array[int], "hidden is written once though it never reads back")
    assert_eq(_log.lines.size(), 1, "and the log has one line for it: %s" % [_log.lines])
    assert_true(_log.lines[0].begins_with("wrote hidden, it read visible before"), "which says the write: %s" % _log.lines[0])


func test_each_change_of_the_mode_wanted_is_one_write() -> void:
    if DisplayServer.get_name() == "headless":
        return
    SaSettings.software_cursor = "always"
    _canvas = _canvas_with_a_ring()
    _ticks(100)

    _canvas.cursor_ring_radius = -1.0
    _ticks(100)
    var expected: Array[int] = [Input.MOUSE_MODE_HIDDEN, Input.MOUSE_MODE_VISIBLE]
    assert_eq(_seat.writes, expected, "wanting visible writes it once")

    _canvas.cursor_ring_radius = RING
    _ticks(100)
    expected.append(Input.MOUSE_MODE_HIDDEN)
    assert_eq(_seat.writes, expected, "and wanting hidden again writes it once more")
    assert_eq(_log.lines.size(), 3, "one line for each write: %s" % [_log.lines])
