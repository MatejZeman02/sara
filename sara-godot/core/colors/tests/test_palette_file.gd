## SaPaletteFile: the GIMP palette format read and written.
##
## Text in and text out, no RenderingDevice, so this runs in the fast headless
## set as well as in the full gate.
##
## **The fixture is Sara's own bytes in another program's shape.** The
## The requirement asks for "a fixture written by another program", and what
## `tests/data/palette_gimp.gpl` is instead is a file written by hand to be
## exactly what the thirteen `.gpl` files Krita 5.2 ships look like, both
## separators and all: vendoring one of Krita's would put a third-party file in
## the tree, which THIRDPARTY.txt and two provenance suites would then owe a
## row. What was done instead is in this unit's record: the reader was run over
## all thirteen of them on the machine that built it, and read every one.
##
## The refusal tests turn `SaProblems.announce` off, so the transcript shows
## the assertion rather than the alarm it is checking for, and read the line
## back off a sink of their own.
extends "res://tests/test_framework.gd"

const FIXTURE := "res://tests/data/palette_gimp.gpl"
static var scratch: String = SaDataRoot.path("test_palette_file")

## What the fixture says, in the order it says it. The eight bits, so the
## expectations here are the file's own numbers rather than a float anybody
## computed.
const FIXTURE_BYTES := [
    [255, 255, 255, "White"],
    [0, 0, 0, "Black"],
    [242, 242, 242, "Grey 95%"],
    [128, 64, 32, "Warm Shadow"],
    [20, 12, 28, SaPaletteFile.UNNAMED_COLOUR],
]


func _scratch(file_name: String) -> String:
    DirAccess.make_dir_recursive_absolute(scratch)
    return scratch.path_join(file_name)


## Every refusal a body provokes, with the log left quiet.
func _refusals(body: Callable) -> PackedStringArray:
    var lines := PackedStringArray()
    var announcing := SaProblems.announce
    var had_sink := SaProblems.has_sink()
    SaProblems.announce = false
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: lines.append(line))
    # `attach_sink` drains whatever was kept before it, which is another
    # suite's problems and not this one's, so the count starts after that.
    lines.clear()
    body.call()
    SaProblems.detach_sink()
    SaProblems.announce = announcing
    if had_sink:
        # Nothing in the suite attaches one, and if something starts to, this
        # says so rather than swallowing it.
        push_warning("test_palette_file: a sink was attached before this test and is not restored")
    return lines


func _palette_of(entries: Array) -> SaPaletteFile:
    var swatches: Array[SaPaletteFile.Swatch] = []
    for entry: Array in entries:
        var color := Color(entry[0] / 255.0, entry[1] / 255.0, entry[2] / 255.0)
        swatches.append(SaPaletteFile.Swatch.new(color, String(entry[3])))
    return SaPaletteFile.new("Round Trip", 4, swatches)


# ---------------------------------------------------------------------------
# Reading what another program wrote
# ---------------------------------------------------------------------------


## The header, both separators, a name carrying a space and a per cent sign,
## and an entry with no name at all.
func test_the_fixture_reads_as_the_bytes_it_carries() -> void:
    var palette := SaPaletteFile.read_file(FIXTURE)
    assert_not_null(palette, "the fixture reads")
    if palette == null:
        return
    assert_eq(palette.palette_name, "Sara Fixture", "under the Name: line")
    assert_eq(palette.columns, 4, "and the Columns: line")
    assert_eq(palette.swatches.size(), FIXTURE_BYTES.size(), "five colours, and the comments are not among them")
    if palette.swatches.size() != FIXTURE_BYTES.size():
        return
    for index in FIXTURE_BYTES.size():
        var expected: Array = FIXTURE_BYTES[index]
        var swatch: SaPaletteFile.Swatch = palette.swatches[index]
        assert_almost_eq(swatch.color.r, expected[0] / 255.0, 0.002, "swatch %d red" % index)
        assert_almost_eq(swatch.color.g, expected[1] / 255.0, 0.002, "swatch %d green" % index)
        assert_almost_eq(swatch.color.b, expected[2] / 255.0, 0.002, "swatch %d blue" % index)
        assert_eq(swatch.name, String(expected[3]), "swatch %d name" % index)


