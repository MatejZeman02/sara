## The file a painter's palette is written to, from the name it is saved under.
##
## A palette is written over only by itself. Two display names can share one
## file ("Ink/Night" and "ink night" both fold to `ink-night`), and a fork of
## "Sara Green (custom)" made a second time wears the same name as the first, so
## the check is whether the file is there and whose it is, never the name on the
## dropdown. A taken file numbers the name, "Sara Green (custom) 2", until both
## the name and its file are free.
##
## The file name drops every character a file system refuses, so a name a
## painter types on Windows writes a file rather than failing the save.
class_name SaThemeFileName
extends RefCounted

## What a file name may not hold on any of the systems Sara runs on: the
## separators, and the characters Windows refuses. Each becomes a hyphen, as a
## space always has, so a name saved earlier still finds its file.
const REFUSED := [" ", "/", "\\", ":", "*", "?", '"', "<", ">", "|"]

## Names Windows keeps for devices, which no file can take whatever its
## extension, so a palette called "Con" would fail the save there.
const RESERVED := [
    "con",
    "prn",
    "aux",
    "nul",
    "com1",
    "com2",
    "com3",
    "com4",
    "com5",
    "com6",
    "com7",
    "com8",
    "com9",
    "lpt1",
    "lpt2",
    "lpt3",
    "lpt4",
    "lpt5",
    "lpt6",
    "lpt7",
    "lpt8",
    "lpt9",
]

## The stem of a name that leaves nothing once the refused characters are gone.
const EMPTY_STEM := "custom"


## *name* as a file stem: lower case, every refused character a hyphen, and no
## control character, dot or hyphen at either end, since Windows drops a
## trailing dot and a stem of dots alone is a folder's name. Never empty.
static func stem(name: String) -> String:
    var out := name.to_lower().strip_edges()
    for refused: String in REFUSED:
        out = out.replace(refused, "-")
    var kept := ""
    for index in out.length():
        if out.unicode_at(index) >= 32 and out.unicode_at(index) != 127:
            kept += out[index]
    kept = kept.lstrip(".-").rstrip(".-")
    if kept.is_empty():
        return EMPTY_STEM
    if RESERVED.has(kept):
        return kept + "-palette"
    return kept


## The name a palette saved as *name* is written under, given that the palette
## in hand is *own_id* and is called *own_name*: *name* itself when its file is
## free, or when it is the palette in hand saved under its own name again, which
## is how Save As updates a palette. Otherwise "<name> N" from two up, the first
## whose file does not exist.
##
## Owning the file is not enough to write over it: "Ink/Night" in hand saved as
## "ink night" is a second palette the painter is naming, and the two share a
## file, so only the same name, in any case and spacing at its ends, rewrites.
static func free_name(name: String, own_id: String, own_name: String) -> String:
    if not _taken_by_another(name, own_id, own_name):
        return name
    var counter := 2
    while FileAccess.file_exists(SaTheme.custom_path(id_of("%s %d" % [name, counter]))):
        counter += 1
    return "%s %d" % [name, counter]


## The id a palette saved as *name* has: the prefix and its file stem.
static func id_of(name: String) -> String:
    return SaTheme.CUSTOM_PREFIX + stem(name)


static func _taken_by_another(name: String, own_id: String, own_name: String) -> bool:
    var id := id_of(name)
    if not FileAccess.file_exists(SaTheme.custom_path(id)):
        return false
    return id != own_id or name.strip_edges().to_lower() != own_name.strip_edges().to_lower()
