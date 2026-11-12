## The changelog the build carries and the welcome window's News pane reads.
##
## `CHANGELOG.md` sits at the repository root, where a person reads it, and
## `packaging/build.sh` copies it into the project for the length of one export
## so it travels inside the binary. That packed copy is the only source a
## shipped Sara has, and `read()` answers it first when it is there.
##
## An editor run has no copy under `res://`, because the file lives in the
## project for the length of an export and is removed again, and an editor run
## is every capture and every suite. `read()` then reads the checkout's own
## `CHANGELOG.md` instead, one directory above the project: same file, read
## from where the repository keeps it, and `source` in the answer says which of
## the two answered. Nothing is fetched, no other page of the repository is
## read, and a
## build never reaches the checkout: the packed copy is there or `read()`
## answers `none`.
##
## **A language module may carry the notes in its language**, as a
## `RELEASE-NOTES.md` of the same sections beside its catalogue. `notes_path()`
## finds the one for the language in force, and `read()` takes each section's
## lines from it where it has that section line for line, and the English
## section's lines where it has not, so a note written after the translation
## shows in English rather than not at all. The English file stays the list of
## releases: a section only the module's file has is never shown.
class_name SaChangelog
extends RefCounted

## Where the export leaves the file, and what an editor run does not have.
const PATH: String = "res://CHANGELOG.md"

## The changelog's file name, which is the checkout reader's own name and the
## name the repository keeps at its root.
const CHECKOUT_NAME: String = "CHANGELOG.md"

## A section opens with this. The file's own "# Changelog" title is level one
## and is not a section.
const SECTION_PREFIX: String = "## "

## The file a language module keeps its notes in, beside its catalogue.
const NOTES_NAME: String = "RELEASE-NOTES.md"

## A line of a section that is a note to its reader and never shown: a
## Markdown comment, which a rendered page hides as well. A language module's
## notes mark each unreviewed section with one.
const COMMENT_PREFIX: String = "<!--"

## How many numbers a version is compared by, "0.10.1" against "0.9.1".
const VERSION_PARTS: int = 3


## The sections a build or an editor run carries, which file answered them, and
## where that file is: `{"source", "path", "notes", "sections"}`, `source` one
## of `build`, `checkout` and `none`.
##
## `notes` is a language module's notes file, `notes_path()`'s answer, and the
## sections' lines come from it where it carries them. The key holds the path
## when the file was read and `""` when the English lines stand alone.
##
## `path` first, and the checkout's copy only when `path` is still the default
## `PATH`: a path handed in names the one file to read, which is what a test
## asking for a file that does not exist relies on. Both empty answers are
## quiet, because an editor run with no checkout beside it and a build with no
## packed file are the ordinary case rather than a fault.
static func read(path: String = PATH, notes: String = "") -> Dictionary[String, Variant]:
    var found: Dictionary[String, Variant] = {"source": "none", "path": "", "notes": "", "sections": []}
    if FileAccess.file_exists(path):
        found = {"source": "build", "path": path, "notes": "", "sections": parse(FileAccess.get_file_as_string(path))}
    elif path == PATH:
        var checkout := _checkout_path()
        if checkout != "" and FileAccess.file_exists(checkout):
            var text := FileAccess.get_file_as_string(checkout)
            found = {"source": "checkout", "path": checkout, "notes": "", "sections": parse(text)}
    if notes != "" and found["source"] != "none" and FileAccess.file_exists(notes):
        var english: Array = found["sections"]
        found["sections"] = localised(english, parse(FileAccess.get_file_as_string(notes)))
        found["notes"] = notes
    return found


## The notes file of the language *locale* names, from the catalogue of
## *registry* that matches it best, the one registered last among equals, or
## `""` when no catalogue of that language has a `RELEASE-NOTES.md` beside it.
##
## Beside the catalogue rather than registered on its own, because the module
## that translates the words is the one that translates the notes, and a
## catalogue already says where its module sits, in the project or in a
## painter's modules folder alike. English has no catalogue and so no notes
## here: the English file is the one `read()` reads first.
static func notes_path(registry: SaTranslationRegistry, locale: String) -> String:
    if registry == null:
        return ""
    var best := ""
    var best_score := 0
    for entry: Dictionary in registry.catalogues():
        var source := str(entry["source"])
        var score := TranslationServer.compare_locales(str(entry["locale"]), locale)
        if source == "" or score <= 0 or score < best_score:
            continue
        var beside := source.get_base_dir().path_join(NOTES_NAME)
        if FileAccess.file_exists(beside):
            best = beside
            best_score = score
    return best


