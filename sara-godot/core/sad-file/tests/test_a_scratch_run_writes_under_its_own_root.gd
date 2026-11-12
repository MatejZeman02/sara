## A run started with `--settings-dir` keeps everything it writes under its own
## root and leaves the painter's `user://` as it found it.
##
## A scratch run on a second machine offered to recover an autosave from
## another session, the painter's, and its Delete button would have removed
## their copy: the flag moved the settings file and nothing else. The gate runs
## every suite with the flag, so this suite is that scratch run. It plants a
## sentinel and a recovery copy in the engine's `user://`, which stands for the
## painter's folder, runs the autosave, a preset save, a colour save, a layout
## save and a recorder start, and finds every file they wrote under the root
## and the painter's folder unchanged, the planted copy never offered.
##
## A run without the flag has one root, `user://`, so there is nothing to tell
## apart, and the suite then holds the other half of the promise: every path
## is the one its constant spelled before, so a painter's data does not move.
extends "res://tests/test_framework.gd"

## The autosave writes a `.sad` and the recorder binds a canvas, and both need
## a RenderingDevice.
const REQUIRES_GPU := true

const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")

## The painter's stand-ins, planted in the engine's own user folder.
const SENTINEL := "user://test_d11_painter/sentinel.txt"
const SENTINEL_TEXT := "the painter's own, never touched by a scratch run"
const PAINTERS_COPY := "user://autosave/untitled-d11-painter.autosave.sad"

## What the engine writes into its user folder for itself, which no flag can
## move: its log and its two shader caches.
const ENGINE_FOLDERS: Array[String] = ["logs", "shader_cache", "vulkan"]

const PRESET_NAME := "d11 probe"

var _host: Node = null
## The data root before the suite wrote into it, so the cleanup removes what
## the suite made and nothing a suite before it left.
var _root_before: Dictionary = {}


func before_each() -> void:
    _host = Node.new()
    EventBus.add_child(_host)
    _root_before = _listing(SaDataRoot.folder())


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    _remove_new_files(SaDataRoot.folder(), _root_before)
    _remove(SENTINEL)
    _remove(PAINTERS_COPY)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SENTINEL.get_base_dir()))


func test_without_the_flag_nothing_moves() -> void:
    if SaDataRoot.moved():
        var flag := SaDataRoot.flag()
        assert_eq(SaDataRoot.folder(), flag.path_join(SaDataRoot.UNDER_FLAG), "the flag's own data folder")
        return
    assert_eq(SaDataRoot.folder(), "user://", "no flag, the engine's user folder")
    assert_eq(SaAutosave.recovery_dir(), "user://autosave", "the recovery copies where they always were")
    assert_eq(SaPresetStore.default_dir(), "user://brush_presets", "the presets")
    var colours := SaColorStore.new()
    assert_eq(colours.path, "user://colors.cfg", "the colours")
    colours.free()
    assert_eq(SaSpirvCache.cache_dir(), "user://spirv_cache", "the compiled kernels")


func test_a_scratch_run_writes_under_its_root_and_leaves_the_painters_folder_alone() -> void:
    if not SaDataRoot.moved():
        return
    var root := ProjectSettings.globalize_path(SaDataRoot.folder()).simplify_path()
    var painters := ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
    assert_false(root.begins_with(painters + "/"), "the root is not inside the painter's folder: %s" % root)

    _plant(SENTINEL, SENTINEL_TEXT.to_utf8_buffer())
    _plant(PAINTERS_COPY, "not a document, only a name the list would show".to_utf8_buffer())
    var painters_before := _listing("user://")

    var written: Array[String] = []
    written.append(_autosave())
    written.append(_preset())
    written.append(_colours())
    written.append(_layout())
    written.append(_recorder())

    for path: String in written:
        var real := ProjectSettings.globalize_path(path).simplify_path()
        assert_true(real.begins_with(root + "/"), "written under the scratch root: %s" % real)
        assert_true(FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path), "and it is there: %s" % path)

    assert_eq(FileAccess.get_file_as_string(SENTINEL), SENTINEL_TEXT, "the sentinel reads as it was planted")
    assert_eq(_listing("user://"), painters_before, "and nothing in the painter's folder was added, changed or removed")
    var offered := SaAutosave.find_recoveries([])
    for entry: Dictionary in offered:
        assert_false(String(entry["copy"]).get_file() == PAINTERS_COPY.get_file(), "the painter's copy is never offered")
    assert_true(offered.size() >= 1, "while the run's own copy is")


## An untitled document's recovery copy, the one that run offered to delete.
func _autosave() -> String:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var autosave := SaAutosave.new()
    autosave.follow_settings = false
    autosave.attach(easel.document)
    easel.add_child(autosave)
    easel.document.fill_layer(Color.RED)
    assert_eq(autosave.save_now(), OK, "the autosave writes")
    assert_true(SaSadFile.finish_saves(), "and the save in the background ends")
    var written := autosave.last_written
    easel.free()
    return written


func _preset() -> String:
    var store := SaPresetStore.new()
    var settings: Resource = BrushSettingsScript.new()
    assert_eq(store.save_preset(PRESET_NAME, settings), PRESET_NAME, "the preset saves")
    return store.dir.path_join(SaPresetStore.sanitize_name(PRESET_NAME) + SaPresetStore.EXTENSION)


func _colours() -> String:
    var colours := SaColorStore.new()
    _host.add_child(colours)
    colours.add_swatch(Color(0.2, 0.4, 0.6))
    return colours.path


func _layout() -> String:
    var layout := DockerLayoutStore.new()
    _host.add_child(layout)
    layout.save(true)
    return layout.path


func _recorder() -> String:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.ensure_easel()
    var recorder := SaRecorder.new()
    _host.add_child(recorder)
    recorder.bind_canvas(canvas)
    assert_true(recorder.start(), "the recorder starts")
    recorder.stop()
    canvas.free()
    return recorder.directory


func _plant(path: String, bytes: PackedByteArray) -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()


func _remove(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Every file and folder under *folder*, relative path -> `[size, modified]`,
## the engine's own folders left out at the top.
func _listing(folder: String) -> Dictionary:
    var out: Dictionary = {}
    _walk(ProjectSettings.globalize_path(folder), "", out)
    return out


func _walk(dir_path: String, prefix: String, out: Dictionary) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    for name: String in dir.get_directories():
        if prefix.is_empty() and ENGINE_FOLDERS.has(name):
            continue
        out[prefix + name + "/"] = []
        _walk(dir_path.path_join(name), prefix + name + "/", out)
    for name: String in dir.get_files():
        var path := dir_path.path_join(name)
        out[prefix + name] = [FileAccess.get_size(path), FileAccess.get_modified_time(path)]


## Takes away what the suite made under *folder*, deepest first, and leaves
## what was there before it ran.
func _remove_new_files(folder: String, before: Dictionary) -> void:
    var base := ProjectSettings.globalize_path(folder)
    var made: Array = []
    for relative: String in _listing(folder):
        if not before.has(relative):
            made.append(relative)
    made.sort()
    made.reverse()
    for relative: String in made:
        DirAccess.remove_absolute(base.path_join(relative.trim_suffix("/")))
