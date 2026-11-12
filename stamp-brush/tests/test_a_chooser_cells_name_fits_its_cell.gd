## A chooser cell's name fits its cell.
##
## In the Brush Editor's pattern chooser a long name such as "Flowypaint Texture
## Gray 0002" must not wrap by the word to as many lines as the name needs, which
## would grow the cell to five lines under a tile the width of a short word and
## make its row of the grid stand taller than the rest.
##
## So the assertions are that a forty character name's
## cell is exactly as tall as a short name's, the label holds two lines and
## ends in an ellipsis past them, and the full name is the cell's tooltip.
## Written against the chooser rather than the label alone, because the cell's
## height is what the grid lays out and a label that wraps to two lines inside
## a cell that still grew would pass a label test and fail the painter.
##
## The last test writes the `.kpp` the scenario imports, so the committed
## fixture cannot drift from the writer, the way `test_pattern.gd` keeps
## `sara-pat-paper.kpp` honest.
extends "res://tests/test_framework.gd"

## The chooser builds a texture per cell, and a generated pattern is a dispatch.
const REQUIRES_GPU := true

const Fixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")
const Probe = preload("res://tests/fixtures/text_cut_probe.gd")
const FIXTURES_DIR := "res://modules/sara-base-modules/stamp-brush/tests/fixtures"

static var scratch_dir: String = SaDataRoot.path("test_d3_chooser_cell_name")
## Forty characters once the store has capitalized the stem, which is the
## length the test asks for, and four more than a typical name.
const LONG_FILE := "sara-fixture-paper-with-a-long-name-0002.png"
const SHORT_FILE := "sara-fixture-short.png"
const LONG_NAME := "Sara Fixture Paper With A Long Name 0002"

## The committed preset the scenario imports, carrying the long-named paper.
const LONG_KPP_COMMITTED := FIXTURES_DIR + "/sara-long-name-paper.kpp"
const LONG_KPP_NAME := "Sara fixture long name"


func after_each() -> void:
    if not DirAccess.dir_exists_absolute(scratch_dir):
        return
    var dir := DirAccess.open(scratch_dir)
    for file in dir.get_files():
        dir.remove(file)
    DirAccess.remove_absolute(scratch_dir)


## A small grey paper: a checker of two greys, so the tile is a picture and not
## a flat field.
static func paper_png() -> PackedByteArray:
    var image := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
    for y in 8:
        for x in 8:
            var lit := 0.75 if (x + y) % 2 == 0 else 0.4
            image.set_pixel(x, y, Color(lit, lit, lit, 1.0))
    return image.save_png_to_buffer()


## The `.kpp` the scenario imports: a plain round brush whose texture is the
## long-named paper, so the import writes that paper where the store lists it.
static func long_name_kpp() -> PackedByteArray:
    var paper := paper_png()
    var params: Dictionary = Fixtures._common_params()
    params["brush_definition"] = [
        "string",
        (
            '<Brush type="auto_brush" useAutoSpacing="0" randomness="0" density="1" autoSpacingCoeff="1" BrushVersion="2"'
            + ' spacing="0.1" angle="0">'
            + ' <MaskGenerator ratio="1" type="circle" vfade="0.5" id="default" spikes="2" antialiasEdges="1" hfade="0.5"'
            + ' diameter="60"/> </Brush>'
        )
    ]
    params["Texture/Pattern/Enabled"] = ["internal", "true"]
    params["Texture/Pattern/PatternFileName"] = ["string", LONG_FILE]
    params["Texture/Pattern/Strength"] = ["internal", "1"]
    var resources := [{"name": LONG_FILE.get_basename(), "filename": LONG_FILE, "type": "patterns", "bytes": paper}]
    return Fixtures._kpp(Fixtures._preset_xml(LONG_KPP_NAME, params, resources), "zTXt")


