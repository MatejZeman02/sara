## The kept swatches load from and save to a GIMP palette.
##
## A "colour palette" is on the side a painter can reach. A class read and
## wrote `.gpl` as a class with no docker on it, and the Swatches row had one
## button, "+", and no way to bring a palette in or hand one on.
##
## Three halves, each asserted where it lives. The store keeps a whole palette in
## one call, so twenty colours are one save and one announcement rather than
## twenty of each. The picker reads a file into a request and writes its kept
## swatches out, through that class. And a load adds after what is kept, which
## was the only answer it had until the row gained a Clear button and with it
## the second one: a load may now stand on what is kept instead of following it,
## and the fourth section below is that pair.
##
## `scenarios/the-swatches-load-and-save-a-palette.json` is the same claim on
## the running app, through the Load and Save buttons and the file dialog they
## put up, and `scenarios/f1-...` is F1's through Clear, Replace and Add.
##
## **The Swatches row is `SaPaletteRow`'s since F1**, which is why the picker's
## half below reads it through `picker.palette_row`: the chips, the four buttons
## and the `.gpl` round trip left `sa_color_picker.gd` when F1's question took
## that file past the advisory, the way the shape and the sliders left it.
extends "res://tests/test_framework.gd"

const FIXTURE := "res://tests/data/palette_gimp.gpl"


## A store that counts its writes rather than making them, so a test can say how
## many saves a call cost without reading the disk.
class CountingStore:
    extends SaColorStore

    var saves: int = 0

    func save() -> void:
        saves += 1


var _scratch: String = ""


func before_each() -> void:
    _scratch = ProjectSettings.globalize_path(SaDataRoot.folder()).path_join("test_g4_palette.gpl")
    if FileAccess.file_exists(_scratch):
        DirAccess.remove_absolute(_scratch)


func after_each() -> void:
    if FileAccess.file_exists(_scratch):
        DirAccess.remove_absolute(_scratch)


func _store() -> CountingStore:
    var store := CountingStore.new()
    store.swatches.assign([Color.RED])
    return store


# --- The store ---------------------------------------------------------------


func test_a_whole_palette_is_one_save_and_one_announcement() -> void:
    var store := _store()
    var heard := [0]
    store.swatches_changed.connect(func() -> void: heard[0] += 1)
    var palette: Array = [Color.GREEN, Color.BLUE, Color.YELLOW, Color.CYAN, Color.MAGENTA]
    store.add_swatches(palette)
    assert_eq(store.saves, 1, "Five colours cost one save")
    assert_eq(heard[0], 1, "and one announcement")
    assert_eq(store.swatches.size(), 6, "and all five are kept")
    store.free()


func test_a_load_adds_after_the_swatches_already_kept() -> void:
    var store := _store()
    store.add_swatches([Color.GREEN, Color.BLUE])
    assert_eq(store.swatches[0], Color.RED, "The swatch that was kept is still first")
    assert_eq(store.swatches[1], Color.GREEN, "and the palette follows it")
    assert_eq(store.swatches[2], Color.BLUE, "in the file's order")
    store.free()


## F1. The clear the argument above was missing: every kept swatch goes, for one
## save and one announcement, exactly the way a whole palette arrives.
func test_clear_swatches_empties_and_announces_once() -> void:
    var store := CountingStore.new()
    store.swatches.assign([Color.RED, Color.GREEN, Color.BLUE])
    var heard := [0]
    store.swatches_changed.connect(func() -> void: heard[0] += 1)
    store.clear_swatches()
    assert_eq(store.swatches.size(), 0, "Every kept swatch goes")
    assert_eq(store.saves, 1, "for one save")
    assert_eq(heard[0], 1, "and one announcement")
    store.free()


## An empty row has nothing to throw away, so a clear writes nothing and tells
## nobody, the same as an empty palette arriving.
func test_clearing_an_empty_row_is_not_a_change() -> void:
    var store := CountingStore.new()
    var heard := [0]
    store.swatches_changed.connect(func() -> void: heard[0] += 1)
    store.clear_swatches()
    assert_eq(store.saves, 0, "Nothing to throw away writes nothing")
    assert_eq(heard[0], 0, "and tells nobody")
    store.free()


