## A picture from the desktop clipboard, made a file a reference board can keep.
##
## The board keeps every picture by its path, so that a document opened again
## finds its references where they were. A picture copied in a browser has no
## file, so it is written once as a PNG into the folder for pasted references
## under the data root, which `--settings-dir` moves, named by the date and time
## of the paste. A file a file manager copied is kept by its own path and
## nothing is written.
##
## The clipboard is read through `SaDesktopPicture.read`, the one reader the
## canvas's Paste and File > New from Clipboard use, so the board reads the
## clipboard the same way they do.
class_name ReferencePaste
extends RefCounted

## The folder under the data root the pasted pictures are written into.
const FOLDER := "reference-pastes"

## What the corner says when there is no picture to paste.
const NOTHING := "The clipboard holds no picture to put on the board."

## The picture on the desktop clipboard, `SaDesktopPicture.read` in everything
## but a suite: a headless run has no desktop clipboard, and a run on the
## machine of whoever runs the gate would paste whatever they last copied.
## Test seam. A suite that replaces it puts `SaDesktopPicture.read` back.
static var desktop_picture: Callable = SaDesktopPicture.read


## The picture on the desktop clipboard, or null when it holds none.
static func read() -> SaDesktopPicture:
    var picture := desktop_picture.call() as SaDesktopPicture if desktop_picture.is_valid() else null
    if picture == null or picture.image == null or picture.image.is_empty():
        return null
    return picture


## The folder the pasted pictures go into, as an absolute path.
static func folder() -> String:
    return ProjectSettings.globalize_path(SaDataRoot.path(FOLDER))


## The file *picture* is kept by: the file it was copied from when a file
## manager put it there, and otherwise a PNG written now. Empty when the PNG
## could not be written, which the corner says.
static func keep(picture: SaDesktopPicture) -> String:
    if _is_a_file(picture.source):
        return picture.source
    DirAccess.make_dir_recursive_absolute(folder())
    var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
    var path := folder().path_join("pasted-%s.png" % stamp)
    var count := 2
    while FileAccess.file_exists(path):
        path = folder().path_join("pasted-%s-%d.png" % [stamp, count])
        count += 1
    var image := picture.image
    if image.get_format() != Image.FORMAT_RGBA8:
        image = image.duplicate() as Image
        image.convert(Image.FORMAT_RGBA8)
    var error := image.save_png(path)
    if error != OK:
        SaMessage.notice(
            TranslationServer.translate("The pasted picture could not be written to %s: %s") % [path, error_string(error)]
        )
        return ""
    return path


## Whether *source* names a file on disk, which is what `SaDesktopPicture`
## puts there for a file a file manager copied, rather than the engine or a
## clipboard program.
static func _is_a_file(source: String) -> bool:
    return source.is_absolute_path() and SaImageImport.is_image_path(source) and FileAccess.file_exists(source)
