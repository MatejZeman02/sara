## The errors and warnings the engine reports while the door listens, kept as
## they happen.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The door read them out of the run log, which the engine buffers, so a
## warning reached the answer late and a client that could not read Sara's
## files had no other way to them. This logger is installed with the engine
## when the door opens and taken out when it closes, and keeps each report with
## its function, file and line. A message the engine repeats every frame is one
## entry with a count, and the entries stop at `CAP`, so a flood an hour long
## holds a bounded list and the `errors` step says how much it left out.
##
## A report that finds the list full is still the answer's, with its level and
## origin, when it was raised during that answer's step. A count in its place
## would name no error, and would sit in `errors` whatever the report's level,
## so the same event, a stroke that laid nothing say, would read as a warning
## while the list had room and as a failure once it filled.
##
## Two readers. The door takes what was raised since its last answer for the
## answer's `errors` and `warnings`, and the `errors` step answers the whole
## session's entries through `lines`, which is what a client asks for when it
## wants the whole list and has a session to ask.
##
## The engine may call a logger from any thread, so everything is under a lock,
## and nothing here prints, because a print from inside a logger is a report
## to every logger again.
##
## Reached by path, like every file of the harness, and one session at a time:
## `install` and `uninstall` keep the one the `errors` step reads.
extends SaErrorCatcher

## Entries kept at most, a session's worth of distinct reports.
const CAP: int = 200

## The levels each filter keeps, the same three `godot_console.wanted` knows.
const FILTERS := {
    "error": ["ERROR", "SCRIPT ERROR", "SHADER ERROR"],
    "warning": ["ERROR", "SCRIPT ERROR", "SHADER ERROR", "WARNING"],
}

## The logger the door has installed, or null while no door listens.
static var _session: Logger = null

## The entries in the order first raised, each a dictionary of `level`,
## `function`, `file`, `line`, `message`, `count` for the session and `fresh`
## for the raises since the last `take`.
var _entries: Array[Dictionary] = []
## Each entry's index in `_entries` by its level, origin and message.
var _index: Dictionary = {}
## Reports that found the list full, since the session began.
var _dropped: int = 0
## The reports since the last take that found the list full, as entries of
## the same shape keyed as `_index` keys them, so the next answer names each
## even though the session's list has no room for it.
var _past: Dictionary = {}
## Reports since the last take past even `_past`'s `CAP`, by level, which one
## step raising more than `CAP` distinct ones would need.
var _past_more: Dictionary = {}
var _lock := Mutex.new()


## Adds *logger*, a fresh one of these, to the engine and makes it the one
## the `errors` step reads. The door calls this when it starts listening.
static func install(logger: Logger) -> void:
    OS.add_logger(logger)
    _session = logger


## Takes *logger* out of the engine, and out of the `errors` step's reach when
## it is the one there.
static func uninstall(logger: Logger) -> void:
    OS.remove_logger(logger)
    if _session == logger:
        _session = null


## Lists the session's errors: every one raised since the door opened, one
## verdict line each with its count and origin, the level one of `error`,
## `warning`, the default, or `all`, `{"errors": {"level": "warning"}}`. Kept by
## the door's logger as they happen, so nothing is read from the run log.
static func capture(args: Variant) -> String:
    var level := level_of(args)
    if _session == null:
        return "SaCapture: errors, no door listens, so nothing keeps them"
    var kept: PackedStringArray = _session.call("lines", level)
    var head := "SaCapture: errors at level %s, %d entries" % [level, kept.size()]
    if kept.is_empty():
        return head
    return head + "\n" + "\n".join(Array(kept).map(func(line: String) -> String: return "SaCapture: " + line))


## The level an `errors` step's *args* ask for, `warning` unless they name one.
static func level_of(args: Variant) -> String:
    return String((args as Dictionary).get("level", "warning")) if args is Dictionary else "warning"


## The session's entries at *level*, whole, for the door's answer to an
## `errors` step. Empty while no door listens.
static func session_entries(level: String) -> Array:
    return _session.call("entries", level) if _session != null else []


