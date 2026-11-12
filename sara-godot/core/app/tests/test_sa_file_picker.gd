## The file picker every caller opens, held against the platform
## through a stand-in, so no window goes up.
##
## A `FileDialog` set to the filesystem asked every drive letter for its label on
## the main thread before the platform's picker came up, and a mapped drive whose
## server did not answer held File › Open for 63 seconds. `SaFilePicker` asks the
## display server for the picker directly, and builds the engine's dialog only
## where the platform has none. What the painter meets has to be what they met
## before: the filters listed the same, Save's name given the filter's extension,
## an answer told to the caller once, and a cancel told as a cancel. The engine's
## dialog is built by the interface, and its suite is
## `ui/pickers/tests/test_a_platform_with_no_picker_gets_the_interface_s_dialog.gd`.
extends "res://tests/test_framework.gd"

var _platform_before: SaFilePicker.Platform = null
var _stand_in: StandIn = null

## The purposes the tests keep a folder for, forgotten after each test.
const _PURPOSE: StringName = &"test_d83_purpose"
const _OTHER: StringName = &"test_d83_other"

## Where the tests make folders, under the suites' data root.
var _scratch: String = SaDataRoot.path("test_d83_file_picker")


func before_each() -> void:
    _platform_before = SaFilePicker.platform
    _stand_in = StandIn.new(true)
    SaFilePicker.platform = _stand_in


func after_each() -> void:
    var cancelled := 0
    while SaFilePicker.newest() != null and cancelled < 100:
        SaFilePicker.newest().cancel()
        cancelled += 1
    assert_null(SaFilePicker.newest(), "A cancelled picker goes away")
    SaFilePicker.platform = _platform_before
    SaSettings.set_module_preference(SaFilePicker.SETTINGS_ID, _PURPOSE, null)
    SaSettings.set_module_preference(SaFilePicker.SETTINGS_ID, _OTHER, null)
    if DirAccess.dir_exists_absolute(_scratch):
        DirAccess.remove_absolute(_scratch.path_join("art"))
        DirAccess.remove_absolute(_scratch)


func test_the_platform_is_asked_and_no_dialog_is_built() -> void:
    var host := Node.new()
    var told: Array = []
    var picker := SaFilePicker.open(host, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(["*.sad ; Sara Document"]), told.append)
    assert_eq(_stand_in.shown, [picker], "the platform is asked for its picker once")
    assert_null(picker.fallback, "and no engine dialog is built")
    assert_true(host.find_children("*", "Window", true, false).is_empty(), "under the host or anywhere below it")
    assert_true(_stand_in.dialogs.is_empty(), "nor shown")
    assert_eq(picker.title, "Open a File", "a picker with no title takes the one the engine's dialog showed")
    assert_true(picker.is_open(), "it waits for its answer")
    host.free()


func test_a_chosen_path_is_told_once_and_a_late_answer_says_nothing() -> void:
    var told: Array = []
    var picker := SaFilePicker.open(null, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(), told.append)
    picker.answer(true, PackedStringArray(["/home/painter/a.sad"]), 0)
    assert_eq(told, ["/home/painter/a.sad"], "the path reaches the caller as a String")
    assert_false(picker.is_open(), "and the picker is no longer open")
    picker.answer(true, PackedStringArray(["/home/painter/b.sad"]), 0)
    picker.choose(PackedStringArray(["/home/painter/c.sad"]))
    assert_eq(told, ["/home/painter/a.sad"], "the platform's window returning after a scenario answered says nothing")


func test_open_files_is_told_the_list() -> void:
    var told: Array = []
    var picker := SaFilePicker.open(null, SaFilePicker.Mode.OPEN_FILES, PackedStringArray(), told.append)
    var paths := PackedStringArray(["/a.png", "/b.png"])
    picker.answer(true, paths, 0)
    assert_eq(told, [paths], "Open Files hears every path, as `files_selected` gave them")
    var one: Array = []
    SaFilePicker.open(null, SaFilePicker.Mode.OPEN_FILES, PackedStringArray(), one.append).choose(PackedStringArray(["/c.png"]))
    assert_eq(one, [PackedStringArray(["/c.png"])], "and a scenario's one path arrives as a list of one")


func test_a_cancel_is_told_as_a_cancel_and_an_empty_answer_is_one() -> void:
    var chosen: Array = []
    var cancelled: Array = []
    var picker := SaFilePicker.open(
        null, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(), chosen.append, "", func() -> void: cancelled.append(true)
    )
    picker.answer(false, PackedStringArray(), 0)
    assert_eq(cancelled, [true], "a cancel reaches the caller's cancel")
    assert_true(chosen.is_empty(), "and chooses nothing")
    assert_false(picker.is_open(), "and puts the picker away")

    var empty := SaFilePicker.open(
        null, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(), chosen.append, "", func() -> void: cancelled.append(true)
    )
    empty.answer(true, PackedStringArray(), 0)
    assert_eq(cancelled, [true, true], "an answer that chose nothing is a cancel, not a picker left open")
    assert_false(empty.is_open(), "so nothing waits on it")


