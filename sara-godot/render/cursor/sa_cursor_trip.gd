## What the compositor did to the pointer between two of Sara's frames: the
## focus going out and coming back, the pointer leaving a window and coming
## over one, and each mode written in answer, with a `Sara cursor:` line in
## the log for each.
##
## One of the parts of the cursor package, private to it. The rest of the tree
## asks [SaCursorPolicy], which forwards here, and the policy stays the single
## writer of the mouse mode: this file says when a write has to be whole and
## makes the write the policy asks for, and decides nothing about what is
## drawn.
##
## **Why an enter writes whole as well as a focus in.** The focus in after a
## trip out writes the mode whole, because the system shows its own
## pointer over Sara while it is out of focus and Godot's mode still reads
## hidden. Two trips are left that a focus in does not see. GNOME Shell's
## Alt+Tab switcher grabs the pointer and draws its own during the grab, so a
## quick Alt+Tab that lands back on Sara may send no focus out or in at all,
## only the pointer leaving Sara's surface and coming back. And a focus in that
## comes before the pointer's enter has its whole write land while the surface
## does not hold the pointer, where the compositor drops it. Both end in an
## enter, so the enter writes whole too. An enter is rare, a few per trip, so
## the two writes it can cost are nothing.
class_name SaCursorTrip
extends RefCounted


## Where a `Sara cursor:` line goes, which is Sara's log. A suite stands a seat
## of its own here to read the lines. The head is put on here, inside the
## print, so the translation template reads the line as the log line it is.
class LogSeat:
    extends RefCounted

    func say(line: String) -> void:
        print("Sara cursor: " + line)


## The seat the lines are said through.
static var log_seat: LogSeat = LogSeat.new()

## Whether Sara has lost the focus to another program since it last had it,
## set by [method note_focus_out] and read by [method note_focus_in].
static var _out_of_focus: bool = false

## Whether the next sync writes the mode whatever it reads, set by a focus in
## after a trip out and by every enter.
static var _write_whole: bool = false

## The mode last written that did not read back afterwards, or -1 when the
## last write read back. Android's display server keeps the asked mode but
## reports visible while its view can neither change the pointer's icon nor
## capture it, so a guard that writes whenever the reading differs would
## write, and say so, on every tick.
static var _unread_write: int = -1


## Hears that another program took the focus. Every overlay hears it, one per
## window, so only the first changes anything or says so.
##
## Nothing is written here: a pen hovering over the canvas while the focus is
## away gets what it got before, the ring and no pointer where the compositor
## honours a hidden one.
static func note_focus_out(read: int) -> void:
    if _out_of_focus:
        return
    _out_of_focus = true
    _say("focus out, the mode reads %s" % mode_name(read))


## Hears that the focus came back, and answers whether the policy now writes
## the whole answer, which is after a trip out only.
static func note_focus_in(read: int) -> bool:
    if not _out_of_focus:
        return false
    _out_of_focus = false
    _write_whole = true
    _say("focus in, the mode reads %s" % mode_name(read))
    return true


## Hears that the pointer came over *window*, after a grab or a focus change or
## from another window, and asks for the whole answer at the next write.
static func note_pointer_entered(window: Window, read: int) -> void:
    _write_whole = true
    _say("pointer entered %s, the mode reads %s" % [_window_name(window), mode_name(read)])


## Hears that the pointer left *window*. Nothing to write: the pointer is the
## compositor's or another window's until it comes back.
static func note_pointer_left(window: Window, read: int) -> void:
    _say("pointer left %s, the mode reads %s" % [_window_name(window), mode_name(read)])


## Whether the write the policy is about to make goes whole, and forgets it,
## since one whole write answers the trip.
static func take_write_whole() -> bool:
    var whole := _write_whole
    _write_whole = false
    return whole


## Whether *seat* needs *wanted* written. After a write that did not read
## back the reading is not to be trusted, so the answer is whether *wanted*
## differs from that write, and a change to the mode the seat already reads is
## written as well. Otherwise it is whether the seat reads something else.
static func needs_write(seat: SaCursorPolicy.MouseModeSeat, wanted: int) -> bool:
    if _unread_write >= 0:
        return _unread_write != wanted
    return seat.read() != wanted


## Writes *mode* through *seat* and says so with what the seat read before,
## the one line a mode write leaves in the log, and remembers the mode when
## the seat does not read it back.
static func write(seat: SaCursorPolicy.MouseModeSeat, mode: int) -> void:
    var before := seat.read()
    seat.write(mode)
    _unread_write = mode if seat.read() != mode else -1
    _say("wrote %s, it read %s before" % [mode_name(mode), mode_name(before)])


## A mouse mode by the name the log gives it.
static func mode_name(mode: int) -> String:
    match mode:
        Input.MOUSE_MODE_VISIBLE:
            return "visible"
        Input.MOUSE_MODE_HIDDEN:
            return "hidden"
        Input.MOUSE_MODE_CAPTURED:
            return "captured"
        Input.MOUSE_MODE_CONFINED:
            return "confined"
        Input.MOUSE_MODE_CONFINED_HIDDEN:
            return "confined hidden"
    return "mode %d" % mode


static func _window_name(window: Window) -> String:
    if window == null or not is_instance_valid(window):
        return "no window"
    return "window %s" % window.name


static func _say(what: String) -> void:
    log_seat.say("%s at %s" % [what, Time.get_time_string_from_system()])
