extends "res://tests/test_framework.gd"

## A swatch carries a name, its chip's tooltip reads it, and a right press
## opens Rename and Remove rather than deleting at once and saying nothing.
## Remove says so in the corner and Undo remove, from the strip's menu or from
## Ctrl+Z while the notice is up, puts the swatch back in its place.
##
## Four halves, each asserted where it lives. The store's two lists and their
## round trip through `colors.cfg` come first, with and without the names key,
## because a profile this build writes has to load in the last one. Then the
## row's tooltip, menu, rename field and `.gpl` names. Then the docker's notice
## and the Ctrl+Z it binds, and last the router asking the docker before the
## history.

const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")

const SKIN := Color8(201, 140, 110)
const SHADOW := Color8(120, 70, 60)
const SKY := Color8(90, 160, 230)

static var scratch_path: String = SaDataRoot.path("test_s44_colors.cfg")

var _gpl: String = ""

## What `SaColors` held before a case that drives the docker, put back after.
var _kept_swatches: Array[Color] = []
var _kept_names: Array[String] = []


## A store that counts its writes rather than making them.
class CountingStore:
    extends SaColorStore

    var saves: int = 0

    func save() -> void:
        saves += 1


func before_each() -> void:
    _gpl = ProjectSettings.globalize_path(SaDataRoot.folder()).path_join("test_s44_palette.gpl")
    _kept_swatches = SaColors.swatches.duplicate()
    _kept_names = SaColors.swatch_names.duplicate()


func after_each() -> void:
    for path: String in [scratch_path, _gpl]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    SaColors.swatches.assign(_kept_swatches)
    SaColors.swatch_names.assign(_kept_names)
    SaColors.last_removed_swatch = null
    SaColors.save()


func _store() -> SaColorStore:
    var store := SaColorStore.new()
    store.path = scratch_path
    return store


# --- The store's two lists ------------------------------------------------------


func test_names_are_kept_in_step_with_the_colours() -> void:
    var store := _store()
    store.add_swatch(SKIN, "Skin")
    store.add_swatch(SKY)
    store.add_swatches([SHADOW, Color.BLACK], ["Skin shadow"])
    assert_eq(store.swatches.size(), 4, "Four colours")
    assert_eq(store.swatch_names, ["Skin", "", "Skin shadow", ""] as Array[String], "and a name for each, empty where none came")
    store.remove_swatch(1)
    assert_eq(store.swatch_names, ["Skin", "Skin shadow", ""] as Array[String], "A removal takes its name with it")
    store.clear_swatches()
    assert_eq(store.swatch_names.size(), 0, "and a clear takes every name")
    store.free()


func test_a_list_assigned_by_hand_is_fitted_before_an_edit() -> void:
    var store := _store()
    store.swatches.assign([SKIN, SKY])
    store.add_swatch(SHADOW, "Skin shadow")
    assert_eq(store.swatch_names, ["", "", "Skin shadow"] as Array[String], "The two colours with no names read as unnamed")
    store.free()


func test_a_rename_trims_and_the_same_name_writes_nothing() -> void:
    var store := CountingStore.new()
    store.add_swatch(SKIN)
    store.rename_swatch(0, "  Skin shadow ")
    assert_eq(store.swatch_names[0], "Skin shadow", "The name is trimmed")
    var saves := store.saves
    store.rename_swatch(0, "Skin shadow")
    assert_eq(store.saves, saves, "The same name again is not a change")
    store.rename_swatch(5, "Nowhere")
    assert_eq(store.swatch_names, ["Skin shadow"] as Array[String], "An index past the end is ignored")
    store.rename_swatch(0, "")
    assert_eq(store.swatch_names[0], "", "and an empty name unnames the swatch")
    store.free()


func test_remove_remembers_and_undo_remove_puts_it_back_in_its_place() -> void:
    var store := _store()
    store.add_swatches([SKIN, SHADOW, SKY], ["Skin", "Skin shadow", "Sky"])
    assert_false(store.undo_remove(), "Nothing removed, nothing to undo")
    store.remove_swatch(1)
    assert_not_null(store.last_removed_swatch, "The removed swatch is remembered")
    if store.last_removed_swatch != null:
        assert_eq(store.last_removed_swatch.index, 1, "with its place")
        assert_eq(store.last_removed_swatch.name, "Skin shadow", "its name")
        assert_true(store.last_removed_swatch.color.is_equal_approx(SHADOW), "and its colour")
    assert_true(store.undo_remove(), "Undo remove answers that it did")
    assert_eq(store.swatches, [SKIN, SHADOW, SKY] as Array[Color], "The colour is back between the two")
    assert_eq(store.swatch_names, ["Skin", "Skin shadow", "Sky"] as Array[String], "with its name")
    assert_null(store.last_removed_swatch, "and nothing is left to undo")
    assert_false(store.undo_remove(), "so a second undo does nothing")
    store.free()


