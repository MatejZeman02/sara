## Where a note is written, and what the file it is written to looks like.
##
## Split out of `sa_note_mode.gd`, which was at 693 lines and is the file the
## note mode's own behaviour lives in. This half is the one thing in there that
## has nothing to do with the pointer or the highlight: the directory, the name
## of the run's markdown file, its two-line header, the append, and the clock
## reading every note is stamped with. All static, and none of it needs a
## window, which is why the tests reach it directly.
class_name SaNoteFile
extends RefCounted

## The environment variable that moves the notes directory, for a harness.
const NOTES_DIR_ENV := "SARA_NOTES_DIR"

## The file this run of Sara appends its notes to, fixed at the first one.
##
## Static, so it is one file per launch of the process rather than one per day.
## A day's file mixed the notes that became units with the ones that did not,
## and a pass over a session of notes now moves a whole file.
static var run_file: String = ""


## `<day>-<HHMM>.md`, named after the day and the minute of the first note of
## this run, and the same name for every note after it.
##
## *now* is a `now()` dictionary rather than a reading of the clock, so a test
## can name the moment instead of waiting for one.
static func run_file_name(at: Dictionary) -> String:
    if run_file.is_empty():
        run_file = "%s-%s.md" % [String(at.get("date", "")), String(at.get("short", ""))]
    return run_file


## The folder this run's notes and images go in, `<base>/<day>-<HHMM>`.
##
## One folder per session rather than one flat folder, which grows to hundreds
## of files side by side. Per session, because `run_file_name` above is
## already per session for the reason given there, and because a session folder
## holds the note file and the images it links together: the link inside a note
## stays the bare file name, which is what makes it resolve wherever the folder
## is moved to afterwards.
##
## The folder is named after the run file's stem rather than after the day, so
## the two sort together and a reader can pair them without opening either. The
## note file keeps its full name inside the folder, redundant as that reads,
## because `archive_notes.py` finds a note by bare file name and `ledger.py`
## records one by it, and a rename would be a third thing to keep in step.
##
## *base* is an absolute path or a Godot one, `user://notes` as readily as
## `/home/someone/notes`, because `path_join` and `DirAccess` both take either.
## What neither takes is a scheme path that has lost a slash, which is what
## `make_run_dir` below is here to say.
static func run_dir(base: String, at: Dictionary) -> String:
    return base.path_join(run_file_name(at).get_basename())


## Makes *dir*, and answers why it could not be made, or `""` when it is there.
##
## The reason rather than a `push_error` of its own, the shape
## `SaCaptureNotes.target_complaint` uses, so the caller writes the prefix and a
## test can read the sentence without a tree to raise it in.
##
## The one failure anybody has hit is a scheme path with one slash where it
## needs two. `pathlib` collapses the pair, so a Python caller that runs
## `user://painter-notes` through `Path` hands over `user:/painter-notes`, which
## is not a Godot path and not an absolute one either. `DirAccess` refuses it,
## and until this the refusal was silent and the note failed one step later
## against the markdown file, whose name is the part of the sentence a reader
## does not doubt.
static func make_run_dir(dir: String) -> String:
    var made := DirAccess.make_dir_recursive_absolute(dir)
    if made == OK:
        return ""
    var why := "A notes folder is an absolute path or one such as `user://notes`."
    if dir.contains(":/") and not dir.contains("://"):
        why += " This path has one slash after the colon where it needs two, as in `user://`."
    return "cannot make %s, error %d. %s" % [dir, made, why]


## The two lines a new notes file opens with: when the run started taking them,
## and the build it was taking them against, which is the one thing a reader of
## the file a week later cannot work out.
static func run_file_header(at: Dictionary) -> String:
    var when := "%s %s" % [String(at.get("date", "")), String(at.get("time", ""))]
    return "# Notes, %s\n\nBuild: %s\n" % [when, SaBuildInfo.describe(SaBuildInfo.read())]


