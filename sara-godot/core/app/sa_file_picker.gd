## A file picker that asks the drives nothing before it opens: the platform's own
## where it has one, put up through the display server, and the engine's built-in
## dialog where it has none. Every picker Sara opens goes through here, so a
## scenario and the summon find an open one in one place rather than hunting for
## a hidden node.
##
## **A `FileDialog` can hold File › Open for a minute on a machine with network
## drives mapped.** Setting its `access` to the filesystem asks every drive letter
## for its label on the main thread before the platform's picker starts, and a
## drive whose server does not answer holds that call until Windows gives up.
## `DisplayServer.file_dialog_show()` builds no `DirAccess` and
## runs the picker on a thread of its own from the start, so this class calls it
## directly, and the interface builds a `FileDialog` (`SaPickers` in `ui/pickers`,
## asked through `SaDialogsInHand`) only where the platform has no picker.
##
## The answer arrives the way a `FileDialog` gives it: a path for Open and Save, the
## paths for Open Files, a folder for a folder, and nothing for a cancel. The list
## of filters the platform shows, and the extension Save adds to a name typed
## without one, are the ones `FileDialog::update_filters()` and
## `FileDialog::_native_dialog_cb()` make, so the picker a painter meets is the
## one the engine's dialog would put up. The labels leave out MIME types, which
## no caller passes.
##
## **A picker handed no starting folder opens in the home folder** on GNOME's
## portal, which keeps no last folder of its own, so Sara keeps it instead, one
## folder per purpose in the profile.
class_name SaFilePicker
extends RefCounted

## What a picker is asked for, numbered as `DisplayServer.FileDialogMode` and
## `FileDialog.FileMode` both number it, so either takes it with a cast.
enum Mode { OPEN_FILE = 0, OPEN_FILES = 1, OPEN_DIR = 2, SAVE_FILE = 4 }

## At most this many filters are named in the "All Recognized" entry's label, as
## the engine's dialog names them. Its patterns carry every filter.
const RECOGNIZED_NAMED: int = 5

## The profile section the last folders are kept under, one key per purpose,
## through the door a module's own preference goes through, because a purpose is
## a key nobody declares ahead: a module's picker brings its own.
const SETTINGS_ID: StringName = &"file_picker"

## The scheme of an address Android's picker answers with. Android lets Sara
## read and write it only while this process lives unless the grant is asked to
## persist, and a picture in Recent would read as missing after a restart.
const CONTENT_SCHEME: String = "content://"

## The platform's side. A suite hands this a stand-in that records the call and
## answers when told, which is how every caller is opened without a window, and
## puts the one it found back after.
static var platform: Platform = Platform.new()

## Every picker put up and not answered yet, oldest first.
static var _open: Array[SaFilePicker] = []

## What the picker was asked for.
var mode: Mode = Mode.OPEN_FILE

## The caller's filters, each `"*.png, *.jpg ; Description"`.
var filters: PackedStringArray = PackedStringArray()

## The title the picker shows, the engine dialog's own for the mode when the
## caller named none.
var title: String = ""

## The node that asked. The picker stands over its window, and the summon holds a
## docker out while a picker one of its nodes asked for is up.
var host: Node = null

## What the picker is for, the key its last folder is kept under: the caller's
## word, or the mode and the filters' extensions when it named none, so Open,
## Import and a module's picker each keep their own.
var purpose: String = ""

## The folder the picker starts in, the one this purpose was last left in.
var folder: String = ""

## The engine's built-in dialog, on a platform with no picker of its own, or null.
## Built by the interface, which answers it through [method choose] and [method
## cancel] as the platform's picker answers through [method answer].
var fallback: Window = null

## Told the chosen path, or the paths for [constant Mode.OPEN_FILES].
var _on_chosen: Callable

## Told a cancel, or empty when the caller has nothing to do on one.
var _on_cancel: Callable


