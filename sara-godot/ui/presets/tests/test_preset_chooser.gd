## The preset chooser: the grid, the two filters, the icon size and the queue
## that keeps opening it cheap.
##
## The chooser is built bare rather than through the tool options bar wherever a
## test can, because it is one control with two hosts and what it does must not
## depend on which one built it.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const ControlWalker := preload("res://harness/controls/sa_control_walker.gd")

const Fixtures = preload("res://tests/fixtures.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
## The recipes the brush ships, and the rule about which of them a template
## can carry, out of `core/`. Handed to `install_shipped`
## because a test machine holds no registries to ask for the role.
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
## The engine's own settings, which is what a full install of the twenty-one
## recipes needs: the wrapper beside it carries three of them.
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
## The class that writes the whole tooltip of a cell, which is where the licence
## line goes.
const PresetEngineMarks := preload("res://ui/dockers/presets/preset_engine_marks.gd")
## The importer's own spellings of the three metadata keys, held against
## `SaPresetMeta`'s below.
const KppImportScript := preload("res://modules/sara-base-modules/stamp-brush/krita/sa_kpp_import.gd")

## A cell's picture is a rendered stroke through the real paint path.
const REQUIRES_GPU := true

## The line a preset of Sara Basic, the basic bundle, says it came from.
const ESSENTIALS_LINE: String = "From Sara Basic 1.0 by Matěj Zeman, GPL-3.0-or-later"

static var scratch_dir: String = SaDataRoot.path("test_preset_chooser")

var _saved_icon_size: int = 48

## The profile's tag filter as it stood, put back after each test, since a press
## on a tag writes it for every chooser after this one.
var _tag_filter_was: Dictionary = {}


func before_each() -> void:
    _tag_filter_was = SaSettings.preset_tag_filter.duplicate()
    SaSettings.preset_tag_filter = {}
    _saved_icon_size = SaSettings.preset_icon_size
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    SaSettings.preset_tag_filter = _tag_filter_was
    SaSettings.preset_icon_size = _saved_icon_size
    ScratchFolder.clear(scratch_dir)


## A chooser over a store holding the three presets Sara ships.
func _chooser() -> SaBrushPresetsChooser:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    return chooser


## One cell per preset, with the name on it.
func test_the_grid_shows_one_cell_per_preset() -> void:
    var chooser := _chooser()
    assert_eq(chooser.visible_names(), ["Fill", "Paint", "Sketch"] as Array[String], "Three cells, sorted")
    assert_eq(chooser.grid.get_child_count(), 3, "and three children in the grid")
    var first := chooser.grid.get_child(0)
    assert_not_null(first.get_node_or_null("Icon"), "A cell carries the picture")
    assert_eq((first.get_node("Name") as Label).text, "Fill", "with the name under it")
    chooser.free()


## The tag filter is the store's own, so a painter meets one filter and not two.
func test_a_tag_narrows_the_grid() -> void:
    var chooser := _chooser()
    chooser.capture_tag("lines")
    assert_eq(chooser.visible_names(), ["Sketch"] as Array[String], "A tag narrows it to what carries it")
    chooser.capture_tag("paint")
    assert_eq(chooser.visible_names(), ["Fill", "Paint"] as Array[String], "another tag, another grid")
    chooser.capture_tag("")
    assert_eq(chooser.visible_names().size(), 3, "and All brings them back")
    chooser.free()


## The search is over the names and is case-blind, because a painter typing a
## preset's name is not typing its capitals.
func test_typed_text_narrows_the_grid() -> void:
    var chooser := _chooser()
    ControlWalker.move(chooser.search_field, "sk")
    assert_eq(chooser.visible_names(), ["Sketch"] as Array[String], "Two letters are enough")
    ControlWalker.move(chooser.search_field, "PAINT")
    assert_eq(chooser.visible_names(), ["Paint"] as Array[String], "and the capitals do not matter")
    ControlWalker.move(chooser.search_field, "")
    assert_eq(chooser.visible_names().size(), 3, "and clearing it brings them back")
    chooser.free()


## The two filters are one question rather than two lists.
func test_a_tag_and_a_search_narrow_together() -> void:
    var chooser := _chooser()
    chooser.capture_tag("paint")
    ControlWalker.move(chooser.search_field, "fi")
    assert_eq(chooser.visible_names(), ["Fill"] as Array[String], "Tagged paint and matching 'fi'")
    chooser.free()


# --- Where a preset came from and under what licence ---------------------------


## The two files that name the same metadata keys: `SaPresetMeta` declares
## them once for the store, which writes the bundle and the licence, and for the
## sentence it reads them back into, and the importer writes all three from a
## Krita bundle. Written out in the importer rather than read off the skeleton,
## because a `const` whose initializer names a global class breaks the class
## cache, so this is the check that
## keeps the spellings one key. The store and the sentence once spelled the bundle's
## key separately, and now it is declared once for both.
func test_the_provenance_keys_agree_across_the_files_that_name_them() -> void:
    assert_eq(
        String(KppImportScript.BUNDLE_META),
        String(SaPresetMeta.BUNDLE_META),
        "The importer writes the bundle key the store reads"
    )
    assert_eq(String(KppImportScript.LICENCE_META), String(SaPresetMeta.LICENCE_META), "One licence key, whoever wrote it")
    assert_eq(
        String(KppImportScript.SOURCE_META), String(SaPresetMeta.SOURCE_META), "and one key for the file an import came from"
    )


## **Every preset the install writes carries its bundle and its licence.** The
## table names the licence once beside the bundle's own name rather than on each
## of the twenty-one recipes, and those two keys are the whole of the sentence a
## painter reads, so a recipe that lost either would be a cell saying nothing
## about whether the brush may be used.
func test_every_installed_preset_carries_its_bundle_and_licence() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    var written := store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    assert_eq(written, ShippedPresetsScript.entries().size(), "Every recipe in the table was written")
    # Sara Basic and Sara Advanced Paint are two bundles, so each preset is read
    # against the bundle its own recipe names, and a drawn recipe names the
    # pictures' licence of its own, which the bundle's gives way to.
    var bundle_of: Dictionary[String, String] = {}
    var own: Dictionary[String, String] = {}
    for entry: Dictionary in ShippedPresetsScript.entries():
        bundle_of[String(entry["name"])] = String(entry["bundle"])
        own[String(entry["name"])] = String(entry.get("licence", ""))
    for preset_name: String in store.list_names():
        var bundle: String = bundle_of.get(preset_name, "")
        var licence: String = own.get(preset_name, "")
        if licence.is_empty():
            licence = ShippedPresetsScript.licence_for(bundle)
        assert_false(licence.is_empty(), "The table names %s's licence" % bundle)
        assert_eq(
            String(store.meta_for(preset_name, SaPresetMeta.BUNDLE_META, "")), bundle, "%s carries its bundle" % preset_name
        )
        assert_eq(
            String(store.meta_for(preset_name, SaPresetMeta.LICENCE_META, "")),
            licence,
            "%s carries the licence the table names" % preset_name
        )


## The one sentence both hosts show, over the four states a preset's file can be
## in: a shipped one, an import whose bundle stated a licence, an import whose
## bundle stated none, and one a painter saved themselves.
func test_the_provenance_says_what_the_preset_s_file_says() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    assert_eq(store.provenance_for("Sketch"), ESSENTIALS_LINE, "A shipped preset names its bundle, version, author and licence")
    store.save_preset(
        "Bundled",
        BrushSettingsScript.new(),
        PackedStringArray(),
        {SaPresetMeta.BUNDLE_META: "Sara fixtures", SaPresetMeta.LICENCE_META: "CC0 1.0"}
    )
    assert_eq(store.provenance_for("Bundled"), "From Sara fixtures, CC0 1.0", "An import says what its bundle stated")
    store.save_preset("Plain import", BrushSettingsScript.new(), PackedStringArray(), {SaPresetMeta.SOURCE_META: "a-brush.kpp"})
    assert_eq(
        store.provenance_for("Plain import"),
        "Imported from a-brush.kpp",
        "A preset with no bundle falls back to the file it came from"
    )
    store.save_preset("Mine", BrushSettingsScript.new())
    assert_eq(store.provenance_for("Mine"), "", "and one a painter saved themselves says nothing")
    assert_eq(store.provenance_for("Nobody"), "", "as does a preset that is not there")


## The cell's tooltip gains the licence under the engine's, which is where a
## painter who wonders whether they may ship a picture painted with this brush
## reads the answer.
func test_a_cells_tooltip_carries_the_bundle_and_its_licence() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    var chooser := SaBrushPresetsChooser.new()
    var marks := PresetEngineMarks.new(chooser, func() -> SaPresetStore: return store, func() -> StringName: return &"stamp")
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return StampSettingsScript.new())
    # By hand, because the grid announces a cell when it enters the tree and a
    # chooser built in a suite is in none.
    for cell: Node in chooser.grid.get_children():
        marks.mark(cell)
    var cell: Control = null
    for child: Node in chooser.grid.get_children():
        if (child.get_node("Name") as Label).text == "Sketch":
            cell = child
    assert_not_null(cell, "Sketch is in the grid")
    var tip := String(cell.tooltip_text)
    assert_true(tip.contains("\nSketch, "), "The tooltip names the preset and its engine under its description, got '%s'" % tip)
    assert_true(tip.ends_with(ShippedPresetsScript.BASIC_ABOUT), "and ends with the bundle's sentence, got '%s'" % tip)
    assert_true(tip.contains(ESSENTIALS_LINE), "after the bundle and its licence, got '%s'" % tip)
    chooser.free()