func test_the_next_edit_forgets_the_removed_swatch() -> void:
    var edits: Array[Callable] = [
        func(store: SaColorStore) -> void: store.add_swatch(Color.WHITE),
        func(store: SaColorStore) -> void: store.add_swatches([Color.WHITE]),
        func(store: SaColorStore) -> void: store.rename_swatch(0, "Renamed"),
        func(store: SaColorStore) -> void: store.clear_swatches(),
    ]
    for edit: Callable in edits:
        var store := _store()
        store.add_swatches([SKIN, SKY])
        store.remove_swatch(1)
        edit.call(store)
        assert_null(store.last_removed_swatch, "An edit after the removal ends its undo")
        store.free()


# --- The round trip through colors.cfg -------------------------------------------


func test_names_survive_a_reload() -> void:
    var store := _store()
    store.add_swatches([SKIN, SHADOW], ["Skin", "Skin shadow"])
    store.free()
    var again := _store()
    again.load_from(scratch_path)
    assert_eq(again.swatches, [SKIN, SHADOW] as Array[Color], "The colours came back")
    assert_eq(again.swatch_names, ["Skin", "Skin shadow"] as Array[String], "and their names")
    again.free()


func test_a_file_from_the_last_build_loads_with_every_swatch_unnamed() -> void:
    var config := ConfigFile.new()
    config.set_value("pair", "foreground", Color.BLACK)
    config.set_value("pair", "background", Color.WHITE)
    config.set_value("lists", "swatches", [SKIN, SKY] as Array[Color])
    config.set_value("lists", "recent", [] as Array[Color])
    config.save(scratch_path)
    var store := _store()
    store.load_from(scratch_path)
    assert_eq(store.swatches, [SKIN, SKY] as Array[Color], "The colours load")
    assert_eq(store.swatch_names, ["", ""] as Array[String], "and a missing names key reads as no names")
    store.free()


## The last build reads `lists/swatches` into an `Array[Color]` and asks for no
## other key, so this is its loader's line run on what this build writes.
func test_a_file_this_build_writes_still_loads_the_way_the_last_build_reads() -> void:
    var store := _store()
    store.add_swatches([SKIN, SKY], ["Skin", "Sky"])
    store.free()
    var config := ConfigFile.new()
    assert_eq(config.load(scratch_path), OK, "The file opens")
    assert_true(config.has_section_key("lists", "swatch_names"), "It carries the names under a key of their own")
    var last_build: Array[Color] = []
    last_build.assign(SaTyped.list(config.get_value("lists", "swatches", [])))
    assert_eq(last_build, [SKIN, SKY] as Array[Color], "and the colours under the key the last build reads, as colours")


func test_a_names_list_of_the_wrong_length_is_fitted_on_load() -> void:
    var config := ConfigFile.new()
    config.set_value("lists", "swatches", [SKIN, SKY, SHADOW] as Array[Color])
    config.set_value("lists", "swatch_names", ["Skin"])
    config.save(scratch_path)
    var store := _store()
    store.load_from(scratch_path)
    assert_eq(store.swatch_names, ["Skin", "", ""] as Array[String], "A short list is padded")
    config.set_value("lists", "swatch_names", ["a", "b", "c", "d"])
    config.save(scratch_path)
    store.load_from(scratch_path)
    assert_eq(store.swatch_names, ["a", "b", "c"] as Array[String], "and a long one cut")
    store.free()


# --- The row: tooltip, menu, rename ---------------------------------------------


func test_a_chip_reads_its_name_before_its_hex() -> void:
    var picker: SaColorPicker = SaColorPickerScript.new()
    picker.set_swatches([SKIN, SKY], ["Skin shadow"])
    var chips := picker.palette_row.chips
    assert_eq(chips[0].tooltip_text, "Skin shadow, #" + SKIN.to_html(false), "A named chip says its name, then its hex")
    assert_eq(chips[1].tooltip_text, "#" + SKY.to_html(false), "and an unnamed one its hex alone")
    picker.free()


func test_a_chip_s_menu_offers_rename_and_remove_and_undo_once_there_is_one() -> void:
    var row := SaPaletteRow.new()
    row.set_swatches([SKIN, SKY])
    assert_true(row.fill_menu(0), "A chip has a menu")
    assert_eq(row.menu.row_labels(), ["Rename", "Remove"] as Array[String], "of Rename and Remove")
    assert_false(row.fill_menu(-1), "The strip with nothing to undo has none")
    row.set_swatches([SKIN], [], true)
    assert_true(row.fill_menu(0), "With a removal to undo")
    assert_eq(row.menu.row_labels(), ["Rename", "Remove", "Undo remove"] as Array[String], "the chip's menu offers it")
    assert_true(row.fill_menu(-1), "and so does the strip")
    assert_eq(row.menu.row_labels(), ["Undo remove"] as Array[String], "alone, since no chip is under the press")
    row.free()


