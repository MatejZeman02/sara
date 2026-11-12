## Android's picker grants Sara a `content://` address only for
## as long as the process lives, so a picture opened or saved through it read as
## missing in the welcome's Recent once Sara started again. The picker's answer
## asks the runtime to keep the grant on every such address, and leaves a plain
## path alone, since a desktop has no grant to keep.
extends "res://tests/test_framework.gd"

const _ADDRESS: String = "content://com.android.externalstorage.documents/document/primary%3APictures%2Fh3403.sad"

var _platform_before: SaFilePicker.Platform = null
var _runtime: Runtime = null


func before_each() -> void:
    _platform_before = SaFilePicker.platform
    _runtime = Runtime.new()
    SaFilePicker.platform = Silent.new(_runtime)


func after_each() -> void:
    while SaFilePicker.newest() != null:
        SaFilePicker.newest().cancel()
    SaFilePicker.platform = _platform_before


func test_an_opened_content_address_is_asked_to_persist_once() -> void:
    var told: Array = []
    var picker := SaFilePicker.open(null, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(["*.sad ; Sara Document"]), told.append)
    picker.answer(true, PackedStringArray([_ADDRESS]), 0)
    assert_eq(_runtime.asked, [[_ADDRESS, true]], "the address is asked to persist once, with persist true")
    assert_eq(told, [_ADDRESS], "and the caller is told the address as the picker gave it")


func test_a_saved_content_address_is_asked_to_persist_once() -> void:
    var told: Array = []
    var picker := SaFilePicker.open(null, SaFilePicker.Mode.SAVE_FILE, PackedStringArray(["*.sad ; Sara Document"]), told.append)
    picker.answer(true, PackedStringArray([_ADDRESS]), 0)
    assert_eq(_runtime.asked, [[_ADDRESS, true]], "a save's address is asked to persist once as well")
    assert_eq(told.size(), 1, "and the caller is told once")


func test_every_content_address_of_open_files_is_asked() -> void:
    var second := _ADDRESS.replace("h3403", "h3403-b")
    var told: Array = []
    var picker := SaFilePicker.open(null, SaFilePicker.Mode.OPEN_FILES, PackedStringArray(), told.append)
    picker.answer(true, PackedStringArray([_ADDRESS, second]), 0)
    assert_eq(_runtime.asked, [[_ADDRESS, true], [second, true]], "each address of a list is asked to persist once")


func test_a_plain_path_is_never_asked() -> void:
    var told: Array = []
    var opened := SaFilePicker.open(null, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(), told.append)
    opened.answer(true, PackedStringArray(["/home/painter/h3403.sad"]), 0)
    var saved := SaFilePicker.open(null, SaFilePicker.Mode.SAVE_FILE, PackedStringArray(["*.sad ; Sara Document"]), told.append)
    saved.answer(true, PackedStringArray(["/home/painter/h3403"]), 0)
    assert_true(_runtime.asked.is_empty(), "a plain path, opened or saved, is never asked to persist")


func test_a_cancel_asks_nothing() -> void:
    var told: Array = []
    var picker := SaFilePicker.open(null, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(), told.append)
    picker.answer(false, PackedStringArray([_ADDRESS]), 0)
    assert_true(_runtime.asked.is_empty(), "a cancelled picker asks the runtime nothing")


func test_a_grant_android_refuses_is_answered_false() -> void:
    assert_true(SaFilePicker.platform.keep_grant(_ADDRESS), "a grant the runtime keeps reads as kept")
    _runtime.answers = 1
    assert_true(SaFilePicker.platform.keep_grant(_ADDRESS), "and so does the 1 the engine's bridge hands back on Android")
    _runtime.answers = 0
    assert_false(SaFilePicker.platform.keep_grant(_ADDRESS), "a 0 reads as not kept")
    _runtime.answers = false
    assert_false(SaFilePicker.platform.keep_grant(_ADDRESS), "and so does a false")
    if not Engine.has_singleton("AndroidRuntime"):
        assert_false(SaFilePicker.Platform.new().keep_grant(_ADDRESS), "and a platform with no runtime keeps nothing")


## The engine's `AndroidRuntime` singleton as far as the picker uses it: it
## records each address asked and answers as told, a bool or the int the
## engine's bridge gives on a device.
class Runtime:
    extends RefCounted

    var asked: Array = []
    var answers: Variant = true

    func updatePersistableUriPermission(uri_string: String, persist: bool) -> Variant:  # gdlint: ignore=function-name
        asked.append([uri_string, persist])
        return answers


## A platform with a picker that puts no window up and keeps its grants through
## the suite's runtime.
class Silent:
    extends SaFilePicker.Platform

    func _init(stand_in: Object) -> void:
        super._init(stand_in)

    func has_picker() -> bool:
        return true

    func show(_picker: SaFilePicker, _platform_filters: PackedStringArray, _parent_id: int, _answer: Callable) -> void:
        pass
