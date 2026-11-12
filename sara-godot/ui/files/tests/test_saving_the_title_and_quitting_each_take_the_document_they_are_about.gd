## Saving, the title and quitting each take the document they
## are about.
##
## Two surfaces in one `SaDocuments`, the way two tabs will hold them, and the
## files flow and the window title built over that owner the way main builds
## them. The quit's question is driven through `confirm_quit`, its buttons
## pressed by their own `pressed` signal, and the saves are driven to their end
## by `SaSadFile.finish_saves`, which a suite can do without a frame.
##
## Both documents are given a file of their own before they are modified, so
## Save All writes rather than asking where to put them. Save As has to ask, so
## the platform is a stand-in that puts no window up and hands the picker back,
## which the case answers in the platform's place.
extends "res://tests/test_framework.gd"

## The saves are real files off real textures, and the preview is read on the
## card.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _first: SaSurface = null
var _second: SaSurface = null
var _documents: SaDocuments = null
var _flow: SaDocumentFiles = null
var _title: SaWindowTitle = null
var _folder := ""
var _quits := 0
var _previous_embedding := true
var _previous_title := ""
var _previous_platform: SaFilePicker.Platform = null
## The recent list as the machine had it, because a save here puts its own file
## at the front of it and the File menu is built out of that list.
var _saved_recent: Array = []


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    for path: String in _saved_recent:
        SaSettings.remove_recent_file(str(path))
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _previous_title = tree.root.title
    _previous_platform = SaFilePicker.platform
    SaFilePicker.platform = StandIn.new()
    _first = Fixtures.make_surface(Vector2i(256, 256))
    _first.id = &"first"
    _second = Fixtures.make_surface(Vector2i(256, 256))
    _second.id = &"second"
    _documents = SaDocuments.new()
    _documents.add(_first)
    _documents.add(_second)
    _folder = OS.get_temp_dir().path_join("sara-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
    _first.get_document().mark_saved(_path("first.sad"))
    _second.get_document().mark_saved(_path("second.sad"))
    _flow = SaDocumentFiles.new(Callable(), _documents)
    EventBus.add_child(_flow)
    _title = SaWindowTitle.new(_documents)
    EventBus.add_child(_title)
    _quits = 0


func after_each() -> void:
    var cancelled := 0
    while SaFilePicker.newest() != null and cancelled < 100:
        SaFilePicker.newest().cancel()
        cancelled += 1
    assert_null(SaFilePicker.newest(), "A cancelled picker goes away")
    SaFilePicker.platform = _previous_platform
    if _title != null:
        _title.free()
        _title = null
    if _flow != null:
        _flow.free()
        _flow = null
    Fixtures.teardown(_first)
    Fixtures.teardown(_second)
    _first = null
    _second = null
    _documents = null
    for file in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(file))
    DirAccess.remove_absolute(_folder)
    for path: String in SaSettings.recent_files():
        SaSettings.remove_recent_file(str(path))
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding
    tree.root.title = _previous_title


func _path(file: String) -> String:
    return _folder.path_join(file)


## Both documents changed since their last save, which is what a painter
## leaving the machine with two paintings open has.
func _modify_both() -> void:
    _first.get_document().modified = true
    _second.get_document().modified = true


func _quit() -> void:
    _quits += 1


## The question the flow has up, which is its own child window.
func _question() -> SaMessage:
    for child in _flow.get_children():
        var dialog := child as SaMessage
        if dialog != null and dialog.visible:
            return dialog
    return null


func _press(index: int) -> void:
    var dialog := _question()
    assert_not_null(dialog, "A question is up to answer")
    if dialog != null:
        dialog.buttons[index].pressed.emit()


func _labels() -> PackedStringArray:
    var out := PackedStringArray()
    var dialog := _question()
    if dialog != null:
        for button in dialog.buttons:
            out.append(button.text)
    return out


func test_the_quit_names_both_modified_documents_and_save_all_writes_them() -> void:
    _modify_both()
    _flow.confirm_quit(_quit)
    var dialog := _question()
    assert_not_null(dialog, "The quit asks")
    if dialog == null:
        return
    assert_eq(dialog.title, "Unsaved changes", "under the title the one-document question uses")
    assert_true(dialog.text_label.text.contains("first.sad"), "The first document is named: %s" % dialog.text_label.text)
    assert_true(dialog.text_label.text.contains("second.sad"), "and the second one as well")
    assert_eq(_labels(), PackedStringArray(["Save All", "Discard All", "Cancel"]), "Save All, Discard All and Cancel")
    assert_eq(_quits, 0, "and nothing quits before it is answered")

    _press(SaQuitPrompt.SAVE_ALL)
    assert_true(SaSadFile.finish_saves(), "Both saves end")
    assert_true(FileAccess.file_exists(_path("first.sad")), "The first document is written")
    assert_true(FileAccess.file_exists(_path("second.sad")), "and so is the second")
    assert_false(_first.get_document().modified, "The first document has no unsaved work left")
    assert_false(_second.get_document().modified, "nor the second")
    assert_eq(_quits, 1, "and the quit runs once, after both files")


