## With embedded subwindows off, the Welcome window,
## New Document, Preferences and every other `SaDialogWindow` sank behind the
## main window on Windows and had a taskbar entry of its own.
##
## The cause: Godot 4.7 on Windows gives a transient window an owner
## only when it is exclusive as well, and a dialog is transient and not
## exclusive. So `SaDialogWindow` now asks the display server for that flag
## after every show through the same `DockerWindow.hold_above_transient_parent`
## the dockers use. What this suite pins is the half that holds on every
## desktop: a shown dialog is held by the window it is transient to, let go on
## a hide and held again on the next show, and `Window.exclusive` is left as
## the dialog set it. The owner Windows sets from that can only be proved on the
## running app.
##
## The dialog is embedded here, the way the docker-hold suite embeds its docker, because
## a dialog that maps an OS window hangs a headless run.
@tool
extends "res://tests/test_framework.gd"


class StubDialog:
    extends SaDialogWindow

    func _init() -> void:
        _init_dialog("StubDialog", "Stub", Vector2i(320, 200), Vector2i(200, 120))


var _host: Node = null
var _previous_embedding: bool = true
var _previous_owner_rule: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    _previous_owner_rule = DockerWindow.owner_needs_exclusive
    tree.root.gui_embed_subwindows = true
    # The Windows path, so a run on any desktop walks the branch the fix added.
    DockerWindow.owner_needs_exclusive = true
    _host = Node.new()
    _host.name = "W2DialogHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    DockerWindow.owner_needs_exclusive = _previous_owner_rule
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


func _dialog() -> SaDialogWindow:
    var dialog := StubDialog.new()
    dialog.visible = false
    _host.add_child(dialog)
    return dialog


func test_a_hidden_dialog_is_held_by_nothing() -> void:
    var dialog := _dialog()
    assert_false(dialog.visible, "The dialog starts hidden")
    assert_null(dialog.held_by, "and a hidden dialog is held by no window")


func test_a_shown_dialog_is_held_by_the_main_window() -> void:
    var dialog := _dialog()
    var root := (Engine.get_main_loop() as SceneTree).root
    dialog.show()
    assert_true(dialog.transient, "A dialog is transient")
    assert_eq(DockerWindow.transient_parent_window(dialog), root, "to the main window")
    assert_eq(dialog.held_by, root, "and a shown dialog is held above it")


func test_the_hold_comes_back_after_a_hide_and_a_show() -> void:
    var dialog := _dialog()
    var root := (Engine.get_main_loop() as SceneTree).root
    dialog.show()
    dialog.hide()
    assert_null(dialog.held_by, "A hide lets the dialog go, since its OS window is gone")
    dialog.show()
    assert_eq(dialog.held_by, root, "and the next show holds it above the main window again")


func test_the_hold_leaves_the_scene_side_modality_alone() -> void:
    var dialog := _dialog()
    dialog.show()
    dialog.hide()
    dialog.show()
    assert_false(dialog.exclusive, "A dialog that was not exclusive does not become exclusive in the scene")


func test_the_dockers_and_the_dialogs_share_one_hold() -> void:
    var dialog := _dialog()
    dialog.show()
    assert_eq(
        DockerWindow.hold_above_transient_parent(dialog),
        dialog.held_by,
        "The dialog's hold is the dockers' own, answering the same window"
    )
