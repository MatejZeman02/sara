## A picture just opened carries its file's name and is not
## unsaved, so closing it asks nothing.
##
## The host is the one the tabs suite builds, a first view from `render/main_canvas.gd` held
## by an `SaDocuments`, the `SaDocumentTabs` over it and the document flow,
## with the window title built over the same owner as main builds it. The
## pictures are copies of a JPEG and a PNG of the suites' data in a folder of
## the run's own, opened through `open_path` as File > Open does, with the depth
## question turned off so the open lands in the same frame. Save As has to ask
## where, so the platform is a stand-in that puts no window up and hands the
## picker back, which the case reads and cancels.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const ViewScript := preload("res://render/main_canvas.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const JPEG_SOURCE := "res://tests/data/import_gradient.jpg"
const PNG_SOURCE := "res://tests/data/import_gradient.png"

var _documents: SaDocuments = null
var _host: Node = null
var _first: Control = null
var _tabs: SaDocumentTabs = null
var _flow: SaDocumentFiles = null
var _title: SaWindowTitle = null
var _folder := ""
var _was_embedding := false
var _was_title := ""
var _was_asking := true
var _was_platform: SaFilePicker.Platform = null
var _saved_recent: Array = []


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    _was_asking = SaSettings.ask_when_opening
    SaSettings.ask_when_opening = false
    _was_platform = SaFilePicker.platform
    SaFilePicker.platform = StandIn.new()
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _was_title = tree.root.title
    _documents = SaDocuments.new()
    tree.current_scene.set(&"documents", _documents)
    _host = Node.new()
    _host.name = "U496Host"
    EventBus.add_child(_host)
    _first = ViewScript.new()
    _host.add_child(_first)
    _documents.add(_first.get("surface") as SaSurface)
    _tabs = SaDocumentTabs.new(_host, _documents, _first)
    tree.current_scene.add_child(_tabs)
    _flow = SaDocumentFiles.new(SaCanvasView.front_canvas, _documents)
    tree.current_scene.add_child(_flow)
    _title = SaWindowTitle.new(_documents)
    tree.current_scene.add_child(_title)
    _folder = OS.get_temp_dir().path_join("sara-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
    DirAccess.copy_absolute(ProjectSettings.globalize_path(JPEG_SOURCE), _path("harbour.jpg"))
    DirAccess.copy_absolute(ProjectSettings.globalize_path(PNG_SOURCE), _path("teapot.png"))


func after_each() -> void:
    var cancelled := 0
    while SaFilePicker.newest() != null and cancelled < 100:
        SaFilePicker.newest().cancel()
        cancelled += 1
    assert_null(SaFilePicker.newest(), "A cancelled picker goes away")
    SaFilePicker.platform = _was_platform
    SaSettings.ask_when_opening = _was_asking
    var tree := Engine.get_main_loop() as SceneTree
    _title.free()
    _flow.free()
    _tabs.free()
    tree.current_scene.set(&"documents", null)
    tree.root.gui_embed_subwindows = _was_embedding
    tree.root.title = _was_title
    _host.free()
    _host = null
    _first = null
    _tabs = null
    _flow = null
    _title = null
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


func _frames(count: int) -> void:
    for frame in count:
        await (Engine.get_main_loop() as SceneTree).process_frame


func _front() -> SaDocument:
    return _documents.front.get_document() if _documents.front != null else null


## Opens the picture at *path* through the flow and waits until the document in
## front is the one it made.
func _open(path: String) -> void:
    _flow.open_path(path)
    for frame in 120:
        if SaDocumentSource.path_of(_front()) == path:
            break
        await (Engine.get_main_loop() as SceneTree).process_frame
    await _frames(2)


## The question the flow has up, which is its own child window.
func _question() -> SaMessage:
    for child in _flow.get_children():
        var dialog := child as SaMessage
        if dialog != null and dialog.visible:
            return dialog
    return null


## The window's title as the front document leaves it.
func _window_title() -> String:
    _title.follow()
    return (Engine.get_main_loop() as SceneTree).root.title


## The front tab's text: off its name button once the bar shows, which is from
## two tabs on, and what that button is written with while it holds one.
func _front_tab() -> String:
    var texts := _tabs.bar.tab_texts()
    var at := _documents.surfaces.find(_documents.front)
    if at >= 0 and at < texts.size():
        return texts[at]
    return SaDocumentTabBar.tab_text(_front())


func _stroke(doc: SaDocument) -> void:
    var pos := Vector2(doc.canvas_size) * 0.5
    var radius := 20.0
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var compute := PaintKernel.compute()
    var region := Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0)
    var paint := SaPaintContext.for_region(doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, Color.RED, radius, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    doc.commit_stroke()


## Reads one opened picture by the three names the painter sees.
func _reads_as(file_name: String) -> void:
    var doc := _front()
    assert_false(doc.modified, "%s opens with nothing unsaved" % file_name)
    assert_eq(doc.file_path, "", "and with no file of its own, so Save asks where")
    assert_eq(_front_tab(), file_name, "Its tab reads the file's name with no star")
    var title := _window_title()
    assert_true(title.begins_with(file_name + " ("), "the title reads it with no star: %s" % title)
    assert_eq(SaDocumentLabel.new(doc).text, file_name, "and Info's Name row names the file")


func test_a_jpeg_and_a_png_open_under_their_names_and_close_asking_nothing() -> void:
    await _open(_path("harbour.jpg"))
    assert_eq(_documents.surfaces.size(), 1, "The JPEG takes the untouched document Sara starts with")
    _reads_as("harbour.jpg")
    await _open(_path("teapot.png"))
    assert_eq(_documents.surfaces.size(), 2, "The PNG opens in a tab of its own, not over the untouched JPEG")
    _reads_as("teapot.png")
    assert_eq(_tabs.bar.tab_texts(), ["harbour.jpg", "teapot.png"] as Array[String], "Two pictures read as two names")

    assert_true(_tabs.close_front(), "Ctrl+W runs on the PNG")
    assert_null(_question(), "and asks nothing")
    await _frames(3)
    assert_eq(_documents.surfaces.size(), 1, "The PNG's tab is gone")
    assert_eq(SaDocumentSource.path_of(_front()), _path("harbour.jpg"), "and the JPEG is in front")
    assert_true(_tabs.close_front(), "Ctrl+W runs on the JPEG")
    assert_null(_question(), "and asks nothing either")
    await _frames(3)
    assert_true(_flow.is_untouched(_front()), "The last close leaves a fresh untitled document")
    assert_eq(SaDocumentFiles.display_name(_front()), "Untitled", "which reads Untitled again")


func test_a_stroke_on_an_opened_picture_asks_on_close_and_save_asks_where_writing_nothing_at_the_picture() -> void:
    var picture := _path("harbour.jpg")
    var before := FileAccess.get_file_as_bytes(picture)
    await _open(picture)
    var doc := _front()
    _stroke(doc)
    await _frames(2)
    assert_true(doc.modified, "A stroke is unsaved work")
    assert_eq(_front_tab(), "harbour.jpg*", "and the tab carries the star")
    assert_true(_window_title().begins_with("harbour.jpg* ("), "so does the title")

    assert_true(_tabs.close_front(), "Ctrl+W runs on the painted picture")
    var question := _question()
    assert_not_null(question, "and asks whether to keep the stroke")
    var said := question.text_label.text if question != null else ""
    assert_true(said.contains("harbour.jpg"), "naming the picture: %s" % said)
    if question != null:
        question.buttons[SaDocumentFiles.PROMPT_CANCEL].pressed.emit()
    await _frames(2)
    assert_eq(_front(), doc, "Cancel keeps the document open")

    _flow.save_document(Callable(), doc)
    var picker := SaFilePicker.newest()
    assert_not_null(picker, "Save asks for a place")
    if picker != null:
        assert_eq(picker.mode, SaFilePicker.Mode.SAVE_FILE, "with a picker that writes a file")
        picker.cancel()
    SaSadFile.finish_saves()
    assert_eq(FileAccess.get_file_as_bytes(picture), before, "The picture on disk is as it was")
    assert_eq(DirAccess.get_files_at(_folder).size(), 2, "and no file was written beside it")
    assert_eq(doc.file_path, "", "The document still has no file of its own")
    assert_true(doc.modified, "and still has the stroke to lose")


## A `.sad` saved and a document rebuilt as a fresh one both stop reading the
## picture's name: the first goes by its own file, the second by none.
func test_the_picture_s_name_gives_way_to_a_sad_and_to_a_fresh_document() -> void:
    await _open(_path("harbour.jpg"))
    var doc := _front()
    doc.mark_saved(_path("harbour.sad"))
    assert_eq(SaDocumentFiles.display_name(doc), "harbour.sad", "A saved document goes by its own file")
    assert_eq(SaDocumentSource.path_of(doc), "", "and no longer by the picture")
    doc.mark_saved("")
    doc.reset_to_default(Vector2i(64, 64))
    assert_eq(SaDocumentFiles.display_name(doc), "Untitled", "A fresh document forgets the picture")


class StandIn:
    extends SaFilePicker.Platform

    func has_picker() -> bool:
        return true

    func show(_picker: SaFilePicker, _platform_filters: PackedStringArray, _parent_id: int, _answer: Callable) -> void:
        pass

    func show_dialog(dialog: Window) -> void:
        push_error("the stand-in has a picker, so no dialog should be shown: %s" % dialog)