func test_the_menu_s_rows_send_what_they_say() -> void:
    var row := SaPaletteRow.new()
    row.set_swatches([SKIN, SKY], [], true)
    var removed: Array = []
    var undone: Array = []
    row.chip_remove_requested.connect(func(index: int) -> void: removed.append(index))
    row.undo_remove_requested.connect(func() -> void: undone.append(true))
    row.fill_menu(1)
    row.choose(SaPaletteRow.MENU_REMOVE)
    assert_eq(removed, [1], "Remove asks for the chip's index")
    row.fill_menu(-1)
    row.choose(SaPaletteRow.MENU_UNDO_REMOVE)
    assert_eq(undone.size(), 1, "and Undo remove asks once")
    row.free()


func test_rename_swaps_a_field_over_the_strip_and_enter_applies_once() -> void:
    var row := SaPaletteRow.new()
    row.set_swatches([SKIN, SKY], ["", "Sky"])
    var asked: Array = []
    row.chip_rename_requested.connect(func(index: int, called: String) -> void: asked.append([index, called]))
    row.fill_menu(1)
    row.choose(SaPaletteRow.MENU_RENAME)
    assert_eq(row.renaming, 1, "The field is up for the chip")
    assert_true(row.rename_edit.visible and not row.flow.visible, "over the strip, in its place")
    assert_eq(row.rename_edit.text, "Sky", "holding the name it had")
    row.rename_edit.text = "Skin shadow"
    row.rename_edit.text_submitted.emit(row.rename_edit.text)
    row.rename_edit.focus_exited.emit()
    assert_eq(asked, [[1, "Skin shadow"]], "Enter and the focus it lets go of are one rename")
    assert_true(row.flow.visible and not row.rename_edit.visible, "and the strip is back")
    row.free()


func test_escape_cancels_a_rename_and_a_click_away_applies_it() -> void:
    var row := SaPaletteRow.new()
    row.set_swatches([SKIN])
    var asked: Array = []
    row.chip_rename_requested.connect(func(index: int, called: String) -> void: asked.append([index, called]))
    row.begin_rename(0)
    row.rename_edit.text = "Thrown away"
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    row.rename_edit.gui_input.emit(escape)
    row.rename_edit.focus_exited.emit()
    assert_eq(asked, [], "Escape writes no name")
    assert_eq(row.renaming, -1, "and takes the field down")
    row.begin_rename(0)
    row.rename_edit.text = "Kept"
    row.rename_edit.focus_exited.emit()
    assert_eq(asked, [[0, "Kept"]], "Leaving the field applies it, as the layer rename does")
    row.free()


func test_the_picker_passes_the_row_s_choices_on() -> void:
    var picker: SaColorPicker = SaColorPickerScript.new()
    picker.set_swatches([SKIN], ["Skin"], true)
    var renamed: Array = []
    var undone: Array = []
    picker.swatch_rename_requested.connect(func(index: int, called: String) -> void: renamed.append([index, called]))
    picker.swatch_undo_remove_requested.connect(func() -> void: undone.append(true))
    picker.palette_row.begin_rename(0)
    picker.palette_row.rename_edit.text = "Skin shadow"
    picker.palette_row.commit_rename()
    picker.palette_row.fill_menu(-1)
    picker.palette_row.choose(SaPaletteRow.MENU_UNDO_REMOVE)
    assert_eq(renamed, [[0, "Skin shadow"]], "The rename reaches the picker's signal")
    assert_eq(undone.size(), 1, "and so does Undo remove")
    picker.free()


# --- Names in a GIMP palette ------------------------------------------------------


func test_a_palette_s_names_are_loaded_and_saved_back() -> void:
    var written := (
        SaPaletteFile
        . new(
            "Named",
            SaPaletteFile.DEFAULT_COLUMNS,
            (
                [
                    SaPaletteFile.Swatch.new(SKIN, "Skin"),
                    SaPaletteFile.Swatch.new(SHADOW, SaPaletteFile.UNNAMED_COLOUR),
                    SaPaletteFile.Swatch.new(SKY, "#" + SKY.to_html(false)),
                ]
                as Array[SaPaletteFile.Swatch]
            )
        )
    )
    assert_true(written.write_file(_gpl), "The fixture writes")
    var picker: SaColorPicker = SaColorPickerScript.new()
    var store := CountingStore.new()
    picker.swatches_add_requested.connect(store.add_swatches)
    picker.palette_row.load_palette_path(_gpl)
    assert_eq(store.swatch_names, ["Skin", "", ""] as Array[String], "A name loads, and Untitled and a bare hex read as none")

    picker.set_swatches(store.swatches, ["Skin", "Skin shadow", ""])
    picker.palette_row.save_palette_path(_gpl)
    var back := SaPaletteFile.read_file(_gpl)
    assert_not_null(back, "The saved palette reads back")
    if back != null:
        var names: Array[String] = []
        for swatch in back.swatches:
            names.append(swatch.name)
        var wanted: Array[String] = ["Skin", "Skin shadow", SaPaletteFile.UNNAMED_COLOUR]
        assert_eq(names, wanted, "with the real names, Untitled for none")
    store.free()
    picker.free()


