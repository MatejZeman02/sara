## Delete asks first, and the file it deletes is kept.
##
## The Colour Themes page's Delete needs a confirmation dialog, because a palette
## the painter made is otherwise lost at one press. The question is half the
## fix and `SaTheme.delete_custom` moving the `.tres` into
## `themes/deleted/` rather than removing it is the other half.
##
## Driven through the page's own handler, with the page in the tree, because
## the question is a `Window` and the host it is added to has to be in one.
## What a painter sees is `scenarios/delete-asks-first-and-keeps-the-file.json`.
extends "res://tests/test_framework.gd"

## The fork every case here makes, and the file name it lands under.
const DOOMED_NAME := "O6 Doomed"
const DOOMED_ID := "custom:o6-doomed"
const DOOMED_FILE := "o6-doomed.tres"

var _saved_theme: String = "default"
var _saved_setting: String = "default"


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _saved_setting = SaSettings.theme_name
    _sweep()


func after_each() -> void:
    _sweep()
    SaSettings.theme_name = _saved_setting
    SaTheme.use_named(_saved_theme)


## Everything this suite can have written, out of the settings folder the gate
## shares with the captures: the fork itself, and the copies of it that the
## deleted folder is now meant to keep.
func _sweep() -> void:
    var palettes := DirAccess.open(SaTheme.custom_dir())
    if palettes != null:
        for file_name in palettes.get_files():
            if file_name.begins_with("o6-doomed"):
                palettes.remove(file_name)
    var kept := DirAccess.open(SaTheme.deleted_dir())
    if kept != null:
        for file_name in kept.get_files():
            if file_name.begins_with("o6-doomed"):
                kept.remove(file_name)


func test_delete_asks_before_it_deletes_and_cancel_leaves_the_palette() -> void:
    var built := _build()
    if built.is_empty():
        return
    var page: SaColorThemesPage = built["page"]

    assert_eq(SaTheme.palette_id, DOOMED_ID, "The fork is the active palette")
    assert_false(page.delete_button.disabled, "and Delete is offered for it")
    page._on_delete()

    var question := SaMessage.live_dialog(built["tree"])
    assert_not_null(question, "Pressing Delete puts a question up rather than deleting")
    if question != null:
        assert_eq(question.title, "Delete palette", "titled for what it is about to do")
        assert_true(question.text_label.text.contains(DOOMED_NAME), "and it names the palette: %s" % question.text_label.text)
        assert_eq(question.buttons.size(), 2, "Cancel and Delete")
        assert_eq(question.buttons[0].text, "Cancel", "Cancel first, so the safe answer is the default")
        assert_eq(question.buttons[1].text, "Delete", "and Delete second")
        assert_true(
            FileAccess.file_exists(SaTheme.custom_path(DOOMED_ID)), "and the file is still there while the question is up"
        )
        question.buttons[0].pressed.emit()

    assert_true(FileAccess.file_exists(SaTheme.custom_path(DOOMED_ID)), "Cancel leaves the file exactly where it was")
    assert_true(SaTheme.custom_ids().has(DOOMED_ID), "and the dropdown still offers it")
    assert_eq(SaTheme.palette_id, DOOMED_ID, "and it is still the active palette")
    _tear_down(built)


func test_answering_delete_moves_the_file_rather_than_removing_it() -> void:
    var built := _build()
    if built.is_empty():
        return
    var page: SaColorThemesPage = built["page"]

    page._on_delete()
    var question := SaMessage.live_dialog(built["tree"])
    assert_not_null(question, "The question is up again")
    if question != null:
        question.buttons[1].pressed.emit()

    assert_false(
        FileAccess.file_exists(SaTheme.custom_path(DOOMED_ID)), "Answering Delete takes the file out of the palettes folder"
    )
    assert_true(
        FileAccess.file_exists(SaTheme.deleted_dir().path_join(DOOMED_FILE)),
        "and puts it under the deleted folder, where a painter can move it back by hand"
    )
    assert_false(SaTheme.custom_ids().has(DOOMED_ID), "A palette in that subfolder is off the dropdown")
    assert_eq(SaTheme.palette_id, "default", "and the interface falls back to the default")
    _tear_down(built)


