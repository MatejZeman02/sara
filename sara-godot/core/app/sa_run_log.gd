## Sara's run log, `godot.log` in Godot's user folder, written by Sara rather
## than by the engine, so a second Sara never takes the log of one running.
##
## **Why not the engine's.** The engine's file logging sets the old log aside
## and opens the file afresh at every start, before any script runs, and a Sara
## already running goes on writing at its old offset, so a second start beside
## a running one leaves the running one's log holding the new run's bytes, then
## a run of zeros, then its own next line. What the engine offers falls short:
## the project setting names one
## path for every run, `--log-file` names one per launch and opens it afresh
## the same way, and an exported Sara on Windows has no launcher to pass it
## anything. So `project.godot` turns the engine's file logging off, its `.pc`
## override included, which the engine turns on by default, and this, the first
## autoload, opens the log before any other script prints.
##
## **Where it is.** `user://logs/godot.log`, or under `--settings-dir`'s
## folder, and on Android `Documents/Sara/godot.log`, where a file manager
## reaches it, as `SaDataRoot.default_log()` says.
##
## **Who holds it.** The log's first line names the process writing it, and
## once that Sara closes, its last line says so. A start that finds the log
## named by another Sara that runs and has not closed it writes a log of its own
## beside it, `godot<time>.<pid>.log`, and puts that file in the project
## setting `SaTrail.log_path()` reads. Otherwise it sets the old log aside the
## way the engine did, copied to `godot<time>.log`, keeps `max_log_files` of
## them and opens the file afresh.
##
## **A launcher's log wins.** The gate, the captures and the door pass
## `--log-file`, which turns the engine's own logging on again for that one
## path, and set `SARA_LOG_FILE` beside it. A run with that variable opens
## nothing here.
##
## What reaches the file is what the engine's logger wrote: every print with
## the colour codes of `print_rich` stripped, and every error and warning in
## the engine's own lines, so `godot_console.py` and the door read it as they
## would the engine's. Beside its own opening and closing lines it lacks only
## the engine's lines from before any script runs, the engine's version, the
## device and the display server's warnings. The boot
## banner's Build, Renderer and Device rows say the first two, and standard
## output still carries all of them.
extends Node

## The engine's setting that names the log, which this reads and, for a log of
## this run's own, writes.
const PATH_SETTING := "debug/file_logging/log_path"
## How many logs the folder keeps, the current one among them.
const KEEP_SETTING := "debug/file_logging/max_log_files"
## Set by a launcher that passed `--log-file`, the variable `SaTrail` reads.
const LAUNCHER_LOG := "SARA_LOG_FILE"


func _init() -> void:
    # The first line of Sara's code that runs, so the ready line can tell the
    # engine's own start from the autoloads.
    SaBootMarks.mark(SaBootMarks.SARA_BEGINS)
    if SaDataRoot.moved():
        ProjectSettings.set_setting(PATH_SETTING, SaDataRoot.log_path())
    if not OS.get_environment(LAUNCHER_LOG).is_empty():
        return
    var fallback := SaDataRoot.default_log()
    var configured := str(ProjectSettings.get_setting(PATH_SETTING, fallback))
    if configured == SaDataRoot.ENGINE_LOG:
        configured = fallback
    var base := ProjectSettings.globalize_path(configured)
    var keep: int = ProjectSettings.get_setting(KEEP_SETTING, 5)
    var writer := Writer.open(base, keep)
    if writer == null:
        push_warning("SaRunLog: %s could not be opened, so this run keeps no log file." % base)
        return
    # The engine's reference is the only one, and the engine lets go of its
    # loggers after every node is freed, so the closing line is the last.
    OS.add_logger(writer)
    ProjectSettings.set_setting(PATH_SETTING, writer.path)