func test_the_newest_open_picker_is_the_one_a_scenario_answers() -> void:
    assert_null(SaFilePicker.newest(), "nothing is open to begin with")
    var first := SaFilePicker.open(null, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(), Callable())
    var second := SaFilePicker.open(null, SaFilePicker.Mode.SAVE_FILE, PackedStringArray(), Callable())
    assert_eq(SaFilePicker.newest(), second, "the one put up last")
    second.cancel()
    assert_eq(SaFilePicker.newest(), first, "and the one before it once that is answered")
    first.cancel()
    assert_null(SaFilePicker.newest(), "then none")


func test_a_picker_is_up_under_the_node_that_asked_and_its_ancestors() -> void:
    var window := Node.new()
    var row := Node.new()
    window.add_child(row)
    var elsewhere := Node.new()
    var picker := SaFilePicker.open(row, SaFilePicker.Mode.OPEN_FILES, PackedStringArray(), Callable())
    assert_true(SaFilePicker.is_up_under(row), "the node that asked has it up")
    assert_true(SaFilePicker.is_up_under(window), "and so does the window holding it")
    assert_false(SaFilePicker.is_up_under(elsewhere), "a node beside them does not")
    picker.cancel()
    assert_false(SaFilePicker.is_up_under(window), "and once it is answered nothing does")
    window.free()
    elsewhere.free()


func test_the_filters_are_listed_as_the_engines_dialog_listed_them() -> void:
    var one := SaFilePicker.new(
        null, SaFilePicker.Mode.SAVE_FILE, PackedStringArray(["*.sad ; Sara Document"]), Callable(), "", Callable()
    )
    assert_eq(
        one.platform_filters(),
        PackedStringArray(["*.sad;Sara Document (*.sad);", "*.*;All Files (*.*);application/octet-stream"]),
        "one filter is listed with All Files after it"
    )
    var three := SaFilePicker.new(
        null,
        SaFilePicker.Mode.OPEN_FILE,
        PackedStringArray(["*.kpp, *.bundle ; Krita presets", "*.kpp ; Krita preset", "*.gpl"]),
        Callable(),
        "",
        Callable()
    )
    assert_eq(
        three.platform_filters(),
        PackedStringArray(
            [
                "*.kpp, *.bundle,*.kpp,*.gpl;All Recognized (*.kpp, *.bundle, *.kpp, *.gpl);",
                "*.kpp, *.bundle;Krita presets (*.kpp, *.bundle);",
                "*.kpp;Krita preset (*.kpp);",
                "*.gpl;(*.gpl);",
                "*.*;All Files (*.*);application/octet-stream",
            ]
        ),
        "several are led by All Recognized, and a filter with no description shows its patterns"
    )


func test_all_recognized_names_five_filters_and_carries_them_all() -> void:
    var six := PackedStringArray(["*.a", "*.b", "*.c", "*.d", "*.e", "*.f"])
    var picker := SaFilePicker.new(null, SaFilePicker.Mode.OPEN_FILE, six, Callable(), "", Callable())
    assert_eq(
        picker.platform_filters()[0],
        "*.a,*.b,*.c,*.d,*.e,*.f;All Recognized (*.a, *.b, *.c, *.d, *.e, ...);",
        "the label stops at five, the patterns do not"
    )


func test_save_gives_a_name_typed_without_an_extension_the_filters_own() -> void:
    var one := SaFilePicker.new(
        null, SaFilePicker.Mode.SAVE_FILE, PackedStringArray(["*.gpl ; GIMP palette"]), Callable(), "", Callable()
    )
    assert_eq(one.with_extension("/p/warm", 0), "/p/warm.gpl", "the one filter's extension is added")
    assert_eq(one.with_extension("/p/warm.GPL", 0), "/p/warm.GPL", "a name that has it, in any case, is kept")
    assert_eq(one.with_extension("/p/warm", 1), "/p/warm", "All Files takes the name as typed")

    var several := SaFilePicker.new(
        null, SaFilePicker.Mode.SAVE_FILE, PackedStringArray(["*.png ; PNG", "*.jpg, *.jpeg ; JPEG"]), Callable(), "", Callable()
    )
    assert_eq(several.with_extension("/p/x.jpeg", 0), "/p/x.jpeg", "All Recognized keeps a name any filter matches")
    assert_eq(several.with_extension("/p/x", 0), "/p/x.png", "and gives one none matches the first filter's extension")
    assert_eq(several.with_extension("/p/x", 2), "/p/x.jpg", "a filter chosen gives its first extension")
    assert_eq(several.with_extension("/p/x.png", 2), "/p/x.png.jpg", "to a name that does not match it, as the engine did")
    assert_eq(several.with_extension("/p/x", 3), "/p/x", "and All Files, last, adds nothing")

    var told: Array = []
    SaFilePicker.open(null, SaFilePicker.Mode.SAVE_FILE, PackedStringArray(["*.gpl ; GIMP palette"]), told.append).answer(
        true, PackedStringArray(["/p/warm"]), 0
    )
    assert_eq(told, ["/p/warm.gpl"], "and the caller hears the name with it")


