## Godot 4.7.2 hides its file dialog before it emits the
## choice, so the picker on the engine's dialog cancels a frame after a hide and
## never on the hide itself. Every test here hides the dialog first and answers
## after, as measured.
extends "res://tests/test_framework.gd"

## The purpose every picker here keeps its folder under, forgotten after each test.
const _PURPOSE: StringName = &"test_purpose"

var _platform_before: SaFilePicker.Platform = null
var _owner_before: Object = null
var _abr_before: Callable = Callable()
var _file_dialog_before: Callable = Callable()


func before_each() -> void:
    _platform_before = SaFilePicker.platform
    SaFilePicker.platform = StandIn.new()
    _owner_before = SaDialogsInHand._owner
    _abr_before = SaDialogsInHand._abr
    _file_dialog_before = SaDialogsInHand._file_dialog
    SaDialogsInHand.attach(self, SaPickers.open_abr, SaPickers.file_dialog)


func after_each() -> void:
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


## A picker on the engine's dialog for *mode*, whose answers land in *told* and
## whose cancels land in *cancels*.
func _open(host: Node, mode: SaFilePicker.Mode, filters: PackedStringArray, told: Array, cancels: Array) -> SaFilePicker:
    return SaFilePicker.open(host, mode, filters, told.append, "", cancels.append.bind(true), _PURPOSE)


## The engine's hide as 4.7.2 makes it before an answer. The dialog the stand-in
## shows is never put on a screen, so it is already hidden and only the signal
## is left to send.
func _hide(dialog: FileDialog) -> void:
    dialog.visible = false
    dialog.visibility_changed.emit()


func _frame() -> void:
    await (Engine.get_main_loop() as SceneTree).process_frame


func test_open_save_and_export_each_answer_with_the_path_after_the_hide() -> void:
    var host := Node.new()
    var cases := [
        [SaFilePicker.Mode.OPEN_FILE, PackedStringArray(["*.png ; PNG"]), "/home/painter/art/still.png", "Open"],
        [SaFilePicker.Mode.SAVE_FILE, PackedStringArray(["*.sad ; Sara document"]), "/home/painter/art/still.sad", "Save"],
        [
            SaFilePicker.Mode.SAVE_FILE,
            PackedStringArray(["*.png ; PNG", "*.jxl ; JPEG XL"]),
            "/home/painter/art/still.jxl",
            "Export"
        ],
    ]
    for case: Array in cases:
        var told: Array = []
        var cancels: Array = []
        var picker := _open(host, case[0], case[1], told, cancels)
        var dialog := picker.fallback as FileDialog
        _hide(dialog)
        dialog.file_selected.emit(case[2])
        await _frame()
        assert_eq(told, [case[2]], "%s answers with the path chosen" % case[3])
        assert_true(cancels.is_empty(), "%s is never cancelled by the hide" % case[3])
        assert_false(picker.is_open(), "%s puts the picker away" % case[3])
    host.free()


func test_open_several_and_open_folder_answer_after_the_hide() -> void:
    var host := Node.new()
    var told: Array = []
    var cancels: Array = []
    var several := _open(host, SaFilePicker.Mode.OPEN_FILES, PackedStringArray(), told, cancels)
    _hide(several.fallback as FileDialog)
    (several.fallback as FileDialog).files_selected.emit(PackedStringArray(["/a/one.png", "/a/two.png"]))
    var folder := _open(host, SaFilePicker.Mode.OPEN_DIR, PackedStringArray(), told, cancels)
    _hide(folder.fallback as FileDialog)
    (folder.fallback as FileDialog).dir_selected.emit("/home/painter/art")
    await _frame()
    assert_eq(told, [PackedStringArray(["/a/one.png", "/a/two.png"]), "/home/painter/art"], "both answer")
    assert_true(cancels.is_empty(), "and neither is cancelled")
    host.free()


func test_a_hide_with_no_answer_cancels_once_a_frame_late() -> void:
    var host := Node.new()
    var told: Array = []
    var cancels: Array = []
    var picker := _open(host, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(), told, cancels)
    _hide(picker.fallback as FileDialog)
    assert_true(cancels.is_empty(), "the hide does not cancel at once")
    assert_true(picker.is_open(), "and leaves the picker waiting for its answer")
    await _frame()
    await _frame()
    assert_eq(cancels, [true], "a frame later the title bar's close is one cancel")
    assert_true(told.is_empty(), "with nothing chosen")
    host.free()


func test_a_choice_emitted_twice_is_one_answer() -> void:
    var host := Node.new()
    var told: Array = []
    var cancels: Array = []
    var picker := _open(host, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(), told, cancels)
    var dialog := picker.fallback as FileDialog
    _hide(dialog)
    dialog.file_selected.emit("/home/painter/art/still.png")
    dialog.file_selected.emit("/home/painter/art/still.png")
    await _frame()
    assert_eq(told, ["/home/painter/art/still.png"], "one answer")
    assert_true(cancels.is_empty(), "and no cancel")
    host.free()


## The platform's side with no picker and no window.
class StandIn:
    extends SaFilePicker.Platform

    func has_picker() -> bool:
        return false

    func show(_picker: SaFilePicker, _platform_filters: PackedStringArray, _parent_id: int, _answer: Callable) -> void:
        push_error("the stand-in has no picker, so the platform's should never be asked for")

    func show_dialog(_dialog: Window) -> void:
        pass