func _write(file_name: String, bytes: PackedByteArray) -> String:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join(file_name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()
    return path


## A chooser over the scratch folder alone, hosted in a box the way the editor's
## page hosts it, so the labels have a theme to measure their lines against.
func _hosted(side: int = SaPatternChooser.DEFAULT_ICON) -> Array:
    _write(LONG_FILE, paper_png())
    _write(SHORT_FILE, paper_png())
    var host := VBoxContainer.new()
    host.size = Vector2(400.0, 400.0)
    var chooser := SaPatternChooser.new(null, side)
    host.add_child(chooser)
    chooser.store = SaPatternStore.new([scratch_dir])
    chooser.refresh()
    return [host, chooser]


func _cell(chooser: SaPatternChooser, pattern_name: String) -> Control:
    for box in chooser.grid.get_children():
        var label := (box as Node).get_node("Name") as Label
        if label.text == pattern_name:
            return box as Control
    return null


## The regression. A forty character name's cell is as tall as a short one's,
## at every size the host may ask for.
func test_a_long_names_cell_is_a_short_names_height() -> void:
    for side: int in [SaPatternChooser.MIN_ICON, SaPatternChooser.DEFAULT_ICON, SaPatternChooser.MAX_ICON]:
        var pair := _hosted(side)
        var chooser: SaPatternChooser = pair[1]
        var long_cell := _cell(chooser, LONG_NAME)
        var short_cell := _cell(chooser, SaPatternStore.name_for(SHORT_FILE))
        assert_not_null(long_cell, "the long name has a cell at %d" % side)
        assert_not_null(short_cell, "and so does the short one")
        if long_cell != null and short_cell != null:
            assert_eq(LONG_NAME.length(), 40, "the name is the length the test asks for")
            assert_almost_eq(
                long_cell.get_combined_minimum_size().y,
                short_cell.get_combined_minimum_size().y,
                0.5,
                (
                    "one row height at %d: %.1f against %.1f"
                    % [side, long_cell.get_combined_minimum_size().y, short_cell.get_combined_minimum_size().y]
                )
            )
            assert_true(
                long_cell.get_combined_minimum_size().x <= float(SaUI.px(side)) + 0.5,
                "and the name never widens the cell past the tile, %.1f" % long_cell.get_combined_minimum_size().x
            )
        (pair[0] as Node).free()


## The label holds two lines and ends in an ellipsis past them.
func test_the_name_holds_two_lines_and_then_an_ellipsis() -> void:
    var pair := _hosted()
    var chooser: SaPatternChooser = pair[1]
    var label := _cell(chooser, LONG_NAME).get_node("Name") as Label
    assert_eq(label.max_lines_visible, SaPatternChooser.NAME_LINES, "two lines")
    assert_eq(label.text_overrun_behavior, SaTheme.TEXT_CUT, "then an ellipsis, the cut that always draws one")
    assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_WORD, "wrapped by the word, so a name a pixel too wide stays whole")
    assert_true(label.custom_minimum_size.y > 0.0, "with the two lines' height declared, %.1f" % label.custom_minimum_size.y)
    var short_label := _cell(chooser, SaPatternStore.name_for(SHORT_FILE)).get_node("Name") as Label
    assert_eq(short_label.custom_minimum_size.y, label.custom_minimum_size.y, "and a short name declares the same floor")
    (pair[0] as Node).free()


## The name's cut ends in an ellipsis at every width the cell may be drawn at,
## on the last of its two lines. The plain
## `OVERRUN_TRIM_ELLIPSIS` adds its ellipsis only while the text it keeps is six
## characters or more, so the setting alone says nothing about the picture, and
## the probe draws the label and compares it with a plain cut.
func test_the_name_never_ends_in_a_plain_cut() -> void:
    var pair := _hosted()
    var chooser: SaPatternChooser = pair[1]
    var label := _cell(chooser, LONG_NAME).get_node("Name") as Label
    var probe := Probe.new(EventBus)
    var result: Dictionary = probe.sweep(label, 140)
    var cut: int = result["cut"]
    var unmarked: Array = result["unmarked"]
    assert_true(cut >= 8, "The sweep met the name cut at %d widths, which is enough to mean the range" % cut)
    assert_true(unmarked.is_empty(), "and it ends in a mark at every one, and did not at %s" % str(unmarked))
    probe.release()
    (pair[0] as Node).free()


## The full name is the cell's tooltip, on the label and on the tile.
func test_the_full_name_is_the_tooltip() -> void:
    var pair := _hosted()
    var chooser: SaPatternChooser = pair[1]
    var cell := _cell(chooser, LONG_NAME)
    assert_eq((cell.get_node("Name") as Label).tooltip_text, LONG_NAME, "the label says the whole name")
    assert_eq((cell.get_node("Tile") as Button).tooltip_text, LONG_NAME, "and so does the tile")
    (pair[0] as Node).free()


## The committed fixture the scenario imports is the one the writer above
## makes, which is what keeps a binary in the tree from drifting.
func test_the_committed_long_name_preset_is_the_written_one() -> void:
    var written := SaKppReader.read_file(_write("sara-long-name-paper-check.kpp", long_name_kpp()))
    var committed := SaKppReader.read_file(LONG_KPP_COMMITTED)
    for key: String in ["name", "engine", "options", "error"]:
        assert_eq(committed[key], written[key], "sara-long-name-paper.kpp agrees on %s" % key)
    var resource: Dictionary = (committed["resources"] as Dictionary).get(LONG_FILE.get_basename(), {})
    assert_eq(String(resource.get("type", "")), "patterns", "the paper rides as a patterns resource")
    assert_eq(SaPatternStore.name_for(String(resource.get("filename", ""))), LONG_NAME, "under the forty character name")
