## The connections that arrived while the door already held a client, and the
## answer each is given before it is closed.
##
## The door serves one client. A second closed before a byte of it was read
## would see a reset, and a notebook that ran `init` a second time would be told
## Sara "hung up with a step outstanding", as if a step might have run. Closing
## at once is also a race: bytes of a request the client has sent
## and the door never read make the close a reset, and the reset can reach the
## client before the answer does. So a refused connection is held until its
## request head has arrived, at most `wait_seconds`, then answered with a 409
## that says another client holds the door and how to free it, and only then
## closed. Nothing of its request is run and its token is never looked at.
extends RefCounted

const DoorWire := preload("res://harness/door/sa_door_wire.gd")

## Refused connections held at once at most, so a program that opens sockets
## and says nothing cannot grow the list without bound.
const HOLD_LIMIT: int = 8

## Seconds a refused connection is held for its request head.
var wait_seconds: float = 5.0
## What the answer says about how long an idle client keeps the door.
var idle_seconds: float = 600.0

var _held: Array[Dictionary] = []


func _init(wait: float, idle: float) -> void:
    wait_seconds = wait
    idle_seconds = idle


## How many refused connections are waiting for their answer.
func waiting() -> int:
    return _held.size()


## Takes *peer*, a connection the door has no room for.
func hold(peer: StreamPeerSocket) -> void:
    if _held.size() >= HOLD_LIMIT:
        peer.disconnect_from_host()
        return
    _held.append({"wire": DoorWire.new(peer), "since": Time.get_ticks_usec()})


## One frame: answers each held connection whose request has come, and lets go
## of one that left, opened with something that is no HTTP request, or has
## waited too long.
func poll() -> void:
    var keep: Array[Dictionary] = []
    for entry in _held:
        var wire := entry["wire"] as DoorWire
        if not wire.connected():
            wire.close()
            continue
        wire.read_available()
        var waited := float(Time.get_ticks_usec() - int(entry["since"])) / 1_000_000.0
        if wire.opens_wrong() or wire.buffered() > DoorWire.Request.HEAD_LIMIT or waited > wait_seconds:
            wire.close()
            continue
        var request := wire.take_request()
        if request == null:
            keep.append(entry)
            continue
        wire.send_http(409, {"ok": false, "error": message(), "help": "close the other client, or wait"}, true)
        wire.close()
    _held = keep


## Every connection let go of, the door closing.
func close() -> void:
    for entry in _held:
        (entry["wire"] as DoorWire).close()
    _held.clear()


## What the refused client reads. The Python client `scripts/sara.py` lets go
## of the door after two idle seconds and attaches again on its next call, so a
## notebook holds it only while a call runs, and the door's own idle drop is
## for a client that never lets go.
func message() -> String:
    return (
        "another notebook or script is connected to Sara, and the door serves one client. "
        + "A notebook through sara.py lets go by itself a moment after its call ends, so trying again shortly is enough. "
        + "Any other client frees the door when it closes, or after it has been idle for %d minutes." % int(idle_seconds / 60.0)
    )
