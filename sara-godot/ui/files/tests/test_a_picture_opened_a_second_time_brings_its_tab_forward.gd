## A picture opened a second time brings its tab forward rather than opening
## a second tab.
##
## The owner holds two surfaces, one an existing document and one a picture
## opened through the flow. Opening the picture a second time brings its tab
## forward and leaves the other tab unchanged. Saving the picture as a .sad
## frees the picture path, so opening the PNG again opens a second tab.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const ViewScript := preload("res://render/main_canvas.gd")

const PNG_SOURCE := "res://tests/data/import_gradient.png"

var _documents: SaDocuments = null
var _host: Node = null
var _first: Control = null
var _tabs: SaDocumentTabs = null
var _flow: SaDocumentFiles = null
var _folder := ""
var _was_embedding := false
var _was_asking := true
var _saved_recent: Array = []


func before_each() -> void:
    _folder = OS.get_temp_dir().path_join("sara-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
    DirAccess.copy_absolute(ProjectSettings.globalize_path(PNG_SOURCE), _path("teapot.png"))
    _saved_recent = SaSettings.recent_files()
    _was_asking = SaSettings.ask_when_opening
    SaSettings.ask_when_opening = false
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _documents = SaDocuments.new()
    tree.current_scene.set(&"documents", _documents)
    _host = Node.new()
    _host.name = "U764Host"
    EventBus.add_child(_host)
    _first = ViewScript.new()
    _host.add_child(_first)
    var first_surface := _first.get("surface") as SaSurface
    _documents.add(first_surface)
    first_surface.get_document().mark_saved(_path("other.sad"))
    _tabs = SaDocumentTabs.new(_host, _documents, _first)
    tree.current_scene.add_child(_tabs)
    _tabs.add_document()
    _flow = SaDocumentFiles.new(SaCanvasView.front_canvas, _documents)
    tree.current_scene.add_child(_flow)


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _flow.free()
    _tabs.free()
    tree.current_scene.set(&"documents", null)
    tree.root.gui_embed_subwindows = _was_embedding
    _host.free()
    _host = null
    _first = null
    _tabs = null
    _flow = null
    _documents = null
    SaColors.follow(null)
    SaSettings.ask_when_opening = _was_asking
    for file in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(file))
    DirAccess.remove_absolute(_folder)
    for path: String in SaSettings.recent_files():
        SaSettings.remove_recent_file(str(path))
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))


func _path(file: String) -> String:
    return _folder.path_join(file)


func _front() -> SaDocument:
    return _documents.front.get_document() if _documents.front != null else null


func _open(path: String) -> void:
    _flow.open_path(path)
    for frame in 120:
        if SaDocumentSource.path_of(_front()) == path:
            break
        await (Engine.get_main_loop() as SceneTree).process_frame
    for frame in 2:
        await (Engine.get_main_loop() as SceneTree).process_frame


func test_a_picture_opened_a_second_time_brings_its_tab_forward() -> void:
    assert_eq(_documents.surfaces.size(), 2, "The owner holds two surfaces to begin with")
    var other_surface := _documents.surfaces[0]
    var other_doc := other_surface.get_document()
    assert_eq(other_doc.file_path, _path("other.sad"), "The first tab holds the other document")

    var picture_path := _path("teapot.png")
    await _open(picture_path)
    assert_eq(_documents.surfaces.size(), 2, "Opening the PNG takes the untouched second document")
    assert_eq(_front(), _documents.surfaces[1].get_document(), "The picture document is in front")
    assert_eq(SaDocumentSource.path_of(_front()), picture_path, "and holds the picture")

    var picture_surface := _documents.surfaces[1]
    _documents.bring_to_front(other_surface)
    assert_eq(_documents.front, other_surface, "The other tab is now in front")

    _flow.open_path(picture_path)
    for frame in 2:
        await (Engine.get_main_loop() as SceneTree).process_frame

    assert_eq(_documents.surfaces.size(), 2, "One tab stands for the picture, no third tab opened")
    assert_eq(_documents.front, picture_surface, "The second open leaves the picture's tab in front")
    assert_eq(other_doc.file_path, _path("other.sad"), "and the other tab is as it was")
    assert_false(other_doc.modified, "with its clean state unchanged")

    picture_surface.get_document().mark_saved(_path("picture.sad"))
    assert_eq(picture_surface.get_document().file_path, _path("picture.sad"), "The picture tab is saved as a .sad")
    assert_eq(SaDocumentSource.path_of(picture_surface.get_document()), "", "and no longer holds the picture path")

    await _open(picture_path)
    assert_eq(_documents.surfaces.size(), 3, "Opening the PNG again reads a second tab opened for it")
    assert_true(_documents.front != picture_surface, "The fresh tab is brought forward")
    assert_eq(SaDocumentSource.path_of(_front()), picture_path, "and it holds the picture")
    assert_eq(picture_surface.get_document().file_path, _path("picture.sad"), "while the first tab keeps its .sad")


func test_a_painted_picture_tab_still_brings_its_tab_forward() -> void:
    var other_surface := _documents.surfaces[0]
    var picture_path := _path("teapot.png")
    await _open(picture_path)
    var picture_surface := _documents.surfaces[1]
    picture_surface.get_document().modified = true

    _documents.bring_to_front(other_surface)
    assert_eq(_documents.front, other_surface, "The other tab is in front")

    _flow.open_path(picture_path)
    for frame in 2:
        await (Engine.get_main_loop() as SceneTree).process_frame

    assert_eq(_documents.surfaces.size(), 2, "No second tab opened for the painted picture")
    assert_eq(_documents.front, picture_surface, "The modified picture tab is brought forward")
    assert_true(picture_surface.get_document().modified, "its unsaved changes kept")
