## Every name Sara cuts ends in an ellipsis, however few
## characters it keeps.
##
## Godot's plain `OVERRUN_TRIM_ELLIPSIS` ends a cut text in "…"
## only while the text it keeps is six characters or more, so "Group 3" was cut
## to "Group" with nothing to say a character was gone, and the Layers
## row is mended. Thirteen other labels and buttons asked for the plain kind. The
## preset button read `Soft Er` with no
## ellipsis, and was answered once with a suite that pinned the setting, which is not
## the result.
##
## Each of the thirteen is drawn here at a sweep of widths, from the whole text
## down to the mark's own, by `TextCutProbe`, and none is ever cut plainly. The
## pattern chooser's cell, the thirteenth, is drawn by the stamp brush module's
## own suite, because the chooser lives there. The suite that pins the preset
## button pins `SaTheme.TEXT_CUT` and this picture instead of the setting.
##
## `scenarios/every-name-sara-cuts-ends-in-an-ellipsis-however-few-characters-it-keeps.json`
## photographs the Brush Presets chooser and the Tool Options preset button in
## the running app.
##
## The filter window's heading, which was once held by its setting alone, is drawn
## here too. The label it named is freed when the page is
## realized, and what the window shows is the title in its drag bar, so that is
## the label the sweep draws and that is the one that asks for the cut.
## `scenarios/the-filter-windows-heading-cuts-with-the-mark-like-the-other-twelve.json`
## photographs it with a name longer than the window.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
## Every label here is drawn into a viewport.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Probe = preload("res://tests/fixtures/text_cut_probe.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## A name a painter might give a preset, long enough that every width the sweep
## draws it at cuts it.
const NAME := "Soft Eraser With A Long Name"

## A filter's title, likewise.
const TITLE := "Hue and Saturation"

## A path that is not there, so its recent card reads "missing", a word of
## seven characters, and its folder and name are long.
const MISSING_PATH := "/home/painter/pictures/A painting with a rather long name.sad"

## How many widths a text has to have been cut at, for the sweep to mean the
## range and not one lucky width.
const ENOUGH := 8

static var scratch_dir: String = SaDataRoot.path("test_d35_cut_names")

var _probe: Probe = null
var _saved_recent: Array = []


class Knob:
    extends SaFilter

    func title() -> String:
        return TITLE

    func build(ui: SaDialog) -> void:
        ui.title(TITLE)
        ui.apply_cancel()

    func parameters() -> Dictionary:
        return {}

    func set_parameters(_values: Dictionary) -> void:
        pass

    func run(_ctx: SaFilterContext) -> void:
        pass


func before_each() -> void:
    _probe = Probe.new(EventBus)
    _saved_recent = SaSettings.recent_files()
    for path: String in _saved_recent:
        SaSettings.remove_recent_file(str(path))
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    _probe.release()
    _probe = null
    SaSettings.remove_recent_file(MISSING_PATH)
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))
    ScratchFolder.clear(scratch_dir)


## Draws *subject* from *widest* down and holds that a cut is never a plain cut.
## *enough* is how many widths it has to have been cut at, and *room* the narrowest
## it is drawn.
func _assert_marked(subject: Control, widest: int, what: String, enough: int = ENOUGH, room: int = Probe.ROOM) -> void:
    var result := _probe.sweep(subject, widest, room)
    var cut: int = result["cut"]
    var unmarked: Array = result["unmarked"]
    assert_true(cut >= enough, "%s: the sweep met the text cut at %d widths, which is enough to mean the range" % [what, cut])
    assert_true(unmarked.is_empty(), "%s: ends in a mark at every one of them, and did not at %s" % [what, str(unmarked)])


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


