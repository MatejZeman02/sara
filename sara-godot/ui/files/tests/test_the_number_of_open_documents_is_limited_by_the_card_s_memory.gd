## The number of open documents is limited by the card's
## memory.
##
## The host is the tabs suite's: a first view from `render/main_canvas.gd`
## held by an `SaDocuments`, the `SaDocumentTabs` over both and the document
## flow, under the runner's scene by the names main gives them, so the
## documents opened hold the easels and layers they hold in Sara. The card's
## memory is stood in with a figure just above what the two open documents
## hold, so a third is refused on any machine the suite runs on.
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
## Every refusal said while a test ran.
var _refused := PackedStringArray()


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _saved_recent = SaSettings.recent_files()
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _documents = SaDocuments.new()
    tree.current_scene.set(&"documents", _documents)
    _host = Node.new()
    _host.name = "U327Host"
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
    DirAccess.copy_absolute(ProjectSettings.globalize_path(FIRST_SOURCE), _path("third.sad"))
    _refused = PackedStringArray()
    SaProblems.announce = false
    SaProblems.attach_sink(func(line: String, kind: SaProblems.Kind) -> void: _seen(line, kind))


func after_each() -> void:
    SaCardMemory.stand_in(-1)
    SaProblems.detach_sink()
    SaProblems.announce = true
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


func _seen(line: String, kind: SaProblems.Kind) -> void:
    if kind == SaProblems.Kind.REFUSAL:
        _refused.append(line)


func _paths() -> PackedStringArray:
    var paths := PackedStringArray()
    for surface in _documents.surfaces:
        paths.append(surface.get_document().file_path)
    return paths


## Each open document's path, whether it is modified, its size and its layers
## by name, which a refusal must leave as it found them.
func _picture() -> Array:
    var out := []
    for surface in _documents.surfaces:
        var doc := surface.get_document()
        var names := PackedStringArray()
        for layer: SaLayer in SaLayerStack.layers(doc):
            names.append(layer.name)
        out.append([doc.file_path, doc.modified, doc.canvas_size, names])
    return out


## Opens the first two files and stands the card's memory in just above what
## they hold: one MiB of room past the margin.
func _two_open_on_a_card_just_big_enough() -> void:
    await _open(_path("first.sad"))
    await _open(_path("second.sad"))
    var room := SaCardMemory.held() + (1 << 20)
    # A card of under ten GiB keeps the margin's floor of one GiB.
    SaCardMemory.stand_in(room + SaCardMemory.MARGIN_FLOOR)
    assert_eq(SaCardMemory.margin(SaCardMemory.total()), SaCardMemory.MARGIN_FLOOR, "The stood-in card keeps the margin's floor")


func test_a_third_file_is_refused_with_the_sentence_and_the_first_two_unchanged() -> void:
    await _two_open_on_a_card_just_big_enough()
    assert_eq(_paths(), PackedStringArray([_path("first.sad"), _path("second.sad")]), "Two documents open")
    var before := _picture()
    var held := SaCardMemory.held()
    var needed := SaCardMemory.for_sad(_path("third.sad"))
    assert_true(needed > (1 << 20), "The third needs more than the MiB of room left: %d bytes" % needed)
    _flow.open_path(_path("third.sad"))
    await (Engine.get_main_loop() as SceneTree).process_frame
    assert_eq(_refused.size(), 1, "The third is refused once: %s" % [_refused])
    var said := _refused[0] if not _refused.is_empty() else ""
    assert_eq(said, SaCardMemory.refusal(needed, held), "with the sentence")
    var budget := SaCardMemory.size_words(SaMemoryBudget.budget())
    assert_true(said.contains("a budget of %s of the card's" % budget), "naming the budget: %s" % said)
    assert_true(said.contains(SaCardMemory.size_words(SaCardMemory.total())), "and the card's memory")
    assert_true(said.contains("the open documents hold"), "what the open documents hold")
    assert_true(said.contains("this one needs"), "and what the new one needs")
    assert_eq(_paths(), PackedStringArray([_path("first.sad"), _path("second.sad")]), "No third tab opens")
    assert_eq(_picture(), before, "and the first two are as they were")
    assert_eq(_documents.front.get_document().file_path, _path("second.sad"), "the second still in front")