## The shipped sentence opens the tooltip, above the engine and the
## provenance, because what a preset is for is what a painter hovering it
## wonders first, and a preset a painter saved themselves has no empty line
## where it would have gone.
func test_a_shipped_cells_tooltip_carries_its_sentence() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    store.save_preset("Mine", StampSettingsScript.new())
    var chooser := SaBrushPresetsChooser.new()
    var marks := PresetEngineMarks.new(chooser, func() -> SaPresetStore: return store, func() -> StringName: return &"stamp")
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return StampSettingsScript.new())
    for cell: Node in chooser.grid.get_children():
        marks.mark(cell)
    var sketch: Control = null
    var mine: Control = null
    for child: Node in chooser.grid.get_children():
        var cell_name := (child.get_node("Name") as Label).text
        if cell_name == "Sketch":
            sketch = child
        elif cell_name == "Mine":
            mine = child
    assert_not_null(sketch, "Sketch is in the grid")
    assert_not_null(mine, "Mine is in the grid")
    var sketch_lines := String(sketch.tooltip_text).split("\n")
    assert_eq(sketch_lines.size(), 4, "Sketch's tooltip is four lines, got %s" % [sketch_lines])
    assert_eq(
        sketch_lines[0],
        "A hard thin line with no smoothing, paler under a light press, for drawing the picture before painting it.",
        "and its first line is the recipe's own sentence"
    )
    assert_true(sketch_lines[1].begins_with("Sketch, "), "with the preset and its engine on the second")
    assert_eq(sketch_lines[2], ESSENTIALS_LINE, "with the provenance on the third")
    assert_eq(sketch_lines[3], ShippedPresetsScript.BASIC_ABOUT, "and the bundle's own sentence on the fourth")
    var mine_lines := String(mine.tooltip_text).split("\n")
    assert_eq(mine_lines.size(), 1, "Mine has no sentence and no provenance, so one line, got %s" % [mine_lines])
    chooser.free()


