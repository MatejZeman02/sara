## The numbers of a `.sad` header that a reader checks before it trusts them:
## the canvas size, refused when no dialog could have made it, and the blend
## reference white and the resolution, read as absent when they have no
## meaning. The size is a refusal because a header that said zero or two
## billion would otherwise reach the document as its canvas, and a fill of a side of
## two billion is a hang rather than an error.
class_name SaSadHeaderNumbers
extends RefCounted

## The longest side a document may have, the one the new document, canvas size
## and image size dialogs offer. Their own constants are held equal to this one
## by this folder's suite of the size, so the limits cannot drift apart.
const MAX_SIDE := 16384

## What a header with no `width` or `height` has always meant.
const ABSENT_SIDE := 1024


## The canvas size *header* says, a missing side read as [constant ABSENT_SIDE].
static func size(header: Dictionary) -> Vector2i:
    return Vector2i(SaTyped.int_at(header, "width", ABSENT_SIDE), SaTyped.int_at(header, "height", ABSENT_SIDE))


## Why the file at *path*, whose header is *header*, cannot be opened at its
## size, or an empty text when a side is between 1 and [constant MAX_SIDE].
static func refusal(header: Dictionary, path: String) -> String:
    var said := size(header)
    if said.x >= 1 and said.y >= 1 and said.x <= MAX_SIDE and said.y <= MAX_SIDE:
        return ""
    return "SaExport.load_sad: '%s' says a canvas of %d by %d, and a side runs from 1 to %d" % [path, said.x, said.y, MAX_SIDE]


## The blend reference white *header* says. Absent means 1.0, which is what
## every file written before W existed meant. A stored zero or negative would
## divide the display-referred modes by nothing, so it reads as absent.
static func white(header: Dictionary) -> float:
    var stored := SaTyped.float_at(header, "blend_reference_white", 1.0)
    return stored if stored > 0.0 else 1.0


## The resolution *header* says. Absent means 72, which is what every file
## written before the key existed was. A zero or negative resolution has no
## physical meaning, so it reads as absent.
static func dpi(header: Dictionary) -> float:
    var stored := SaTyped.float_at(header, "dpi", SaDocument.DEFAULT_DPI)
    return stored if stored > 0.0 else SaDocument.DEFAULT_DPI
