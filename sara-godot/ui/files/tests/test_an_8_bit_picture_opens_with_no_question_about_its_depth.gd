## An 8-bit picture opens with no question about its depth.
##
## The open question is never asked of a JPEG or 8-bit PNG,
## "The file does not say whether it is 16-bit or 32-bit float", since such a file
## holds neither. Here a JPEG, an 8-bit PNG and a WebP are opened through
## `open_path`, which hands a picture to `_open_image_as_document`, on the
## preferences a fresh profile has, and each lands with no window at the
## remembered depth. An EXR still asks, and so does the JPEG once Preferences
## asks every time, in the sentence that says it holds 8 bits.
##
## The flow is built in the tree the way the Android picker suite builds it, so the window
## that asks is a real child of the flow and its being shown is what is read.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const ViewScript := preload("res://render/main_canvas.gd")

const PNG := "res://tests/data/import_gradient.png"
const JPEG := "res://tests/data/import_gradient.jpg"
const EXR := "res://tests/data/import_linear.exr"
## The size of both gradients, which is not the size of the easel they open on.
const PICTURE_SIZE := Vector2i(300, 200)
## The part of the open question's sentence an 8-bit file is told.
const EIGHT_BIT_WORDS := "It holds 8 bits a channel"

var _documents: SaDocuments = null
var _host: Node = null
var _first: Control = null
var _tabs: SaDocumentTabs = null
var _flow: SaDocumentFiles = null
var _folder := ""
var _was_embedding := false
var _saved_recent: Array = []
var _was: Dictionary = {}


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    _was = {
        "ask_when_opening": SaSettings.ask_when_opening,
        "ask_eight_bit_when_opening": SaSettings.ask_eight_bit_when_opening,
        "import_depth": SaSettings.import_depth,
    }
    # A fresh profile's answers, read off a bare settings object rather than
    # written out here, so a changed default is what this suite tests.
    var bare := SaSettingsValues.new()
    SaSettings.ask_when_opening = bare.ask_when_opening
    SaSettings.ask_eight_bit_when_opening = bare.ask_eight_bit_when_opening
    bare.free()
    # The opposite of the default, so a document that ignored the remembered
    # depth would land at the default and be seen.
    SaSettings.import_depth = "f32"
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _documents = SaDocuments.new()
    tree.current_scene.set(&"documents", _documents)
    _host = Node.new()
    _host.name = "U498Host"
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
    var picture := Image.load_from_file(ProjectSettings.globalize_path(PNG))
    picture.save_webp(_webp())


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var dialog := _dialog()
    if dialog != null:
        dialog.hide()
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
    for key: String in _was:
        SaSettings.set(key, _was[key])
    for file in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(file))
    DirAccess.remove_absolute(_folder)
    for path: String in SaSettings.recent_files():
        SaSettings.remove_recent_file(str(path))
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))


func _webp() -> String:
    return _folder.path_join("gradient.webp")


func _dialog() -> SaImportFitDialog:
    if _flow == null:
        return null
    return _flow.get_node_or_null(NodePath("ImportFitDialog")) as SaImportFitDialog


func _asked() -> bool:
    var dialog := _dialog()
    return dialog != null and dialog.visible


## Opens *path* through File > Open's own call, and gives a window a frame to
## show, so a question asked is seen.
func _open(path: String) -> SaDocument:
    _flow.open_path(path)
    await (Engine.get_main_loop() as SceneTree).process_frame
    return _documents.front.get_document()


func test_a_fresh_profile_asks_about_floats_and_not_about_bytes() -> void:
    assert_true(SaSettings.ask_when_opening, "A fresh profile asks about a float file")
    assert_false(SaSettings.ask_eight_bit_when_opening, "and does not ask every time")
    assert_eq(SaSettingsKeys.place_of(&"ask_eight_bit_when_opening").size(), 2, "and the switch has a place in the file")
    assert_false(SaOpenDepth.asks_for(SaImageImport.read(JPEG)), "so a JPEG is not asked about")
    assert_true(SaOpenDepth.asks_for(SaImageImport.read(EXR)), "and an EXR is")


func test_a_jpeg_opens_with_no_question_at_the_remembered_depth() -> void:
    var doc := await _open(JPEG)
    assert_false(_asked(), "No window asked about the JPEG")
    assert_eq(doc.canvas_size, PICTURE_SIZE, "and it became the document")
    assert_eq(doc.color_space.depth, SaColorSpace.Depth.F32, "at the remembered depth")
    assert_eq(String(doc.color_space.id), String(SaImageImport.convention_for(JPEG).id), "in its format's gamut")


func test_an_8_bit_png_opens_with_no_question_at_the_remembered_depth() -> void:
    var doc := await _open(PNG)
    assert_false(_asked(), "No window asked about the 8-bit PNG")
    assert_eq(doc.canvas_size, PICTURE_SIZE, "and it became the document")
    assert_eq(doc.color_space.depth, SaColorSpace.Depth.F32, "at the remembered depth")


func test_a_webp_opens_with_no_question_at_the_remembered_depth() -> void:
    assert_eq(SaImageImport.depth_for(SaImageImport.read(_webp())), -1, "The WebP holds bytes")
    var doc := await _open(_webp())
    assert_false(_asked(), "No window asked about the WebP")
    assert_eq(doc.canvas_size, PICTURE_SIZE, "and it became the document")
    assert_eq(doc.color_space.depth, SaColorSpace.Depth.F32, "at the remembered depth")


func test_a_float_file_still_asks() -> void:
    var before := _documents.front.get_document()
    await _open(EXR)
    assert_true(_asked(), "The EXR is asked about")
    assert_true(_dialog().show_next_time, "with its Show this next time switch on")
    assert_false(EIGHT_BIT_WORDS in _dialog()._size_label.text, "and not in the 8-bit sentence")
    assert_true(_documents.front.get_document() == before, "and nothing opens before it is answered")


func test_asking_every_time_asks_about_a_jpeg_in_the_8_bit_words() -> void:
    SaSettings.ask_eight_bit_when_opening = true
    await _open(JPEG)
    assert_true(_asked(), "With Preferences asking every time the JPEG is asked about")
    assert_true(EIGHT_BIT_WORDS in _dialog()._size_label.text, "in the sentence that says it holds 8 bits")
    assert_eq(_dialog().chosen_depth(), SaColorSpace.Depth.F32, "on the remembered depth")


func test_the_question_switched_off_asks_about_nothing() -> void:
    SaSettings.ask_eight_bit_when_opening = true
    SaSettings.ask_when_opening = false
    var doc := await _open(JPEG)
    assert_false(_asked(), "Show this next time turned off asks about no picture")
    assert_eq(doc.canvas_size, PICTURE_SIZE, "and the JPEG opened at once")
