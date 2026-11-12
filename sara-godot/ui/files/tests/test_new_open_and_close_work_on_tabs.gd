## New, Open and Close work on tabs.
##
## The host stands in for main the way the tabs suite builds it: a first view
## from `render/main_canvas.gd`, held by an `SaDocuments` the runner hands
## `SaCanvasView.front_canvas()`, and the `SaDocumentTabs` over both. The tabs
## and the document flow stand under the runner's scene by the names main gives
## them, since each finds the other there, and the files opened are copies of
## two `.sad` files of the suites' data read through the real loader.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const ViewScript := preload("res://render/main_canvas.gd")

## Two documents of different sizes, so which one is open shows in its canvas.
const FIRST_SOURCE := "res://tests/data/plain_v4.sad"
const SECOND_SOURCE := "res://tests/data/screen_over_twice_white_v4.sad"

var _documents: SaDocuments = null
var _host: Node = null
var _first: Control = null
var _tabs: SaDocumentTabs = null
var _flow: SaDocumentFiles = null
var _folder := ""
var _was_embedding := false
var _saved_recent: Array = []


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _documents = SaDocuments.new()
    tree.current_scene.set(&"documents", _documents)
    _host = Node.new()
    _host.name = "U326Host"
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
    DirAccess.copy_absolute(ProjectSettings.globalize_path(FIRST_SOURCE), _path("first.sad"))
    DirAccess.copy_absolute(ProjectSettings.globalize_path(SECOND_SOURCE), _path("second.sad"))


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
    for file in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(file))
    DirAccess.remove_absolute(_folder)
    for path: String in SaSettings.recent_files():
        SaSettings.remove_recent_file(str(path))
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))


func _path(file: String) -> String:
    return _folder.path_join(file)


## Opens *path* through the flow and waits for the loader, which may answer on
## a later frame, until the front document is that file.
func _open(path: String) -> void:
    _flow.open_path(path)
    for frame in 120:
        if _front_path() == path:
            return
        await (Engine.get_main_loop() as SceneTree).process_frame


func _front_path() -> String:
    var doc := _documents.front.get_document() if _documents.front != null else null
    return doc.file_path if doc != null else ""


func _paths() -> PackedStringArray:
    var out := PackedStringArray()
    for surface in _documents.surfaces:
        out.append(surface.get_document().file_path)
    return out


## The question the flow has up, which is its own child window.
func _question() -> SaMessage:
    for child in _flow.get_children():
        var dialog := child as SaMessage
        if dialog != null and dialog.visible:
            return dialog
    return null


func test_a_file_opened_on_a_fresh_start_takes_the_untouched_tab_and_one_open_comes_forward() -> void:
    assert_true(_flow.is_untouched(_documents.front.get_document()), "Sara starts with an untitled, untouched document")
    await _open(_path("first.sad"))
    assert_eq(_documents.surfaces.size(), 1, "A file opened on a fresh start replaces the untouched document")
    assert_eq(_front_path(), _path("first.sad"), "and it is the file")
    await _open(_path("second.sad"))
    assert_eq(_documents.surfaces.size(), 2, "A second file opens in a tab of its own")
    assert_eq(_paths(), PackedStringArray([_path("first.sad"), _path("second.sad")]), "after the first")
    await _open(_path("first.sad"))
    assert_eq(_documents.surfaces.size(), 2, "The first opened again opens no third tab")
    assert_eq(_front_path(), _path("first.sad"), "and brings the first's tab forward")


func test_a_file_opens_beside_a_modified_untitled_document_and_asks_nothing() -> void:
    _documents.front.get_document().modified = true
    await _open(_path("first.sad"))
    assert_null(_question(), "Nothing is asked, since nothing is thrown away")
    assert_eq(_documents.surfaces.size(), 2, "The painted untitled document keeps its tab")
    assert_true(_documents.surfaces[0].get_document().modified, "unchanged")


func test_a_file_that_will_not_read_leaves_no_tab() -> void:
    await _open(_path("first.sad"))
    var broken := FileAccess.open(_path("broken.sad"), FileAccess.WRITE)
    broken.store_string("not a Sara document")
    broken.close()
    SaProblems.announce = false
    await _open(_path("broken.sad"))
    for frame in 5:
        await (Engine.get_main_loop() as SceneTree).process_frame
    SaProblems.announce = true
    assert_eq(_paths(), PackedStringArray([_path("first.sad")]), "The tab opened for it closes again")


