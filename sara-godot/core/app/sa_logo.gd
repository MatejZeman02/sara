## The Sara mark, pre-rendered for the terminal.
##
## Generated from ui/icon.png by scripts/gen_logo.py. Each cell is an upper
## half block whose foreground is the top pixel and background the bottom one,
## so one character carries two pixels and the result is square on screen.
## Fully transparent pixels emit a bare space with no colour, so the mark sits
## on whatever background the terminal already has.
##
## The rows are BBCode, about fifty characters a cell, so they live in
## `assets/sa_logo.json` as an array of strings and not in a script. A `.json`
## is packed as it is, so no export filter names it.
##
## Regenerate with:  python3 scripts/gen_logo.py
class_name SaLogo
extends RefCounted

## Width in character cells.
const WIDTH: int = 32

const PATH := "res://assets/sa_logo.json"

static var _rows: PackedStringArray = PackedStringArray()


## The rows of the mark, top to bottom, each one line of BBCode for `print_rich`.
## Read from the asset the first time and kept. An asset that is missing or is
## no array of strings gives no rows, so the banner prints with no mark.
static func lines() -> PackedStringArray:
    if _rows.is_empty():
        var read: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
        if read is Array:
            for row: Variant in read:
                _rows.append(str(row))
    return _rows
