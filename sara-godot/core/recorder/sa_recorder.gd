## The timelapse recorder: one JPEG a moment after the canvas settles.
##
## Godot ships no video encoder and does not need one. Every edit that
## announces itself through the document restarts a short timer, and when the
## timer runs out with nothing new the easel's output is read back once and
## written as a frame. Hard rule 1 forbids a readback during a stroke, not
## after one, and a debounced grab on commit is inside the rule and makes a
## better timelapse than a per-frame capture would.
##
## The frame goes through the display conversion, so a timelapse looks like
## the screen looked: a linear document's floats are encoded through the same
## kernel Image > Convert uses, on a copy of the output, before the readback.
##
## Frames run to a gigabyte an hour at 4K, so a cap on bytes stops the
## recording and says so rather than filling the disk. Turning the frames into
## a video is a system ffmpeg's job, the first `OS.execute` in the tree, with
## a found-or-not check and its failure reported through `SaProblems`.
class_name SaRecorder
extends Node

## A frame was written: its path and the count so far.
signal frame_written(path: String, count: int)
## Recording stopped, with why: "stopped", "cap", or an error.
signal stopped(reason: String)

## Where the frames go until a painter picks a folder: under the data root, asked
## through [method default_directory].
const DEFAULT_FOLDER := "timelapse"
const FRAME_PATTERN := "frame_%05d.jpg"
const DEFAULT_CAP_BYTES: int = 1024 * 1024 * 1024
## What the refusal says when the cap stops a recording, in the plural form its
## count of frames picks.
const CAPPED_ONE := "The timelapse reached its cap of %d MB after %d frame, so recording stopped."
const CAPPED_MANY := "The timelapse reached its cap of %d MB after %d frames, so recording stopped."

## Seconds of quiet after the last edit before a frame is taken.
var settle_seconds: float = 2.0
var quality: float = 0.9
var cap_bytes: int = DEFAULT_CAP_BYTES
var directory: String = default_directory()

var recording: bool = false
var frame_count: int = 0
var bytes_written: int = 0

var _canvas: SaCanvas = null
var _timer: Timer = null
var _pending: bool = false
## The error pipe of the ffmpeg `make_video` started, read once it has ended.
var _video_errors: FileAccess = null


## The folder a recording starts in when no one chose another.
static func default_directory() -> String:
    return SaDataRoot.path(DEFAULT_FOLDER)


func _init() -> void:
    name = "SaRecorder"
    _timer = Timer.new()
    _timer.one_shot = true
    _timer.timeout.connect(_on_settled)
    add_child(_timer)


## Points the recorder at the canvas whose easel it reads. The document is
## the same node across File > New and Open, so one connection lasts.
func bind_canvas(canvas: SaCanvas) -> void:
    if _canvas != null and _canvas.document != null:
        if _canvas.document.document_changed.is_connected(_on_document_changed):
            _canvas.document.document_changed.disconnect(_on_document_changed)
    _canvas = canvas
    if _canvas != null and _canvas.document != null:
        _canvas.document.document_changed.connect(_on_document_changed)


func start(into: String = "") -> bool:
    if _canvas == null:
        SaProblems.refuse("SaRecorder", tr("There is no canvas to record."))
        return false
    if not into.is_empty():
        directory = into
    var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
    if err != OK and err != ERR_ALREADY_EXISTS:
        SaProblems.report("SaRecorder", tr("Cannot create '%s' (%s).") % [directory, error_string(err)])
        return false
    frame_count = _existing_frames()
    bytes_written = _existing_bytes()
    recording = true
    _pending = false
    return true


func stop(reason: String = "stopped") -> void:
    if not recording:
        return
    recording = false
    _pending = false
    _timer.stop()
    stopped.emit(reason)


## Every edit restarts the quiet period. Called for anything the document
## announces, which a stroke commit, a layer operation and an undo all do.
func _on_document_changed() -> void:
    if not recording:
        return
    _pending = true
    if is_inside_tree():
        _timer.start(settle_seconds)


func _on_settled() -> void:
    if recording and _pending:
        _pending = false
        capture_frame()


## Writes the next frame now. Public so a test and the docker can ask for one
## without waiting out the timer.
func capture_frame() -> String:
    if _canvas == null or _canvas.canvas == null:
        return ""
    var image := display_image(_canvas)
    if image == null:
        return ""
    frame_count += 1
    var path := directory.path_join(FRAME_PATTERN % frame_count)
    var err := image.save_jpg(path, quality)
    if err != OK:
        frame_count -= 1
        SaProblems.report("SaRecorder", tr("Could not write '%s' (%s).") % [path, error_string(err)])
        stop(error_string(err))
        return ""
    var size := FileAccess.open(path, FileAccess.READ)
    if size != null:
        bytes_written += size.get_length()
        size.close()
    frame_written.emit(path, frame_count)
    if bytes_written >= cap_bytes:
        @warning_ignore("integer_division")
        var cap_mb := cap_bytes / 1048576
        SaProblems.refuse("SaRecorder", tr_n(CAPPED_ONE, CAPPED_MANY, frame_count) % [cap_mb, frame_count])
        stop("cap")
    return path