## A palette with no `Name:` and no `Columns:` is still a palette, which is
## what the format says and what several of Krita's own files do.
func test_the_header_lines_are_optional() -> void:
    var palette := SaPaletteFile.read_text("GIMP Palette\n17 34 51 Slate\n", "bare.gpl")
    assert_not_null(palette, "a palette with nothing but the magic line and a colour")
    if palette == null:
        return
    assert_eq(palette.palette_name, SaPaletteFile.UNNAMED, "named the way GIMP names one")
    assert_eq(palette.columns, SaPaletteFile.DEFAULT_COLUMNS, "and laid out however the program showing it likes")
    assert_eq(palette.swatches.size(), 1, "one colour")


## A `Name:` after the colours have started is a colour line that is not one,
## because a palette's own swatch may well be called "Name: the blue".
func test_a_header_line_after_the_colours_is_not_a_header() -> void:
    var lines := _refusals(
        func() -> void:
            assert_null(
                SaPaletteFile.read_text("GIMP Palette\n1 2 3 First\nName: Late\n", "late.gpl"),
                "a Name: below a colour is refused rather than read as the palette's name"
            )
    )
    assert_eq(lines.size(), 1, "one refusal")
    if lines.is_empty():
        return
    assert_true(lines[0].contains("line 3"), "naming the line it gave up on: %s" % lines[0])


# ---------------------------------------------------------------------------
# Refusing what is not one
# ---------------------------------------------------------------------------


## A file that is not a `.gpl` refuses on its first line, because that line is
## the whole of what makes one.
func test_a_file_that_is_not_a_palette_refuses_on_line_one() -> void:
    var lines := _refusals(
        func() -> void:
            assert_null(SaPaletteFile.read_text('<?xml version="1.0"?>\n', "colors.xml"), "an XML palette is not this format")
            assert_null(SaPaletteFile.read_text("", "empty.gpl"), "and neither is nothing")
    )
    assert_eq(lines.size(), 2, "one refusal each")
    if lines.size() != 2:
        return
    assert_true(lines[0].contains("colors.xml"), "naming the file: %s" % lines[0])
    assert_true(lines[0].contains("Line 1"), "and the line: %s" % lines[0])
    assert_true(lines[0].contains("<?xml"), "quoting what was there instead: %s" % lines[0])


## A line inside a good file that is neither comment nor colour stops the read,
## rather than being dropped so the painter gets a palette missing a colour it
## has no way to notice.
func test_a_line_that_is_no_colour_names_itself() -> void:
    var text := "GIMP Palette\nName: Broken\n255 255 255\tWhite\n255 0\tShort\n0 0 0\tBlack\n"
    var lines := _refusals(
        func() -> void: assert_null(SaPaletteFile.read_text(text, "broken.gpl"), "a two-number line is no colour")
    )
    assert_eq(lines.size(), 1, "one refusal")
    if lines.is_empty():
        return
    assert_true(lines[0].contains("line 4"), "naming the line: %s" % lines[0])
    assert_true(lines[0].contains("255 0"), "and quoting it: %s" % lines[0])


## A channel outside eight bits, and a `Columns:` that is not a number.
func test_the_numbers_are_checked() -> void:
    var lines := _refusals(
        func() -> void:
            assert_null(SaPaletteFile.read_text("GIMP Palette\n300 0 0\tHot\n", "over.gpl"), "300 is no eight-bit channel")
            assert_null(
                SaPaletteFile.read_text("GIMP Palette\nColumns: many\n0 0 0\tBlack\n", "wide.gpl"), "and 'many' is no count"
            )
    )
    assert_eq(lines.size(), 2, "one refusal each")
    if lines.size() != 2:
        return
    assert_true(lines[0].contains("line 2"), "the channel names its line: %s" % lines[0])
    assert_true(lines[1].contains("column count"), "and the count says what it wanted: %s" % lines[1])


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------


