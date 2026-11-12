## The Reference docker's boards in a `.sad`, and the pictures' own file bytes
## beside them when Preferences > Files keeps them inside the file.
##
## **Why the bytes.** A board is a list of paths and rectangles, so a painting
## sent to another machine opened with an empty frame where each picture was,
## and a picture pasted from a browser lives only as a PNG in Sara's data
## folder. With the switch on, which a painter turns on, a save stores each
## picture's file as it is on disk, a pasted PNG included, not decoded and
## encoded again, and once however many boards show it.
##
## **How it is kept.** The boards stay under `reference_boards` as an older
## Sara writes them, and the bytes are blobs named by a second key, `reference_pictures`,
## one entry per path with its offset and size. Both are additive to v4: an
## older Sara never reads the second key and draws a placeholder for a path it
## cannot find, and this Sara opens a file without the key
## as paths only.
##
## **Which wins on open.** The path, when it resolves, so an edit of the
## original outside Sara still shows. The stored bytes only when it does not.
## Opened, the bytes ride in the board's entry under `bytes` and in the picture
## the board makes, so a save on the other machine stores them again although
## the path still does not resolve there. That key is memory only and is never
## written into the header itself.
##
## A file of its own beside the writer rather than in the docker's folder, which
## stands at the size an agent reads whole, and in `core` because the writer and
## the reader call it and `core` never names `ui`. The docker names this.
class_name SaSadReferencePictures
extends RefCounted

## The header key the boards are written under, paths and rectangles.
const BOARDS_KEY := "reference_boards"
## The header key that names each stored picture's blob, by its path.
const PICTURES_KEY := "reference_pictures"
## The key a picture's entry in memory carries its stored bytes under.
const BYTES_KEY := "bytes"


## A picture read back from stored bytes: the pixels and the space its own
## bytes name, which the board keeps as a read from the path would have.
class Held:
    extends RefCounted

    var image: Image = null
    var space: SaColorSpace = null

    func _init(held_image: Image, held_space: SaColorSpace) -> void:
        image = held_image
        space = held_space


## Writes *boards*, the document's `reference_boards`, into *header*, and with
## *keep* each picture's file bytes into *blobs*. Nothing is written for no
## board, so a document without one has the header it always had.
##
## A picture's bytes are its file's as they are now, or the bytes it was opened
## with when the file is gone. A canvas element has no file and a path stored
## once is not stored again.
static func write_header(boards: Array, header: Dictionary[String, Variant], blobs: PackedByteArray, keep: bool) -> void:
    if boards.is_empty():
        return
    var written: Array = []
    var stored: Dictionary[String, Variant] = {}
    for board: Variant in boards:
        if not (board is Dictionary):
            written.append(board)
            continue
        var copy: Dictionary = board
        copy = copy.duplicate()
        var pictures: Array = []
        for entry: Variant in SaTyped.list(copy.get("pictures")):
            if not (entry is Dictionary):
                pictures.append(entry)
                continue
            var plain: Dictionary = entry
            plain = plain.duplicate()
            var held: Variant = plain.get(BYTES_KEY)
            plain.erase(BYTES_KEY)
            pictures.append(plain)
            var path := SaTyped.text_at(plain, "path", "")
            if not keep or path.is_empty() or SaTyped.bool_at(plain, "canvas", false) or stored.has(path):
                continue
            var bytes := _bytes_of(path, held)
            if bytes.is_empty():
                continue
            stored[path] = {"path": path, "offset": blobs.size(), "size": bytes.size()}
            blobs.append_array(bytes)
        copy["pictures"] = pictures
        written.append(copy)
    header[BOARDS_KEY] = written
    if not stored.is_empty():
        header[PICTURES_KEY] = stored.values()


## The boards *header* holds, each picture whose bytes the file stored carrying
## them under `bytes`. An empty array for a file with no board.
static func boards_from(header: Dictionary[String, Variant], blobs: PackedByteArray) -> Array:
    var boards := SaTyped.list(header.get(BOARDS_KEY))
    var stored: Dictionary[String, PackedByteArray] = {}
    for item: Variant in SaTyped.list(header.get(PICTURES_KEY)):
        var entry := SaTyped.strings(item)
        var offset := SaTyped.int_at(entry, "offset", -1)
        var size := SaTyped.int_at(entry, "size", 0)
        # A stored picture past the blob region is a damaged file, and the
        # picture is a placeholder rather than a slice of whatever lies there.
        if offset < 0 or size <= 0 or offset + size > blobs.size():
            continue
        stored[SaTyped.text_at(entry, "path", "")] = blobs.slice(offset, offset + size)
    if stored.is_empty():
        return boards
    for board: Variant in boards:
        if not (board is Dictionary):
            continue
        var plain: Dictionary = board
        for entry: Variant in SaTyped.list(plain.get("pictures")):
            if not (entry is Dictionary):
                continue
            var picture: Dictionary = entry
            var path := SaTyped.text_at(picture, "path", "")
            if stored.has(path):
                picture[BYTES_KEY] = stored[path]
    return boards


## The picture *bytes* hold, read through the reader the file at *path* would
## have been read with, or null when no reader takes them.
##
## The readers take a path, so the bytes are written under the original's own
## file name in a folder of their own under the system's temporary folder, read,
## and the file is deleted. The name keeps the format the extension claims for a
## file whose first bytes no reader recognises.
static func read_held(bytes: PackedByteArray, path: String) -> Held:
    if bytes.is_empty():
        return null
    var folder := OS.get_temp_dir().path_join("sara-reference-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
    if DirAccess.make_dir_recursive_absolute(folder) != OK:
        return null
    var name := path.get_file() if not path.get_file().is_empty() else "picture.png"
    var unpacked := folder.path_join(name)
    var file := FileAccess.open(unpacked, FileAccess.WRITE)
    if file == null:
        DirAccess.remove_absolute(folder)
        return null
    file.store_buffer(bytes)
    file.close()
    var was := SaProblems.announce
    # The picture is drawn as a placeholder when it cannot be read, as a missing
    # path is, rather than announced over a painting that opened fine.
    SaProblems.announce = false
    var image := SaImageImport.read(unpacked)
    SaProblems.announce = was
    var held := Held.new(image, SaImageImport.space_for(unpacked)) if image != null else null
    DirAccess.remove_absolute(unpacked)
    DirAccess.remove_absolute(folder)
    return held


## The bytes to store for *path*: its file's as they are now, or *held*, the
## bytes the picture was opened with, when the file is gone.
static func _bytes_of(path: String, held: Variant) -> PackedByteArray:
    if not path.begins_with("res://") and FileAccess.file_exists(path):
        var bytes := FileAccess.get_file_as_bytes(path)
        if not bytes.is_empty():
            return bytes
    return held if held is PackedByteArray else PackedByteArray()
