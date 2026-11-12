## Save As gives `noext` and `sketch.jpg` a `.sad` name, where a document named exactly
## as typed would leave a `.jpg` no other program could open.
##
## `sad_path_for` is held over such names, and the questions are
## driven through `choose_save_name` on a flow with no canvas behind it, whose
## *proceed* records the name it was handed instead of saving, so what is held
## is which name a save would write. A button is pressed by its own `pressed`
## signal, which is the index the question answers with.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

var _previous_embedding: bool = true
var _flow: SaDocumentFiles = null
var _folder := ""
var _chosen: Array[String] = []

## The skeleton's formats with the image formats module's after them, as the
## running app registers them, built again before each test.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _flow = SaDocumentFiles.new()
    EventBus.add_child(_flow)
    _folder = OS.get_temp_dir().path_join("sara-s64-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)
    _chosen.clear()


func after_each() -> void:
    if _flow != null:
        _flow.free()
        _flow = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding
    for file in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(file))
    DirAccess.remove_absolute(_folder)


func _choose(file: String) -> void:
    _flow.choose_save_name(_folder.path_join(file), func(path: String) -> void: _chosen.append(path))


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


func _touch(file: String) -> void:
    var handle := FileAccess.open(_folder.path_join(file), FileAccess.WRITE)
    handle.store_string("already here")
    handle.close()


func test_sad_path_for_keeps_a_sad_and_appends_to_anything_else() -> void:
    assert_eq(SaDocumentFiles.sad_path_for("/p/noext"), "/p/noext.sad", "No extension gets .sad")
    assert_eq(SaDocumentFiles.sad_path_for("/p/sketch.sad"), "/p/sketch.sad", "A .sad is kept")
    assert_eq(SaDocumentFiles.sad_path_for("/p/sketch.SAD"), "/p/sketch.SAD", "in any case")
    assert_eq(SaDocumentFiles.sad_path_for("/p/sketch.v2"), "/p/sketch.v2.sad", "An unrelated extension gets .sad after it")
    assert_eq(SaDocumentFiles.sad_path_for("/p/mismatch.jpg"), "/p/mismatch.jpg.sad", "and so does a picture's")


func test_picture_and_container_names_are_told_apart() -> void:
    for name: String in ["a.png", "a.jpg", "a.JPEG", "a.webp", "a.exr", "a.tif", "a.tiff", "a.ora", "a.bmp", "a.tga"]:
        assert_true(SaDocumentFiles.is_picture_name(name), "%s names a picture" % name)
    for name: String in ["noext", "a.sad", "a.v2", "a.txt"]:
        assert_false(SaDocumentFiles.is_picture_name(name), "%s does not" % name)


func test_no_extension_is_saved_as_a_sad_without_a_question() -> void:
    _choose("noext")
    assert_null(_question(), "Nothing is asked")
    assert_eq(_chosen, [_folder.path_join("noext.sad")], "noext is written as noext.sad")


func test_a_sad_name_is_kept_as_typed() -> void:
    _choose("sketch.Sad")
    assert_null(_question(), "Nothing is asked")
    assert_eq(_chosen, [_folder.path_join("sketch.Sad")], "the name is kept")


func test_a_picture_name_asks_and_add_sad_is_the_default() -> void:
    _choose("mismatch.jpg")
    var dialog := _question()
    assert_not_null(dialog, "A picture's extension asks")
    if dialog == null:
        return
    assert_true(dialog.text_label.text.contains("not a JPG"), "and says what it will not be: %s" % dialog.text_label.text)
    assert_true(dialog.text_label.text.contains("mismatch.jpg.sad"), "and the name it offers")
    assert_eq(dialog.buttons[SaDocumentFiles.NAME_ADD_SAD].text, "Add .sad", "Add .sad comes first")
    assert_eq(_chosen, [], "nothing is saved before it is answered")
    _press(SaDocumentFiles.NAME_ADD_SAD)
    assert_eq(_chosen, [_folder.path_join("mismatch.jpg.sad")], "Add .sad writes mismatch.jpg.sad")


func test_keep_the_name_writes_the_name_as_typed() -> void:
    _choose("mismatch.jpg")
    _press(SaDocumentFiles.NAME_KEEP)
    assert_eq(_chosen, [_folder.path_join("mismatch.jpg")], "Keep the name writes mismatch.jpg")


func test_cancel_and_escape_write_nothing() -> void:
    _choose("mismatch.jpg")
    _press(SaDocumentFiles.NAME_CANCEL)
    assert_eq(_chosen, [], "Cancel writes nothing")

    _choose("mismatch.png")
    var tree := Engine.get_main_loop() as SceneTree
    var said := SaMessage.capture_message(tree, {"close": "escape"})
    assert_true(said.ends_with("answered %d" % SaDocumentFiles.NAME_CANCEL), "Escape answers Cancel: %s" % said)
    assert_eq(_chosen, [], "and writes nothing")


func test_an_appended_name_that_exists_asks_with_cancel_the_default() -> void:
    _touch("noext.sad")
    _choose("noext")
    var dialog := _question()
    assert_not_null(dialog, "The appended name exists, so it asks")
    if dialog == null:
        return
    assert_true(dialog.text_label.text.contains("noext.sad already exists"), "and names it: %s" % dialog.text_label.text)
    assert_eq(_chosen, [], "nothing is saved before it is answered")
    _press(SaDocumentFiles.REPLACE_CANCEL)
    assert_eq(_chosen, [], "Cancel writes nothing")

    _choose("noext")
    _press(SaDocumentFiles.REPLACE)
    assert_eq(_chosen, [_folder.path_join("noext.sad")], "Replace writes over it")


func test_add_sad_over_an_existing_name_asks_again() -> void:
    _touch("mismatch.jpg.sad")
    _choose("mismatch.jpg")
    _press(SaDocumentFiles.NAME_ADD_SAD)
    assert_eq(_chosen, [], "The appended name exists, so nothing is written yet")
    var dialog := _question()
    assert_not_null(dialog, "and the replace question is up")
    _press(SaDocumentFiles.REPLACE)
    assert_eq(_chosen, [_folder.path_join("mismatch.jpg.sad")], "Replace writes mismatch.jpg.sad")


## The picker asked about the name as typed, so a kept name is not asked again.
func test_a_kept_name_that_exists_is_not_asked_about_twice() -> void:
    _touch("mismatch.jpg")
    _choose("mismatch.jpg")
    _press(SaDocumentFiles.NAME_KEEP)
    assert_eq(_chosen, [_folder.path_join("mismatch.jpg")], "Keep the name writes at once")
