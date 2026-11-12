## Every one of the eight pickers Sara opens asks the platform for its own and
## builds no `FileDialog`, and what the painter chooses reaches the caller.
##
## A `FileDialog` set to the filesystem asks each mapped network drive for its
## label on the main thread before the picker's thread starts, which freezes
## File › Open for as long as the drives take. The eight callers open
## `SaFilePicker`, which asks the display server directly. Each
## case here presses the painter's own button where one can be reached, with a
## stand-in for the platform that records the picker and puts no window up, and
## holds that no `FileDialog` stands under the caller, that the picker is the one
## the caller asks for, and that a choice and a cancel reach the caller as
## the dialog's did. What a caller does with a path it was told, reading a preset bundle
## into the store or a document into the canvas, is its own suites' business, so
## those cases hold that the picker tells the method the old dialog was wired to.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The export dialog reads its canvas back, and the reference board uploads its
## pictures.
const REQUIRES_GPU := true

const ExportDialogScript = preload("res://ui/dialogs/document/export_dialog.gd")
const REFERENCE_IMAGE := "res://ui/icon.png"

## Where a `FileDialog.new()` could be written, and the one file allowed to,
## the interface's, since the picker's fallback lives outside core.
const SOURCE_ROOTS: Array[String] = ["res://core", "res://ui", "res://harness", "res://render", "res://tools", "res://modules"]
const THE_ONE_BUILDER := "res://ui/pickers/sa_pickers.gd"
const SKIP_DIRS: Array[String] = [".godot", ".conda", ".git", "tests", "scratch", "build"]

var _platform_before: SaFilePicker.Platform = null
var _stand_in: StandIn = null

## The skeleton's formats with the image formats module's after them, as the
## running app registers them, built again before each test.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    _platform_before = SaFilePicker.platform
    _stand_in = StandIn.new()
    SaFilePicker.platform = _stand_in


func after_each() -> void:
    var cancelled := 0
    while SaFilePicker.newest() != null and cancelled < 100:
        SaFilePicker.newest().cancel()
        cancelled += 1
    assert_null(SaFilePicker.newest(), "A cancelled picker goes away")
    SaFilePicker.platform = _platform_before


## The one picker the stand-in was asked for, held against what a caller asked.
func _the_one_picker(host: Node, mode: SaFilePicker.Mode, what: String) -> SaFilePicker:
    assert_eq(_stand_in.shown.size(), 1, "%s asks the platform for one picker" % what)
    var picker: SaFilePicker = _stand_in.shown[0] if not _stand_in.shown.is_empty() else null
    if picker == null:
        return null
    assert_eq(picker.mode, mode, "%s asks for the mode its dialog had" % what)
    assert_null(picker.fallback, "%s builds no FileDialog while the platform has a picker" % what)
    assert_true(host.find_children("*", "FileDialog", true, false).is_empty(), "and none stands under %s" % what)
    assert_true(SaFilePicker.is_up_under(host), "and the picker counts as up under %s" % what)
    return picker


## The picker tells *method* on *target*, which is what the old dialog's
## `file_selected` was connected to.
func _tells(picker: SaFilePicker, target: Object, method: StringName, what: String) -> void:
    if picker == null:
        return
    assert_eq(picker._on_chosen.get_object(), target, "%s tells its own caller" % what)
    assert_eq(picker._on_chosen.get_method(), method, "%s tells the method its dialog was wired to" % what)


func _press(host: Node, button_name: String) -> void:
    var button := host.find_child(button_name, true, false) as BaseButton
    assert_not_null(button, "the button %s is there to press" % button_name)
    if button != null:
        button.pressed.emit()


func test_no_file_outside_the_picker_builds_a_file_dialog() -> void:
    var builders: Array[String] = []
    for root in SOURCE_ROOTS:
        _collect_builders(root, builders)
    assert_eq(builders, [THE_ONE_BUILDER], "only the picker builds a FileDialog, for a platform with no picker of its own")


