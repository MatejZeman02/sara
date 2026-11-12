## The GIMP palette format, `.gpl`, read and written.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The plain text palette GIMP, Krita, Inkscape and Aseprite all read, which is
## what a painter means by "bring my palette in". A first line saying
## `GIMP Palette`, an optional `Name:` and `Columns:`, `#` comments, then one
## line per colour: three integers and, after them, whatever the painter called
## it.
##
## **This class holds no docker and no store.** It is a file format and nothing
## else: text in, a list of swatches out, the same text back. What puts the
## swatches on screen is the palette docker, and this file, a reader with no
## docker on it, has no scenario of its own.
##
## **A `.gpl` is eight-bit and curve-encoded, and Sara's canvas may be anything.**
## The three numbers on a line are the picker's values through sRGB's curve, and
## Sara's stored colours are the document's own: a linear document holds mid grey
## at 0.214 where the file says 128. They mean the document's gamut, as a picked
## colour does, so `255 0 0` is P3's red in a P3 document. Every colour crosses
## through [method SaColorSpace.from_display] on the way in and
## [method SaColorSpace.to_display] on the way out, the same pair the eyedropper
## and the colour wheel use, and the space is an argument of the call rather than
## a field, because the same palette read for two documents is two different sets
## of stored values. An RGB document on the sRGB curve takes the exact passthrough
## that pair promises, so nothing rounds where nothing should.
##
## **A refusal is a message, not half a palette.** A file that is not a `.gpl`
## refuses through [SaProblems] naming the line it gave up on, and answers null.
## A line inside a good file that is neither a header, a comment nor a colour
## does the same, because a palette that silently drops the rows it could not
## read is worse than one that did not open: the painter sees swatches and has
## no way to know which are missing.
##
## **Each refusal builds its own line rather than going through a helper**, and
## that is not an oversight. Every `SaProblems.refuse` call site carries its
## own lookup, `tests/test_refusals_translate.gd` reads the tree to check
## it, and a helper taking a finished string would put the lookup somewhere the
## sweep cannot see it and the string extractor cannot either.
## `TranslationServer.translate` rather than `tr`, because these are static
## functions with no `self` to reach `tr` through.
class_name SaPaletteFile
extends RefCounted

## Who a refusal is from, in the class's own name, the way [SaProblems] asks.
const SOURCE := "SaPaletteFile"

## The first line, exactly, and the whole of what makes a file this format.
const MAGIC := "GIMP Palette"

## What the file is called on disk, without the dot.
const EXTENSION := "gpl"

## The name a palette carrying no `Name:` line is given, which is GIMP's own
## word for it.
const UNNAMED := "Untitled"

## The name a colour carrying nothing after its three numbers is given. GIMP
## writes this too rather than an empty column, so a round trip through GIMP
## and back does not turn a blank into the word and call it a change.
const UNNAMED_COLOUR := "Untitled"

## No `Columns:` line, which means the program showing it chooses. Written out
## again as a `Columns:` line all the same, because GIMP writes one always.
const DEFAULT_COLUMNS: int = 0

## The largest `Columns:` believed. A palette laid out a thousand wide is a
## number read off the wrong line.
const MAX_COLUMNS: int = 256


## One colour and what the painter called it.
##
## A class rather than a [Dictionary] so that a swatch answers for its own
## fields and a caller reading `swatch.name` is checked at parse time.
class Swatch:
    extends RefCounted

    ## The colour in the document's coordinates, not the file's eight bits.
    var color: Color

    ## The rest of the line after the three numbers, or [constant
    ## SaPaletteFile.UNNAMED_COLOUR]. Kept verbatim, spaces and all, because a
    ## palette's names are the painter's words and "Skin shadow 2" is one name.
    var name: String

    func _init(of_color: Color, called: String) -> void:
        color = of_color
        name = called


## What the `Name:` line said, or [constant UNNAMED].
var palette_name: String

## What the `Columns:` line said, or [constant DEFAULT_COLUMNS].
var columns: int

## The colours, in the file's order.
var swatches: Array[Swatch]


func _init(called: String, in_columns: int, of_swatches: Array[Swatch]) -> void:
    palette_name = called
    columns = in_columns
    swatches = of_swatches


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------