func _init(
    asked_by: Node,
    asked_mode: Mode,
    asked_filters: PackedStringArray,
    on_chosen: Callable,
    shown_title: String,
    on_cancel: Callable,
    asked_purpose: String = ""
) -> void:
    host = asked_by
    mode = asked_mode
    filters = asked_filters
    purpose = asked_purpose if not asked_purpose.is_empty() else purpose_of(asked_mode, asked_filters)
    folder = start_folder(purpose)
    title = shown_title if not shown_title.is_empty() else _engine_title(asked_mode)
    _on_chosen = on_chosen
    _on_cancel = on_cancel


## Puts a picker up over *host*'s window and tells *on_chosen* what the painter
## picks: a `String` path, or a `PackedStringArray` for [constant
## Mode.OPEN_FILES]. *on_cancel* hears an Escape or a close. *asked_purpose*
## names what the picker is for when its filters do not, as Export's change with
## the format. Answers the picker, which a suite answers in the platform's place.
static func open(
    asked_by: Node,
    asked_mode: Mode,
    asked_filters: PackedStringArray,
    on_chosen: Callable,
    shown_title: String = "",
    on_cancel: Callable = Callable(),
    asked_purpose: String = ""
) -> SaFilePicker:
    var picker := SaFilePicker.new(asked_by, asked_mode, asked_filters, on_chosen, shown_title, on_cancel, asked_purpose)
    _open.append(picker)
    if platform.has_picker():
        platform.show(picker, picker.platform_filters(), picker.parent_window_id(), picker.answer)
    else:
        picker._build_fallback()
    return picker


## The picker put up last and not answered yet, or null. What a scenario's
## `file_picker` step answers, since no injected click reaches a window the
## platform draws.
static func newest() -> SaFilePicker:
    return _open[-1] if not _open.is_empty() else null


## The key a picker for *for_mode* and *for_filters* keeps its folder under: the
## mode and every extension the filters name, in their order, `open_file_sad_png`.
static func purpose_of(for_mode: Mode, for_filters: PackedStringArray) -> String:
    var words := PackedStringArray([str(Mode.find_key(for_mode)).to_lower()])
    for entry in for_filters:
        for pattern in _patterns(entry):
            var extension := pattern.get_extension().to_lower()
            if not extension.is_empty() and not words.has(extension):
                words.append(extension)
    return "_".join(words)


## The folder a picker for *for_purpose* starts in: the one it was last left in,
## or the nearest folder above it that is still there, then Pictures, then home.
## Empty when none of them is, which leaves the choice to the platform.
static func start_folder(for_purpose: String) -> String:
    var kept := str(SaSettings.module_preference(SETTINGS_ID, StringName(for_purpose), ""))
    var found := nearest_folder(kept)
    if not found.is_empty():
        return found
    var home := OS.get_environment("USERPROFILE" if OS.get_name() == "Windows" else "HOME")
    for candidate: String in [OS.get_system_dir(OS.SYSTEM_DIR_PICTURES), home]:
        if not candidate.is_empty() and DirAccess.dir_exists_absolute(candidate):
            return candidate
    return ""


## *path* when it is a folder that is there, or the nearest one above it that
## is. A filesystem's root does not count, so a folder on a drive that has gone
## falls through to Pictures rather than opening at `/` or `C:/`.
static func nearest_folder(path: String) -> String:
    var at := path.simplify_path()
    while not at.is_empty():
        var above := at.get_base_dir()
        if above == at:
            return ""
        if DirAccess.dir_exists_absolute(at):
            return at
        at = above
    return ""


## Whether a picker that *node*, or a node under it, asked for is up. A picker the
## platform draws is no window of the tree, so this is the only way to see it.
static func is_up_under(node: Node) -> bool:
    for picker: SaFilePicker in _open:
        var asker := picker.host
        if is_instance_valid(asker) and (asker == node or node.is_ancestor_of(asker)):
            return true
    return false


## The platform's answer, in the shape `DisplayServer.file_dialog_show()` calls
## back with. An answer that chose nothing is a cancel, since the engine's dialog
## said nothing at all to one and left its caller waiting.
func answer(status: bool, paths: PackedStringArray, filter_index: int) -> void:
    if not status or paths.is_empty():
        cancel()
        return
    for path in paths:
        if path.begins_with(CONTENT_SCHEME):
            platform.keep_grant(path)
    if mode == Mode.SAVE_FILE:
        choose(PackedStringArray([with_extension(paths[0], filter_index)]))
        return
    choose(paths)