func test_file_open_import_and_save_as_ask_the_platform() -> void:
    var files := SaDocumentFiles.new()
    files.open_with_dialog()
    var opened := _the_one_picker(files, SaFilePicker.Mode.OPEN_FILE, "File › Open")
    _tells(opened, files, &"_open_chosen", "File › Open")
    if opened != null:
        assert_eq(opened.filters.size(), 3, "File › Open offers Sara, OpenRaster and the images, as before")
        assert_eq(opened.filters[0], "*.sad ; Sara Document", "a document first")
        opened.cancel()
        assert_false(SaFilePicker.is_up_under(files), "a cancel puts it away and asks nothing")

    _stand_in.shown.clear()
    files.import_with_dialog()
    var imported := _the_one_picker(files, SaFilePicker.Mode.OPEN_FILE, "File › Import")
    _tells(imported, files, &"import_path", "File › Import")

    _stand_in.shown.clear()
    files.save_as(Callable())
    var saved := _the_one_picker(files, SaFilePicker.Mode.SAVE_FILE, "File › Save As")
    _tells(saved, files, &"choose_save_name", "File › Save As")
    if saved != null:
        assert_eq(saved.filters, PackedStringArray(["*.sad ; Sara Document"]), "Save As writes a document")
    files.free()


func test_file_export_asks_the_platform_and_writes_what_was_chosen() -> void:
    var canvas := _painted_canvas()
    var dialog := ExportDialogScript.new(canvas, &"png")
    var exported: Array = []
    dialog.exported.connect(func(written: String, error: Error) -> void: exported.append([written, error]))
    dialog.default_button.pressed.emit()
    var picker := _the_one_picker(dialog, SaFilePicker.Mode.SAVE_FILE, "File › Export")
    var path := ProjectSettings.globalize_path(SaDataRoot.path("test_d26_exported"))
    if picker != null:
        assert_eq(picker.filters, PackedStringArray(["*.png ; PNG Image"]), "for the format the dialog is on")
        picker.answer(true, PackedStringArray([path]), 0)
    # A PNG is written over frames, so the suite drives it to its end.
    SaExportInTurns.finish_all()
    assert_eq(exported, [[path + ".png", OK]], "the name typed without an extension is written as a PNG")
    assert_true(FileAccess.file_exists(path + ".png"), "and the file is there")
    DirAccess.remove_absolute(path + ".png")

    dialog.default_button.pressed.emit()
    SaFilePicker.newest().cancel()
    assert_eq(exported.size(), 1, "a cancel writes nothing")
    dialog.free()
    canvas.free()


func test_the_reference_dockers_open_asks_the_platform_and_places_the_pictures() -> void:
    var docker := ReferenceDocker.new()
    docker.board_view.size = Vector2(400, 300)
    _press(docker, "OpenButton")
    var picker := _the_one_picker(docker, SaFilePicker.Mode.OPEN_FILES, "the Reference docker's Open")
    if picker != null:
        picker.answer(true, PackedStringArray([REFERENCE_IMAGE, REFERENCE_IMAGE]), 0)
    assert_eq(docker.board().pictures.size(), 2, "both pictures chosen are placed on the board")

    _press(docker, "OpenButton")
    SaFilePicker.newest().cancel()
    assert_eq(docker.board().pictures.size(), 2, "and a cancel places nothing")
    assert_false(SaFilePicker.is_up_under(docker), "and leaves no picker holding the docker")
    docker.free()


func test_the_palette_rows_load_and_save_ask_the_platform() -> void:
    var row := SaPaletteRow.new()
    row.load_palette_button.pressed.emit()
    var loaded := _the_one_picker(row, SaFilePicker.Mode.OPEN_FILE, "the palette's Load")
    _tells(loaded, row, &"load_palette_path", "the palette's Load")
    if loaded != null:
        assert_eq(loaded.filters, PackedStringArray(["*.gpl ; GIMP palette"]), "a GIMP palette")
        loaded.cancel()

    _stand_in.shown.clear()
    row.save_palette_button.pressed.emit()
    var saved := _the_one_picker(row, SaFilePicker.Mode.SAVE_FILE, "the palette's Save")
    var path := ProjectSettings.globalize_path(SaDataRoot.path("test_d26_palette"))
    if saved != null:
        saved.answer(true, PackedStringArray([path]), 0)
    assert_true(FileAccess.file_exists(path + ".gpl"), "the palette is written where the painter chose, as a .gpl")
    DirAccess.remove_absolute(path + ".gpl")
    row.free()