## The easel's output as the screen shows it, in 8 bits.
##
## A document that stores something other than encoded sRGB is converted through
## the kernel Image > Convert uses, so the frame is what the view shader would
## have drawn, and the narrowing rounds rather than truncating, which would put
## every value on the step below it. Both run a chunk cell at a time rather than
## over a copy of the whole frame.
func display_image(canvas: SaCanvas) -> Image:
    # A frame is the whole picture, so what the window left unshown goes in first.
    if canvas.easel != null:
        canvas.easel.flush()
    var output: SaTexture = canvas.canvas
    var document := canvas.document
    if output == null or document == null:
        return null
    return SaExportGamut.encoded_byte_image(output, document.color_space, SaColorSpace.srgb())


## Whether a system ffmpeg is installed, asked of the file system rather than by
## running it.
##
## `OS.execute` of a program that is not there is a child process that cannot
## start, and the engine's own line for it ("Could not create child process",
## with a backtrace on the builds that report it) lands in the console of a
## painter who has done nothing wrong. The Recorder docker asks this at `_ready`,
## so a machine without ffmpeg printed it on every boot, and the frames it was
## asked about are not the reason. Nothing has to be run to answer the question:
## a program is an executable file in a directory `PATH` already lists.
static func ffmpeg_available() -> bool:
    return program_available("ffmpeg")


## Whether *program* is an executable file in one of the directories *search_path*
## lists, `PATH` when that is empty.
##
## Windows never names a program's extension in `PATH`, so each entry is tried
## with the suffixes `PATHEXT` names as well, and the separator is the platform's:
## the two are the same question about which system is reading the variable. An
## entry that is a directory is not a program, and `FileAccess.file_exists`
## answers false for one.
##
## The execute bit is not asked for. A file that carries the name and cannot be
## run is a rarity, and the run that finds out reports it through `SaProblems`,
## where the file system's answer would have to be read differently on every
## platform Sara builds for.
static func program_available(program: String, search_path: String = "") -> bool:
    if program.is_empty():
        return false
    var windows := OS.get_name() == "Windows"
    var names := PackedStringArray([program])
    if windows:
        for extension in OS.get_environment("PATHEXT").split(";", false):
            names.append(program + extension.to_lower())
    var path := search_path if not search_path.is_empty() else OS.get_environment("PATH")
    for folder in path.split(";" if windows else ":", false):
        for program_name in names:
            if FileAccess.file_exists(folder.path_join(program_name)):
                return true
    return false


## Asks ffmpeg to join the frames in *directory* into *video_path*, without
## waiting for it. The process id, or -1 with the reason reported.
##
## libx264 in yuv420p halves the colour planes and refuses a width or height
## that is odd, so the picture is padded up to the next even size by at most
## one row and one column. Only errors are logged and no progress is printed,
## so the pipe [method video_error] reads stays far below what a pipe holds.
func make_video(video_path: String, fps: int = 12) -> int:
    if not ffmpeg_available():
        SaProblems.report("SaRecorder", tr("ffmpeg was not found on this system, so no video can be made from the frames."))
        return -1
    if frame_count <= 0:
        SaProblems.refuse("SaRecorder", tr("There are no frames in '%s' to make a video from.") % directory)
        return -1
    var frames := ProjectSettings.globalize_path(directory).path_join("frame_%05d.jpg")
    var args := PackedStringArray(
        [
            "-y",
            "-framerate",
            str(fps),
            "-i",
            frames,
            "-vf",
            "pad=ceil(iw/2)*2:ceil(ih/2)*2",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-nostdin",
            "-loglevel",
            "error",
            "-nostats",
            ProjectSettings.globalize_path(video_path)
        ]
    )
    _video_errors = null
    var started := OS.execute_with_pipe("ffmpeg", args, false)
    var pid: int = started.get("pid", -1)
    if pid < 0:
        SaProblems.report("SaRecorder", tr("ffmpeg could not be started."))
        return -1
    var pipe: Variant = started.get("stderr")
    if pipe is FileAccess:
        _video_errors = pipe
    return pid


## The last line ffmpeg printed on its error output, "" when it printed none.
##
## A pipe never reports its end while the engine holds it, so the read takes
## the bytes the pipe has ready and stops, which is all of them once the
## process has ended. A read for more would wait for ever.
func video_error() -> String:
    var last := ""
    if _video_errors == null:
        return last
    var waiting := _video_errors.get_length()
    var text := _video_errors.get_buffer(waiting).get_string_from_utf8() if waiting > 0 else ""
    _video_errors = null
    for line in text.split("\n", false):
        if not line.strip_edges().is_empty():
            last = line.strip_edges()
    return last


func _existing_frames() -> int:
    var count := 0
    var dir := DirAccess.open(directory)
    if dir == null:
        return 0
    for file_name in dir.get_files():
        if file_name.begins_with("frame_") and file_name.ends_with(".jpg"):
            count += 1
    return count


func _existing_bytes() -> int:
    var total := 0
    var dir := DirAccess.open(directory)
    if dir == null:
        return 0
    for file_name in dir.get_files():
        if file_name.begins_with("frame_") and file_name.ends_with(".jpg"):
            var file := FileAccess.open(directory.path_join(file_name), FileAccess.READ)
            if file != null:
                total += file.get_length()
                file.close()
    return total
