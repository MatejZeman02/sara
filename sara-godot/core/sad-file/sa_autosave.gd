## The timed autosave: a recovery copy written after a few minutes of work,
## only once the painter has stopped, and offered back on the next launch.
##
## The interval only arms the save. The save then waits for the Idle After
## preference's seconds with no change to the document and no stroke in
## progress, and for no other save to be running. The wait stands although the
## save does not stall the window: a copy taken mid-stroke would hold half a
## stroke, and the quiet is when a snapshot of the card costs the painter least.
##
## **In the background.** One autosave is one `SaSadFile.save_in_background`,
## the save File > Save runs. The tick asks the card for the hashes of the
## document's textures and returns, the walk takes the snapshot once they are
## in and the document still stands where it stood at the ask, the readback
## runs a few textures a frame and the file is written on a worker, so the
## window never waits for it, where a snapshot taken at the tick held a frame
## of 0.7 s on the seasons file. What is painted after the snapshot is in the
## document and not in the copy. The progress
## line shows it as it shows a Save, by the copy's own file name, so a painter
## who sees the line move knows it is the autosave and not their file.
##
## **Once written.** `saved` and `last_written` follow the file when it is on
## disk, not when it is asked for. A recovery copy that lands after the
## document turned clean, by a Save or an undo back to the saved state, or
## after `discard_recovery` was asked while it was being written, is deleted
## as it lands, so it never outlives a clean document.
##
## The wait is `SaSettings.idle_after_seconds`, the one every idle job reads,
## five seconds by default, and not a wait of the autosave's own. It is read at
## each check rather than mirrored, so a change in Preferences takes effect at
## the next frame, and a suite that sets it is heard with `follow_settings` off.
##
## Two targets. By default the copy goes to `<name>.autosave.sad` beside the
## document, or under `user://autosave/` for a document that has never been
## saved, was opened from `res://` or is an address Android's picker handed
## over, and the painter's own file is never
## written on a timer. With `SaSettings.autosave_to_working_file` on it writes
## the document itself, as a Save would, and the `.sad1` chain keeps the
## version before, except for a `res://` document, which is the checkout's own
## file in a run from source and read only in an exported build.
##
## **The codec is the file's.** The working file is written in the codec it
## holds, so over a file saved as JPEG XL the painted chunks are coded in JPEG
## XL on the pool and the rest copied, which `SaSadSave` reads from the last
## save's record of the path. The recovery copy claims nothing and is
## written in Zstd whatever the working file holds, since it exists for a crash
## and opens in any Sara, with the module or without it.
##
## **When the display goes.** A lost Wayland compositor ends the engine with a
## trap and no frame after it, so `PerDocument` keeps a `DisplayGone` logger
## that hears the engine's report of it and writes every recovery copy at once,
## on the main thread, before the trap. The timer cannot be trusted to have
## written one recently, since it waits minutes.
##
## A `Node`, so it ticks with the frame and dies with main. The clock is passed
## in rather than read, so a test can drive minutes in a call.
class_name SaAutosave
extends Node

const RECOVERY_SUFFIX := ".autosave.sad"
## The folder the recovery copies go in, under the data root, so a run
## with its own settings folder never lists or deletes the painter's copies.
const RECOVERY_FOLDER := "autosave"

## The path just written, once it is on disk, for whoever wants to know.
signal saved(path: String)

## The recovery copies a previous session left, as `find_recoveries` answers
## them, and never empty. The autosave finds and says, and the interface asks:
## a class under `core` opens no window, so the dialogs of `ui/main` hear this
## and answer through `open_recovery` and `delete_recovery`.
signal recoveries_found(pending: Array)

var document: SaDocument = null

## Seconds of work between saves, 0 for never. Mirrored from Preferences each
## tick while `follow_settings` is on, which a test turns off.
var interval_seconds: float = 120.0
var write_working_file: bool = false
var follow_settings: bool = true

## The recovery copy this session last wrote, set once it is on disk, and
## removed once the document is clean again or the painter quits on purpose.
var last_written: String = ""

## Which surfaces asked a painter about recovery copies this session, in order:
## `"chain"` for the one window per copy the boot opens when the welcome window
## does not, `"pane"` for the welcome window's recovery row. The dump reads it,
## because a shot of an empty pane and a shot of a boot that found nothing look
## the same.
var offer_surfaces: Array[String] = []

