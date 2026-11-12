## Which loader File > Open hands a path to, read off its name when the name
## has an extension and off its first bytes when it has none.
##
## Android's picker hands back a content address such as
## `content://com.android.providers.downloads.documents/document/186`, with no
## extension at all, so routing by the name sent every picture chosen there to
## the `.sad` loader, which said "File unrecognized" about a plain PNG.
## A path with no extension is a `.sad` when it starts with a `.sad`'s magic, a
## picture when a flat format claims its header, and a layered file when a
## layered format does. Anything else still goes to the `.sad` loader, whose
## refusal names the path.
class_name SaOpenRoute
extends RefCounted

enum Kind { SAD, PICTURE, LAYERED }

var kind: Kind = Kind.SAD
## The layered format that reads the path, set only for `Kind.LAYERED`.
var layered: SaImageFormat = null


func _init(path: String) -> void:
    if path.get_extension().is_empty():
        _by_bytes(path)
        return
    var formats := SaImageImport.formats()
    if formats.flat_named(path) != null:
        kind = Kind.PICTURE
        return
    layered = formats.layered_named(path)
    if layered != null:
        kind = Kind.LAYERED


func _by_bytes(path: String) -> void:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return
    var head := file.get_buffer(SaImageFormatRegistry.HEAD_BYTES)
    file.close()
    var magic := head.slice(0, 4).get_string_from_ascii()
    if magic == SaSadFile.SAD_MAGIC_V4:
        return
    if not SaImageImport.format_of_header(head).is_empty():
        kind = Kind.PICTURE
        return
    for format in SaImageImport.formats().layered():
        if format.claims.is_valid() and format.claims.call(head) == true:
            kind = Kind.LAYERED
            layered = format
            return