func test_the_path_rows_choose_asks_the_platform_for_a_folder() -> void:
    var written: Array = []
    var host := VBoxContainer.new()
    var box := SaPathRow.make(written.append, host)
    host.add_child(box)
    _press(box, "ChooseButton")
    var picker := _the_one_picker(host, SaFilePicker.Mode.OPEN_DIR, "the path row's Choose")
    if picker != null:
        picker.answer(true, PackedStringArray(["/home/painter/art"]), 0)
    assert_eq(written, ["/home/painter/art"], "the folder chosen is written to the row's setting")

    _press(box, "ChooseButton")
    SaFilePicker.newest().cancel()
    assert_eq(written, ["/home/painter/art"], "and a cancel writes nothing")
    host.free()


func test_the_presets_pages_import_asks_the_platform() -> void:
    var page := SaBrushPresetsPage.new()
    _press(page, "PresetsImportButton")
    var picker := _the_one_picker(page, SaFilePicker.Mode.OPEN_FILE, "the Brush Presets page's Import")
    _tells(picker, page, &"import_path", "the Brush Presets page's Import")
    if picker != null:
        assert_eq(picker.title, "Import Krita Presets", "under the title it had")
        assert_eq(picker.filters.size(), 3, "offering presets, a preset and a bundle")
        picker.cancel()
    assert_eq(page.last_path, "", "a cancel imports nothing")
    page.free()


func test_the_shortcuts_pages_import_asks_the_platform() -> void:
    var page := SaShortcutsPage.new()
    _press(page, "ImportKritaButton")
    var picker := _the_one_picker(page, SaFilePicker.Mode.OPEN_FILE, "the Shortcuts page's Import from Krita")
    _tells(picker, page, &"import_krita_file", "the Shortcuts page's Import from Krita")
    if picker != null:
        assert_eq(picker.filters, PackedStringArray(["*.shortcuts ; Krita Shortcuts"]), "a Krita shortcuts file")
    page.free()


func test_load_tip_asks_the_platform() -> void:
    var told: Array = []
    SaBrushTipMask.choose_file(told.append)
    var root := (Engine.get_main_loop() as SceneTree).root
    var picker := _the_one_picker(root, SaFilePicker.Mode.OPEN_FILE, "Load Tip")
    if picker != null:
        assert_eq(picker.title, "Load Brush Tip", "under the title it had")
        assert_eq(picker.filters.size(), 5, "offering a tip, a PNG, a GIMP brush, a GIMP pipe and a Photoshop collection")
        picker.answer(true, PackedStringArray(["/home/painter/tip.gbr"]), 2)
    assert_eq(told, ["/home/painter/tip.gbr"], "the tip chosen reaches the brush")


func _painted_canvas() -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    canvas.document.fill_layer(Color(0.25, 0.5, 0.75, 1.0))
    canvas.easel.request_composite()
    canvas.easel.process_pending_composite()
    return canvas


func _collect_builders(dir_path: String, into: Array[String]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    for sub in dir.get_directories():
        if not SKIP_DIRS.has(sub):
            _collect_builders(dir_path.path_join(sub), into)
    for file in dir.get_files():
        if not file.ends_with(".gd"):
            continue
        var path := dir_path.path_join(file)
        if FileAccess.get_file_as_string(path).contains("FileDialog.new("):
            into.append(path)


## The platform with a picker and no window: it keeps each picker it was asked
## to show, which the suite answers in the painter's place.
class StandIn:
    extends SaFilePicker.Platform

    var shown: Array[SaFilePicker] = []

    func has_picker() -> bool:
        return true

    func show(picker: SaFilePicker, _platform_filters: PackedStringArray, _parent_id: int, _answer: Callable) -> void:
        shown.append(picker)

    func show_dialog(dialog: Window) -> void:
        push_error("the stand-in has a picker, so no dialog should be shown: %s" % dialog)