var _elapsed_since_save: float = 0.0
var _last_activity_msec: int = 0
var _session_stamp: String = ""
## How many times the recovery copy was retired, so a copy being written when
## it was is deleted as it lands rather than kept.
var _retirements: int = 0


func _init() -> void:
    name = "SaAutosave"
    _session_stamp = Time.get_datetime_string_from_system(false, false).replace(":", "-")


## Watches *doc*. Every change resets the quiet clock, and the document turning
## clean, which is a save or a load, retires the recovery copy.
func attach(doc: SaDocument) -> void:
    document = doc
    _last_activity_msec = Time.get_ticks_msec()
    if not doc.document_changed.is_connected(_on_activity):
        doc.document_changed.connect(_on_activity)
    if not doc.chunks_invalidated.is_connected(_on_chunks_invalidated):
        doc.chunks_invalidated.connect(_on_chunks_invalidated)
    if not doc.modified_changed.is_connected(_on_modified_changed):
        doc.modified_changed.connect(_on_modified_changed)


## Stops watching, for a document the painter closed. The copy this autosave
## wrote goes, and so does one being written, as it lands, because a close is
## a choice the painter made and only a crash leaves a copy behind. After it
## the timer asks for nothing, since it has no document.
func detach() -> void:
    discard_recovery()
    if document != null:
        for pair: Array in [
            [document.document_changed, _on_activity],
            [document.chunks_invalidated, _on_chunks_invalidated],
            [document.modified_changed, _on_modified_changed],
        ]:
            var sent: Signal = pair[0]
            var heard: Callable = pair[1]
            if sent.is_connected(heard):
                sent.disconnect(heard)
    document = null
    _elapsed_since_save = 0.0


func _process(delta: float) -> void:
    if follow_settings:
        interval_seconds = SaSettings.autosave_interval_minutes * 60.0
        write_working_file = SaSettings.autosave_to_working_file
    tick(delta, Time.get_ticks_msec())


## One frame of the timer. Returns whether a save was asked for. It runs in
## the background, so the file is not on disk yet when this returns.
func tick(delta: float, now_msec: int) -> bool:
    if document == null or not document.modified or interval_seconds <= 0.0:
        _elapsed_since_save = 0.0
        return false
    _elapsed_since_save += delta
    if _elapsed_since_save < interval_seconds:
        return false
    if now_msec - _last_activity_msec < SaSettings.idle_after_seconds * 1000.0 or is_stroke_open():
        return false
    # A save running already, the painter's or the last autosave, holds what
    # the painter has anyway, and this one would only queue behind it.
    if SaSadFile.saving():
        return false
    var err := save_now()
    _elapsed_since_save = 0.0
    return err == OK


## Whether a stroke is being painted: the stroke buffer holds chunks until the
## commit, and an erase paints straight into the layer through the transaction.
func is_stroke_open() -> bool:
    if document == null:
        return false
    if document.stroke_layer != null and not document.stroke_layer.chunks.is_empty():
        return true
    return document.stroke_transaction != null and document.stroke_transaction.direct_paint


## Tells the timer something happened now, so the wait for quiet starts again.
func note_activity(now_msec: int) -> void:
    _last_activity_msec = now_msec


## Asks for the autosave once, wherever the settings send it, in the
## background, rounding as a Save does. The working file claims the document
## and keeps the `.sad1` chain, and the recovery copy claims nothing and keeps
## no older copy. OK means the save was asked for, `saved` when it is on disk.
func save_now() -> Error:
    if document == null:
        return ERR_UNCONFIGURED
    if write_working_file and not document.file_path.is_empty() and not is_in_resources(document.file_path):
        var file := document.file_path
        SaSadFile.save_in_background(document, file, -1, null, true, _on_working_file_written.bind(file), true, &"", true)
        return OK
    var path := recovery_path()
    if path.begins_with(recovery_dir()):
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(recovery_dir()))
    SaSadFile.save_in_background(document, path, 0, null, false, _on_recovery_written.bind(path, _retirements), true, &"", true)
    return OK


## Writes the recovery copy now, on this thread, for a Sara about to die: the
## engine has lost its display and will end the process once the report of it
## returns, so there is no frame left for a save in the background. A save of
## the background running already is driven to its end first, since the copy
## and the working file may both be in it. Nothing is written for a document
## with no unsaved work.
func save_before_the_end() -> Error:
    if document == null or not document.modified:
        return OK
    @warning_ignore("integer_division")
    SaSadFile.finish_saves(DisplayGone.LONGEST_WAIT_MSEC / 2)
    var path := recovery_path()
    if path.begins_with(recovery_dir()):
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(recovery_dir()))
    var err := SaSadFile.save_file(document, path, 0)
    if err == OK:
        last_written = path
    return err


