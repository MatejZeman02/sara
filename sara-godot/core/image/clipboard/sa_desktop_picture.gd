## A picture on the desktop clipboard, what its colours mean and the name its
## layer takes, and how it is read off the clipboard.
##
## Paste puts Sara's own clipboard down when Copy left something there and the
## desktop has not been given anything since, `SaClipboard.desktop_changed`,
## and otherwise asks [method read]. A picture copied in a browser, a screenshot or
## a file a file manager copied comes in the way a dropped file does, through
## the Fit dialog, so it is an import and never a readback.
##
## Under Wayland the engine says the clipboard holds a picture whether or not
## one was copied, and hands over an empty one, so trusting that answer leaves
## Ctrl+V doing nothing and saying nothing. A picture is judged by its size
## here, and on Linux the display server's own clipboard program is asked when
## the engine has none.
##
## **A file manager's Copy is a list of files, never a picture.** Nautilus 51.1
## offers `x-special/gnome-copied-files` (a `copy` line, then a `file://` line
## for each file), `text/uri-list` (the same addresses, each ending in CRLF),
## and a plain text of the bare paths one a line, with no `file://` at all.
## The engine's own clipboard reads only that plain text, so a bare absolute
## path is an address here as much as a `file://` line is, and the two lists
## are asked of the clipboard program when the plain text names nothing. Only
## the first picture of several is pasted, and [member left_out] counts the
## rest.
class_name SaDesktopPicture
extends RefCounted

## The program that hands over the clipboard's picture where the engine sees
## none, by the display server Sara runs on, with the arguments that ask it for
## a PNG. Both exit with an error when the clipboard offers no PNG.
const PROGRAMS: Dictionary = {
    "Wayland": ["wl-paste", "--type", "image/png"],
    "X11": ["xclip", "-selection", "clipboard", "-t", "image/png", "-o"],
}

## What asks the clipboard for the files a file manager copied, by the display
## server, in the order asked. Each exits with an error or prints nothing when
## the clipboard holds no files. Explorer leaves only a file drop list, which
## the engine's text clipboard never sees, so Windows asks PowerShell for it,
## one full path a line. PowerShell costs most of a second to start, which is
## the other reason [method read] asks the lists only when the plain text was
## empty.
const FILE_LISTS: Dictionary = {
    "Wayland":
    [
        ["wl-paste", "--type", "text/uri-list"],
        ["wl-paste", "--type", "x-special/gnome-copied-files"],
    ],
    "X11":
    [
        ["xclip", "-selection", "clipboard", "-t", "text/uri-list", "-o"],
        ["xclip", "-selection", "clipboard", "-t", "x-special/gnome-copied-files", "-o"],
    ],
    "Windows":
    [
        ["powershell", "-NoProfile", "-Command", "Get-Clipboard -Format FileDropList | ForEach-Object { $_.FullName }"],
    ],
}

## What a paste says when several pictures were copied and only the first came.
const LEFT_OUT_LINE := "Only the first of the %d pictures copied was pasted."

## Where a program's PNG is written to be read, under the data root, and
## removed once read.
const FILE_NAME := "desktop-clipboard.png"

## How much of a program's output one read of its pipe takes.
const PIPE_CHUNK: int = 65536

## How long a program may go without writing a byte before the paste stops
## waiting for it, and how long each look at its empty pipe waits.
const SILENCE_MSEC: int = 3000
const POLL_MSEC: int = 2

var image: Image
var space: SaColorSpace
var layer_name: String

## Where it came from: the engine, the program that handed it over, or the
## file a `file://` address named. The probe prints it and nothing decides on
## it.
var source: String

## How many more pictures the copied list named after the one taken. A paste
## of several files takes the first, and says so when this is above zero.
var left_out: int = 0


## Screen pixels in sRGB under the name a paste gives, unless the picture came
## from a file that says otherwise.
func _init(picture: Image, from: String, colours: SaColorSpace = null, named: String = "", more: int = 0) -> void:
    image = picture
    left_out = more
    source = from
    space = colours if colours != null else SaColorSpace.srgb()
    layer_name = named if not named.is_empty() else String(TranslationServer.translate("Pasted Picture"))


## The picture on the desktop clipboard, or null when there is none Sara can
## read.
##
## The engine first, which is all macOS needs. Then the files the plain text
## clipboard names, a `file://` address or a bare path, read the way a dropped
## file is. Then, when that text was empty, the file lists a Copy leaves
## beside it, asked of the clipboard program. Then, on Linux, the program's
## PNG, for a picture the engine does not see. A missing program is no
## picture, and the Paste that asked says so.
##
## **The lists are asked only when the plain text was empty.** Every file
## manager that writes a plain text at all writes the paths into it, so a text
## that named no file is somebody copying words and not files, and the lists
## would cost a program start on each such Ctrl+V for nothing. Explorer writes
## no text at all, which is why the lists exist, and so does a compositor whose
## clipboard the engine cannot reach.
static func read() -> SaDesktopPicture:
    if DisplayServer.clipboard_has_image():
        var picture := DisplayServer.clipboard_get_image()
        if picture != null and not picture.is_empty():
            return SaDesktopPicture.new(picture, "the engine")
    var text := DisplayServer.clipboard_get()
    var named := _at_address(text)
    if named != null:
        return named
    if text.strip_edges().is_empty():
        named = _from_lists(DisplayServer.get_name())
        if named != null:
            return named
    return _from_program(DisplayServer.get_name())