## Tells the caller *paths* were chosen, the whole list for [constant
## Mode.OPEN_FILES] and the first path for any other mode. A picker already
## answered says nothing twice, which is the platform's window coming back after
## a scenario answered in its place.
func choose(paths: PackedStringArray) -> void:
    if not _close() or paths.is_empty():
        return
    _remember(paths[0])
    if not _on_chosen.is_valid():
        return
    if mode == Mode.OPEN_FILES:
        _on_chosen.call(paths)
    else:
        _on_chosen.call(paths[0])


## Keeps the folder *path* was chosen in as where this purpose starts next time,
## the chosen folder itself for [constant Mode.OPEN_DIR]. Made absolute, since
## the platform's picker knows no `res://` or `user://` a scenario chooses in.
func _remember(path: String) -> void:
    var absolute := ProjectSettings.globalize_path(path)
    var chosen_in := absolute if mode == Mode.OPEN_DIR else absolute.get_base_dir()
    if not chosen_in.is_empty():
        SaSettings.set_module_preference(SETTINGS_ID, StringName(purpose), chosen_in)


## Tells the caller the picker was put away with nothing chosen.
func cancel() -> void:
    if _close() and _on_cancel.is_valid():
        _on_cancel.call()


## Whether the picker is up and waiting for an answer.
func is_open() -> bool:
    return _open.has(self)


## The window the picker stands over: the one *host* is drawn in, or the main
## window when the host is in no tree.
func parent_window_id() -> int:
    if not is_instance_valid(host) or not host.is_inside_tree():
        return DisplayServer.MAIN_WINDOW_ID
    return host.get_window().get_window_id()


## The filters as the platform is handed them, each `patterns;label;mime`: one
## "All Recognized" entry first when there are several, then each filter, then
## "All Files", the list `FileDialog::update_filters()` builds.
func platform_filters() -> PackedStringArray:
    var out := PackedStringArray()
    if filters.size() > 1:
        var named := PackedStringArray()
        var patterns := PackedStringArray()
        var mimes := PackedStringArray()
        for i in filters.size():
            var pattern := _part(filters[i], 0)
            var mime := _part(filters[i], 2)
            if not pattern.is_empty():
                patterns.append(pattern)
                if i < RECOGNIZED_NAMED:
                    named.append(pattern)
            if not mime.is_empty():
                mimes.append(mime)
        var shown := ", ".join(named) + (", ..." if filters.size() > RECOGNIZED_NAMED else "")
        var label := "%s (%s)" % [TranslationServer.translate("All Recognized"), shown]
        out.append("%s;%s;%s" % [",".join(patterns), label, ",".join(mimes)])
    for entry in filters:
        var pattern := _part(entry, 0)
        var description := _part(entry, 1)
        var label := "%s (%s)" % [description, pattern] if not description.is_empty() else "(%s)" % pattern
        out.append("%s;%s;%s" % [pattern, label, _part(entry, 2)])
    var every := "%s (*.*)" % TranslationServer.translate("All Files")
    out.append("*.*;%s;application/octet-stream" % every)
    return out


## *path* with the extension the filter at *filter_index* of [method
## platform_filters] asks for, when the name was typed without one of its own.
## "All Files" takes the name as typed, and "All Recognized" takes it when any
## filter matches and gives it the first filter's extension when none does.
## A `content://` address is the document the platform's picker already made,
## and Android's picker shows no extension and adds none, so a name appended to
## it names no document and the save into it fails. It is answered as it came,
## and a picture saved under a bare name is opened by its first bytes.
func with_extension(path: String, filter_index: int) -> String:
    if path.begins_with(CONTENT_SCHEME):
        return path
    var several := filters.size() > 1
    if filters.is_empty() or filter_index >= filters.size() + (1 if several else 0) or filter_index < 0:
        return path
    if several and filter_index == 0:
        for entry in filters:
            if _matches(path, entry):
                return path
        return path + "." + _patterns(filters[0])[0].get_extension()
    var entry := filters[filter_index - (1 if several else 0)]
    if _matches(path, entry):
        return path
    var first := _patterns(entry)[0]
    return path + first.substr(1) if first.begins_with("*") else path