func test_an_empty_palette_is_not_a_change() -> void:
    var store := _store()
    var heard := [0]
    store.swatches_changed.connect(func() -> void: heard[0] += 1)
    store.add_swatches([])
    assert_eq(store.saves, 0, "Nothing to keep writes nothing")
    assert_eq(heard[0], 0, "and tells nobody")
    assert_eq(store.swatches.size(), 1, "and leaves the kept swatch where it was")
    store.free()


# --- The picker ---------------------------------------------------------------


func test_the_row_carries_a_load_a_save_and_a_clear() -> void:
    var picker := SaColorPicker.new()
    var row := picker.palette_row
    assert_not_null(row, "The picker has a Swatches row of its own (F1)")
    assert_not_null(row.load_palette_button, "which has a Load button")
    assert_not_null(row.save_palette_button, "and a Save button")
    assert_not_null(row.clear_palette_button, "and a Clear button")
    assert_eq(row.load_palette_button.get_parent(), row.heading, "on the heading of that strip")
    assert_true(
        row.load_palette_button.tooltip_text.contains("You choose whether"),
        "and Load's tooltip says the painter chooses rather than it only adding: %s" % row.load_palette_button.tooltip_text
    )
    picker.free()


func test_loading_the_fixture_asks_for_its_colours_in_one_request() -> void:
    var picker := SaColorPicker.new()
    var asked: Array = []
    picker.swatches_add_requested.connect(func(colors: Array, _names: Array) -> void: asked.append(colors))
    var count := picker.palette_row.load_palette_path(FIXTURE)
    var expected := SaPaletteFile.read_file(FIXTURE)
    assert_true(count > 0, "The fixture has colours: %d" % count)
    assert_eq(asked.size(), 1, "One request for the whole palette")
    if expected != null and asked.size() == 1:
        assert_eq((asked[0] as Array).size(), expected.swatches.size(), "carrying every colour the file holds")
        assert_eq((asked[0] as Array)[0], expected.swatches[0].color, "in the file's order")
    picker.free()


func test_a_file_that_is_not_a_palette_asks_for_nothing() -> void:
    var picker := SaColorPicker.new()
    var asked: Array = []
    picker.swatches_add_requested.connect(func(colors: Array, _names: Array) -> void: asked.append(colors))
    var not_a_palette := ProjectSettings.globalize_path(SaDataRoot.folder()).path_join("test_g4_not_a_palette.gpl")
    var file := FileAccess.open(not_a_palette, FileAccess.WRITE)
    file.store_string("this is not a palette\n")
    file.close()
    assert_eq(picker.palette_row.load_palette_path(not_a_palette), 0, "A refused file adds no colours")
    assert_eq(asked.size(), 0, "and asks for nothing")
    DirAccess.remove_absolute(not_a_palette)
    picker.free()


func test_saved_swatches_read_back_as_the_same_colours() -> void:
    var picker := SaColorPicker.new()
    var kept: Array = [Color8(255, 0, 0), Color8(12, 200, 90), Color8(128, 128, 128)]
    picker.set_swatches(kept)
    assert_true(picker.palette_row.save_palette_path(_scratch), "The kept swatches write to a file")
    var back := SaPaletteFile.read_file(_scratch)
    assert_not_null(back, "which reads back as a palette")
    if back != null:
        assert_eq(back.swatches.size(), kept.size(), "with every swatch")
        for i in kept.size():
            assert_eq(back.swatches[i].color.to_html(false), (kept[i] as Color).to_html(false), "swatch %d to the byte" % i)
        assert_eq(back.palette_name, "test_g4_palette", "named after its file")
        # The row keeps names now, and one without a name is written as
        # GIMP's own "Untitled" rather than as its hex.
        assert_eq(back.swatches[1].name, SaPaletteFile.UNNAMED_COLOUR, "and an unnamed colour written as GIMP writes one")
    picker.free()


## The whole trip a painter makes: save, clear, load, and the same row again.
func test_a_saved_palette_loads_back_into_an_empty_store() -> void:
    var picker := SaColorPicker.new()
    var store := CountingStore.new()
    picker.swatches_add_requested.connect(store.add_swatches)
    var kept: Array = [Color8(40, 60, 200), Color8(250, 210, 30)]
    picker.set_swatches(kept)
    picker.palette_row.save_palette_path(_scratch)
    assert_eq(store.swatches.size(), 0, "The store starts empty")
    picker.palette_row.load_palette_path(_scratch)
    assert_eq(store.swatches.size(), 2, "and holds the two colours after the load")
    assert_eq(store.swatches[0].to_html(false), (kept[0] as Color).to_html(false), "the first as it was saved")
    assert_eq(store.saves, 1, "for one save")
    store.free()
    picker.free()