## The first picture the files *text* names, or null when it names none. The
## other pictures it names are counted in [member left_out].
static func _at_address(text: String) -> SaDesktopPicture:
    var pictures := PackedStringArray()
    for path in paths_in(text):
        if SaImageImport.is_image_path(path) and FileAccess.file_exists(path):
            pictures.append(path)
    for at in pictures.size():
        var picture := SaImageImport.read(pictures[at])
        if picture != null:
            var path := pictures[at]
            var more := pictures.size() - at - 1
            return SaDesktopPicture.new(picture, path, SaImageImport.space_for(path), path.get_file().get_basename(), more)
    return null


## The absolute paths *text* names, one a line, in the order written.
##
## A line is a `file://` address, a bare absolute path, or neither and skipped:
## the `copy` or `cut` line `x-special/gnome-copied-files` begins with, a `#`
## comment of a `text/uri-list`, or text that names no file at all. Whether the
## file is there is not asked here.
static func paths_in(text: String) -> PackedStringArray:
    var paths := PackedStringArray()
    for line in text.split("\n", false):
        var path := _path_of(line.strip_edges())
        if not path.is_empty():
            paths.append(path)
    return paths


## The path one line names, or nothing.
static func _path_of(line: String) -> String:
    if line.begins_with("file://"):
        var path := line.trim_prefix("file://").uri_decode()
        # `file://localhost/home/...` names the same file as `file:///home/...`,
        # and `file:///C:/...` is the drive's path without its first slash.
        if not path.begins_with("/"):
            path = path.substr(maxi(path.find("/"), 0))
        if path.length() > 2 and path[2] == ":":
            path = path.substr(1)
        return path
    # A bare path, `/home/...` or `C:\...` and `C:/...`, as Nautilus and
    # Explorer write it. A relative name is text, not a file.
    if line.begins_with("/") and not line.begins_with("//"):
        return line
    if line.length() > 2 and line[1] == ":" and (line[2] == "\\" or line[2] == "/"):
        return line.replace("\\", "/")
    return ""


## The first picture of the files a file manager copied, asked of the
## clipboard program for *server* list by list, or null.
static func _from_lists(server: String) -> SaDesktopPicture:
    for entry: Variant in SaTyped.list(FILE_LISTS.get(server)):
        var command := PackedStringArray(SaTyped.list(entry))
        if command.is_empty() or not SaRecorder.program_available(command[0]):
            continue
        var named := _at_address(_output_of(command[0], command.slice(1)).get_string_from_utf8())
        if named != null:
            return named
    return null


## The line a paste shows when *count* more pictures were copied than it took.
static func left_out_line(count: int) -> String:
    return String(TranslationServer.translate(LEFT_OUT_LINE)) % (count + 1)


## The PNG the clipboard program for *server* hands over, or null when there is
## no such program, it is not installed, or the clipboard holds no PNG.
##
## Written to a file under the data root and read from there, so it is read
## the way a dropped PNG is, its gamut included, and removed once read.
static func _from_program(server: String) -> SaDesktopPicture:
    var command := PackedStringArray(SaTyped.list(PROGRAMS.get(server)))
    if command.is_empty() or not SaRecorder.program_available(command[0]):
        return null
    var bytes := _output_of(command[0], command.slice(1))
    DirAccess.make_dir_recursive_absolute(SaDataRoot.folder())
    var path := SaDataRoot.path(FILE_NAME)
    var file := FileAccess.open(path, FileAccess.WRITE) if not bytes.is_empty() else null
    if file == null:
        return null
    file.store_buffer(bytes)
    file.close()
    var picture := SaImageImport.read(path)
    var colours := SaImageImport.space_for(path)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    return SaDesktopPicture.new(picture, command[0], colours) if picture != null else null


## What *program* writes to its standard output, or nothing when it exits with
## an error, which is how both clipboard programs refuse a type they do not
## hold, or when it goes quiet for `SILENCE_MSEC` without finishing.
##
## **Through a pipe, not `OS.execute`.** That one hands its output over as text,
## which a PNG is not, and on Linux in 4.7 it runs the command line through a
## shell whether output is asked for or not, so a `sh -c` line that wrote into
## a file arrived with its `$1` and `$@` already expanded to nothing. The pipe
## starts the program with its arguments as they are and reads its bytes. What
## the program says on a refusal stays on the pipe's own stderr rather than in
## Sara's console.
##
## **Not blocking, and given up on.** A clipboard program can wait without
## end for a selection it cannot reach, `wl-paste` for a keyboard focus of its
## own on a compositor without the data-control protocol, and a blocking read
## would then hold the paste and the whole window with it. Whether the program
## was still running is asked before each read, so bytes it wrote just before
## it left are still read.
static func _output_of(program: String, arguments: PackedStringArray) -> PackedByteArray:
    var run := OS.execute_with_pipe(program, arguments, false)
    var stdio: Variant = run.get("stdio")
    if not stdio is FileAccess:
        return PackedByteArray()
    var pipe: FileAccess = stdio
    var pid := SaTyped.int_at(run, "pid", -1)
    var bytes := PackedByteArray()
    var quiet_until := Time.get_ticks_msec() + SILENCE_MSEC
    while true:
        var running := OS.is_process_running(pid)
        var chunk := pipe.get_buffer(PIPE_CHUNK)
        if not chunk.is_empty():
            bytes.append_array(chunk)
            quiet_until = Time.get_ticks_msec() + SILENCE_MSEC
        elif not running:
            break
        elif Time.get_ticks_msec() > quiet_until:
            OS.kill(pid)
            return PackedByteArray()
        else:
            OS.delay_msec(POLL_MSEC)
    return bytes if OS.get_process_exit_code(pid) == 0 else PackedByteArray()