## The logger the engine hands every line to, from any thread.
class Writer:
    extends SaErrorCatcher

    ## The first line of a log, before the process id and the time.
    const OPENED := "Sara log: opened by process "
    ## The last line of a log whose Sara closed it, before the process id.
    const CLOSED := "Sara log: closed by process "
    ## How far from its end a log is read for the closing line.
    const TAIL_BYTES := 256

    ## The file this writes, as a path outside Godot.
    var path: String = ""
    var _file: FileAccess = null
    var _lock := Mutex.new()
    ## Set while a line is written, so an error the write raises is not
    ## handed back to it.
    var _writing: bool = false
    ## The engine's own pattern for a terminal colour code.
    var _colour := RegEx.create_from_string("\u001b\\[((?:\\d|;)*)([a-zA-Z])")

    func _init(file: FileAccess, at: String) -> void:
        _file = file
        path = at
        _write("%s%d at %s\n" % [OPENED, OS.get_process_id(), Time.get_datetime_string_from_system(false, true)])

    ## Opens the log at *base*, or one of this run's own beside it while
    ## another Sara holds that one. *keep* is how many logs the folder keeps.
    ## Null when no file would open.
    static func open(base: String, keep: int) -> Writer:
        DirAccess.make_dir_recursive_absolute(base.get_base_dir())
        var stamp := Time.get_datetime_string_from_system().replace(":", ".")
        var at := base
        if SaProcess.another_runs(holder(base)):
            at = "%s%s.%d.%s" % [base.get_basename(), stamp, OS.get_process_id(), base.get_extension()]
        elif FileAccess.file_exists(base) and keep > 1:
            DirAccess.copy_absolute(base, "%s%s.%s" % [base.get_basename(), stamp, base.get_extension()])
            _keep_newest(base, keep - 1)
        var file := FileAccess.open(at, FileAccess.WRITE)
        if file == null:
            return null
        return Writer.new(file, at)

    ## The process the log at *base* names as its writer, and 0 when it names
    ## none or that process has closed it.
    static func holder(base: String) -> int:
        var file := FileAccess.open(base, FileAccess.READ)
        if file == null:
            return 0
        var first := file.get_line()
        if not first.begins_with(OPENED):
            return 0
        file.seek(maxi(0, file.get_length() - TAIL_BYTES))
        # As ASCII, since the cut may fall inside a character and the line
        # looked for has none outside it.
        var tail := file.get_buffer(TAIL_BYTES).get_string_from_ascii().strip_edges()
        if tail.get_slice("\n", tail.count("\n")).begins_with(CLOSED):
            return 0
        return first.trim_prefix(OPENED).get_slice(" ", 0).to_int()

    ## Removes all but the *backups* newest set-aside logs beside *base*, the
    ## way the engine's logger did: by name, which begins with the time.
    static func _keep_newest(base: String, backups: int) -> void:
        var folder := base.get_base_dir()
        var aside := PackedStringArray()
        for name in DirAccess.get_files_at(folder):
            if name != base.get_file() and name.begins_with(base.get_file().get_basename()):
                if name.get_extension() == base.get_extension():
                    aside.append(name)
        aside.sort()
        for i in aside.size() - backups:
            DirAccess.remove_absolute(folder.path_join(aside[i]))

    func _caught_message(message: String, _error: bool) -> void:
        _write(_colour.sub(message, "", true) if message.contains("\u001b") else message)

    func _caught_error(report: Dictionary) -> void:
        var where := "%s (%s:%d)" % [report["function"], report["file"], report["line"]]
        var text := "%s: %s\n   at: %s\n" % [report["kind"], report["text"], where]
        for backtrace: ScriptBacktrace in report["backtraces"]:
            if not backtrace.is_empty():
                text += backtrace.format(3) + "\n"
        _write(text)

    ## Writes the closing line once the engine lets go of the logger, or a
    ## suite does. Spelled out here rather than in a method, since a method
    ## call on `self` fails inside `PREDELETE`.
    func _notification(what: int) -> void:
        if what != NOTIFICATION_PREDELETE:
            return
        _lock.lock()
        if _file != null:
            _file.store_string("%s%d\n" % [CLOSED, OS.get_process_id()])
            _file.close()
            _file = null
        _lock.unlock()

    ## Every line is flushed as it comes, as the debug export's engine logger
    ## does, so a run killed mid-line leaves every line before it.
    func _write(text: String) -> void:
        _lock.lock()
        if _file != null and not _writing:
            _writing = true
            _file.store_string(text)
            _file.flush()
            _writing = false
        _lock.unlock()