## The dimmed line under the grid: the same sentence about the preset the brush
## is holding, and no row at all when the file has nothing to say.
func test_the_line_under_the_grid_follows_the_loaded_preset() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(StampSettingsScript.new(), ShippedPresetsScript)
    store.save_preset("Mine", StampSettingsScript.new())
    # In an array because a lambda captures a local by value: the line has to see
    # the name the test moves on to, not the one it was built with.
    var loaded := [""]
    var line := BrushPresetsDocker.ProvenanceLine.new(
        func() -> SaPresetStore: return store, func() -> String: return String(loaded[0])
    )
    line.sync()
    assert_eq(line.text, "", "No preset loaded, nothing said")
    assert_false(line.visible, "and no empty row under the grid")
    loaded[0] = "Sketch"
    line.sync()
    assert_eq(line.text, ESSENTIALS_LINE, "The loaded preset's bundle and licence")
    assert_true(line.visible, "and the row is there to read")
    loaded[0] = "Mine"
    line.sync()
    assert_eq(line.text, "", "A preset with nothing to say empties it")
    assert_false(line.visible, "and the row goes away rather than leaving a gap")
    line.free()


## A click on a cell says which preset, and the host decides what that means.
func test_a_cell_reports_its_preset() -> void:
    var chooser := _chooser()
    var seen: Array[String] = []
    chooser.preset_chosen.connect(func(picked: String) -> void: seen.append(picked))
    ((chooser.grid.get_child(1) as Control).get_node("Icon") as Button).pressed.emit()
    assert_eq(seen, ["Paint"] as Array[String], "The second cell is Paint and it says so")
    chooser.free()


## The size lives in the profile, so the bar's popup and the docker read one
## number and a restart reads it back.
func test_the_icon_size_is_read_from_the_profile() -> void:
    SaSettings.preset_icon_size = 72
    var chooser := _chooser()
    assert_eq(chooser.icon_size(), 72, "The grid draws at the size the profile holds")
    var button := (chooser.grid.get_child(0) as Control).get_node("Icon") as Button
    assert_almost_eq(button.custom_minimum_size.x, float(SaUI.px(72)), 0.5, "and the cell is that wide")
    SaSettings.preset_icon_size = 30
    chooser.refresh()
    assert_eq(chooser.icon_size(), 30, "and it follows the profile down")
    chooser.free()


