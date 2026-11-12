## No text the interface writes holds a character one of the
## four shipped faces lacks.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The kind button beside + in the Layers docker and a group's fold mark were
## the triangle U+25BE in their text, and the Colour Picker's swap button the
## arrow U+21C4. The default Inter has neither, nor has Atkinson Hyperlegible,
## so on a machine with no system font to lend the glyph each drew a white box
## holding "25 BE". They are icons now, and so are the Recorder's and the brush
## editor's fold arrows, the top bar's reset, the toolbox's flyout corner and the
## Arrange page's grip, which the same scan found.
##
## This is the scan, so the next arrow is caught in the gate rather than by a
## painter. It reads every string literal of every `.gd` file under `res://ui/`,
## escapes decoded, and fails on a character outside Basic Latin and the General
## Punctuation block that a shipped face, Regular or Bold, has no glyph for. A
## suite's own folder is left out, because a test may hold any character as data.
## Drawn rather than written is the fix: an icon from `assets/icons/` through
## `SaUI.set_button_icon`, or a `_draw` of its own.
##
## What a person sees is
## `scenarios/the-layer-kind-arrow-the-group-fold-mark-and-the-swap-button-draw.json`,
## the same docker in each of the four faces.
extends "res://tests/test_framework.gd"

const ROOT := "res://ui"

## Basic Latin and the General Punctuation block, which every face has whole
## enough that a dash or a quote is never a box.
const BASIC_LATIN_END := 0x80
const PUNCTUATION_START := 0x2000
const PUNCTUATION_END := 0x206F


## Every shipped face as `[name, font]`, Regular and Bold of each family that
## ships files. The engine's Open Sans is left out, which is the face a missing
## glyph falls back from rather than one that lacks it.
func _faces() -> Array:
    var out: Array = []
    for id: String in SaFonts.FAMILIES:
        var family: Dictionary = SaFonts.FAMILIES[id]
        if String(family["regular"]).is_empty():
            continue
        out.append(["%s Regular" % family["name"], SaFonts.regular(id)])
        out.append(["%s Bold" % family["name"], SaFonts.bold(id)])
    return out


## The characters *source* writes inside string literals, as `[line, code]`.
## A comment is skipped, a triple-quoted string may run over lines, and `\u`
## and `\U` escapes are decoded, so writing a glyph as an escape does not hide
## it from the scan.
func _characters_in_strings(source: String) -> Array:
    var out: Array = []
    var line := 1
    var quote := ""
    var i := 0
    var n := source.length()
    while i < n:
        var c := source[i]
        if c == "\n":
            line += 1
            if quote.length() == 1:
                quote = ""
            i += 1
            continue
        if quote.is_empty():
            if c == "#":
                while i < n and source[i] != "\n":
                    i += 1
                continue
            if c == '"' or c == "'":
                quote = c.repeat(3) if source.substr(i, 3) == c.repeat(3) else c
                i += quote.length()
                continue
            i += 1
            continue
        if source.substr(i, quote.length()) == quote:
            i += quote.length()
            quote = ""
            continue
        if c == "\\" and i + 1 < n:
            var kind := source[i + 1]
            var digits := 4 if kind == "u" else (6 if kind == "U" else 0)
            if digits > 0 and source.substr(i + 2, digits).is_valid_hex_number():
                out.append([line, source.substr(i + 2, digits).hex_to_int()])
                i += 2 + digits
            else:
                i += 2
            continue
        out.append([line, c.unicode_at(0)])
        i += 1
    return out


## Whether every face may be asked about *code* at all: Basic Latin and the
## General Punctuation block are taken as read.
static func _is_checked(code: int) -> bool:
    return code >= BASIC_LATIN_END and not (code >= PUNCTUATION_START and code <= PUNCTUATION_END)


## Whether *source* holds anything the scan could find, a character past Basic
## Latin or an escape that may stand for one. Most scripts hold neither, and
## walking those a character at a time would be most of what the suite costs.
static func _may_hold_a_glyph(source: String) -> bool:
    return source.to_utf8_buffer().size() != source.length() or source.contains("\\u") or source.contains("\\U")


## Every `.gd` file under *dir_path*, suites' folders left out, relative to the
## project.
func _scripts(dir_path: String, out: Array[String]) -> void:
    for sub: String in DirAccess.get_directories_at(dir_path):
        if sub != "tests":
            _scripts(dir_path.path_join(sub), out)
    for file: String in DirAccess.get_files_at(dir_path):
        if file.get_extension() == "gd":
            out.append(dir_path.path_join(file))


func test_every_shipped_face_loads() -> void:
    var faces := _faces()
    assert_eq(faces.size(), 8, "four families, Regular and Bold of each")
    for face: Array in faces:
        assert_not_null(face[1], "%s loads" % face[0])


## The scan is only as good as `has_char`, so it is held to two answers the
## survey of the files found: Inter has U+21BA and lacks
## U+25BE.
func test_a_face_says_which_glyphs_it_lacks() -> void:
    var inter := SaFonts.regular("inter")
    assert_true(inter.has_char(0x21BA), "Inter has the anticlockwise arrow")
    assert_false(inter.has_char(0x25BE), "and not the small down triangle, which the kind button drew as a box")
    assert_true(inter.has_char("A".unicode_at(0)), "and a letter, of course")


func test_the_scan_reads_strings_and_their_escapes_and_skips_comments() -> void:
    var down := String.chr(0x25BE)
    var source := (
        "\n"
        . join(
            [
                "# %s in a comment is prose nobody draws" % down,
                'var a := "%s"' % down,
                'var b := "\\u21c4 and \\U01F600"',
                "var c := '''one",
                "%s two'''" % down,
                'var d := "plain" # %s' % down,
            ]
        )
    )
    var found := _characters_in_strings(source).filter(func(hit: Array) -> bool: return _is_checked(int(hit[1])))
    assert_eq(
        found, [[2, 0x25BE], [3, 0x21C4], [3, 0x1F600], [5, 0x25BE]], "a literal, two escapes and a long string, no comment"
    )
    assert_false(_is_checked(0x2014), "an em dash is General Punctuation, taken as read")
    assert_false(_is_checked("A".unicode_at(0)), "and a letter is Basic Latin")
    assert_true(_is_checked(0xB0), "while the degree sign is asked about")
    assert_true(_may_hold_a_glyph(source), "A script with either is walked")
    assert_true(_may_hold_a_glyph('var b := "\\u21c4"'), "an escape alone is enough")
    assert_false(_may_hold_a_glyph('var a := "plain" # and a comment'), "and one of plain letters is passed over")


## The guard itself. A failure names the file, the line, the character and the
## faces it is missing from.
func test_no_string_under_ui_holds_a_glyph_a_face_lacks() -> void:
    var faces := _faces()
    var scripts: Array[String] = []
    _scripts(ROOT, scripts)
    assert_true(scripts.size() > 150, "the scan reads the interface's scripts, found %d" % scripts.size())
    var problems: Array[String] = []
    for path: String in scripts:
        var source := FileAccess.get_file_as_string(path)
        if not _may_hold_a_glyph(source):
            continue
        for hit: Array in _characters_in_strings(source):
            var code := int(hit[1])
            if not _is_checked(code):
                continue
            var lacking: Array[String] = []
            for face: Array in faces:
                if not (face[1] as Font).has_char(code):
                    lacking.append(String(face[0]))
            if not lacking.is_empty():
                problems.append("%s:%d U+%04X is missing from %s" % [path, int(hit[0]), code, ", ".join(lacking)])
    assert_true(problems.is_empty(), "Draw these as an icon or a _draw rather than as text:\n%s" % "\n".join(problems))
