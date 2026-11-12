## A file dropped onto Sara brings Sara's window forward, restored when it was
## minimised, before the question the drop asks opens, and a second start that
## hands its file over goes through the same helper.
##
## The document files object lives in a window of its own under the suite's
## tree, so `get_window()` is a window the suite can minimise, and
## `SaWindowForward.raise` is swapped for a witness that records each call with
## the window's mode and whether the fit dialog had opened by then. The drop
## from a real file manager on a seat is read by hand.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Placing a picture rebinds the easel's textures, which needs a RenderingDevice.
const REQUIRES_GPU := true

## 300 by 200, so on a 64 by 64 canvas the fit dialog asks.
const PICTURE := "res://tests/data/import_gradient.png"
const SAD := "res://tests/data/plain_v4.sad"

var _formats: SaRegistries
var _saved_recent: Array = []
var _saved_fit: String = ""
var _asked_depth: bool = true
var _saved_raise: Callable
var _window: Window = null
var _canvas: SaCanvas = null
var _files: SaDocumentFiles = null
## One entry per raise: the mode the window had and whether a fit dialog was open.
var _calls: Array[Dictionary] = []


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    _saved_recent = SaSettings.recent_files()
    _saved_fit = SaSettings.import_fit
    _asked_depth = SaSettings.ask_when_opening
    SaSettings.import_fit = "ask"
    SaSettings.ask_when_opening = false
    _saved_raise = SaWindowForward.raise
    _calls.clear()
    SaWindowForward.raise = func(window: Window) -> void:
        _calls.append({"mode": window.mode, "dialog": _dialog_open(), "window": window})
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(64, 64)
    _canvas.easel = SaEasel.create_default(Vector2i(64, 64))
    _canvas.add_child(_canvas.easel)
    _window = Window.new()
    _window.name = "U499Window"
    _files = SaDocumentFiles.new(func() -> SaCanvas: return _canvas)
    _window.add_child(_files)
    # Deferred, since the first case runs while the root is still setting up
    # the runner's children and refuses a child then.
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.add_child.call_deferred(_window)
    await tree.process_frame


func after_each() -> void:
    SaWindowForward.raise = _saved_raise
    _window.free()
    _canvas.free()
    for path: String in [PICTURE, SAD]:
        SaSettings.remove_recent_file(path)
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))
    SaSettings.import_fit = _saved_fit
    SaSettings.ask_when_opening = _asked_depth


func _dialog_open() -> bool:
    for child in _files.find_children("*", "SaImportFitDialog", true, false):
        if (child as Window).visible:
            return true
    return false


func _drop(path: String) -> void:
    _window.files_dropped.emit(PackedStringArray([ProjectSettings.globalize_path(path)]))
    await (Engine.get_main_loop() as SceneTree).process_frame
    await (Engine.get_main_loop() as SceneTree).process_frame


func test_a_dropped_picture_brings_the_window_forward_before_its_fit_dialog() -> void:
    await _drop(PICTURE)
    assert_eq(_calls.size(), 1, "one drop of a picture raises the window once")
    if _calls.is_empty():
        return
    assert_eq(_calls[0]["window"], _window, "and the window it raises is the one the drop landed on")
    assert_false(bool(_calls[0]["dialog"]), "before the fit dialog opens")
    assert_true(_dialog_open(), "and the fit dialog opens after it")


func test_a_dropped_sad_brings_the_window_forward_once() -> void:
    await _drop(SAD)
    assert_eq(_calls.size(), 1, "one drop of a .sad raises the window once")


func test_a_minimised_window_is_restored_before_it_is_raised() -> void:
    _window.mode = Window.MODE_MINIMIZED
    await _drop(PICTURE)
    assert_eq(_calls.size(), 1, "a drop on a minimised window raises it once")
    if _calls.is_empty():
        return
    assert_true(int(_calls[0]["mode"]) != Window.MODE_MINIMIZED, "and it is no longer minimised when it is raised")


func test_a_file_nothing_takes_raises_nothing() -> void:
    await _drop("res://project.godot")
    assert_eq(_calls.size(), 0, "a drop Sara does not take leaves the other window in front")


func test_the_single_instance_handover_uses_the_same_helper() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var lock := SaDataRoot.path("single-instance.lock")
    var listener := SaSingleInstance.Listener.new(lock, true)
    _window.mode = Window.MODE_MINIMIZED
    _window.add_child(listener)
    var opened := PackedStringArray()
    listener.serve(func(path: String) -> void: opened.append(path))
    var held := SaSingleInstance.read_lock(lock)
    var peer := StreamPeerTCP.new()
    assert_eq(peer.connect_to_host(SaSingleInstance.LOOPBACK, int(held.get("port", 0))), OK, "a second start reaches the first")
    var line := JSON.stringify({"token": str(held.get("token", "")), "paths": ["/tmp/handed.sad"]}) + "\n"
    var sent := false
    for i in 120:
        peer.poll()
        if not sent and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
            peer.put_data(line.to_utf8_buffer())
            sent = true
        if not _calls.is_empty():
            break
        await tree.process_frame
    peer.disconnect_from_host()
    listener.free()
    assert_eq(opened, PackedStringArray(["/tmp/handed.sad"]), "the handed path opens")
    assert_eq(_calls.size(), 1, "and _take raises the window through SaWindowForward, once")
    if _calls.is_empty():
        return
    assert_true(int(_calls[0]["mode"]) != Window.MODE_MINIMIZED, "restored from minimised first, by the same rule as a drop")