# --- What a load does to what was kept -----------------------------------


## The two answers that differ, on one store: Replace leaves the file's colours
## and no others, Add leaves the kept ones and then the file's. A picker outside
## a tree cannot put the question up, so the answer is said here rather than
## pressed, which is the one thing the scenario and this cannot both do.
func test_a_replace_leaves_exactly_the_files_colours() -> void:
    var picker := SaColorPicker.new()
    var store := _three_kept(picker)
    var loaded: Array = [Color.YELLOW, Color.CYAN, Color.MAGENTA, Color.WHITE, Color.BLACK]
    picker.palette_row.answer_load(SaPaletteRow.LoadAnswer.REPLACE, loaded)
    assert_eq(store.swatches.size(), 5, "The file's five, and not the three that were kept")
    assert_eq(store.swatches[0], Color.YELLOW, "the first as the file holds it")
    assert_eq(store.swatches[4], Color.BLACK, "and the last")
    store.free()
    picker.free()


func test_an_add_leaves_the_kept_list_followed_by_the_files() -> void:
    var picker := SaColorPicker.new()
    var store := _three_kept(picker)
    var loaded: Array = [Color.YELLOW, Color.CYAN]
    picker.palette_row.answer_load(SaPaletteRow.LoadAnswer.ADD, loaded)
    assert_eq(store.swatches.size(), 5, "The three, and the two after them")
    assert_eq(store.swatches[2], Color.BLUE, "the kept ones still first")
    assert_eq(store.swatches[3], Color.YELLOW, "and the file's in its own order")
    store.free()
    picker.free()


## Cancel is Escape on the question and the close button with it: the row is the
## one answer that leaves the kept swatches alone.
func test_a_cancelled_load_changes_nothing() -> void:
    var picker := SaColorPicker.new()
    var store := _three_kept(picker)
    picker.palette_row.answer_load(SaPaletteRow.LoadAnswer.CANCEL, [Color.YELLOW])
    assert_eq(store.swatches.size(), 3, "The kept swatches are where they were")
    assert_eq(store.saves, 0, "and nothing was written")
    store.free()
    picker.free()


## A picker holding three kept swatches and a store wired to it the way
## `color_docker.gd` wires the running one.
func _three_kept(picker: SaColorPicker) -> CountingStore:
    var store := CountingStore.new()
    store.swatches.assign([Color.RED, Color.GREEN, Color.BLUE])
    picker.set_swatches(store.swatches)
    picker.swatches_add_requested.connect(store.add_swatches)
    picker.swatches_clear_requested.connect(store.clear_swatches)
    return store


## Clear on an empty row did nothing when pressed and looked as if
## it would. It is dimmed on the check its handler makes, the row being empty,
## and a kept swatch lights it.
func test_clear_is_dimmed_while_the_row_is_empty() -> void:
    var picker := SaColorPicker.new()
    var clear := picker.palette_row.clear_palette_button
    assert_true(clear.disabled, "A row with nothing kept offers no Clear")
    picker.set_swatches([Color.RED])
    assert_false(clear.disabled, "and one swatch kept lights it")
    picker.set_swatches([])
    assert_true(clear.disabled, "An emptied row dims it again")
    picker.free()


# --- The strip under its heading, and what Default shows -----

## The five rows the Default layout ships off, by the names the profile uses.
const SHIPPED_OFF: Array[String] = [
    "Swatches", "Recent Colours", "Hex Input", SaPickerSliders.ELEMENT_RGB, SaPickerSliders.ELEMENT_OKHSV
]
## And the two it ships on: the shape, whose element keeps its old name, and
## the pair.
const SHIPPED_ON: Array[String] = ["HSV Wheel", "Selected Colour Preview"]
const DEFAULT_LAYOUT := "res://layouts/default.cfg"