# --- The docker's notice and the Ctrl+Z it binds ---------------------------------


func _undo_key() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_Z
    event.physical_keycode = KEY_Z
    event.ctrl_pressed = true
    event.pressed = true
    return event


func _with_notice() -> Node:
    var host := Node.new()
    host.name = "S44NoticeHost"
    EventBus.add_child(host)
    SaMessage.install(host)
    return host


func test_remove_shows_the_notice_and_ctrl_z_under_it_puts_the_swatch_back() -> void:
    var host := _with_notice()
    SaColors.swatches.assign([SKIN, SHADOW, SKY])
    SaColors.swatch_names.assign(["Skin", "Skin shadow", "Sky"])
    ColorDocker.remove_swatch(1)
    var notice := SaMessage.notice_widget()
    var chords := SaShortcutStore.chords_for(&"edit_undo")
    assert_true(notice != null and notice.showing(), "Remove puts a line up")
    if notice != null and not chords.is_empty():
        assert_eq(notice.label.text, "Swatch removed. %s puts it back." % chords[0], "saying it went and how to have it back")

    var history: Array = []
    var otherwise := func(_event: InputEvent) -> StringName:
        history.append(true)
        return &"edit_undo"
    var answered := ColorDocker.answer_undo(_undo_key(), otherwise)
    assert_eq(answered, ColorDocker.UNDO_REMOVE_ACTION, "Ctrl+Z under the line is the swatch's")
    assert_eq(history, [], "and the picture's history is not stepped")
    assert_eq(SaColors.swatches, [SKIN, SHADOW, SKY] as Array[Color], "The swatch is back in its place")
    assert_eq(SaColors.swatch_names[1], "Skin shadow", "with its name")

    assert_eq(ColorDocker.answer_undo(_undo_key(), otherwise), &"edit_undo", "The next Ctrl+Z is the history's again")
    assert_eq(history.size(), 1, "which hears it")
    host.free()


func test_ctrl_z_after_the_notice_has_gone_is_the_history_s() -> void:
    var host := _with_notice()
    SaColors.swatches.assign([SKIN, SKY])
    SaColors.swatch_names.assign(["", ""])
    ColorDocker.remove_swatch(0)
    SaMessage.notice("A later line over it")
    var history: Array = []
    var otherwise := func(_event: InputEvent) -> StringName:
        history.append(true)
        return &"edit_undo"
    ColorDocker.answer_undo(_undo_key(), otherwise)
    assert_eq(history.size(), 1, "A later line ends the binding, so the history hears Ctrl+Z")
    assert_eq(SaColors.swatches, [SKY] as Array[Color], "and the swatch stays removed")
    assert_true(ColorDocker.undo_remove(), "The strip's Undo remove still has it")
    assert_eq(SaColors.swatches, [SKIN, SKY] as Array[Color], "and puts it back first")
    host.free()


## The router asks the docker before the history, which is the one line this
## unit adds to `shortcut_router.gd`. A document with one step stands behind it,
## so a Ctrl+Z that reached the history would move its index.
func test_the_router_gives_ctrl_z_to_the_swatch_while_the_notice_is_up() -> void:
    var host := _with_notice()
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var undo_redo := easel.document.undo_redo
    undo_redo.create_action("Paint")
    undo_redo.add_do_method(func() -> void: pass)
    undo_redo.add_undo_method(func() -> void: pass)
    undo_redo.commit_action()
    var canvas := SaCanvas.new()
    canvas.easel = easel
    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return canvas
    router.tool_machine_provider = func() -> ToolMachine: return null

    SaColors.swatches.assign([SKIN, SKY])
    SaColors.swatch_names.assign(["Skin", ""])
    ColorDocker.remove_swatch(0)
    assert_true(router.handle(_undo_key()), "The router takes Ctrl+Z")
    assert_eq(SaColors.swatches, [SKIN, SKY] as Array[Color], "and the swatch is back")
    assert_eq(undo_redo.get_current_action(), 0, "while the stroke stays")
    router.handle(_undo_key())
    assert_eq(undo_redo.get_current_action(), -1, "and the next Ctrl+Z undoes the stroke")

    router.free()
    canvas.free()
    easel.free()
    host.free()
