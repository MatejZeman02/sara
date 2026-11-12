## A close request asks about unsaved work, and quits at once when there is none.
##
## The files flow is built over an owner holding two documents, the way main
## builds it. A close request, the window manager's or Ctrl+Q, reaches
## `confirm_quit`, and with a modified document it has to put up the question
## and wait for the painter. A termination signal never reaches this path,
## since the engine installs no handler for it and the process ends by the
## signal's default action, which the scenario
## `sigterm-ends-sara-within-seconds-whatever-the-document-holds.py`
## measures, so the question stays the window's alone.
##
## Both documents carry a file name, so the question can name the one it is
## about. Nothing is written, because every question here is cancelled.
extends "res://tests/test_framework.gd"

## The documents are surfaces over real textures.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _first: SaSurface = null
var _second: SaSurface = null
var _documents: SaDocuments = null
var _flow: SaDocumentFiles = null
var _quits := 0
var _previous_embedding := true


func before_each() -> void:
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
    var folder := OS.get_temp_dir().path_join("sara-close-request-%d" % OS.get_process_id())
    _first.get_document().mark_saved(folder.path_join("first.sad"))
    _second.get_document().mark_saved(folder.path_join("second.sad"))
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
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


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


func test_a_close_request_puts_up_the_question_for_a_modified_document() -> void:
    _first.get_document().modified = true
    _flow.confirm_quit(_quit)
    var standing := _questions()
    assert_eq(standing.size(), 1, "The close request asks")
    if standing.is_empty():
        return
    assert_eq(standing[0].text_label.text, "Save the changes to first.sad before quitting?", "about the modified document")
    assert_eq(_quits, 0, "and does not quit while the question stands")
    standing[0].buttons[SaDocumentFiles.PROMPT_CANCEL].pressed.emit()
    assert_eq(_quits, 0, "Cancel keeps Sara open")


func test_a_close_request_with_no_unsaved_work_quits_without_asking() -> void:
    _flow.confirm_quit(_quit)
    assert_eq(_questions().size(), 0, "Nothing is asked")
    assert_eq(_quits, 1, "and the quit runs once")
