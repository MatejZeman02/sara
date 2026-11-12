## What the session printed and raised, as an answer carries it.
##
## Two readings of one session's output, held together because both are a
## client's view of what Sara said while its step ran. `printed` is the run
## log's own lines since the last dump, kept by an offset that walks forward,
## and `errors` and `warnings` are what the logger caught in the step, capped
## so one answer stays small.
extends RefCounted

## Errors and warnings an answer carries at most, each list, so a step that
## sets off an error every frame does not undo what the compact answer saves.
const RAISED_CAP: int = 12

## Characters of one error or warning line's message at most, its origin kept
## after them.
const RAISED_CHARS: int = 300

## What an engine puts before the file and line an error was raised at.
const ORIGIN_MARK: String = " at: "

## The most of the origin a cut line keeps.
const ORIGIN_CHARS: int = 160

## How far into the run log this session has read, so a dump carries what was
## written since, which is the lines since the last request that set `dump`.
##
## Advanced when an answer goes out rather than when a request arrives, because
## the engine's log is buffered: a line printed by a step is not always in the
## file by the time the next request is read, and an offset taken then repeated
## every earlier line in every later answer.
var _offset: int = 0


## Starts reading at the log's end, which is where a session that has just
## taken a client starts, so it does not open with the whole of startup in its
## first `printed`.
func start_at_the_end() -> void:
    _offset = size()


## The lines written since the last call, and the offset moves to exactly where
## this read ended, never to a fresh length: the log is buffered, and a line
## that lands between the read and a second look at the size is a line no dump
## would ever carry.
func printed_since() -> Array:
    var read := read_since(_offset)
    _offset = int(read["offset"])
    return read["lines"] as Array


## The errors and warnings in *taken*, what the logger kept since the last
## answer, as `{"errors": [...], "warnings": [...]}`, each list stopping at
## `RAISED_CAP` with a last line saying how many more. A failed step's error is
## kept even when its text is also a verdict line, because the session's list
## carries it and a client reading `errors` alone must see the step failed.
static func raised_in(taken: Dictionary) -> Dictionary:
    var out := {}
    for key: String in ["errors", "warnings"]:
        var kept: Array = []
        for raised: Variant in taken.get(key, []):
            kept.append(cut(String(raised)))
        out[key] = _capped(kept)
    return out


## *line* with its message cut at `RAISED_CHARS` and its origin kept after
## the cut. The origin, ` at: file:line`, is the part a client acts on, and a
## long path in the message pushed it past a cut taken from the end, so the cut
## is of the message and the origin is added to what is left, `ORIGIN_CHARS` at
## most. A line with no origin is cut at the cap.
static func cut(line: String) -> String:
    if line.length() <= RAISED_CHARS:
        return line
    var at := line.rfind(ORIGIN_MARK)
    if at < 0:
        return line.left(RAISED_CHARS)
    var message := line.left(at)
    if message.length() > RAISED_CHARS:
        message = message.left(RAISED_CHARS) + "..."
    return message + line.substr(at).left(ORIGIN_CHARS)


static func _capped(lines: Array) -> Array:
    if lines.size() <= RAISED_CAP:
        return lines
    var out := lines.slice(0, RAISED_CAP)
    out.append("and %d more" % (lines.size() - RAISED_CAP))
    return out


## The run log's lines since *offset*, and the offset they end at, which is
## what a dump's `printed` holds and what no compact answer reads.
##
## What this can and cannot deliver, measured rather than assumed. The engine's
## file logger buffers: a `push_warning` or an engine error turns up here in
## whatever flush the engine chooses, and a step's own `print` was still absent
## twenty frames after the step. So a raw socket client gets the errors and
## warnings of a session, late but in order, and not the executor's own lines.
##
## `scripts/sara_door.py` fills `printed` in from the child process's pipe
## instead, which carries prints, warnings and errors alike as they happen, and
## is what every client of this door in the tree uses.
##
## `get_buffer` after the seek rather than `get_as_text`, which reads the whole
## file whatever the cursor is at. With that, every answer carried every line
## the session had ever printed.
static func read_since(offset: int) -> Dictionary:
    var empty := {"lines": [], "offset": offset}
    var log_path := path()
    if not FileAccess.file_exists(log_path):
        return empty
    var file := FileAccess.open(log_path, FileAccess.READ)
    if file == null:
        return empty
    var size_now := file.get_length()
    if size_now <= offset:
        file.close()
        return empty
    file.seek(offset)
    var text := file.get_buffer(size_now - offset).get_string_from_utf8()
    file.close()
    var out: Array = []
    for line in text.split("\n", false):
        var trimmed := String(line).strip_edges()
        if not trimmed.is_empty():
            out.append(trimmed)
    return {"lines": out, "offset": size_now}


## Where the engine is writing its run log, which `SaTrail` knows, since a
## launcher's `--log-file` moves it.
static func path() -> String:
    return SaTrail.log_path()


static func size() -> int:
    var log_path := path()
    if not FileAccess.file_exists(log_path):
        return 0
    var file := FileAccess.open(log_path, FileAccess.READ)
    if file == null:
        return 0
    var length := file.get_length()
    file.close()
    return length
