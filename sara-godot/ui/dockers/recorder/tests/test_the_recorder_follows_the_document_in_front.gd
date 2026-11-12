## The recorder follows the document in front, and a recording goes with it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The docker bound the canvas it first found and kept it, so a recording
## started with one document open wrote nothing once a second was brought
## forward, while its status still said Recording. The host stands in for main
## the way the document tabs suite builds one, and the docker sits under it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const ViewScript := preload("res://render/main_canvas.gd")
const DockerScript = preload("res://ui/dockers/recorder/recorder_docker.gd")

static var scratch_dir: String = SaDataRoot.path("test_recorder_follows")

var _documents: SaDocuments = null
var _host: Node = null
var _first: Control = null
var _tabs: SaDocumentTabs = null
var _docker: RecorderDocker = null
var _saved_directory: String = ""
var _was_embedding := false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _saved_directory = SaSettings.recorder_directory
    SaSettings.recorder_directory = scratch_dir
    _wipe()
    _documents = SaDocuments.new()
    tree.current_scene.set(&"documents", _documents)
    _host = Node.new()
    _host.name = "RecorderFollowHost"
    EventBus.add_child(_host)
    _first = ViewScript.new()
    _host.add_child(_first)
    _documents.add(_first.get("surface") as SaSurface)
    _tabs = SaDocumentTabs.new(_host, _documents, _first)
    _host.add_child(_tabs)
    _docker = DockerScript.new() as RecorderDocker
    _host.add_child(_docker)
    _docker._bind_main_canvas()


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    tree.current_scene.set(&"documents", null)
    tree.root.gui_embed_subwindows = _was_embedding
    _host.free()
    _host = null
    _first = null
    _tabs = null
    _docker = null
    _documents = null
    SaColors.follow(null)
    SaSettings.recorder_directory = _saved_directory
    _wipe()


func _wipe() -> void:
    if not DirAccess.dir_exists_absolute(scratch_dir):
        return
    for file_name: String in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(scratch_dir.path_join(file_name))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_dir))


func test_a_second_document_in_front_is_the_one_recorded() -> void:
    var first := SaCanvasView.canvas_of(_documents.front)
    assert_eq(_docker.recorder._canvas, first, "The recorder starts on the first document")
    _docker.record_button.button_pressed = true
    assert_true(_docker.recorder.recording, "and records it")

    var second_surface := _tabs.add_document()
    var second := SaCanvasView.canvas_of(second_surface)
    assert_eq(_docker.recorder._canvas, second, "A second document brought forward is the canvas it reads")
    assert_true(_docker.recorder.recording, "and the recording goes on")

    second.document.document_changed.emit()
    assert_true(_docker.recorder._pending, "An edit in the second document is waited out for a frame")
    assert_not_null(_docker.recorder.capture_frame(), "which is written")
    assert_eq(_docker.recorder.frame_count, 1, "as the first frame")
    assert_true(FileAccess.file_exists(scratch_dir.path_join("frame_00001.jpg")), "on disk")

    _documents.bring_to_front(_documents.surfaces[0])
    assert_eq(_docker.recorder._canvas, first, "Bringing the first back is followed too")
    _docker.recorder.capture_frame()
    assert_eq(_docker.recorder.frame_count, 2, "its frame is the next in the one count")
    assert_true(FileAccess.file_exists(scratch_dir.path_join("frame_00001.jpg")), "and the earlier frame is still there")
    assert_true(FileAccess.file_exists(scratch_dir.path_join("frame_00002.jpg")), "beside it")


func test_stopping_and_starting_again_binds_the_document_in_front() -> void:
    _docker.record_button.button_pressed = true
    _docker.record_button.button_pressed = false
    # The binding is dropped, as a docker built before any document holds none,
    # so only the start can find the document in front.
    _docker.recorder.bind_canvas(null)
    _tabs.add_document()
    var second := SaCanvasView.canvas_of(_documents.front)
    _docker.record_button.button_pressed = true
    assert_true(_docker.recorder.recording, "Record starts")
    assert_eq(_docker.recorder._canvas, second, "on the document in front")