## The working file is on disk. The save itself marked the document saved
## when nothing changed after its snapshot. A failure is reported by the save.
func _on_working_file_written(err: Error, path: String) -> void:
    if err == OK:
        saved.emit(path)


## The recovery copy is on disk. Kept when the document still has unsaved
## work and was not clean at any moment since the copy was asked for, and
## otherwise deleted, because a Save or an undo to the saved state has made
## it stale. A failure is reported by the save.
func _on_recovery_written(err: Error, path: String, retirements: int) -> void:
    if err != OK:
        return
    if document == null or not document.modified or retirements != _retirements:
        delete_recovery(path)
        return
    last_written = path
    saved.emit(path)


## Where this document's recovery copy goes: beside it, or under the user
## directory for one that has no beside yet. An untitled copy is named for the
## session and for the document, so two untitled documents from two runs, or
## two open at once in one run, never share a file. The document's instance id
## is unique while the run lasts, which is as long as the name has to be.
func recovery_path() -> String:
    if document != null and not document.file_path.is_empty():
        return recovery_path_for(document.file_path)
    var which := document.get_instance_id() if document != null else 0
    return recovery_dir().path_join("untitled-%s-%d%s" % [_session_stamp, which, RECOVERY_SUFFIX])


## The folder an untitled document's recovery copy goes in, under the data
## root.
static func recovery_dir() -> String:
    return SaDataRoot.path(RECOVERY_FOLDER)


## The recovery copy of the file at *file_path*: beside it, or under the
## recovery folder for a file under `res://`, named for its whole path so two
## fixtures of one name in two folders keep two copies. A test or a lesson
## opening a fixture then leaves the checkout as it found it.
##
## A `content://` address goes under the recovery folder as well. Android's
## picker grants the one address it handed over, and one made up beside it
## names no document, so a copy written there fails and the work is lost.
static func recovery_path_for(file_path: String) -> String:
    if is_in_resources(file_path):
        var relative := file_path.trim_prefix("res://").get_basename().replace("/", "-")
        return recovery_dir().path_join("res-%s%s" % [relative, RECOVERY_SUFFIX])
    if is_content_address(file_path):
        return recovery_dir().path_join("content-%s%s" % [_content_name(file_path), RECOVERY_SUFFIX])
    return file_path.get_basename() + RECOVERY_SUFFIX


## Whether *file_path* is an address Android's picker handed over, which
## names a document only as a whole and has no folder to write beside it.
static func is_content_address(file_path: String) -> bool:
    return file_path.begins_with("content://")


## A file name for the copy of the document at *address*: the name the
## address ends in, so the painter reads which document it was, and a hash of
## the whole address, so two documents of one name, or two of Downloads'
## numbered `msf` kind, never share a copy.
static func _content_name(address: String) -> String:
    var tail := address.uri_decode().get_file()
    tail = tail.substr(tail.rfind(":") + 1).get_basename().validate_filename()
    return "%s-%s" % [tail, address.md5_text().left(12)]


## Whether *file_path* is under `res://`, which the autosave never writes.
static func is_in_resources(file_path: String) -> bool:
    return file_path.begins_with("res://")


## Removes the copy this session wrote, and the one being written once it
## lands. Called once the document is clean and when the painter quits on
## purpose, so only a crash leaves one behind.
func discard_recovery() -> void:
    _retirements += 1
    if last_written.is_empty():
        return
    if FileAccess.file_exists(last_written):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(last_written))
    last_written = ""


