## A picture opened through Android's picker opens by what it
## holds.
##
## The picker hands back a content address with no extension, and `open_path`
## sent every such path to the `.sad` loader, which refused a plain PNG as
## "File unrecognized". Here a PNG, a JPEG and a `.sad` of the suites' data are
## each copied to a name with no extension and opened through the real flow,
## built the way the tabs suite builds it, and each is read as what it is.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const ViewScript := preload("res://render/main_canvas.gd")

const PNG_SOURCE := "res://tests/data/import_gradient.png"
const JPEG_SOURCE := "res://tests/data/import_gradient.jpg"
const SAD_SOURCE := "res://tests/data/plain_v4.sad"
## The size of both gradients, which is not the size of the easel they open on.
const PICTURE_SIZE := Vector2i(300, 200)

var _documents: SaDocuments = null
var _host: Node = null
var _first: Control = null
var _tabs: SaDocumentTabs = null
var _flow: SaDocumentFiles = null
var _folder := ""
var _was_embedding := false
var _saved_recent: Array = []
var _asks := true


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    _asks = SaSettings.ask_when_opening
    SaSettings.ask_when_opening = false
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _documents = SaDocuments.new()
    tree.current_scene.set(&"documents", _documents)
    _host = Node.new()
    _host.name = "U372Host"
    EventBus.add_child(_host)
    _first = ViewScript.new()
    _host.add_child(_first)
    _documents.add(_first.get("surface") as SaSurface)
    _tabs = SaDocumentTabs.new(_host, _documents, _first)
    tree.current_scene.add_child(_tabs)
    _flow = SaDocumentFiles.new(SaCanvasView.front_canvas, _documents)
    tree.current_scene.add_child(_flow)
    _folder = OS.get_temp_dir().path_join("sara-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
    DirAccess.copy_absolute(ProjectSettings.globalize_path(PNG_SOURCE), _path("186"))
    DirAccess.copy_absolute(ProjectSettings.globalize_path(JPEG_SOURCE), _path("187"))
    DirAccess.copy_absolute(ProjectSettings.globalize_path(SAD_SOURCE), _path("188"))


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
    SaSettings.ask_when_opening = _asks
    for file in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(file))
    DirAccess.remove_absolute(_folder)
    for path: String in SaSettings.recent_files():
        SaSettings.remove_recent_file(str(path))
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))


func _path(file: String) -> String:
    return _folder.path_join(file)


## Opens *path* through the flow and waits until the front document is what
## *landed* says, since a `.sad` may answer on a later frame.
func _open(path: String, landed: Callable) -> SaDocument:
    _flow.open_path(path)
    for frame in 120:
        if landed.call(_documents.front.get_document()):
            break
        await (Engine.get_main_loop() as SceneTree).process_frame
    return _documents.front.get_document()


func _is_picture(doc: SaDocument) -> bool:
    return doc != null and doc.canvas_size == PICTURE_SIZE


func _names(doc: SaDocument) -> Array:
    var out: Array = []
    for layer in SaLayerOps.new(doc).layers():
        out.append(String(layer.name))
    return out


func test_the_route_reads_each_file_by_its_first_bytes() -> void:
    assert_eq(SaOpenRoute.new(_path("186")).kind, SaOpenRoute.Kind.PICTURE, "A PNG with no extension is a picture")
    assert_eq(SaOpenRoute.new(_path("187")).kind, SaOpenRoute.Kind.PICTURE, "and so is a JPEG")
    assert_eq(SaOpenRoute.new(_path("188")).kind, SaOpenRoute.Kind.SAD, "and a .sad with no extension is a .sad")


func test_a_png_with_no_extension_opens_as_a_picture() -> void:
    var doc := await _open(_path("186"), _is_picture)
    assert_eq(doc.canvas_size, PICTURE_SIZE, "The PNG became the document, at its own size")
    assert_eq(_names(doc), ["186"], "as its one layer, named after the file")
    assert_eq(doc.file_path, "", "and, being a picture rather than a .sad, it has no file yet")


func test_a_jpeg_with_no_extension_opens_as_a_picture() -> void:
    var doc := await _open(_path("187"), _is_picture)
    assert_eq(doc.canvas_size, PICTURE_SIZE, "The JPEG became the document, at its own size")
    assert_eq(_names(doc), ["187"], "as its one layer, named after the file")


func test_a_sad_with_no_extension_opens_as_a_sad() -> void:
    var doc := await _open(_path("188"), func(d: SaDocument) -> bool: return d != null and d.file_path == _path("188"))
    assert_eq(doc.file_path, _path("188"), "The .sad is the document, marked as that file")
    assert_false(doc.modified, "and saved, as a .sad opened by name is")