## Open must not start in the home folder every time, with the
## painter's last folder Pictures, because GNOME's portal keeps no last folder.
## Each purpose keeps its own, so Open, Import and Save do not move each other.
func test_each_purpose_has_its_own_key() -> void:
    var sad := PackedStringArray(["*.sad ; Sara Document", "*.png, *.jpg ; Image"])
    var images := PackedStringArray(["*.png, *.jpg ; Image"])
    assert_eq(SaFilePicker.purpose_of(SaFilePicker.Mode.OPEN_FILE, sad), "open_file_sad_png_jpg", "Open's key")
    assert_true(
        SaFilePicker.purpose_of(SaFilePicker.Mode.OPEN_FILE, images) != SaFilePicker.purpose_of(SaFilePicker.Mode.OPEN_FILE, sad),
        "Import's is not Open's"
    )
    assert_true(
        SaFilePicker.purpose_of(SaFilePicker.Mode.SAVE_FILE, sad) != SaFilePicker.purpose_of(SaFilePicker.Mode.OPEN_FILE, sad),
        "nor is Save's"
    )
    var named := SaFilePicker.new(null, SaFilePicker.Mode.SAVE_FILE, images, Callable(), "", Callable(), _PURPOSE)
    assert_eq(named.purpose, _PURPOSE, "a caller's own word wins")


func test_a_chosen_folder_is_where_its_purpose_starts_next() -> void:
    var art := _scratch.path_join("art")
    DirAccess.make_dir_recursive_absolute(art)
    SaFilePicker.open(null, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(), Callable(), "", Callable(), _PURPOSE).choose(
        PackedStringArray([art.path_join("study.png")])
    )
    assert_eq(SaSettings.module_preference(SaFilePicker.SETTINGS_ID, _PURPOSE), art, "the folder is kept in the profile")
    var next := SaFilePicker.open(null, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(), Callable(), "", Callable(), _PURPOSE)
    assert_eq(next.folder, art, "and the next picker for it starts there")
    assert_eq(_stand_in.shown[-1], next, "handed to the platform with it")
    var other := SaFilePicker.open(null, SaFilePicker.Mode.OPEN_FILE, PackedStringArray(), Callable(), "", Callable(), _OTHER)
    assert_true(other.folder != art, "another purpose does not start there")

    var folders := SaFilePicker.open(null, SaFilePicker.Mode.OPEN_DIR, PackedStringArray(), Callable(), "", Callable(), _OTHER)
    folders.choose(PackedStringArray([art]))
    assert_eq(SaFilePicker.start_folder(_OTHER), art, "a chosen folder is kept as itself, not its parent")


func test_a_folder_that_is_gone_falls_back() -> void:
    var gone := _scratch.path_join("gone/deeper")
    SaSettings.set_module_preference(SaFilePicker.SETTINGS_ID, _PURPOSE, gone)
    DirAccess.make_dir_recursive_absolute(_scratch)
    assert_eq(SaFilePicker.start_folder(_PURPOSE), _scratch, "the nearest folder above it that is there")

    SaSettings.set_module_preference(SaFilePicker.SETTINGS_ID, _PURPOSE, "/sara-d83-no-such-drive/art")
    var pictures := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
    var home := OS.get_environment("USERPROFILE" if OS.get_name() == "Windows" else "HOME")
    var expected := pictures if not pictures.is_empty() and DirAccess.dir_exists_absolute(pictures) else home
    assert_eq(SaFilePicker.start_folder(_PURPOSE), expected, "a tree that is gone whole is Pictures, then home, never the root")
    assert_eq(SaFilePicker.nearest_folder("/"), "", "the root is never the answer")


## The platform's side with no window: it says whether it has a picker, and keeps
## what it was asked to show.
class StandIn:
    extends SaFilePicker.Platform

    var has_one: bool = true
    var shown: Array[SaFilePicker] = []
    var dialogs: Array[Window] = []

    func _init(platform_has_one: bool) -> void:
        has_one = platform_has_one

    func has_picker() -> bool:
        return has_one

    func show(picker: SaFilePicker, _platform_filters: PackedStringArray, _parent_id: int, _answer: Callable) -> void:
        shown.append(picker)

    func show_dialog(dialog: Window) -> void:
        dialogs.append(dialog)