func _caught_error(report: Dictionary) -> void:
    var where := {"function": report["function"], "file": report["file"], "line": report["line"]}
    # A script's `push_error` is reported from the engine's own source, so
    # the script's frame, when the engine kept one, is the origin worth having.
    for trace: ScriptBacktrace in report["backtraces"]:
        if trace != null and trace.get_frame_count() > 0:
            where = {"function": trace.get_frame_function(0), "file": trace.get_frame_file(0), "line": trace.get_frame_line(0)}
            break
    _keep(report["kind"], where, String(report["text"]).strip_edges())


## Printed lines are the run log's, not the door's errors.
func _caught_message(_message: String, _error: bool) -> void:
    pass


func _keep(level: String, where: Dictionary, message: String) -> void:
    var key := "%s|%s|%s|%d|%s" % [level, where["function"], where["file"], where["line"], message]
    _lock.lock()
    if _index.has(key):
        var entry: Dictionary = _entries[int(_index[key])]
        entry["count"] = int(entry["count"]) + 1
        entry["fresh"] = int(entry["fresh"]) + 1
    elif _entries.size() < CAP:
        var entry := where.duplicate()
        entry["level"] = level
        entry["message"] = message
        entry["count"] = 1
        entry["fresh"] = 1
        _index[key] = _entries.size()
        _entries.append(entry)
    else:
        _dropped += 1
        _keep_past(key, level, where, message)
    _lock.unlock()


## Keeps a report the session's list had no room for until the next take, under
## the lock `_keep` holds.
func _keep_past(key: String, level: String, where: Dictionary, message: String) -> void:
    if _past.has(key):
        var entry: Dictionary = _past[key]
        entry["fresh"] = int(entry["fresh"]) + 1
    elif _past.size() < CAP:
        var entry := where.duplicate()
        entry["level"] = level
        entry["message"] = message
        entry["fresh"] = 1
        _past[key] = entry
    else:
        _past_more[level] = int(_past_more.get(level, 0)) + 1


## What was raised since the last take, as `{"errors": [...], "warnings":
## [...]}` of one line each, the entry's count in this spell after it when
## more than one. A report that found the session's list full is named here
## all the same, after the kept ones, so the answer to a step is the same
## whether the list has filled or not. The spell starts again from here.
func take() -> Dictionary:
    var errors: Array = []
    var warnings: Array = []
    _lock.lock()
    for entry in _entries:
        var fresh := int(entry["fresh"])
        if fresh == 0:
            continue
        entry["fresh"] = 0
        var into: Array = warnings if entry["level"] == "WARNING" else errors
        into.append(_line(entry, fresh))
    for entry: Dictionary in _past.values():
        var into: Array = warnings if entry["level"] == "WARNING" else errors
        into.append(_line(entry, int(entry["fresh"])))
    for level: String in _past_more:
        var into: Array = warnings if level == "WARNING" else errors
        into.append("%s: and %d more raised in this step" % [level, int(_past_more[level])])
    _past.clear()
    _past_more.clear()
    _lock.unlock()
    return {"errors": errors, "warnings": warnings}


## The session's entries at *level*, each a copy with its session count, and a
## last `{"level": "DROPPED", "count": n}` when the list filled.
func entries(level: String) -> Array:
    var out: Array = []
    _lock.lock()
    for entry in _entries:
        if _wanted(String(entry["level"]), level):
            var copy := entry.duplicate()
            copy.erase("fresh")
            out.append(copy)
    if _dropped > 0:
        out.append({"level": "DROPPED", "message": "reports past the %d kept" % CAP, "count": _dropped})
    _lock.unlock()
    return out


## The session's entries at *level* as the lines the `errors` step prints.
func lines(level: String) -> PackedStringArray:
    var out := PackedStringArray()
    for entry: Dictionary in entries(level):
        out.append(_line(entry, int(entry["count"])))
    return out


static func _wanted(entry_level: String, level: String) -> bool:
    return level == "all" or not FILTERS.has(level) or (FILTERS[level] as Array).has(entry_level)


## One entry as a line, `ERROR: message at: function (file:line)`, with
## ` x<count>` when it was raised more than once.
static func _line(entry: Dictionary, count: int) -> String:
    var text := "%s: %s" % [entry["level"], entry.get("message", "")]
    if entry.has("file"):
        text += " at: %s (%s:%d)" % [entry["function"], entry["file"], int(entry["line"])]
    if count > 1:
        text += " x%d" % count
    return text