## The recovery copies worth offering: every untitled one under the user
## directory, and beside each recent file a copy newer than the file itself.
## Each entry is {"copy": path, "original": path or ""}.
##
## A `res://` document's copy sits in the recovery folder too, and is offered
## once, with its original, when that document is among the recent files, and
## as an untitled one when it is not.
static func find_recoveries(recent_files: Array) -> Array:
    var found: Array = []
    var shadows: Array = recent_files.map(func(original: String) -> String: return recovery_path_for(original))
    var folder := recovery_dir()
    var dir := DirAccess.open(folder)
    if dir != null:
        for entry in dir.get_files():
            if entry.ends_with(RECOVERY_SUFFIX) and not shadows.has(folder.path_join(entry)):
                found.append({"copy": folder.path_join(entry), "original": ""})
    for original: String in recent_files:
        var copy := recovery_path_for(original)
        if not FileAccess.file_exists(copy):
            continue
        # Older than the file it shadows means the file was saved after it, and
        # the copy is stale. Equal is kept: the times are whole seconds, and a
        # copy the painter can delete beats one they never see.
        if FileAccess.file_exists(original) and FileAccess.get_modified_time(copy) < FileAccess.get_modified_time(original):
            continue
        found.append({"copy": copy, "original": original})
    return found


## Which surface the boot offers recovery copies on: the welcome window's row
## when that window opens, and otherwise the chain of windows, so a painter
## never meets both and a painter who turned the welcome window off still gets
## their work back. Static and handed the one fact, so a test asks it directly.
static func surface_at_start(welcome_opens: bool) -> String:
    return "pane" if welcome_opens else "chain"


## Announces every copy `find_recoveries` found on `recoveries_found`, for the
## chain of windows the interface opens, one per copy. Silent when there is
## none, so a listener never opens on an empty list.
func offer_recoveries(recent_files: Array) -> void:
    offer_surfaces.append("chain")
    var pending := find_recoveries(recent_files)
    if not pending.is_empty():
        recoveries_found.emit(pending)


## The copies the welcome window's recovery row draws, which are exactly the
## ones the chain would have asked about, recorded as offered in the pane.
func recoveries_for_pane(recent_files: Array) -> Array:
    offer_surfaces.append("pane")
    return find_recoveries(recent_files)


## Delete, from either surface: the copy goes and nothing else is touched.
static func delete_recovery(copy: String) -> void:
    if FileAccess.file_exists(copy):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(copy))


## Loads the copy and makes the document the original file with unsaved
## changes, so Save writes where the painter expects and the copy is retired
## by that save rather than by this load. Open, from either surface, the chain
## of windows and the welcome window's row.
func open_recovery(canvas: SaCanvas, copy: String, original: String) -> void:
    if document == null:
        return
    var err := SaExport.load_sad(document, copy)
    if err != OK:
        SaProblems.report("SaAutosave", tr("Could not open the recovery copy '%s' (%s).") % [copy, error_string(err)])
        return
    if canvas != null:
        canvas.resize_canvas(document.canvas_size)
    document.file_path = original
    document.modified = true
    last_written = copy


func _on_activity() -> void:
    _last_activity_msec = Time.get_ticks_msec()


func _on_chunks_invalidated(_grid_positions: Array) -> void:
    _last_activity_msec = Time.get_ticks_msec()


func _on_modified_changed(modified: bool) -> void:
    if not modified:
        discard_recovery()
        _elapsed_since_save = 0.0


## One timed autosave per open document, so a crash with two documents open
## loses neither. An inner class, because main names the autosave already.
##
## Each `SaAutosave` watches one document and writes that document's recovery
## copy, under a name of its own. This node holds them: `attach` as a document
## is opened, `detach` as it is closed, which stops its timer and removes its
## copy while the others keep theirs. The autosaves are its children, so they
## tick with the frame and die with it.
##
## The list is written by this class alone and read from outside.
class PerDocument:
    extends Node

    ## The autosaves, one per open document, in the order the documents opened.
    var held: Array[SaAutosave] = []

    ## The logger that hears the engine lose its display, while this is in the
    ## tree.
    var _display_gone: DisplayGone = null

    func _init() -> void:
        name = "SaAutosavePerDocument"

    func _enter_tree() -> void:
        if _display_gone == null:
            _display_gone = DisplayGone.new(save_all_before_the_end)
            OS.add_logger(_display_gone)

    func _exit_tree() -> void:
        if _display_gone != null:
            OS.remove_logger(_display_gone)
            _display_gone = null

    ## The display went while the engine's Wayland thread held the report, so
    ## the copies are written here, in the first frame after.
    func _process(_delta: float) -> void:
        if _display_gone != null and _display_gone.waits():
            _display_gone.answer()

    ## Writes the recovery copy of every open document with unsaved work, on
    ## this thread and at once. Answers how many were written.
    func save_all_before_the_end() -> int:
        var written := 0
        for autosave in held:
            if autosave.document != null and autosave.document.modified and autosave.save_before_the_end() == OK:
                written += 1
        return written

    ## The autosave of *doc*, started when it has none yet. Answers null for no
    ## document.
    func attach(doc: SaDocument) -> SaAutosave:
        if doc == null:
            return null
        var found := of(doc)
        if found != null:
            return found
        var autosave := SaAutosave.new()
        autosave.name = "SaAutosave%d" % held.size()
        add_child(autosave)
        autosave.attach(doc)
        held.append(autosave)
        return autosave

    ## Stops the autosave of *doc*, a document the painter closed, and removes its
    ## recovery copy. The other documents' autosaves and copies are untouched.
    ## Answers whether *doc* had one.
    func detach(doc: SaDocument) -> bool:
        var found := of(doc)
        if found == null:
            return false
        held.erase(found)
        found.detach()
        # A copy being written when the document closed is deleted by the
        # autosave as it lands, so the autosave lives until every save has ended.
        if SaSadFile.saving():
            SaSadFile.after_saves(_drop.bind(found), "closing a document")
        else:
            _drop(found)
        return true

    func _drop(autosave: SaAutosave) -> void:
        if is_instance_valid(autosave):
            remove_child(autosave)
            autosave.free()

    ## The autosave watching *doc*, or null.
    func of(doc: SaDocument) -> SaAutosave:
        for autosave in held:
            if autosave.document == doc:
                return autosave
        return null

    ## Removes every recovery copy this session wrote, for a quit the painter chose.
    func discard_all() -> void:
        for autosave in held:
            autosave.discard_recovery()