## Takes the picker off the list of open ones and frees the built-in dialog when
## there is one. Answers false for a picker that was already answered.
func _close() -> bool:
    var at := _open.find(self)
    if at < 0:
        return false
    _open.remove_at(at)
    if is_instance_valid(fallback):
        fallback.queue_free()
    return true


## The engine's own dialog, for a platform with no picker, built by the
## interface through `SaDialogsInHand`, since core names no window class. A host
## with nothing attached says so in the corner, and a dialog with nowhere to
## stand, both a cancel.
func _build_fallback() -> void:
    fallback = SaDialogsInHand.file_dialog(self)
    if fallback == null:
        cancel()
        return
    platform.show_dialog(fallback)


## The title the engine's dialog gives *for_mode* when its caller names none.
static func _engine_title(for_mode: Mode) -> String:
    match for_mode:
        Mode.OPEN_FILES:
            return TranslationServer.translate("Open Files")
        Mode.OPEN_DIR:
            return TranslationServer.translate("Choose a Folder")
        Mode.SAVE_FILE:
            return TranslationServer.translate("Save a File")
    return TranslationServer.translate("Open a File")


## Part *index* of a filter, `patterns ; description ; mime`, trimmed.
static func _part(entry: String, index: int) -> String:
    return entry.get_slice(";", index).strip_edges() if entry.get_slice_count(";") > index else ""


## A filter's patterns, `*.png` and the rest, trimmed.
static func _patterns(entry: String) -> PackedStringArray:
    var out := PackedStringArray()
    for pattern in _part(entry, 0).split(","):
        out.append(pattern.strip_edges())
    return out


## Whether *path*'s file name matches any pattern of *entry*, case aside.
static func _matches(path: String, entry: String) -> bool:
    for pattern in _patterns(entry):
        if not pattern.is_empty() and path.matchn(pattern):
            return true
    return false


## The display server's picker, whether the platform has one, and the showing of
## the engine's dialog where it has none. A suite puts a subclass in [member
## SaFilePicker.platform] that records the call and puts no window up, and answers
## through [method SaFilePicker.answer] when the suite says so.
class Platform:
    extends RefCounted

    ## The object asked to keep an Android grant, a suite's stand-in, or null,
    ## when the engine's `AndroidRuntime` singleton is asked at the time.
    var runtime: Object = null

    func _init(asked_runtime: Object = null) -> void:
        runtime = asked_runtime

    ## Asks Android to keep Sara's read and write grant on *address* past this
    ## process, which a picker's grant is not by itself. Answers whether it was
    ## kept. A platform with no `AndroidRuntime` keeps nothing and is told so
    ## only by false, since a desktop has no grant to keep.
    func keep_grant(address: String) -> bool:
        var asked := runtime
        if asked == null and Engine.has_singleton("AndroidRuntime"):
            asked = Engine.get_singleton("AndroidRuntime")
        if asked == null:
            return false
        # The engine's bridge hands Kotlin's Boolean back as an int, 1 or 0.
        var answered: Variant = asked.call("updatePersistableUriPermission", address, true)
        var kept: bool = (answered is bool and answered == true) or (answered is int and answered != 0)
        if not kept:
            print("SaFilePicker: Android kept no grant on ", address)
        return kept

    func has_picker() -> bool:
        return DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)

    ## *answer* is [method SaFilePicker.answer], called back on the main thread
    ## once the platform's window returns. The picker starts in its purpose's
    ## [member SaFilePicker.folder], since a platform asked for none opens
    ## wherever it likes, the home folder for GNOME's portal.
    func show(picker: SaFilePicker, platform_filters: PackedStringArray, parent_id: int, answer: Callable) -> void:
        var shown_mode := picker.mode as DisplayServer.FileDialogMode
        DisplayServer.file_dialog_show(picker.title, picker.folder, "", false, shown_mode, platform_filters, answer, parent_id)

    ## Shows the engine's dialog, which a suite leaves hidden, since a `Window`
    ## shown from a suite maps a real one.
    func show_dialog(dialog: Window) -> void:
        dialog.popup_centered(Vector2i(700, 500))
