## The verdict lines the app prints while the door listens, kept as they are
## printed so the answer to a step carries them the moment the step settles.
##
## A verdict line is one that opens with `SaCapture: `, the prefix every step
## of the table prints its outcome under, whether it went out as a `print` or,
## for a stroke that reached no dab, as an error. The engine may call a logger
## from any thread, so the lines are kept under a lock. The door's own lines
## open with `SaAgentDoor: ` and are not a step's, so they are left out. A
## failed stroke prints its line and pushes it as an error too, so an error
## whose line is already kept is not kept a second time.
##
## **A long answer is not printed whole.** A `layers` answer of the 540-layer
## mirrors file is a line of 116 kB, and a session that asked for it after each
## step wrote tens of megabytes of log, which the run log then held for a
## week. `say` hands a line longer than `LOG_CHARS` to the door's answer whole
## and prints a short line in its place naming its size, so the client reads
## what it always read and the log stays small. With no door listening,
## a scenario run, the line is printed whole, since that is where it is read.
class_name SaDoorVerdicts
extends SaErrorCatcher

## What a verdict line opens with.
const PREFIX := "SaCapture: "
## Lines kept between two answers at most, so a painter's session that
## prints for an hour with nobody asking holds a bounded list.
const CAP: int = 400
## The longest verdict line the log is given whole while the door listens. A
## glance or a measure of a busy file stays under it, and a layer stack of a
## few dozen layers does too.
const LOG_CHARS: int = 4000
## How much of a cut line the log keeps, enough to say which step it was.
const HEAD_CHARS: int = 120

## The verdict lines of the door that listens, or null with none.
static var _open: SaDoorVerdicts = null

var _lines: PackedStringArray = []
var _lock := Mutex.new()


## Starts keeping the verdict lines, for the door that has begun to listen.
static func install() -> SaDoorVerdicts:
    var kept := SaDoorVerdicts.new()
    OS.add_logger(kept)
    _open = kept
    return kept


## Stops keeping *kept*, for the door that closed.
static func uninstall(kept: SaDoorVerdicts) -> void:
    OS.remove_logger(kept)
    if _open == kept:
        _open = null


## Prints *text*, a step's verdict lines, and hands any line too long for the
## log to the listening door instead, printing what it was and its size. The
## short line opens without the verdict prefix, so the door keeps one line.
static func say(text: String) -> void:
    for line in text.split("\n"):
        if _open == null or line.length() <= LOG_CHARS:
            print(line)
            continue
        _open._keep(line, false)
        print(
            (
                "SaAgentDoor: %s, cut from %d characters, the answer holds it whole"
                % [line.trim_prefix(PREFIX).left(HEAD_CHARS), line.length()]
            )
        )


func _caught_message(message: String, _error: bool) -> void:
    _keep(message, false)


func _caught_error(report: Dictionary) -> void:
    _keep(report["text"], true)


## Every line since the last take, in the order printed, and an empty
## list from then on.
func take() -> PackedStringArray:
    _lock.lock()
    var out := _lines
    _lines = PackedStringArray()
    _lock.unlock()
    return out


func _keep(text: String, pushed: bool) -> void:
    if not text.contains(PREFIX):
        return
    _lock.lock()
    for line in text.split("\n", false):
        var trimmed := line.strip_edges()
        if pushed and _lines.has(trimmed):
            continue
        if trimmed.begins_with(PREFIX) and _lines.size() < CAP:
            _lines.append(trimmed)
    _lock.unlock()