## A pick during the question. The answer arrives on a later frame and neither window is exclusive, so
## a painter can pick another palette on the dropdown while the question is up.
## The pick is `SaSettings.theme_name`, the same write the dropdown makes, and
## the answer must not overwrite it with the default whatever was live. The file
## that goes is still the one the question named, and the palette on screen is
## the one the painter picked.
func test_a_palette_picked_while_the_question_is_up_survives_the_answer() -> void:
    var built := _build()
    if built.is_empty():
        return
    var page: SaColorThemesPage = built["page"]

    assert_eq(SaTheme.palette_id, DOOMED_ID, "The fork is the active palette")
    page._on_delete()
    var question := SaMessage.live_dialog(built["tree"])
    assert_not_null(question, "The question is up")

    SaSettings.theme_name = "krita"
    assert_eq(SaTheme.palette_id, "krita", "A pick under the question puts Krita Grey on screen")

    if question != null:
        question.buttons[1].pressed.emit()

    assert_false(
        FileAccess.file_exists(SaTheme.custom_path(DOOMED_ID)), "Answering Delete still moves the palette the question named"
    )
    assert_true(FileAccess.file_exists(SaTheme.deleted_dir().path_join(DOOMED_FILE)), "into the deleted folder")
    assert_eq(SaTheme.palette_id, "krita", "and the palette on screen is the one the painter picked")
    assert_eq(SaSettings.theme_name, "krita", "and so is the one the profile keeps")
    _tear_down(built)


## The reason the deleted folder numbers rather than writes over: two palettes
## of the same name, deleted one after the other, are two files in there. A
## folder that keeps only the last one deleted is no safer than removing.
func test_a_second_palette_of_the_same_name_does_not_overwrite_the_first() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    var first := Color(0.9, 0.1, 0.1, 1.0)
    var second := Color(0.1, 0.2, 0.9, 1.0)

    _fork_and_delete(first)
    _fork_and_delete(second)

    var kept_first := _load_deleted(DOOMED_FILE)
    var kept_second := _load_deleted("o6-doomed-2.tres")
    assert_not_null(kept_first, "The first deletion is still under the deleted folder")
    assert_not_null(kept_second, "and the second is beside it, numbered")
    if kept_first != null:
        assert_true(kept_first.accent_primary.is_equal_approx(first), "with the colours the first palette had")
    if kept_second != null:
        assert_true(kept_second.accent_primary.is_equal_approx(second), "and the second its own")


## A shipped palette has no file of the painter's to keep, and Delete is
## disabled over one, so the handler asks nothing rather than putting a question
## up that can only answer no.
func test_a_shipped_palette_asks_nothing() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    SaTheme.use_named("krita")
    var page := SaColorThemesPage.new()
    page._on_delete()
    assert_null(SaMessage.live_dialog(tree), "No fork, no question")
    assert_eq(SaTheme.palette_id, "krita", "and the shipped palette is still active")
    page.free()


## Forks the default under the doomed name, paints one colour into it so the
## file on disk can be told apart, and answers Delete through the page's own
## handler.
func _fork_and_delete(accent: Color) -> void:
    SaTheme.use_named("default")
    var id := SaTheme.fork(DOOMED_NAME)
    assert_eq(id, DOOMED_ID, "The name is the file name")
    assert_true(SaTheme.set_color("accent_primary", accent), "and a swatch writes into it")
    var page := SaColorThemesPage.new()
    page._on_delete_answered(SaColorThemesPage.DELETE_CONFIRM, id)
    page.free()


func _load_deleted(file_name: String) -> SaPalette:
    var path := SaTheme.deleted_dir().path_join(file_name)
    if not FileAccess.file_exists(path):
        return null
    return ResourceLoader.load(path, "SaPalette", ResourceLoader.CACHE_MODE_IGNORE) as SaPalette


## A page in the tree with a fork of its own selected, and the subwindows
## embedded so the question does not map an OS window and block the run.
func _build() -> Dictionary:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree, for the window the question opens in")
    if tree == null:
        return {}

    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "O6DeleteTestHost"
    EventBus.add_child(host)

    SaTheme.use_named("default")
    var page := SaColorThemesPage.new()
    host.add_child(page)
    SaTheme.fork(DOOMED_NAME)

    return {"tree": tree, "host": host, "page": page, "embedded": embedded}


func _tear_down(built: Dictionary) -> void:
    var tree: SceneTree = built["tree"]
    # The question frees itself on the answer, and it does so deferred, so it is
    # still in the tree when the assertions above run and gone a frame later.
    var left := SaMessage.live_dialog(tree)
    if left != null:
        left.queue_free()
    (built["host"] as Node).free()
    tree.root.gui_embed_subwindows = bool(built["embedded"])