## Hears the engine lose its Wayland display and holds the end until the
## recovery copies are written.
##
## When the compositor goes, the engine's `_wl_display_check_error` reports
## the client error and then traps on the spot, on whichever thread found it,
## most often the engine's own Wayland thread. Nothing reaches the scene tree
## first: the crash handler's `NOTIFICATION_CRASH` is sent from that thread and
## refused by the root for it. The report itself goes to every logger before the
## trap, on the thread that found the error, so this logger is the one place
## Sara hears it in time.
##
## On the main thread the copies are written at once, inside the report. On
## another thread the report is held, the main thread's next frame writes them
## and lets it go, and a main thread that never comes back lets it go after
## `LONGEST_WAIT_MSEC`, so a Sara whose frames stopped too still ends.
## *write* is the main thread's work, constructed in, and answers how many
## copies it wrote.
class DisplayGone:
    extends SaErrorCatcher

    ## The engine's function that reports a lost display and then traps.
    const REPORTER := "_wl_display_check_error"
    ## How long a held report waits for the main thread.
    const LONGEST_WAIT_MSEC := 20000
    ## The line the log carries once the copies are written.
    const SAID := "Sara display: the compositor went, %d recovery cop%s written before the engine ends, %s"
    ## The end of that line for the thread that found the lost display.
    const FOUND_BY_MAIN := "found by the main thread"
    const FOUND_BY_ANOTHER := "found by another thread, which waited"

    var _write: Callable
    var _lock := Mutex.new()
    var _asked: bool = false
    var _answered: bool = false
    ## Whether a thread other than the main one is holding its report.
    var _held: bool = false

    func _init(write: Callable) -> void:
        _write = write

    ## Whether a report is held for the main thread.
    func waits() -> bool:
        _lock.lock()
        var held := _asked and not _answered
        _lock.unlock()
        return held

    ## Writes the copies on the main thread and lets the held report go.
    func answer() -> void:
        var written: int = _write.call()
        _lock.lock()
        _answered = true
        _lock.unlock()
        _lock.lock()
        var by := FOUND_BY_ANOTHER if _held else FOUND_BY_MAIN
        _lock.unlock()
        print(SAID % [written, "y" if written == 1 else "ies", by])

    ## Nothing is kept: this listens for one report in a whole session.
    func _caught_message(_message: String, _error: bool) -> void:
        pass

    func _caught_error(report: Dictionary) -> void:
        if str(report["function"]) != REPORTER:
            return
        var on_main := OS.get_thread_caller_id() == OS.get_main_thread_id()
        _lock.lock()
        var done := _answered
        _asked = true
        _held = _held or not on_main
        _lock.unlock()
        if done:
            return
        if on_main:
            answer()
            return
        var until := Time.get_ticks_msec() + LONGEST_WAIT_MSEC
        while waits() and Time.get_ticks_msec() < until:
            OS.delay_msec(10)