## The slider's ends are fixed, and a value outside them is brought back
## rather than stored.
func test_the_icon_size_is_clamped_to_the_spec_s_range() -> void:
    SaSettings.preset_icon_size = 500
    assert_eq(SaSettings.preset_icon_size, SaBrushPresetsChooser.MAX_ICON, "Past the top it stops at 128")
    SaSettings.preset_icon_size = 1
    assert_eq(SaSettings.preset_icon_size, SaBrushPresetsChooser.MIN_ICON, "and under the bottom at 30")


## The grid opens without rendering, and a
## cell with no picture yet shows its name rather than nothing.
func test_opening_renders_nothing_and_every_cell_is_still_there() -> void:
    var chooser := _chooser()
    var report := chooser.chooser_report()
    assert_eq(int(report["count"]), 3, "Three cells")
    assert_eq(int(report["drawn"]), 0, "none of them drawn yet")
    assert_eq(int(report["pending"]), 3, "and all three waiting")
    for cell in chooser.grid.get_children():
        assert_eq((cell.get_node("Name") as Label).text.is_empty(), false, "A cell with no picture still carries its name")
    chooser.free()


## And the pictures arrive without the chooser being reopened, a frame's share
## of one at a time. It was a whole picture a frame, and those
## frames were the slow ones after a cold start's Ready.
func test_the_thumbnails_arrive_a_frames_share_at_a_time() -> void:
    var chooser := _chooser()
    chooser._process(0.0)
    var report := chooser.chooser_report()
    assert_true(int(report["drawn"]) <= 1, "One frame finishes one thumbnail at most, %d" % int(report["drawn"]))
    assert_eq(int(report["drawn"]) + int(report["pending"]), 3, "and the others are still to come")
    var frames := 1
    while int(chooser.chooser_report()["pending"]) > 0 and frames < 1000:
        chooser._process(0.0)
        frames += 1
    assert_eq(int(chooser.chooser_report()["drawn"]), 3, "Frame after frame every thumbnail arrives")
    assert_true(frames >= 3, "over a frame a thumbnail at least, %d frames" % frames)
    chooser.free()
    chooser = _chooser()
    chooser._process(0.0)
    chooser.capture_finish()
    assert_eq(int(chooser.chooser_report()["drawn"]), 3, "Draining the queue draws the rest")
    assert_eq(int(chooser.chooser_report()["pending"]), 0, "with nothing left")
    chooser.free()


## A second open reads the PNGs, which is what makes the grid cheap the second
## time as well as the first.
func test_a_second_open_queues_nothing() -> void:
    var chooser := _chooser()
    chooser.capture_finish()
    var store := chooser.store
    var again := SaBrushPresetsChooser.new()
    again.bind_store(store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new())
    var report := again.chooser_report()
    assert_eq(int(report["pending"]), 0, "Nothing to render")
    assert_eq(int(report["drawn"]), 3, "and every cell has its picture already")
    again.free()
    chooser.free()


# --- The mark on the loaded cell ------------------------------------------------


## A chooser over the same three presets, told that the brush is on *loaded*.
func _marked_chooser(loaded: String) -> SaBrushPresetsChooser:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(BrushSettingsScript.new(), ShippedPresetsScript)
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(
        store, StateBrushScript, func() -> Resource: return BrushSettingsScript.new(), func() -> String: return loaded
    )
    return chooser


## The grid once drew three identical cells whatever the brush was
## on, so the name lived only somewhere else on the screen.
func test_the_loaded_cell_is_marked_and_the_others_are_not() -> void:
    var chooser := _marked_chooser("Paint")
    assert_eq(String(chooser.chooser_report()["marked"]), "Paint", "The report names the loaded cell")
    var marked := (chooser.grid.get_child(1) as Control).get_node("Icon") as Button
    var plain := (chooser.grid.get_child(0) as Control).get_node("Icon") as Button
    assert_true(marked.has_theme_stylebox_override("normal"), "and that cell is drawn with a rim of its own")
    assert_false(plain.has_theme_stylebox_override("normal"), "which the cells beside it do not carry")
    var label := (chooser.grid.get_child(1) as Control).get_node("Name") as Label
    assert_true(label.has_theme_color_override("font_color"), "and its name is drawn in the accent")
    chooser.free()


