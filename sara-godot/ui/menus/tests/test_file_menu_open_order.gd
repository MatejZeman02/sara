## File > Open puts its picker up before it asks about unsaved changes.
##
## This reads the source rather than driving the menu, and the reason is worth
## writing down: every branch of `SaDocumentFiles`, the flow the File menu runs,
## that could tell the two orders apart needs a live
## document, which needs a canvas, which needs
## `get_tree().current_scene` to be Sara's own main scene. No suite in `tests/`
## stubs that, and one built for this would be a second main rather than a test.
## With no document `confirm_discard` calls its callable at once, so the old
## order and the new one behave identically in anything a headless suite can
## reach.
##
## So the order itself is proved by `scenarios/file-dialog-order.json` on the
## running app, and what is here is the regression guard: the wiring the old
## bug was, spelled out, so putting it back fails a run rather than a screenshot.
extends "res://tests/test_framework.gd"

const MENU_PATH := "res://ui/menus/file_menu.gd"
## Where the picker and the question live.
const FILES_PATH := "res://ui/files/sa_document_files.gd"
## Where the File menu's rows are commands since the menus became lists of them.
const COMMANDS_PATH := "res://ui/menus/sa_menu_commands.gd"


func _source(path: String = MENU_PATH) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""


## The body of `func <name>`, up to the blank line before the next declaration.
func _body_of(source: String, name: String) -> String:
    var at := source.find("func %s(" % name)
    if at == -1:
        return ""
    var end := source.find("\nfunc ", at + 1)
    return source.substr(at, (end - at) if end != -1 else -1)


func test_the_open_row_opens_the_picker_rather_than_the_question() -> void:
    var source := _source()
    assert_true(not source.is_empty(), "The File menu's script is on disk")
    assert_true(source.contains('[ID_OPEN, &"file_open"]'), "The Open row is the file_open command")

    # The command hands the action to the flow, whose own branch answers it.
    var commands := _body_of(_source(COMMANDS_PATH), "_file_action")
    assert_true(commands.contains("files.run_action(action)"), "whose handler runs the flow's action")
    var dispatch := _body_of(_source(FILES_PATH), "run_action")
    var open_at := dispatch.find('&"file_open":')
    var save_at := dispatch.find('&"file_save":')
    assert_true(open_at != -1 and save_at > open_at, "The Open action is answered above the Save one")

    var open_branch := dispatch.substr(open_at, save_at - open_at)
    assert_true(open_branch.contains("open_with_dialog()"), "and it opens the picker")
    assert_false(
        open_branch.contains("confirm_discard"),
        "with no unsaved-changes question in front of it, which was 18:40's whole complaint"
    )


func test_the_chosen_file_opens_with_no_question() -> void:
    var source := _source(FILES_PATH)
    var opener := _body_of(source, "open_with_dialog")
    assert_true(opener.contains(", _open_chosen)"), "The picker's answer goes through the chosen file's handler")
    var chosen := _body_of(source, "_open_chosen")
    assert_true(chosen.contains("open_path(path)"), "which opens the file that was chosen")


## No chosen file is asked about, an image included.
##
## A file opens in a tab of its own, or in the untitled and untouched document, so it throws nothing away and
## there is nothing to ask. This is the assertion that keeps the question from
## coming back in front of an open.
func test_no_chosen_file_is_asked_about() -> void:
    var chosen := _source_lines_of("_open_chosen")
    assert_false(chosen.contains("confirm_discard"), "No question is asked")
    assert_false(chosen.contains("is_image_path"), "for an image as little as for a document")

    assert_true(SaImageImport.is_image_path("a-painting.jpg"), "A jpg is an image")
    assert_false(SaImageImport.is_image_path("a-painting.sad"), "and a Sara document is not")


func _source_lines_of(name: String) -> String:
    return _body_of(_source(FILES_PATH), name)
