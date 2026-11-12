## A New Document template saved under a name a saved template already holds
## asks before it writes over it.
##
## Saving "Portrait", changing the size and saving "Portrait" again once lost
## the first template's size with no question. These save through the
## row's own field and button, read the file the first save wrote, and answer
## the question by its buttons. The check is on the file a name writes, so
## "a/b" and "a:b", which the sanitiser folds to one stem, ask too.
##
## The dialog is never added to the tree, for the reason
## `test_new_document_rows.gd` gives.
extends "res://tests/test_framework.gd"

## The dialog builds a colour space browser, which draws a gamut.
const REQUIRES_GPU := true

## Disposable, and under the data root as every folder a run writes is.
var _saved_root: String = SaDataRoot.path("test_templates_%d" % OS.get_process_id())

var _types: SaLayerTypeRegistry = null
var _kept_root: String = ""
var _kept_last: String = ""


func before_each() -> void:
    _types = SaLayerTypeRegistry.new()
    _types.register(SaLayerTypeDescriptor.paper())
    _types.register(SaLayerTypeDescriptor.canvas())
    _kept_root = NewDocumentTemplates.root
    _kept_last = SaSettings.last_template
    NewDocumentTemplates.root = _saved_root
    _empty_saved_root()


func after_each() -> void:
    _empty_saved_root()
    NewDocumentTemplates.root = _kept_root
    SaSettings.last_template = _kept_last
    _types = null


## Removes what a case saved, by hand rather than through the trash, so a run
## leaves nothing in the painter's.
func _empty_saved_root() -> void:
    if not DirAccess.dir_exists_absolute(_saved_root):
        return
    for file: String in DirAccess.get_files_at(_saved_root):
        DirAccess.remove_absolute(_saved_root.path_join(file))
    DirAccess.remove_absolute(_saved_root)


## Sets the size rows and saves *typed* by the row's field and button.
func _save_at(dialog: NewDocumentDialog, size: Vector2i, typed: String) -> void:
    dialog.page.row(&"width").drive(size.x)
    dialog.page.row(&"height").drive(size.y)
    dialog.template_saver.name_field.text = typed
    dialog.template_saver.save_button.pressed.emit()


## The size the template file *stem* holds.
func _size_in(stem: String) -> Vector2i:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_saved_root.path_join(stem + ".json")))
    var size: Array = (parsed as Dictionary)["size"]
    return Vector2i(int(size[0]), int(size[1]))


## The question the dialog put up, or null.
func _question(dialog: NewDocumentDialog) -> SaMessage:
    for child in dialog.get_children(true):
        if child is SaMessage and not child.is_queued_for_deletion():
            return child as SaMessage
    return null


## Presses the question's button that reads *label*.
func _press(question: SaMessage, label: String) -> void:
    for button in question.buttons:
        if button.text == label:
            button.pressed.emit()
            return
    assert_true(false, "The question has a %s button" % label)


func test_portrait_saved_twice_asks_and_cancel_keeps_the_first() -> void:
    var dialog := NewDocumentDialog.new(_types)
    _save_at(dialog, Vector2i(1200, 1600), "Portrait")
    assert_null(_question(dialog), "the first save asks nothing")
    assert_eq(_size_in("Portrait"), Vector2i(1200, 1600), "and writes the first size")

    _save_at(dialog, Vector2i(2400, 3200), "Portrait")
    var question := _question(dialog)
    assert_not_null(question, "the second save under the name asks")
    assert_true(dialog.replace_question == question, "and the dialog holds the question")
    var said := question.text_label.get_parsed_text()
    assert_true(said.contains("'Portrait'"), "naming the template: %s" % said)
    assert_eq(_size_in("Portrait"), Vector2i(1200, 1600), "the first template is unchanged while it asks")
    assert_eq(question.buttons[question._default_index].text, "Cancel", "Cancel is the default")

    _press(question, "Cancel")
    assert_eq(_size_in("Portrait"), Vector2i(1200, 1600), "Cancel writes nothing")
    assert_eq(dialog.template_saver.name_field.text, "Portrait", "and leaves the name in the field")
    assert_null(dialog.replace_question, "and no question waits")
    dialog.free()


func test_portrait_saved_twice_and_confirmed_writes_the_second_size() -> void:
    var dialog := NewDocumentDialog.new(_types)
    _save_at(dialog, Vector2i(1200, 1600), "Portrait")
    _save_at(dialog, Vector2i(2400, 3200), "Portrait")
    var question := _question(dialog)
    assert_not_null(question, "the second save asks")
    _press(question, "Replace")
    assert_eq(_size_in("Portrait"), Vector2i(2400, 3200), "Replace writes the second size")
    assert_eq(dialog.template, "saved:Portrait", "the row shows the template")
    assert_eq(dialog.template_saver.name_field.text, "", "and the field is emptied as after any save")
    assert_eq(DirAccess.get_files_at(_saved_root).size(), 1, "into the one file")
    dialog.free()


func test_two_names_the_sanitiser_folds_to_one_file_ask() -> void:
    assert_eq(SaPresetStore.sanitize_name("a/b"), SaPresetStore.sanitize_name("a:b"), "the two names share a stem")
    var dialog := NewDocumentDialog.new(_types)
    _save_at(dialog, Vector2i(800, 600), "a/b")
    assert_null(_question(dialog), "the first asks nothing")
    _save_at(dialog, Vector2i(640, 480), "a:b")
    var question := _question(dialog)
    assert_not_null(question, "the second, a different name for the same file, asks")
    var said := question.text_label.get_parsed_text()
    assert_true(said.contains("'a/b'"), "naming the template the file holds: %s" % said)
    assert_eq(_size_in(SaPresetStore.sanitize_name("a/b")), Vector2i(800, 600), "and the file is unchanged")
    _press(question, "Cancel")
    dialog.free()
