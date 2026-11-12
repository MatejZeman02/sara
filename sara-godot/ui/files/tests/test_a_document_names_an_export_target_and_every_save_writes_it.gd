## A document names an export target and every save writes it.
##
## A surface with one colour filled, the files flow over it the way main builds
## it, and File > Export Target's dialog naming the target as the picker would.
## The saves are driven to their end by `SaSadFile.finish_saves`, and the
## status line is a real one, hearing the bus as the app's does.
extends "res://tests/test_framework.gd"

## The saves and the exports are read back off the card.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _surface: SaSurface = null
var _documents: SaDocuments = null
var _flow: SaDocumentFiles = null
var _dialog: SaExportTargetsDialog = null
var _line: SaStatusLine = null
var _folder := ""
## The recent list as the machine had it, because a save puts its file there.
var _saved_recent: Array = []
var _previous_embedding := true
var _previous_platform: SaFilePicker.Platform = null


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _previous_platform = SaFilePicker.platform
    SaFilePicker.platform = StandIn.new()
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _surface.get_document().fill_layer(Color(0.8, 0.3, 0.1, 1.0))
    _documents = SaDocuments.new()
    _documents.add(_surface)
    _folder = OS.get_temp_dir().path_join("sara-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder.path_join("game/art"))
    _flow = SaDocumentFiles.new(Callable(), _documents)
    EventBus.add_child(_flow)
    _dialog = SaExportTargetsDialog.new()
    _flow.add_child(_dialog)
    _line = SaStatusLine.new(func() -> SaSurface: return _surface)
    EventBus.add_child(_line)


func after_each() -> void:
    var cancelled := 0
    while SaFilePicker.newest() != null and cancelled < 100:
        SaFilePicker.newest().cancel()
        cancelled += 1
    assert_null(SaFilePicker.newest(), "A cancelled picker goes away")
    SaFilePicker.platform = _previous_platform
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _previous_embedding
    if _line != null:
        _line.free()
        _line = null
    if _flow != null:
        _flow.free()
        _flow = null
    _dialog = null
    Fixtures.teardown(_surface)
    _surface = null
    _documents = null
    _remove_all(_folder)
    for path: String in SaSettings.recent_files():
        SaSettings.remove_recent_file(str(path))
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))


func _remove_all(folder: String) -> void:
    for sub in DirAccess.get_directories_at(folder):
        _remove_all(folder.path_join(sub))
    for file in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(file))
    DirAccess.remove_absolute(folder)


## Saves the document at *sad* through the flow, as Ctrl+S does once it has a file.
func _save(sad: String, surface: SaSurface = _surface) -> void:
    surface.get_document().mark_saved(sad)
    surface.get_document().modified = true
    _flow.save_document(Callable(), surface.get_document())
    assert_true(SaSadFile.finish_saves(), "The save ends")


## What File > Export writes for *depth* with the dialog's starting options,
## through the same writer, at *path*: the rolloff where the view's tonemap is,
## and the impasto lighting on, which a document with no height never lights.
func _exported(path: String, depth: int) -> PackedByteArray:
    var format := SaImageFormatRegistry.shared().find(&"png")
    var write := SaImageFormat.Write.new()
    write.depth = depth
    write.rolloff = SaSettings.tonemap_highlights
    write.relief = true
    write.mapping = SaGamutMapping.for_export(SaSettings.gamut_mapping, false)
    assert_eq(format.writer.call(_surface.get_document().get_parent() as SaEasel, path, write), OK, "File > Export writes")
    return FileAccess.get_file_as_bytes(path)


func test_a_png_target_is_written_byte_for_byte_as_file_export_writes_it() -> void:
    for depth: int in [8, 16]:
        var target := _folder.path_join("game/art/hero_%d.png" % depth)
        _dialog.open_for(_surface.get_document())
        if depth == 8:
            # Named as the painter names one: Add Target... and the picker.
            (_dialog.find_child("AddButton", true, false) as Button).pressed.emit()
            var picker := SaFilePicker.newest()
            assert_not_null(picker, "Add Target... asks for the file")
            if picker == null:
                return
            picker.choose(PackedStringArray([target]))
        else:
            _dialog.add_target(target, depth)
        assert_true(_dialog.shown_paths().has(target), "The dialog lists the %d-bit target" % depth)
        _dialog.hide()
        _save(_folder.path_join("hero.sad"))
        assert_true(FileAccess.file_exists(target), "The save wrote the %d-bit target" % depth)
        var written := FileAccess.get_file_as_bytes(target)
        var exported := _exported(_folder.path_join("export_%d.png" % depth), depth)
        # The file names the second it was written in, so a pair either side of
        # a second's turn is written again, once.
        if written != exported:
            _save(_folder.path_join("hero.sad"))
            written = FileAccess.get_file_as_bytes(target)
            exported = _exported(_folder.path_join("export_%d.png" % depth), depth)
        assert_true(written.size() > 0, "The %d-bit target holds a picture" % depth)
        assert_true(written == exported, "The %d-bit target is the bytes File > Export writes" % depth)
    var kept: Array = _surface.get_document().module_data[SaExportTargets.KEY]
    assert_eq(str(kept[0]["path"]), "game/art/hero_8.png", "The .sad keeps the path from its own folder")