## *english* with each section's lines taken from the section of *notes* of the
## same version, when that section has as many lines, and left English
## otherwise.
##
## Line for line, because the English file grows between two drafts of a
## translation: a section that gained a line since its translation was written
## reads whole in English rather than in a language that leaves the new line
## out. Every section is a copy, so the parsed English is never written over.
static func localised(english: Array, notes: Array) -> Array:
    var by_version := {}
    for section: Dictionary in notes:
        by_version[str(section["version"])] = section
    var out: Array = []
    for section: Dictionary in english:
        var copy: Dictionary = section.duplicate()
        var theirs: Dictionary = by_version.get(str(section["version"]), {})
        var ours: PackedStringArray = section["lines"]
        var translated: PackedStringArray = theirs.get("lines", PackedStringArray())
        if not theirs.is_empty() and translated.size() == ours.size():
            copy["lines"] = translated
        out.append(copy)
    return out


## Where the repository keeps the changelog, or `""` in anything but an editor
## run.
##
## `OS.has_feature("editor")` is the whole guard. An exported build has no
## checkout above it, and a directory beside a binary is a directory Sara did
## not write, so a release note read out of it would be a claim about somebody
## else's file.
static func _checkout_path() -> String:
    if not OS.has_feature("editor"):
        return ""
    return ProjectSettings.globalize_path("res://").path_join("..").path_join(CHECKOUT_NAME).simplify_path()


## Every section, newest first, as `{"version": String, "lines": PackedStringArray}`.
static func sections(path: String = PATH) -> Array:
    return read(path)["sections"]


## The sections newer than `version`, newest first. `""` is every section.
##
## "Newer than 0.10.0" is 0.10.1 and above, so a pane that remembers the last
## version a painter saw asks for exactly what they have not read.
static func since(version: String, path: String = PATH) -> Array:
    return newer_than(sections(path), version)


## The sections of `all` newer than `version`, newest first.
static func newer_than(all: Array, version: String) -> Array:
    if version == "":
        return all
    var out: Array = []
    for section: Dictionary in all:
        if compare_versions(str(section["version"]), version) > 0:
            out.append(section)
    return out


## The sections of `text`, newest first.
##
## The pure half of `sections()`, so a test parses a string without a file to
## put it in. Sorted by version rather than kept in file order, because the
## pane's first row is the version a painter is on and a file written by hand
## is a file that can be appended in the wrong place.
static func parse(text: String) -> Array:
    var out: Array = []
    var current: Dictionary[String, Variant] = {}
    # A PackedStringArray read back out of the dictionary is a copy, so the
    # lines are gathered here and handed over when the section closes. Appending
    # to `current["lines"]` would grow nothing.
    var lines := PackedStringArray()
    for raw in text.split("\n"):
        var line := String(raw).strip_edges()
        if line.begins_with(SECTION_PREFIX):
            if not current.is_empty():
                current["lines"] = lines
                out.append(current)
            current = {"version": line.substr(SECTION_PREFIX.length()).strip_edges()}
            lines = PackedStringArray()
        elif not current.is_empty() and line != "" and not line.begins_with(COMMENT_PREFIX):
            lines.append(line)
    if not current.is_empty():
        current["lines"] = lines
        out.append(current)
    out.sort_custom(
        func(a: Dictionary[String, Variant], b: Dictionary[String, Variant]) -> bool:
            return compare_versions(str(a["version"]), str(b["version"])) > 0
    )
    return out


## -1, 0 or 1. "0.10.1" is above "0.9.1", which a string compare gets wrong.
##
## Three numbers at a time. A part that is not a whole number reads as zero, so
## a version nobody can order sinks rather than raising.
##
## A heading that carries no number at all is the open section the file is
## written with, "## Unreleased", and it holds what the next release will
## carry, so it stands above every version rather than under them. Read as a
## version it was three zeroes and sank below 0.6.0, which left the oldest
## release at the top of the News pane of every run made between two closes.
static func compare_versions(a: String, b: String) -> int:
    var a_open := is_open(a)
    var b_open := is_open(b)
    if a_open != b_open:
        return 1 if a_open else -1
    if a_open:
        return 0
    var left := _numbers(a)
    var right := _numbers(b)
    for i in VERSION_PARTS:
        if left[i] != right[i]:
            return 1 if left[i] > right[i] else -1
    return 0


## Whether *version* names no release, which is the open section's heading.
##
## A number anywhere among the three parts makes it a release, however the rest
## of the heading is written, so "0.20.0 (draft)" is ordered by its numbers and
## only a heading of words alone stands above them. An empty heading is not
## open, so a `## ` with nothing after it sinks as it did.
##
## Public, because the News pane writes such a heading in the painter's
## language rather than as the file's word.
static func is_open(version: String) -> bool:
    if version.strip_edges() == "":
        return false
    for part in version.split("."):
        if String(part).strip_edges().is_valid_int():
            return false
    return true


static func _numbers(version: String) -> Array[int]:
    var out: Array[int] = [0, 0, 0]
    var parts := version.split(".")
    for i in mini(VERSION_PARTS, parts.size()):
        # `String.to_int()` deletes non-digits rather than parsing, so "0.11"
        # would read as 11. The guard is what makes the read a parse.
        var text := String(parts[i]).strip_edges()
        if text.is_valid_int():
            out[i] = text.to_int()
    return out
