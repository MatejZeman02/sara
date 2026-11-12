## The one logger Sara hands the engine: whatever is printed or raised while
## it listens, kept as a report.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Thirty files once wrote their own `Logger`, each with the engine's eight
## arguments, its own lock and its own idea of which text a report carries.
## This is the one class that says `extends Logger`. A
## suite makes one, `listening()`, reads what it caught by kind and calls
## `stop()`. The run log, the door's verdicts and errors and the MIDI inputs
## extend it and answer `_caught_error` and `_caught_message` instead of the
## engine's two methods, so each reads a report already named and worded.
##
## In `core/api` because a module catches the engine's errors too, and a
## module sees the door and nothing else of the skeleton.
##
## The engine may call a logger from any thread, so what is kept is kept
## under a lock, and nothing here prints, because a print from inside a logger
## is a report to every logger again.
class_name SaErrorCatcher
extends Logger

## The kind of a report the engine raised with `push_error` or its own error.
const ERROR := "ERROR"
## The kind of a warning.
const WARNING := "WARNING"
## The kind of a script's own error.
const SCRIPT := "SCRIPT ERROR"
## The kind of a shader's compile error.
const SHADER := "SHADER ERROR"
## The kind of a line printed with `print`.
const PRINTED := "PRINTED"
## The kind of a line printed with `printerr`.
const PRINTED_AS_ERROR := "PRINTED AS ERROR"
## Every kind that is an error, the warnings left out.
const ERRORS: Array[String] = [ERROR, SCRIPT, SHADER]
## Every kind the engine raises, warnings with the errors.
const RAISED: Array[String] = [ERROR, SCRIPT, SHADER, WARNING]
## Both kinds of printed line.
const PRINTS: Array[String] = [PRINTED, PRINTED_AS_ERROR]
## How the engine's `Logger.ErrorType` reads as a kind, the names the run log
## has always written and `scripts/godot_console.py` filters on.
const KINDS := {
    ERROR_TYPE_ERROR: ERROR,
    ERROR_TYPE_WARNING: WARNING,
    ERROR_TYPE_SCRIPT: SCRIPT,
    ERROR_TYPE_SHADER: SHADER,
}

## Every report kept, in the order caught.
var _caught: Array[Dictionary] = []
var _caught_lock := Mutex.new()


## A fresh catcher the engine already hands its lines to.
static func listening() -> SaErrorCatcher:
    var catcher := SaErrorCatcher.new()
    OS.add_logger(catcher)
    return catcher


## Takes this catcher out of the engine. What it caught stays readable.
func stop() -> void:
    OS.remove_logger(self)


func _log_message(message: String, error: bool) -> void:
    _caught_message(message, error)


func _log_error(
    function: String,
    file: String,
    line: int,
    code: String,
    rationale: String,
    _editor_notify: bool,
    error_type: int,
    script_backtraces: Array[ScriptBacktrace]
) -> void:
    _caught_error(
        {
            "kind": KINDS.get(error_type, ERROR),
            "function": function,
            "file": file,
            "line": line,
            "code": code,
            "rationale": rationale,
            "text": rationale if not rationale.is_empty() else code,
            "backtraces": script_backtraces,
        }
    )


## A line printed while this listens, *error* when it went to `printerr`. A
## subclass answers it to do its own work, and this keeps it as a report of
## `kind` and `text`, the line without its surrounding blanks.
func _caught_message(message: String, error: bool) -> void:
    var kind := PRINTED_AS_ERROR if error else PRINTED
    _hold({"kind": kind, "text": message.strip_edges()})


## A report the engine raised, a dictionary of `kind`, `function`, `file`,
## `line`, `code`, `rationale`, `text`, which is the rationale or else the code,
## and `backtraces`, the script's frames when the engine kept them. A subclass
## answers it to do its own work, and this keeps it without its frames.
func _caught_error(report: Dictionary) -> void:
    var kept := report.duplicate()
    kept.erase("backtraces")
    _hold(kept)


## The reports kept of the *kinds* named, copies in the order caught.
func reports(kinds: Array[String]) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    _caught_lock.lock()
    for report in _caught:
        var kind: String = report["kind"]
        if kinds.has(kind):
            out.append(report.duplicate())
    _caught_lock.unlock()
    return out


## The text of each report kept of the *kinds* named.
func texts(kinds: Array[String]) -> PackedStringArray:
    var out := PackedStringArray()
    for report in reports(kinds):
        var text: String = report["text"]
        out.append(text)
    return out


## Each report of the *kinds* named as the line a suite's failure message
## shows, `function: code rationale` for a raised one and the text for a
## printed one.
func described(kinds: Array[String]) -> PackedStringArray:
    var out := PackedStringArray()
    for report in reports(kinds):
        if report.has("function"):
            out.append("%s: %s %s" % [report["function"], report["code"], report["rationale"]])
        else:
            var text: String = report["text"]
            out.append(text)
    return out


## Every line printed while this listened, `print` and `printerr` alike.
func printed() -> PackedStringArray:
    return texts(PRINTS)


func _hold(report: Dictionary) -> void:
    _caught_lock.lock()
    _caught.append(report)
    _caught_lock.unlock()