func test_a_sad_moved_with_its_game_folder_writes_the_target_at_its_new_place() -> void:
    var first_home := _folder.path_join("before")
    DirAccess.make_dir_recursive_absolute(first_home.path_join("art"))
    _surface.get_document().mark_saved(first_home.path_join("scene.sad"))
    _dialog.open_for(_surface.get_document())
    _dialog.add_target(first_home.path_join("art/tree"))
    _save(first_home.path_join("scene.sad"))
    assert_true(FileAccess.file_exists(first_home.path_join("art/tree.png")), "The target is written beside the .sad")

    var moved := _folder.path_join("after")
    assert_eq(DirAccess.rename_absolute(first_home, moved), OK, "The folder moves whole")
    DirAccess.remove_absolute(moved.path_join("art/tree.png"))
    var opened := Fixtures.make_surface(Vector2i(256, 256))
    _documents.add(opened)
    assert_eq(SaSadFile.load_file(opened.get_document(), moved.path_join("scene.sad")), OK, "The moved .sad opens")
    opened.get_document().mark_saved(moved.path_join("scene.sad"))
    var targets := SaExportTargets.of(opened.get_document())
    assert_eq(targets.size(), 1, "The opened document names its target")
    if not targets.is_empty():
        assert_eq(targets[0].path, moved.path_join("art/tree.png"), "read from the .sad's new folder")
    _save(moved.path_join("scene.sad"), opened)
    assert_true(FileAccess.file_exists(moved.path_join("art/tree.png")), "The save writes the target at its new place")
    assert_false(FileAccess.file_exists(first_home.path_join("art/tree.png")), "and nothing at the old one")
    Fixtures.teardown(opened)


func test_a_target_that_cannot_be_written_leaves_the_save_done_and_is_named() -> void:
    var blocker := _folder.path_join("blocker")
    var file := FileAccess.open(blocker, FileAccess.WRITE)
    file.store_string("a file where the target's folder would be")
    file.close()
    var target := blocker.path_join("sky.png")
    _dialog.open_for(_surface.get_document())
    _dialog.add_target(target)
    var sad := _folder.path_join("sky.sad")
    _save(sad)
    assert_true(FileAccess.file_exists(sad), "The .sad is written")
    assert_false(_surface.get_document().modified, "and the document is saved")
    assert_false(FileAccess.file_exists(target), "The target is not")
    assert_true(_line.save_label.visible, "The status line speaks")
    assert_true(_line.save_label.text.contains(target), "and names the target: %s" % _line.save_label.text)


func test_save_as_into_another_folder_keeps_writing_the_same_file() -> void:
    var target := _folder.path_join("game/art/rock.png")
    _surface.get_document().mark_saved(_folder.path_join("rock.sad"))
    _dialog.open_for(_surface.get_document())
    _dialog.add_target(target)
    DirAccess.make_dir_recursive_absolute(_folder.path_join("elsewhere"))
    _surface.get_document().modified = true
    _flow.save_as(Callable(), &"", _surface.get_document())
    var picker := SaFilePicker.newest()
    assert_not_null(picker, "Save As asks where to put it")
    if picker == null:
        return
    picker.choose(PackedStringArray([_folder.path_join("elsewhere/rock.sad")]))
    assert_true(SaSadFile.finish_saves(), "The save ends")
    assert_eq(SaExportTargets.of(_surface.get_document())[0].path, target, "The target is the same file")
    assert_true(FileAccess.file_exists(target), "and is written")
    var kept: Array = _surface.get_document().module_data[SaExportTargets.KEY]
    assert_eq(str(kept[0]["path"]), "../game/art/rock.png", "kept from the new folder")


## A platform that has a picker and shows nothing, so the pickers are answered
## here rather than by a window on somebody's screen.
class StandIn:
    extends SaFilePicker.Platform

    func has_picker() -> bool:
        return true

    func show(_picker: SaFilePicker, _platform_filters: PackedStringArray, _parent_id: int, _answer: Callable) -> void:
        pass

    func show_dialog(dialog: Window) -> void:
        push_error("the stand-in has a picker, so no dialog should be shown: %s" % dialog)