## New lands in the untouched document the way Open does, so
## a painter's first Ctrl+N leaves one tab and not an Untitled they never asked for.
func test_new_takes_the_untouched_document_as_open_does() -> void:
    var canvas := SaDocumentFiles.canvas_for_new(Engine.get_main_loop() as SceneTree, null)
    assert_not_null(canvas, "New has a canvas to build on")
    assert_eq(_documents.surfaces.size(), 1, "the untouched document's, and no tab beside it")
    assert_eq(SaCanvasView.canvas_of(_documents.front), canvas, "the one in front")


func test_new_opens_a_tab_beside_a_painted_document() -> void:
    _documents.front.get_document().modified = true
    var canvas := SaDocumentFiles.canvas_for_new(Engine.get_main_loop() as SceneTree, null)
    assert_not_null(canvas, "New has a canvas to build on")
    assert_eq(_documents.surfaces.size(), 2, "in a tab of its own")
    assert_eq(SaCanvasView.canvas_of(_documents.front), canvas, "brought to the front")
    assert_true(_documents.surfaces[0].get_document().modified, "and the painted one keeps its tab")


func test_new_from_clipboard_opens_a_tab_of_the_pictures_size() -> void:
    var image := Image.create_empty(321, 123, false, Image.FORMAT_RGBA8)
    image.fill(Color(1.0, 0.0, 0.0, 1.0))
    var was: Callable = SaNewFromClipboard.desktop_picture
    SaNewFromClipboard.desktop_picture = func() -> SaDesktopPicture: return SaDesktopPicture.new(image, "the engine")
    var before := _documents.front.get_document()
    before.modified = true
    _flow.new_from_clipboard()
    SaNewFromClipboard.desktop_picture = was
    assert_null(_question(), "Nothing is asked")
    assert_eq(_documents.surfaces.size(), 2, "The picture opens in a tab of its own")
    assert_eq(_documents.front.get_document().canvas_size, Vector2i(321, 123), "the picture's size")
    assert_eq(_documents.surfaces[0].get_document(), before, "and the document before keeps its tab")


func test_closing_a_modified_document_of_two_asks_about_it_alone_and_discard_leaves_the_other() -> void:
    await _open(_path("first.sad"))
    await _open(_path("second.sad"))
    var kept := _documents.surfaces[0]
    var kept_layers := SaLayerOps.new(kept.get_document()).layers().size()
    var closing := _documents.front
    closing.get_document().modified = true
    assert_true(_tabs.close_front(), "Close runs on the front document")
    var question := _question()
    assert_not_null(question, "A modified document is asked about")
    var said := question.text_label.text if question != null else ""
    assert_true(said.contains("second.sad"), "naming it: %s" % said)
    assert_false(said.contains("first.sad"), "and not the other")
    question.buttons[SaDocumentFiles.PROMPT_DISCARD].pressed.emit()
    for frame in 3:
        await (Engine.get_main_loop() as SceneTree).process_frame
    assert_eq(_documents.surfaces, [kept] as Array[SaSurface], "Discard closes that document alone")
    assert_eq(_front_path(), _path("first.sad"), "and the other comes forward")
    assert_false(kept.get_document().modified, "unchanged")
    assert_eq(SaLayerOps.new(kept.get_document()).layers().size(), kept_layers, "with its layers")


func test_closing_the_last_tab_leaves_a_fresh_untitled_document() -> void:
    await _open(_path("first.sad"))
    var old := _documents.front
    _tabs.close_front()
    for frame in 3:
        await (Engine.get_main_loop() as SceneTree).process_frame
    assert_eq(_documents.surfaces.size(), 1, "One document is still open")
    assert_true(_documents.front != old, "a new one")
    assert_true(_flow.is_untouched(_documents.front.get_document()), "untitled and untouched")


func test_the_close_command_is_ctrl_w_under_file() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> SaEasel: return null, func() -> Array: return [])
    _tabs.register_commands(registries)
    var close := registries.commands.get_descriptor(SaDocumentTabs.CLOSE_COMMAND)
    assert_not_null(close, "File > Close is a command")
    if close != null:
        assert_eq(close.category, &"file", "under File")
        assert_eq(SaCommandRegistry.key_text(close.default_events[0]), "Ctrl+W", "on Ctrl+W")


func test_every_path_on_the_command_line_is_taken() -> void:
    var args := PackedStringArray(["--capture", _path("first.sad"), _path("second.sad")])
    assert_eq(SaBoot.document_paths(args), PackedStringArray([_path("first.sad"), _path("second.sad")]), "Both paths, in order")
    assert_eq(SaBoot.document_path(args), _path("first.sad"), "and the first is still the one the welcome window asks about")