## `$SARA_NOTES_DIR`, else `Documents/Sara` on Android, else `notes` under
## the data root, beside the logs and the brushes, where the painter's guide
## sends a person looking for what to send back. A developer who sorts notes
## from a folder of their own points the variable at it.
##
## Android's before the home folder, because there the home folder is the
## app's private one, and a person with a tablet and no `adb` sends back what
## a file manager finds in `Documents/Sara`, the log beside the notes.
static func default_notes_dir() -> String:
    var from_env := OS.get_environment(NOTES_DIR_ENV)
    if not from_env.is_empty():
        return from_env
    var shared := SaDataRoot.shared()
    if not shared.is_empty():
        return shared
    return ProjectSettings.globalize_path(SaDataRoot.path("notes"))


## Adds *entry* to *path*, writing *header* first when the file is new.
static func append(path: String, entry: String, header: String) -> bool:
    var existed := FileAccess.file_exists(path)
    var file := FileAccess.open(path, FileAccess.READ_WRITE if existed else FileAccess.WRITE)
    if file == null:
        return false
    if existed:
        file.seek_end()
    else:
        file.store_string(header)
    file.store_string(entry)
    file.close()
    return true


## Zips *dir* into `<dir>.zip` beside it, one entry per file at the bare name
## the markdown links, so the links still resolve inside the zip, plus the
## engine's own log from *log_dir* under a `logs/` prefix, if any is found
## there. Returns the zip's path, or "" when there is nothing at all to zip or
## the zip could not be written, which the caller turns into the notice rather
## than a silent no-op.
##
## *dir* need not exist: a session that took no note never made it, and the
## log alone is still worth zipping, at the path *dir* would have had.
static func export_run_dir(dir: String, log_dir: String = "") -> String:
    var note_files := DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()
    var log_files := log_files_for(log_dir)
    if note_files.is_empty() and log_files.is_empty():
        return ""
    var zip_path := dir + ".zip"
    var packer := ZIPPacker.new()
    if packer.open(zip_path) != OK:
        push_error("SaNoteFile: cannot write %s" % zip_path)
        return ""
    for file in note_files:
        var bytes := FileAccess.get_file_as_bytes(dir.path_join(file))
        packer.start_file(file)
        packer.write_file(bytes)
        packer.close_file()
    for file in log_files:
        var bytes := FileAccess.get_file_as_bytes(log_dir.path_join(file))
        packer.start_file("logs/%s" % file)
        packer.write_file(bytes)
        packer.close_file()
    packer.close()
    return zip_path


## `godot.log` and the two rotated files newest by name from *log_dir*, or
## empty when the folder is unset, missing or holds neither. Godot names a
## rotation `godot<ISO timestamp>.log`, which sorts newest-last already, so
## picking the two newest needs no `modified_time` read.
##
## Public so `SaNoteMode.export_notes` can tell, before it writes the notice,
## whether the zip it is about to make will hold a log.
static func log_files_for(log_dir: String) -> PackedStringArray:
    if log_dir.is_empty() or not DirAccess.dir_exists_absolute(log_dir):
        return PackedStringArray()
    var files := DirAccess.get_files_at(log_dir)
    var has_current := files.has("godot.log")
    var rotated: Array = []
    for file in files:
        if file != "godot.log":
            rotated.append(file)
    rotated.sort()
    rotated.reverse()
    var out := PackedStringArray()
    if has_current:
        out.append("godot.log")
    for i in range(min(2, rotated.size())):
        out.append(rotated[i])
    return out


## The folder the engine writes its log into, asked of `SaTrail` the way
## `SaAgentDoor._log_path` asks it, so the path is never written a third time.
static func engine_log_dir() -> String:
    return SaTrail.log_path().get_base_dir()


## A control's name with everything a file name cannot carry replaced.
static func file_safe(text: String) -> String:
    var out := ""
    for character in text:
        var plain: bool = character.is_valid_identifier() or character.is_valid_int() or character == "-"
        out += character if plain else "_"
    return out if not out.is_empty() else "control"


## The moment a note was frozen, in the four shapes the entry and the two file
## names each want it in.
static func now() -> Dictionary:
    var t := Time.get_datetime_dict_from_system()
    return {
        "date": "%04d-%02d-%02d" % [t.year, t.month, t.day],
        "time": "%02d:%02d:%02d" % [t.hour, t.minute, t.second],
        "compact": "%02d%02d%02d" % [t.hour, t.minute, t.second],
        "short": "%02d%02d" % [t.hour, t.minute],
    }