## A rim that a hover or a press paints over is gone exactly while the painter
## is looking at it, so every Button state carries it.
func test_the_mark_survives_a_hover_and_a_press() -> void:
    var chooser := _marked_chooser("Paint")
    var marked := (chooser.grid.get_child(1) as Control).get_node("Icon") as Button
    for state: String in SaBrushPresetsChooser.MARK_STATES:
        assert_true(marked.has_theme_stylebox_override(state), "The mark is drawn in the %s state" % state)
    chooser.free()


## **The rim costs the cell nothing.** `_columns_that_fit` takes the widest
## cell as the grid's pitch, so a marked cell wider than the rest would move
## every other cell wherever the mark landed. The rim's margin stays under the
## icon size the button already declares.
func test_marking_a_cell_moves_no_other_cell() -> void:
    SaSettings.preset_icon_size = 48
    var plain_grid := _marked_chooser("")
    var plain_width := (plain_grid.grid.get_child(1) as Control).get_combined_minimum_size().x
    var marked_grid := _marked_chooser("Paint")
    var marked_width := (marked_grid.grid.get_child(1) as Control).get_combined_minimum_size().x
    assert_almost_eq(marked_width, plain_width, 0.5, "A marked cell is the width an unmarked one is")
    plain_grid.free()
    marked_grid.free()


## The brush on no preset, which is what `new_preset` announces, marks nothing
## rather than marking the first cell.
func test_no_preset_marks_no_cell() -> void:
    var chooser := _marked_chooser("")
    assert_eq(String(chooser.chooser_report()["marked"]), "", "Nothing loaded, nothing marked")
    for index in chooser.grid.get_child_count():
        var button := (chooser.grid.get_child(index) as Control).get_node("Icon") as Button
        assert_false(button.has_theme_stylebox_override("normal"), "and no cell carries a rim")
    chooser.free()


## A filter that hides the loaded preset marks nothing, and clearing it brings
## the mark back, because the mark is a cell on screen and not a name in a var.
func test_a_filter_that_hides_the_loaded_preset_marks_nothing() -> void:
    var chooser := _marked_chooser("Fill")
    assert_eq(String(chooser.chooser_report()["marked"]), "Fill", "Marked while it is showing")
    ControlWalker.move(chooser.search_field, "sk")
    assert_eq(chooser.visible_names(), ["Sketch"] as Array[String], "A search hides it")
    assert_eq(String(chooser.chooser_report()["marked"]), "", "so there is no cell to mark")
    ControlWalker.move(chooser.search_field, "")
    assert_eq(String(chooser.chooser_report()["marked"]), "Fill", "and clearing it brings the mark back")
    chooser.free()


## A chooser nobody told marks nothing rather than failing, which is what the
## three-argument `bind_store` in the rest of this suite gets.
func test_an_unbound_chooser_marks_nothing() -> void:
    var chooser := _chooser()
    assert_eq(String(chooser.chooser_report()["marked"]), "", "No source, no mark")
    chooser.free()


# --- The bar's popup, which is the chooser's first host ------------------------


## **The bar has no popup.** The preset buttons open a separate
## window, not a dropdown menu, so the grid this
## suite is about lives only in the Brush Presets docker and the button opens
## that. What stays here is the half the popup never owned: the list of names
## every other caller reads.
func test_the_bar_holds_the_list_and_opens_the_docker() -> void:
    var host := Node.new()
    EventBus.add_child(host)
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var bar := ToolOptionsBar.new()
    host.add_child(bar)
    bar.target_tool_machine = machine
    bar.preset_store.dir = scratch_dir
    # The bar installs the shipped recipes on its first refresh, and the role
    # they come through is registered by a main scene a test host has none of
    # they come through is registered by a main scene a test host has none of,
    # so the suite hands them over as the app's caller does.
    bar.preset_store.install_shipped(machine.get_tool("brush").settings, ShippedPresetsScript)
    bar._ready()

    assert_false("chooser" in bar.preset_box, "The group holds no grid of its own")
    assert_false("chooser_popup" in bar.preset_box, "and no popup to put one in")
    assert_eq(bar.preset_names().size(), ShippedPresetsScript.entries().size(), "and the list of names is what it was")

    # No docker in a test host, so this is the answer a bar with nothing to open
    # gives rather than a crash. `test_presets_docker.gd` opens a real one.
    assert_false(bar.preset_box.open_presets_docker(), "Opening it says so when there is no docker")

    host.free()
    Fixtures.teardown(surface, machine)
