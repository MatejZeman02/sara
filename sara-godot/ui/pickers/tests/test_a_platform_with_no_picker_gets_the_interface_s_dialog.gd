## A file picker on a platform with no picker of its own gets
## the engine's dialog from the interface, through `SaDialogsInHand`, and a host
## with nothing attached says so in the corner rather than doing nothing.
##
extends "res://tests/test_framework.gd"

## The purpose the folder test keeps a folder for, forgotten after each test.
const _PURPOSE: StringName = &"test_purpose"

## Where the folder test makes its folder, under the suites' data root.
var _scratch: String = SaDataRoot.path("test_file_picker")

var _platform_before: SaFilePicker.Platform = null
var _owner_before: Object = null
var _abr_before: Callable = Callable()
var _file_dialog_before: Callable = Callable()
var _refused: Array[String] = []


func before_each() -> void:
    _platform_before = SaFilePicker.platform
    SaFilePicker.platform = StandIn.new()
    _owner_before = SaDialogsInHand._owner
    _abr_before = SaDialogsInHand._abr
    _file_dialog_before = SaDialogsInHand._file_dialog
    SaDialogsInHand.attach(self, SaPickers.open_abr, SaPickers.file_dialog)
    _refused.clear()
    EventBus.paint_refused.connect(_on_refused)


func after_each() -> void:
    EventBus.paint_refused.disconnect(_on_refused)
    var cancelled := 0
    while SaFilePicker.newest() != null and cancelled < 100:
        SaFilePicker.newest().cancel()
        cancelled += 1
    assert_null(SaFilePicker.newest(), "A cancelled picker goes away")
    SaFilePicker.platform = _platform_before
    SaDialogsInHand.detach(self)
    if _owner_before != null:
        SaDialogsInHand.attach(_owner_before, _abr_before, _file_dialog_before)
    SaSettings.set_module_preference(SaFilePicker.SETTINGS_ID, _PURPOSE, null)
    if DirAccess.dir_exists_absolute(_scratch):
        DirAccess.remove_absolute(_scratch)


func _on_refused(sentence: String) -> void:
    _refused.append(sentence)


## Where the platform has no picker the engine's dialog stands in, under the node
## that asked, and is freed by its answer. A dialog that asked for the platform's
## window never announced a change of visibility, so each caller once freed its
## own only on a choice or a cancel, and this is where that went.
func test_a_platform_with_no_picker_gets_the_engines_dialog_freed_by_its_answer() -> void:
    var host := Node.new()
    var told: Array = []
    var picker := SaFilePicker.open(host, SaFilePicker.Mode.OPEN_DIR, PackedStringArray(), told.append, "Choose a folder")
    var dialog := picker.fallback as FileDialog
    assert_not_null(dialog, "the engine's dialog is built")
    if dialog == null:
        host.free()
        return
    assert_eq(dialog.get_parent(), host, "under the node that asked")
    assert_eq(dialog.file_mode, FileDialog.FILE_MODE_OPEN_DIR, "for the mode asked")
    assert_eq(dialog.title, "Choose a folder", "with the title asked")
    assert_eq((SaFilePicker.platform as StandIn).dialogs, [dialog], "and shown through the platform")
    # Godot 4.7.2 hides the dialog before it answers.
    dialog.visible = false
    dialog.visibility_changed.emit()
    dialog.dir_selected.emit("/home/painter/art")
    assert_eq(told, ["/home/painter/art"], "its answer reaches the caller")
    assert_true(dialog.is_queued_for_deletion(), "and frees it")

    var cancelled := SaFilePicker.open(host, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(), told.append)
    (cancelled.fallback as FileDialog).canceled.emit()
    assert_true(cancelled.fallback.is_queued_for_deletion(), "a cancel frees it too")
    assert_false(cancelled.is_open(), "and puts the picker away")
    assert_true(_refused.is_empty(), "with nothing said in the corner")
    host.free()


func test_the_engine_dialog_starts_in_the_purposes_folder() -> void:
    DirAccess.make_dir_recursive_absolute(_scratch)
    SaSettings.set_module_preference(SaFilePicker.SETTINGS_ID, _PURPOSE, _scratch)
    var host := Node.new()
    var picker := SaFilePicker.open(host, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(), Callable(), "", Callable(), _PURPOSE)
    assert_eq((picker.fallback as FileDialog).current_dir, _scratch, "where there is no platform picker")
    host.free()


func test_a_host_with_nothing_attached_says_so_in_the_corner() -> void:
    SaDialogsInHand.detach(self)
    var host := Node.new()
    var told: Array = []
    var cancels: Array = []
    var picker := SaFilePicker.open(
        host, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(), told.append, "", cancels.append.bind(true)
    )
    assert_null(picker.fallback, "No dialog is built")
    assert_true(host.get_children().is_empty(), "and nothing is put under the host")
    assert_eq(_refused, ["There is no file picker here to open."], "The corner says so")
    assert_false(picker.is_open(), "and the picker is put away")
    assert_eq(cancels, [true], "told to its caller as a cancel")
    assert_true(told.is_empty(), "with nothing chosen")
    host.free()


## The platform's side with no picker and no window: it keeps the dialogs it
## was asked to show.
class StandIn:
    extends SaFilePicker.Platform

    var dialogs: Array[Window] = []

    func has_picker() -> bool:
        return false

    func show(_picker: SaFilePicker, _platform_filters: PackedStringArray, _parent_id: int, _answer: Callable) -> void:
        push_error("the stand-in has no picker, so the platform's should never be asked for")

    func show_dialog(dialog: Window) -> void:
        dialogs.append(dialog)