## The palette in *text*, or null with the reason refused through [SaProblems].
##
## *file_name* is what a refusal calls the file, so a message names something
## the painter can find. *space* is the document the colours are being read
## for, and null means sRGB, where the conversion is the identity.
static func read_text(text: String, file_name: String, space: SaColorSpace = null) -> SaPaletteFile:
    var target := space if space != null else SaColorSpace.srgb()
    var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    if lines.is_empty() or lines[0].strip_edges() != MAGIC:
        var first := lines[0].strip_edges() if not lines.is_empty() else ""
        SaProblems.refuse(
            SOURCE, TranslationServer.translate('%s does not open with "%s". Line 1 is "%s".') % [file_name, MAGIC, first]
        )
        return null

    var called := UNNAMED
    var in_columns := DEFAULT_COLUMNS
    var found: Array[Swatch] = []
    # The header lines may only appear before the first colour, which is what
    # every writer does and what keeps a `Name:` in a palette's own swatch list
    # from being read as the palette's name.
    var in_header := true
    for index in range(1, lines.size()):
        var line := lines[index]
        var trimmed := line.strip_edges()
        if trimmed.is_empty() or trimmed.begins_with("#"):
            continue
        if in_header and trimmed.begins_with("Name:"):
            called = trimmed.substr(5).strip_edges()
            if called.is_empty():
                called = UNNAMED
            continue
        if in_header and trimmed.begins_with("Columns:"):
            var counted := _columns_of(trimmed.substr(8).strip_edges())
            if counted < 0:
                SaProblems.refuse(
                    SOURCE,
                    (
                        TranslationServer.translate('%s, line %s: "%s" is not a valid column count.')
                        % [file_name, index + 1, trimmed]
                    )
                )
                return null
            in_columns = counted
            continue
        var swatch := _swatch_of(line)
        if swatch == null:
            SaProblems.refuse(
                SOURCE,
                (
                    TranslationServer.translate('%s, line %s: "%s" is neither a comment nor a colour.')
                    % [file_name, index + 1, trimmed]
                )
            )
            return null
        in_header = false
        found.append(Swatch.new(target.from_display(swatch.color), swatch.name))
    return SaPaletteFile.new(called, in_columns, found)


## The palette at *path*, or null with the reason refused through [SaProblems].
static func read_file(path: String, space: SaColorSpace = null) -> SaPaletteFile:
    if not FileAccess.file_exists(path):
        SaProblems.refuse(SOURCE, TranslationServer.translate("%s is not there to read.") % path.get_file())
        return null
    var text := FileAccess.get_file_as_string(path)
    if text.is_empty():
        SaProblems.refuse(SOURCE, TranslationServer.translate("%s is empty.") % path.get_file())
        return null
    return read_text(text, path.get_file(), space)


## One entry line as a swatch in sRGB display coordinates, or null when the
## line is not one.
##
## Split on runs of whitespace, because the format is written with tabs by some
## programs and with padded spaces by others, and the same reader has to take
## both. The name is the rest of the line after the third number rather than a
## fourth field, so "Grey 95%" survives as one name.
static func _swatch_of(line: String) -> Swatch:
    var trimmed := line.strip_edges()
    var channels := PackedInt32Array()
    var at := 0
    while channels.size() < 3:
        while at < trimmed.length() and _is_space(trimmed[at]):
            at += 1
        var start := at
        while at < trimmed.length() and not _is_space(trimmed[at]):
            at += 1
        if at == start:
            return null
        var word := trimmed.substr(start, at - start)
        if not word.is_valid_int():
            return null
        var value := word.to_int()
        if value < 0 or value > 255:
            return null
        channels.append(value)
    var called := trimmed.substr(at).strip_edges()
    if called.is_empty():
        called = UNNAMED_COLOUR
    var display := Color(channels[0] / 255.0, channels[1] / 255.0, channels[2] / 255.0)
    return Swatch.new(display, called)


## A `Columns:` value, or -1 when the text is not one.
static func _columns_of(text: String) -> int:
    if not text.is_valid_int():
        return -1
    var value := text.to_int()
    if value < 0 or value > MAX_COLUMNS:
        return -1
    return value


static func _is_space(character: String) -> bool:
    return character == " " or character == "\t"


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------


## The palette as the text of a `.gpl`, in the shape GIMP itself writes: the
## magic line, a `Name:`, a `Columns:`, a bare `#`, then the colours as three
## numbers right-aligned in three columns and a tab before the name.
##
## *space* is the document the colours are in, and the same argument
## [method read_text] took, so a palette read for a linear document and written
## back out lands on the eight bits it came from.
func to_text(space: SaColorSpace = null) -> String:
    var source := space if space != null else SaColorSpace.srgb()
    var out := PackedStringArray()
    out.append(MAGIC)
    out.append("Name: %s" % palette_name)
    out.append("Columns: %d" % columns)
    out.append("#")
    for swatch in swatches:
        var display := source.to_display(swatch.color)
        out.append("%3d %3d %3d\t%s" % [_byte_of(display.r), _byte_of(display.g), _byte_of(display.b), swatch.name])
    # A trailing newline, because a text file's last line ends like every other
    # one and GIMP's own writer puts it there.
    return "\n".join(out) + "\n"


## The palette written to *path*, or false with the reason reported. A fault
## rather than a refusal: the painter asked for a file and did not get one.
func write_file(path: String, space: SaColorSpace = null) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        SaProblems.report(
            SOURCE,
            (
                TranslationServer.translate("%s could not be written: %s.")
                % [path.get_file(), error_string(FileAccess.get_open_error())]
            )
        )
        return false
    file.store_string(to_text(space))
    file.close()
    return true


## One channel as the eight bits a `.gpl` carries.
##
## Rounded rather than truncated, and clamped, because hard rule 5's
## out-of-range values reach here: a colour above white is a real value in the
## document and 255 is the most this format can say about it.
static func _byte_of(channel: float) -> int:
    return clampi(int(roundf(channel * 255.0)), 0, 255)
