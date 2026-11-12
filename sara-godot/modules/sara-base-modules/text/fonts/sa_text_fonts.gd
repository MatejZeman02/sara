## The fonts a text layer can be set in: the three Sara ships for text and any
## file a painter or the door loads, each by its family name.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The shipped three cover three kinds of lettering**, Source Serif 4 for titles,
## Comic Neue for comic lettering and Caveat for handwriting, all under the
## SIL Open Font Licence, their licences beside them and in `THIRDPARTY.txt`.
## They are loaded as the imported resources an export packs, so a shipped
## build finds them where the editor does.
##
## **A font is named by what a `.sad` keeps of it**, [method identity]: the
## family, the style, the PostScript name and the SHA-256 of the font's bytes.
## A text layer draws from the outlines it stored and never from the font, so a
## family this table cannot reach changes nothing in the picture, and only an
## edit needs the font again.
##
## One table for the process. A font loaded in one document is there for the
## next, as a font installed on the machine is.
extends RefCounted

## The size every outline is read and every line shaped at, in pixels. The
## outline call hints below the font's own units per em whatever the font's
## `hinting` says, and shaping rounds advances to whole pixels at the size
## shaped, so both are asked at a size where half a pixel is 0.03 units of a
## 1000 unit em and scaled to the size drawn.
const READ_SIZE := 16384
## The family a new text is set in.
const DEFAULT_FAMILY := "Source Serif 4"
## The shipped families, by the name their files give, in the order the
## tool's Font row lists them.
const SHIPPED: Dictionary[String, String] = {
    "Source Serif 4": "res://modules/sara-base-modules/text/fonts/shipped/SourceSerif4-Regular.ttf",
    "Comic Neue": "res://modules/sara-base-modules/text/fonts/shipped/ComicNeue-Regular.ttf",
    "Caveat": "res://modules/sara-base-modules/text/fonts/shipped/Caveat-Variable.ttf",
}

## Every font this process has opened, by family.
static var _open: Dictionary[String, FontFile] = {}
## The file each family loaded by [method load_file] came from.
static var _files: Dictionary[String, String] = {}
## What [method identity] read of each font, by its RID. A hash of the whole
## file on every key typed would be the slowest part of a keystroke.
static var _identities: Dictionary[int, Dictionary] = {}


## The font of *family*, opened on first use, or null when no shipped file and
## no loaded one carries that family.
static func font_for(family: String) -> FontFile:
    if _open.has(family):
        return _open[family]
    if not SHIPPED.has(family):
        return null
    var held: Variant = load(SHIPPED[family])
    var font: FontFile = held if held is FontFile else null
    if font != null:
        _open[family] = font
    return font


## Whether *family* can be shaped now.
static func has_family(family: String) -> bool:
    return font_for(family) != null


## Every family that can be shaped now, the shipped ones first.
static func families() -> PackedStringArray:
    var found := PackedStringArray(SHIPPED.keys())
    for family: String in _open:
        if not family in found:
            found.append(family)
    return found


## Opens the font file at *path*, a TTF, an OTF, a WOFF or a WOFF2, and answers
## its family, or an empty string when the file is not a font. A family loaded
## again from another file takes the newer file.
static func load_file(path: String) -> String:
    var font := FontFile.new()
    if font.load_dynamic_font(path) != OK or font.get_font_name().is_empty():
        return ""
    var family := font.get_font_name()
    _open[family] = font
    _files[family] = path
    return family


## Lets go of a family [method load_file] opened, as a font uninstalled or a
## file moved away leaves it. A shipped family is always there and stays.
static func forget(family: String) -> void:
    if SHIPPED.has(family):
        return
    _open.erase(family)
    _files.erase(family)


## What a `.sad` keeps to name *font*: its family, style, PostScript name and
## the SHA-256 of its bytes, so a file opened on another machine can say which
## font it was set in and whether the one found there is the same.
static func identity(font: FontFile) -> Dictionary:
    if font == null:
        return {}
    var known: int = font.get_rids()[0].get_id()
    if _identities.has(known):
        return _identities[known].duplicate()
    var names: Dictionary = font.get_ot_name_strings()
    var postscript := ""
    var english: Variant = names.get("en", {})
    if english is Dictionary:
        postscript = String((english as Dictionary).get("postscript_name", ""))
    var hashing := HashingContext.new()
    hashing.start(HashingContext.HASH_SHA256)
    hashing.update(font.data)
    _identities[known] = {
        "family": font.get_font_name(),
        "style": font.get_font_style_name(),
        "postscript": postscript,
        "sha256": hashing.finish().hex_encode(),
    }
    return _identities[known].duplicate()