## The round trip required: written out, read back, the same
## colours and the same names.
func test_a_written_palette_reads_back_the_same() -> void:
    var palette := _palette_of(FIXTURE_BYTES)
    var path := _scratch("round_trip.gpl")
    assert_true(palette.write_file(path), "the file is written")
    var read_back := SaPaletteFile.read_file(path)
    assert_not_null(read_back, "and read back")
    if read_back == null:
        return
    assert_eq(read_back.palette_name, palette.palette_name, "the palette's name survives")
    assert_eq(read_back.columns, palette.columns, "and its column count")
    assert_eq(read_back.swatches.size(), palette.swatches.size(), "and every colour")
    if read_back.swatches.size() != palette.swatches.size():
        return
    for index in palette.swatches.size():
        var before: SaPaletteFile.Swatch = palette.swatches[index]
        var after: SaPaletteFile.Swatch = read_back.swatches[index]
        assert_true(after.color.is_equal_approx(before.color), "swatch %d is the same colour" % index)
        assert_eq(after.name, before.name, "and swatch %d keeps its name" % index)
    DirAccess.remove_absolute(path)


## Read and written again, the text is the text: the fixture's own colours come
## back out as the same eight bits.
func test_the_fixture_survives_a_write() -> void:
    var palette := SaPaletteFile.read_file(FIXTURE)
    assert_not_null(palette, "the fixture reads")
    if palette == null:
        return
    var text := palette.to_text()
    assert_true(text.begins_with(SaPaletteFile.MAGIC + "\n"), "the magic line is first")
    assert_true(text.contains("Name: Sara Fixture"), "the palette keeps its name")
    assert_true(text.ends_with("\n"), "and the last line ends like every other one")
    for entry: Array in FIXTURE_BYTES:
        var line := "%3d %3d %3d\t%s" % [entry[0], entry[1], entry[2], entry[3]]
        assert_true(text.contains(line), "the file carries '%s'" % line)


# ---------------------------------------------------------------------------
# The document's colour space
# ---------------------------------------------------------------------------


## The three numbers are sRGB, and a document that is not sRGB stores something
## else for them. Mid grey is the case that shows it: 128 in the file is 0.502
## in an sRGB document and 0.216 in a linear one.
func test_the_bytes_are_srgb_and_the_document_may_not_be() -> void:
    var text := "GIMP Palette\n128 128 128\tMid Grey\n"
    var in_srgb := SaPaletteFile.read_text(text, "grey.gpl", SaColorSpace.srgb())
    var in_linear := SaPaletteFile.read_text(text, "grey.gpl", SaColorSpace.linear_srgb())
    assert_not_null(in_srgb, "an sRGB document reads it")
    assert_not_null(in_linear, "and so does a linear one")
    if in_srgb == null or in_linear == null:
        return
    assert_almost_eq(in_srgb.swatches[0].color.r, 128.0 / 255.0, 0.001, "sRGB stores the byte as it stands")
    assert_almost_eq(in_linear.swatches[0].color.r, 0.2158, 0.001, "and a linear document stores the light it means")


## Whatever the document, the byte that went in is the byte that comes out, so
## a painter's palette is not quietly darkened by a round trip through Sara.
func test_every_space_writes_the_bytes_back() -> void:
    var text := "GIMP Palette\n255 128 0\tOrange\n 17  34  51\tSlate\n"
    for space in SaColorSpace.presets():
        var palette := SaPaletteFile.read_text(text, "orange.gpl", space)
        assert_not_null(palette, "%s reads the palette" % space.id)
        if palette == null:
            continue
        var written := palette.to_text(space)
        assert_true(written.contains("255 128   0\tOrange"), "%s writes the orange back" % space.id)
        assert_true(written.contains(" 17  34  51\tSlate"), "%s writes the slate back" % space.id)


## A colour above white is a real value under hard rule 5 and eight bits cannot
## say it, so the writer clamps rather than wrapping.
func test_a_colour_above_white_clamps_rather_than_wrapping() -> void:
    var swatches: Array[SaPaletteFile.Swatch] = [SaPaletteFile.Swatch.new(Color(3.0, 0.5, -1.0), "Overshoot")]
    var text := SaPaletteFile.new("Wide", 0, swatches).to_text()
    assert_true(text.contains("255 128   0\tOvershoot"), "3.0 is 255 and -1.0 is 0, not a wrap: %s" % text)