func test_a_new_document_is_refused_the_same_way() -> void:
    await _two_open_on_a_card_just_big_enough()
    var before := _picture()
    var tree := Engine.get_main_loop() as SceneTree
    assert_null(SaDocumentFiles.canvas_for_new(tree, null, Vector2i(1024, 1024)), "New has no canvas to build on")
    assert_eq(_refused.size(), 1, "and says why: %s" % [_refused])
    assert_eq(_picture(), before, "The two open documents are as they were")


func test_a_document_that_fits_opens() -> void:
    await _open(_path("first.sad"))
    await _open(_path("second.sad"))
    SaCardMemory.stand_in(SaCardMemory.held() + SaCardMemory.for_sad(_path("third.sad")) + SaCardMemory.MARGIN_FLOOR)
    await _open(_path("third.sad"))
    assert_eq(_refused.size(), 0, "Nothing is refused: %s" % [_refused])
    assert_eq(_documents.surfaces.size(), 3, "and the third opens beside the two")


func test_an_unread_card_refuses_nothing() -> void:
    SaCardMemory.stand_in(0)
    assert_eq(SaCardMemory.refusal(1 << 40), "", "A card whose memory reads as nothing sets no limit")


func test_a_sad_needs_its_canvas_and_its_chunks() -> void:
    var header := SaSadFile.header_at(_path("first.sad"))
    var size := Vector2i(int(header["width"]), int(header["height"]))
    var needed := SaCardMemory.for_sad(_path("first.sad"))
    assert_true(needed >= SaCardMemory.for_canvas(size), "At least the easel's canvas: %d" % needed)
    var painted := needed - SaCardMemory.for_canvas(size)
    assert_eq(painted % SaCardMemory.PAINTED_BYTES_PER_TEXEL, 0, "and whole painted texels beside it")
    assert_eq(SaCardMemory.for_sad(_path("missing.sad")), 0, "A file that does not read needs nothing")


## What `nvidia-smi` prints on Linux and on Windows alike, a name and MiB a card.
func test_nvidia_smi_s_lines_read_as_the_named_card_s_bytes() -> void:
    var one := "NVIDIA GeForce RTX 3090, 24576\n"
    assert_eq(SaCardMemory.nvidia_bytes(one, "anything"), 24576 << 20, "An only card is the card")
    var two := "NVIDIA GeForce GTX 1650, 4096\nNVIDIA GeForce RTX 3090, 24576\n"
    assert_eq(SaCardMemory.nvidia_bytes(two, "NVIDIA GeForce GTX 1650"), 4096 << 20, "Of two, the one Sara draws on")
    assert_eq(SaCardMemory.nvidia_bytes("", "x"), 0, "Nothing printed reads as nothing")


## What `reg query` prints for the display adapters of Windows.
func test_the_registry_s_lines_read_as_the_largest_adapter_s_bytes() -> void:
    var text := (
        "HKEY_LOCAL_MACHINE\\...\\0000\r\n"
        + "    HardwareInformation.qwMemorySize    REG_QWORD    0x200000000\r\n\r\n"
        + "HKEY_LOCAL_MACHINE\\...\\0001\r\n"
        + "    HardwareInformation.qwMemorySize    REG_QWORD    0x8000000\r\n"
    )
    assert_eq(SaCardMemory.registry_bytes(text), 8 << 30, "8 GiB, the larger adapter's")
    assert_eq(SaCardMemory.registry_bytes("ERROR: not found"), 0, "No adapter reads as nothing")


func test_new_from_clipboard_is_refused_the_same_way() -> void:
    await _two_open_on_a_card_just_big_enough()
    var before := _picture()
    var picture := Image.create_empty(512, 512, false, Image.FORMAT_RGBA8)
    var was: Callable = SaNewFromClipboard.desktop_picture
    SaNewFromClipboard.desktop_picture = func() -> SaDesktopPicture: return SaDesktopPicture.new(picture, "the engine")
    _flow.new_from_clipboard()
    SaNewFromClipboard.desktop_picture = was
    assert_eq(_refused.size(), 1, "The picture's document is refused: %s" % [_refused])
    assert_eq(_picture(), before, "and the two open documents are as they were")