## The strip is named, its heading carries the three buttons that act on the
## whole of it, and the + is its first cell, where the next chip lands.
func test_the_strip_has_a_heading_that_carries_load_save_and_clear() -> void:
    var picker := SaColorPicker.new()
    var row := picker.palette_row
    assert_eq(row.get_child(0), row.heading, "The heading is the strip's first row")
    assert_eq(row.heading_label.text, "Swatches", "and it says Swatches")
    for button: Button in [row.load_palette_button, row.save_palette_button, row.clear_palette_button]:
        assert_eq(button.get_parent(), row.heading, "%s sits on the heading's row" % button.name)
    assert_eq(row.flow.get_child(0), row.add_swatch_button, "The + is the strip's first cell")

    picker.set_swatches([Color.RED, Color.GREEN])
    assert_eq(row.chips.size(), 2, "Two kept colours are two chips")
    assert_eq(row.chips[0].get_parent(), row.flow, "in the strip")
    assert_true(row.chips[0].get_index() > row.add_swatch_button.get_index(), "after the +")
    picker.set_swatches([Color.BLUE])
    assert_eq(row.flow.get_child(0), row.add_swatch_button, "and a rebuild leaves the + first")
    picker.free()


## An empty strip says so, in a muted line beside the +, where a dimmed Clear
## was the only sign of it. A kept colour takes the line away.
func test_an_empty_strip_says_so_in_a_muted_line() -> void:
    var picker := SaColorPicker.new()
    var row := picker.palette_row
    assert_true(row.empty_line.visible, "Nothing kept shows the line")
    assert_eq(row.empty_line.get_parent(), row.flow, "in the strip")
    assert_false(row.empty_line.text.is_empty(), "and it says something: %s" % row.empty_line.text)
    assert_eq(row.empty_line.get_theme_color("font_color"), SaTheme.palette.text_muted, "in the muted colour")
    picker.set_swatches([Color.RED])
    assert_false(row.empty_line.visible, "A kept colour takes it away")
    picker.set_swatches([])
    assert_true(row.empty_line.visible, "and an emptied strip says so again")
    picker.free()


## The Default layout ships the Colour Picker as the shape and the pair alone,
## hiding all but the preview and selector, and a fresh profile,
## which reads `DEFAULT_HIDDEN` rather than the layout, hides the same five.
func test_the_default_layout_ships_the_shape_and_the_pair_alone() -> void:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(DEFAULT_LAYOUT), OK, "The Default layout loads")
    var section := SaDockerLayoutPresets.VISIBILITY_SECTION
    for element: String in SHIPPED_OFF:
        assert_false(bool(cfg.get_value(section, "ColorPicker/" + element, true)), "Default ships %s off" % element)
        assert_true(SaSettingsLayout.DEFAULT_HIDDEN["ColorPicker"].has(element), "and a fresh profile hides it")
        assert_true(SaSettingsLayout.DEFAULT_ORDERS["ColorPicker"].has(element), "while it stays a row a painter switches on")
    for element: String in SHIPPED_ON:
        assert_true(bool(cfg.get_value(section, "ColorPicker/" + element, false)), "Default ships %s on" % element)
        assert_false(SaSettingsLayout.DEFAULT_HIDDEN["ColorPicker"].has(element), "and a fresh profile shows it")


## Applied, the layout leaves the picker with the shape and the pair drawn and
## the five rows down. What the profile held before is put back, so the rest of
## the run reads the profile it had.
func test_the_default_layout_applied_shows_the_shape_and_the_pair() -> void:
    var cfg := ConfigFile.new()
    cfg.load(DEFAULT_LAYOUT)
    var section := SaDockerLayoutPresets.VISIBILITY_SECTION
    var was: Dictionary = {}
    for element: String in SHIPPED_OFF + SHIPPED_ON:
        was[element] = SaSettings.get_element_visible("ColorPicker", element)
        SaSettings.set_element_visible("ColorPicker", element, bool(cfg.get_value(section, "ColorPicker/" + element)))

    var picker := SaColorPicker.new()
    picker.apply_layout_settings()
    assert_true(picker.shape.visible, "The shape is drawn")
    assert_true(picker.preview_box.visible, "and so is the pair")
    for hidden: Control in [picker.palette_row, picker.recent_box, picker.hex_row, picker.rgb_sliders, picker.okhsv_sliders]:
        assert_false(hidden.visible, "%s is down" % hidden.name)
    picker.free()

    for element: String in was:
        SaSettings.set_element_visible("ColorPicker", element, was[element])
