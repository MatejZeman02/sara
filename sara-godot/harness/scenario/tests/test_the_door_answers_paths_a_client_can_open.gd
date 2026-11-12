## A path the door answers, or is sent, is a path of the machine.
##
## A Windows Python reading a layer got `user://captures/read_pixels-0.npy`, which
## `np.load` cannot open, and `doc.show()` sent `C:\Users\me\look.png` and had Sara
## put `user://captures/` in front of it. Neither shows on Linux when the capture
## folder is absolute and a path begins with a slash, so this suite puts the
## folder under the data root, which is `user://` in a run with no
## `--settings-dir` as the gate's is, the way a Sara with no `--capture-out` has
## it, and sends the path a Windows client sends.
##
## A drive letter cannot be written on Linux, so what is held for it is where
## the step resolves the path to, and that it made nothing of its own under the
## capture folder. `String.is_absolute_path` reads a drive letter the same on every
## platform, which is what lets a suite on Linux hold it.
extends "res://tests/test_framework.gd"

## Reads chunks back, and `look` composites.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const PixelDriver = preload("res://harness/scenario/sa_scenario_pixels.gd")
const ScenarioDocument := preload("res://harness/scenario/sa_scenario_document.gd")

const SIZE := Vector2i(64, 64)

## What a Windows client sends for a file in its temporary folder.
const DRIVE_PATH := "C:\\Users\\me\\AppData\\Local\\Temp\\sara-look-x\\look.png"

var _host: Node = null
var _folder: String = ""

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


func before_each() -> void:
    _folder = SaDataRoot.path("test_d2_paths_%d" % OS.get_process_id())
    _host = Node.new()
    _host.name = "PathsTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    if _host != null:
        _host.free()
        _host = null
    var machine := ProjectSettings.globalize_path(_folder)
    if not DirAccess.dir_exists_absolute(machine):
        return
    for name in DirAccess.get_files_at(machine):
        DirAccess.remove_absolute(machine.path_join(name))
    DirAccess.remove_absolute(machine)


## A path the engine reads as absolute stays as it was sent, and only a name
## goes under the folder.
func test_look_path_leaves_an_absolute_path_alone() -> void:
    var folder := "/tmp/captures"
    for sent: String in [
        "/tmp/a/look.png",
        "\\\\server\\share\\look.png",
        DRIVE_PATH,
        "C:/Users/me/look.png",
        SaDataRoot.DEFAULT + "look.png",
        "res://look.png"
    ]:
        assert_eq(ScenarioDocument.look_path(folder, sent), sent, "%s is absolute and is taken as written" % sent)
    assert_eq(ScenarioDocument.look_path(folder, "look.png"), "/tmp/captures/look.png", "a bare name lands in the folder")
    assert_eq(ScenarioDocument.look_path(folder, "sub/look.png"), "/tmp/captures/sub/look.png", "a relative one too")
    assert_eq(ScenarioDocument.look_path("", "look.png"), "look.png", "and with no folder there is nothing to put it under")


## A `read_pixels` into a `user://` folder answers where the file is on the
## machine, and the file is there under that name.
func test_a_read_answers_a_path_numpy_can_open() -> void:
    var doc := _document()
    DirAccess.make_dir_recursive_absolute(_folder)

    var answer := PixelDriver.read_into(doc, {"layer": 0, "rect": [0, 0, 4, 4], "file": "layer.npy"}, _folder)

    assert_false(answer.has("error"), "the read answers without a refusal: %s" % answer)
    var path := String(answer["path"])
    assert_false(path.contains("://"), "the answer names no Godot path: %s" % path)
    assert_true(path.is_absolute_path(), "but an absolute one")
    assert_eq(path, ProjectSettings.globalize_path(_folder).path_join("layer.npy"), "the one the file was written to")
    var bytes := FileAccess.get_file_as_bytes(path)
    assert_eq(
        bytes.slice(0, 6),
        PackedByteArray([0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]),
        "and opening it, by the machine's own path, gives NumPy's magic"
    )
    doc.free()


## The same read with no `file` names the default file in that folder.
func test_a_read_with_no_file_answers_the_default_name_as_a_machine_path() -> void:
    var doc := _document()
    DirAccess.make_dir_recursive_absolute(_folder)

    var answer := PixelDriver.read_into(doc, {"layer": 0, "rect": [0, 0, 2, 2]}, _folder)

    var path := String(answer["path"])
    assert_eq(path.get_file(), "read_pixels-0.npy", "the default name is the layer's index")
    assert_false(path.begins_with(SaDataRoot.DEFAULT), "and the folder is spelled the machine's way")
    assert_true(FileAccess.file_exists(path), "with the file in it")
    doc.free()


## A bare name lands in the capture folder, and the picture is there.
func test_look_writes_a_bare_name_into_the_capture_folder() -> void:
    var canvas := _canvas()
    var document := ScenarioDocument.new(SaCaptureRun.new(_folder))

    document.look({"path": "look.png"})

    var machine := ProjectSettings.globalize_path(_folder).path_join("look.png")
    assert_true(FileAccess.file_exists(machine), "the picture is in the folder, at %s" % machine)
    canvas.free()


## A path with a drive letter and backslashes is where the client said, and the
## step neither puts the capture folder in front of it nor makes the folder.
## Linux has no such drive, so the engine logs that it cannot save the picture,
## and the log line is the step doing what it was told.
func test_look_does_not_put_the_capture_folder_before_a_drive_letter() -> void:
    var canvas := _canvas()
    var document := ScenarioDocument.new(SaCaptureRun.new(_folder))

    document.look({"path": DRIVE_PATH})

    assert_false(
        DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_folder)), "nothing was made under the capture folder"
    )
    canvas.free()


## An absolute path of this machine is written as it is, folder or not.
func test_look_writes_an_absolute_path_where_it_was_told() -> void:
    var canvas := _canvas()
    var elsewhere := OS.get_temp_dir().path_join("sara-d2-look-%d.png" % OS.get_process_id())
    var document := ScenarioDocument.new(SaCaptureRun.new(_folder))

    document.look({"path": elsewhere})

    assert_true(FileAccess.file_exists(elsewhere), "the picture is at %s" % elsewhere)
    assert_false(
        DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_folder)), "and the capture folder was not made for it"
    )
    DirAccess.remove_absolute(elsewhere)
    canvas.free()


func _document() -> SaDocument:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := SaDocument.new()
    doc.setup_default_document(SIZE, compositor)
    return doc


## A live canvas in the tree, the one `look` reads back.
func _canvas() -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = SIZE
    canvas.easel = SaEasel.create_default(SIZE, null, SaColorSpace.oklab())
    canvas.add_child(canvas.easel)
    _host.add_child(canvas)
    canvas.easel.request_full_composite()
    _front = Fixtures.FrontDocuments.over(canvas)
    canvas.easel.process_pending_composite()
    return canvas