## The probe has to see the fault it is here for, on a label and on a button,
## or every test below it measures nothing.
func test_the_probe_sees_a_plain_cut_on_a_label_and_a_button() -> void:
    var label := Label.new()
    label.text = "Group 3"
    label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    var plain: Dictionary = _probe.sweep(label, 120)
    assert_true(int(plain["cut"]) >= ENOUGH, "The label was cut at %d widths" % int(plain["cut"]))
    assert_false((plain["unmarked"] as Array).is_empty(), "and the plain kind left some of them with no mark")

    var button := Button.new()
    button.text = "Soft Er"
    button.clip_text = true
    button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    var plain_button: Dictionary = _probe.sweep(button, 120)
    assert_false((plain_button["unmarked"] as Array).is_empty(), "and so did the button, which is the preset button's case")

    var forced := Label.new()
    forced.text = "Group 3"
    forced.text_overrun_behavior = SaTheme.TEXT_CUT
    var marked: Dictionary = _probe.sweep(forced, 120)
    assert_true(int(marked["cut"]) >= ENOUGH, "The shared cut is cut at %d widths" % int(marked["cut"]))
    assert_true((marked["unmarked"] as Array).is_empty(), "and none of them is without a mark: %s" % str(marked["unmarked"]))


func test_the_shared_cut_is_the_kind_that_always_marks() -> void:
    assert_eq(SaTheme.TEXT_CUT, TextServer.OVERRUN_TRIM_ELLIPSIS_FORCE, "One constant says which cut Sara asks for")


func test_the_brush_editors_preset_name_ends_in_a_mark() -> void:
    var strip := HBoxContainer.new()
    var bar := SaBrushEditorPresetBar.new()
    bar.build_name_controls(strip)
    bar.preset_label.text = NAME
    assert_eq(bar.preset_label.text_overrun_behavior, SaTheme.TEXT_CUT, "The label asks for the shared cut")
    _assert_marked(bar.preset_label, 240, "The editor's preset name")
    strip.free()
    bar.free()


func test_a_palette_slot_ends_in_a_mark() -> void:
    var ring := PaletteSlotRing.new(Callable())
    var cell := ring.cells[0]
    cell.text = NAME
    assert_eq(cell.text_overrun_behavior, SaTheme.TEXT_CUT, "The cell asks for the shared cut")
    _assert_marked(cell, 240, "A palette slot's name")
    ring.free()


func test_a_presets_chooser_name_ends_in_a_mark() -> void:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.save_preset(NAME, StampSettingsScript.new())
    var chooser := SaBrushPresetsChooser.new()
    chooser.bind_store(store, StateBrushScript, func() -> Resource: return StampSettingsScript.new())
    var label := chooser.grid.get_child(0).get_node("Name") as Label
    assert_eq(label.text, NAME, "The cell carries the preset's name")
    assert_eq(label.max_lines_visible, SaBrushPresetsChooser.NAME_LINES, "wrapped to the lines the chooser makes room for")
    _assert_marked(label, 160, "The chooser's name, on the last line it keeps")
    chooser.free()


## The button's label is the word Presets whatever is
## loaded, so that is the text the sweep cuts. The preset's name is in the
## tooltip, which is never cut.
func test_the_preset_button_ends_in_a_mark() -> void:
    var presets := ToolOptionsPresets.new()
    presets.selected_preset = NAME
    presets.sync_menu()
    assert_eq(presets.preset_menu.text, ToolOptionsPresets.PRESET_LABEL, "The button carries its own label")
    assert_true(presets.preset_menu.tooltip_text.contains(NAME), "and the name whole in its tooltip")
    _assert_marked(presets.preset_menu, 240, "The preset button")
    presets.free()


func test_a_dropdown_button_ends_in_a_mark() -> void:
    var button := SaChoiceButton.new()
    button.text = NAME
    assert_eq(button.text_overrun_behavior, SaTheme.TEXT_CUT, "The dropdown asks for the shared cut")
    _assert_marked(button, 240, "A dropdown's label")
    button.free()


func test_a_factor_sliders_label_ends_in_a_mark() -> void:
    var slider := FactorSlider.new()
    var label: Label = slider._label
    label.text = "Opacity 100 percent of the whole"
    assert_eq(label.text_overrun_behavior, SaTheme.TEXT_CUT, "The slider's label asks for the shared cut")
    _assert_marked(label, 240, "The slider's label")
    slider.free()