func test_one_modified_document_is_asked_about_word_for_word_as_before() -> void:
    _first.get_document().modified = true
    _flow.confirm_quit(_quit)
    var dialog := _question()
    assert_not_null(dialog, "The quit asks")
    if dialog == null:
        return
    assert_eq(dialog.title, "Unsaved changes", "under the title it always had")
    assert_eq(dialog.text_label.text, "Save the changes to first.sad before quitting?", "in the sentence it always said")
    assert_eq(_labels(), PackedStringArray(["Save", "Discard", "Cancel"]), "with Save, Discard and Cancel")

    _press(SaDocumentFiles.PROMPT_DISCARD)
    assert_eq(_quits, 1, "Discard quits")
    assert_false(FileAccess.file_exists(_path("first.sad")), "and writes nothing")


func test_discard_all_quits_and_cancel_leaves_both_open() -> void:
    _modify_both()
    _flow.confirm_quit(_quit)
    _press(SaQuitPrompt.CANCEL)
    assert_eq(_quits, 0, "Cancel does not quit")
    assert_true(_first.get_document().modified, "The first document is still unsaved")
    assert_true(_second.get_document().modified, "and so is the second")

    _flow.confirm_quit(_quit)
    _press(SaQuitPrompt.DISCARD_ALL)
    assert_eq(_quits, 1, "Discard All quits")
    assert_false(FileAccess.file_exists(_path("first.sad")), "and writes neither file")
    assert_false(FileAccess.file_exists(_path("second.sad")), "nor the other")


func test_a_save_writes_the_document_it_is_about_and_leaves_the_front_one_alone() -> void:
    _modify_both()
    assert_true(_documents.bring_to_front(_second), "The second document is in front")
    _flow.save_document(Callable(), _first.get_document())
    assert_true(SaSadFile.finish_saves(), "The save ends")
    assert_true(FileAccess.file_exists(_path("first.sad")), "The document named is written")
    assert_false(FileAccess.file_exists(_path("second.sad")), "and the one in front is not")
    assert_false(_first.get_document().modified, "The document named has no unsaved work left")
    assert_true(_second.get_document().modified, "and the one in front still has its own")


## Save As reads the document before its picker opens, so a painter who brings
## another painting forward while that window stands still writes the one the
## Save As was about, and the file goes nowhere near the document in front.
func test_save_as_writes_the_document_it_was_asked_about_though_another_came_forward() -> void:
    _modify_both()
    assert_eq(_documents.front, _first, "The first document is in front")
    _flow.save_as(Callable(), &"", _first.get_document())
    var picker := SaFilePicker.newest()
    assert_not_null(picker, "Save As asks where to put it")
    if picker == null:
        return
    assert_eq(picker.mode, SaFilePicker.Mode.SAVE_FILE, "with a picker that writes a file")
    assert_true(_documents.bring_to_front(_second), "The second document comes forward while the picker stands")
    picker.choose(PackedStringArray([_path("as.sad")]))
    assert_true(SaSadFile.finish_saves(), "The save ends")
    assert_eq(_first.get_document().file_path, _path("as.sad"), "The document Save As was about is written where it was named")
    assert_false(_first.get_document().modified, "and has no unsaved work left")
    assert_eq(_second.get_document().file_path, _path("second.sad"), "The document in front keeps its own file")
    assert_true(_second.get_document().modified, "and its own unsaved work")


func test_a_question_with_no_document_named_is_about_the_front_one() -> void:
    _modify_both()
    assert_true(_documents.bring_to_front(_second), "The second document is in front")
    _flow.confirm_discard("closing", _quit)
    var dialog := _question()
    assert_not_null(dialog, "The guard asks")
    if dialog == null:
        return
    assert_eq(dialog.text_label.text, "Save the changes to second.sad before closing?", "about the document in front")
    _press(SaDocumentFiles.PROMPT_CANCEL)
    assert_eq(_quits, 0, "and Cancel does nothing")


func test_the_window_title_follows_the_front_document() -> void:
    var window := (Engine.get_main_loop() as SceneTree).root
    assert_eq(window.title, _expected_title(_first.get_document()), "The title names the document in front")

    assert_true(_documents.bring_to_front(_second), "The second document comes forward")
    assert_eq(window.title, _expected_title(_second.get_document()), "and the title names it instead")

    _second.get_document().modified = true
    assert_eq(window.title, _expected_title(_second.get_document()), "A change to it marks the title")
    assert_true(window.title.contains("second.sad*"), "with the star after its name: %s" % window.title)

    _first.get_document().modified = true
    assert_true(window.title.contains("second.sad*"), "A change to the other document leaves the title alone")

    assert_true(_documents.bring_to_front(_first), "The first document comes back")
    assert_true(window.title.contains("first.sad*"), "and the title names it with its own mark: %s" % window.title)


## The title the front document earns, which is its name, its unsaved mark and
## the gamut a colour picked in it means.
func _expected_title(document: SaDocument) -> String:
    var mark := "*" if document.modified else ""
    return "%s%s (%s) - Sara" % [document.file_path.get_file(), mark, document.color_space.gamut().display_name]


## A platform that has a picker and shows nothing, so Save As can be answered
## here rather than by a window on somebody's screen.
class StandIn:
    extends SaFilePicker.Platform

    func has_picker() -> bool:
        return true

    func show(_picker: SaFilePicker, _platform_filters: PackedStringArray, _parent_id: int, _answer: Callable) -> void:
        pass

    func show_dialog(dialog: Window) -> void:
        push_error("the stand-in has a picker, so no dialog should be shown: %s" % dialog)
