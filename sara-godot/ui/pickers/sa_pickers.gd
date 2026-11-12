## The windows core asks the interface for through `SaDialogsInHand`: the
## chooser Load Tip opens on an `.abr`, and the engine's file dialog a file
## picker stands in with on a platform with no picker of its own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Both were once built in core, and `core` never names `ui`.
## [method attach] attaches them when the interface starts and takes them away
## when its host leaves the tree. It builds no window until one is asked for, so
## it is no `install` line of the boot's, each of which puts up a window that
## `test_filter_dialog_starts_hidden` asks after.
class_name SaPickers
extends RefCounted


## Attaches the chooser and the file dialog to `SaDialogsInHand`, owned by
## *host*, and takes them away when *host* leaves the tree.
static func attach(host: Node) -> void:
    if host == null:
        return
    if SaDialogsInHand._owner == host:
        return
    SaDialogsInHand.attach(host, open_abr, file_dialog)
    host.tree_exiting.connect(func() -> void: SaDialogsInHand.detach(host), CONNECT_ONE_SHOT)


## Opens the chooser on the collection at *path* over the main window.
static func open_abr(path: String, on_chosen: Callable) -> void:
    SaAbrChooser.open(path, on_chosen)


## The engine's own dialog for *picker*, under the node that asked or the root
## when that node has gone, answering through the picker's [method
## SaFilePicker.choose] and [method SaFilePicker.cancel]. Null where there is no
## root to stand under, which the picker takes as a cancel.
static func file_dialog(picker: SaFilePicker) -> Window:
    var parent: Node = picker.host if is_instance_valid(picker.host) else null
    if parent == null:
        var loop := Engine.get_main_loop() as SceneTree
        parent = loop.root if loop != null else null
    if parent == null:
        return null
    var dialog := FileDialog.new()
    dialog.access = FileDialog.ACCESS_FILESYSTEM
    dialog.file_mode = picker.mode as FileDialog.FileMode
    dialog.filters = picker.filters
    dialog.title = picker.title
    if not picker.folder.is_empty():
        dialog.current_dir = picker.folder
    parent.add_child(dialog)
    dialog.file_selected.connect(func(path: String) -> void: picker.choose(PackedStringArray([path])))
    dialog.files_selected.connect(picker.choose)
    dialog.dir_selected.connect(func(path: String) -> void: picker.choose(PackedStringArray([path])))
    dialog.canceled.connect(picker.cancel)
    # Hidden by anything else, the title bar's close among them, is put away,
    # a frame late. Godot 4.7.2.stable (ed1daf0bf, as measured) hides the
    # dialog first and emits `file_selected` after, so a cancel made on the hide
    # itself would close the picker before the choice reached it. A choice or a
    # cancel that comes in that frame has closed the picker already, and the
    # late cancel finds it closed and says nothing.
    dialog.visibility_changed.connect(
        func() -> void:
            if is_instance_valid(dialog) and not dialog.visible:
                _cancel_next_frame(picker)
    )
    return dialog


## Cancels *picker* on the next frame, or at the end of this one when there is
## no tree to count frames by.
static func _cancel_next_frame(picker: SaFilePicker) -> void:
    var loop := Engine.get_main_loop() as SceneTree
    if loop == null:
        picker.cancel.call_deferred()
        return
    loop.process_frame.connect(func() -> void: picker.cancel(), CONNECT_ONE_SHOT)