func test_the_tablet_pages_readout_ends_in_a_mark() -> void:
    var label := Label.new()
    var readout := SaTabletCalibration.Readout.new(label)
    readout.show_values([0.5, 0.9, 12, 40])
    assert_eq(label.text_overrun_behavior, SaTheme.TEXT_CUT, "The readout asks for the shared cut")
    _assert_marked(label, 240, "The tablet readout, in the shortest form it has")
    label.free()


func test_a_recovery_rows_detail_ends_in_a_mark() -> void:
    var row := WelcomeRecoveryRow.new()
    row.refresh([{"copy": "/home/painter/recovery/A painting with a rather long name.sad", "original": MISSING_PATH}])
    var detail := row.find_child("Detail", true, false) as Label
    assert_not_null(detail, "The row carries its detail line")
    if detail != null:
        _assert_marked(detail, 240, "The recovery row's detail")
    row.free()


func test_a_recent_cards_lines_end_in_a_mark() -> void:
    SaSettings.add_recent_file(MISSING_PATH)
    var grid := WelcomeRecentGrid.new()
    assert_eq(grid.cards.size(), 1, "The grid draws the one card")
    var box := grid.cards[0].get_parent().get_node_or_null("Padding/Column")
    assert_not_null(box, "and its column of words")
    if box != null:
        # "missing" is seven characters, the shape of the fault.
        _assert_marked(box.get_node("Date") as Label, 68, "The card's date line, which says missing", 4, 20)
        _assert_marked(box.get_node("FileName") as Label, 200, "The card's file name")
        _assert_marked(box.get_node("Folder") as Label, 200, "The card's folder")
    grid.free()


func test_a_filters_heading_ends_in_a_mark() -> void:
    var easel := _easel()
    var document := easel.document
    var registry := SaFilterRegistry.new()
    var knob := Knob.new()
    registry.register(knob, &"d35_suite")
    var key := SaFilterRegistry.key_for(&"d35_suite", knob)
    var record := SaFilterOps.new(document).attach(document.active_layer, key, {})
    var panel := SaFilterPanel.new(record, knob, document)
    var heading := panel.get_node("Heading") as Label
    assert_eq(heading.text, TITLE, "The panel names the filter")
    _assert_marked(heading, 200, "The filter panel's heading")

    # The window's heading is the drag bar's title, since a page realized over a
    # found filter frees every label put in its rows, and it is the one label
    # every dialog's bar carries. It is drawn the way the panel's is, from the
    # whole text down to the mark's own width.
    var window := SaFilterEditWindow.new()
    window.watch(registry)
    window.open(record, document)
    assert_null(window.find_child("Heading", true, false), "A found filter's window draws no heading of its own")
    var bar := window.drag_handle.find_child("TitleLabel", true, false) as Label
    assert_not_null(bar, "the drag bar holds the heading")
    if bar != null:
        assert_eq(bar.text, "%s on %s" % [TITLE, document.active_layer.name], "which names the filter and its layer")
        assert_eq(bar.text_overrun_behavior, SaTheme.TEXT_CUT, "and asks for the shared cut")
        _assert_marked(bar, 240, "The filter window's heading")

    # What a filter nothing provides leaves is a sentence that wraps, so no
    # width cuts it, and what it can be held to is the cut it asks for.
    var gone := SaFilterOps.new(document).attach(document.active_layer, &"nobody.gone")
    window.open(gone, document)
    var sentence := window.find_child("Heading", true, false) as Label
    assert_not_null(sentence, "A filter nothing provides leaves the window its heading")
    if sentence != null:
        assert_eq(sentence.text_overrun_behavior, SaTheme.TEXT_CUT, "and it asks for the shared cut")
        assert_true(sentence.autowrap_mode != TextServer.AUTOWRAP_OFF, "though it wraps, so no width cuts it")
    window.free()
    panel.free()
    easel.free()
