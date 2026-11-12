## A second quit while the quit question stands asks nothing more.
##
## The files flow built over an owner holding two documents, the way main
## builds it, and `confirm_quit` asked twice the way a painter pressing Ctrl+Q
## twice, or Ctrl+Q and then the window's close button, asks it. One "Unsaved
## changes" window has to stand, and its answer has to work: Save writes every
## modified document once and the quit runs once, and Cancel leaves the
## question free to be asked again.
##
## Both documents are given a file of their own before they are modified, so a
## save writes rather than asking where to put it, and the saves are driven to
## their end by `SaSadFile.finish_saves`, which a suite can do without a frame.
extends "res://tests/test_framework.gd"

## The saves are real files off real textures.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _first: SaSurface = null
var _second: SaSurface = null
var _documents: SaDocuments = null
var _flow: SaDocumentFiles = null
var _folder := ""
var _quits := 0
## How many times each document went from unsaved to saved, by its id.
var _saves: Dictionary = {}
var _previous_embedding := true
## The recent list as the machine had it, because a save here puts its own file
## at the front of it.
var _saved_recent: Array = []


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    for path: String in _saved_recent:
        SaSettings.remove_recent_file(str(path))
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _first = Fixtures.make_surface(Vector2i(256, 256))
    _first.id = &"first"
    _second = Fixtures.make_surface(Vector2i(256, 256))
    _second.id = &"second"
    _documents = SaDocuments.new()
    _documents.add(_first)
    _documents.add(_second)
    _folder = OS.get_temp_dir().path_join("sara-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
    _first.get_document().mark_saved(_folder.path_join("first.sad"))
    _second.get_document().mark_saved(_folder.path_join("second.sad"))
    _saves = {&"first": 0, &"second": 0}
    _first.get_document().modified_changed.connect(_count_save.bind(&"first"))
    _second.get_document().modified_changed.connect(_count_save.bind(&"second"))
    _flow = SaDocumentFiles.new(Callable(), _documents)
    EventBus.add_child(_flow)
    _quits = 0


func after_each() -> void:
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


func _count_save(modified: bool, id: StringName) -> void:
    if not modified:
        _saves[id] += 1


func _quit() -> void:
    _quits += 1


## Every question the flow has up, each its own child window.
func _questions() -> Array[SaMessage]:
    var out: Array[SaMessage] = []
    for child in _flow.get_children():
        var dialog := child as SaMessage
        if dialog != null and dialog.visible:
            out.append(dialog)
    return out


func _press(index: int) -> void:
    var standing := _questions()
    assert_eq(standing.size(), 1, "One question is up to answer")
    if not standing.is_empty():
        standing[0].buttons[index].pressed.emit()


func test_two_modified_documents_asked_twice_stand_one_window_whose_save_all_saves_both() -> void:
    _first.get_document().modified = true
    _second.get_document().modified = true
    _flow.confirm_quit(_quit)
    _flow.confirm_quit(_quit)
    var standing := _questions()
    assert_eq(standing.size(), 1, "A second quit puts up no second window")
    if standing.is_empty():
        return
    assert_eq(standing[0].title, "Unsaved changes", "The one standing is the quit's question")
    assert_eq(standing[0].buttons[SaQuitPrompt.SAVE_ALL].text, "Save All", "naming both documents")

    _press(SaQuitPrompt.SAVE_ALL)
    assert_true(SaSadFile.finish_saves(), "Both saves end")
    assert_true(FileAccess.file_exists(_folder.path_join("first.sad")), "The first document is written")
    assert_true(FileAccess.file_exists(_folder.path_join("second.sad")), "and so is the second")
    assert_false(_first.get_document().modified, "The first document has no unsaved work left")
    assert_false(_second.get_document().modified, "nor the second")
    assert_eq(_saves, {&"first": 1, &"second": 1}, "Each document is saved once")
    assert_eq(_quits, 1, "and the quit runs once")


func test_one_modified_document_asked_twice_stands_one_window_whose_save_saves_it_once() -> void:
    _first.get_document().modified = true
    _flow.confirm_quit(_quit)
    _flow.confirm_quit(_quit)
    var standing := _questions()
    assert_eq(standing.size(), 1, "A second quit puts up no second window")
    if standing.is_empty():
        return
    assert_eq(standing[0].text_label.text, "Save the changes to first.sad before quitting?", "in the sentence it always said")
    assert_eq(standing[0].buttons[SaDocumentFiles.PROMPT_SAVE].text, "Save", "with Save as its first button")

    _press(SaDocumentFiles.PROMPT_SAVE)
    assert_true(SaSadFile.finish_saves(), "The save ends")
    assert_true(FileAccess.file_exists(_folder.path_join("first.sad")), "The document is written")
    assert_eq(_saves, {&"first": 1, &"second": 0}, "once, and the other document is left alone")
    assert_eq(_quits, 1, "and the quit runs once")


func test_after_a_cancel_a_new_quit_asks_again() -> void:
    _first.get_document().modified = true
    _flow.confirm_quit(_quit)
    _press(SaDocumentFiles.PROMPT_CANCEL)
    assert_eq(_questions().size(), 0, "Cancel takes the question down")
    assert_eq(_quits, 0, "and does not quit")
    assert_true(_first.get_document().modified, "and the document is still unsaved")

    _flow.confirm_quit(_quit)
    assert_eq(_questions().size(), 1, "A quit after the Cancel asks again")
    _press(SaDocumentFiles.PROMPT_DISCARD)
    assert_eq(_quits, 1, "and its Discard quits")
