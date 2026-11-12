## The Recorder counts frames as taken and says when the video is done.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The line read "Recording. 0 frames so far." for the two seconds before the
## first frame, "1 frames, 0.0 MB" for a 37 KB frame, and "ffmpeg is writing"
## with a path only Godot reads long after the file was there. So the start
## says when a frame comes, counts and sizes read as a painter counts them, and
## Make Video asks after its ffmpeg until it ends. `process_alive` stands in for the process, so
## no case here runs ffmpeg. The run in the app is
## `scenarios/the-recorder-counts-frames-as-taken-and-says-when-the-video-is-done.json`.
extends "res://tests/test_framework.gd"

const DockerScript = preload("res://ui/dockers/recorder/recorder_docker.gd")

## Where a recording in this suite writes, wiped after each case.
static var scratch_dir: String = SaDataRoot.path("test_s69_recorder")

var _saved_directory: String = ""
var _saved_settle: float = 2.0
var _host: Node = null
var _canvas: SaCanvas = null
## What the stand-in process answers when asked whether it still runs.
var _alive: bool = true
## The pids the stand-in was asked about.
var _asked: Array[int] = []


func before_each() -> void:
    _saved_directory = SaSettings.recorder_directory
    _saved_settle = SaSettings.recorder_settle_seconds
    SaSettings.recorder_directory = scratch_dir
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_dir))
    _host = Node.new()
    _host.name = "S69RecorderHost"
    EventBus.add_child(_host)
    _alive = true
    _asked.clear()


func after_each() -> void:
    _host.free()
    _host = null
    if _canvas != null:
        _canvas.free()
        _canvas = null
    SaSettings.recorder_directory = _saved_directory
    SaSettings.recorder_settle_seconds = _saved_settle
    for file_name: String in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_dir.path_join(file_name)))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_dir))


## The docker under a plain Node, so `_init` runs and `_ready` does not, with
## the stand-in process in place of ffmpeg's.
func _detached() -> RecorderDocker:
    var docker := DockerScript.new() as RecorderDocker
    var holder := Node.new()
    _host.add_child(holder)
    holder.add_child(docker)
    docker.process_alive = func(pid: int) -> bool:
        _asked.append(pid)
        return _alive
    return docker


func _write(path: String, bytes: int) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    var body := PackedByteArray()
    body.resize(bytes)
    file.store_buffer(body)
    file.close()


func test_a_size_reads_kb_under_a_megabyte_and_mb_over() -> void:
    assert_eq(RecorderDocker.size_text(0), "0 KB", "Nothing written is 0 KB")
    assert_eq(RecorderDocker.size_text(100), "1 KB", "a few bytes are at least 1 KB, never 0")
    assert_eq(RecorderDocker.size_text(37 * 1024 + 200), "37 KB", "a 37 KB frame reads 37 KB, not 0.0 MB")
    assert_eq(RecorderDocker.size_text(1048575), "1024 KB", "a byte under a megabyte is still KB")
    assert_eq(RecorderDocker.size_text(1048576), "1.0 MB", "a megabyte is MB")
    assert_eq(RecorderDocker.size_text(1258291), "1.2 MB", "and more reads one decimal")


func test_a_count_takes_its_plural() -> void:
    assert_eq(RecorderDocker.frames_text(0), "0 frames", "No frames is plural")
    assert_eq(RecorderDocker.frames_text(1), "1 frame", "one frame is not '1 frames'")
    assert_eq(RecorderDocker.frames_text(2), "2 frames", "two are plural")


func test_the_start_says_when_a_frame_comes() -> void:
    var docker := _detached()
    _canvas = SaCanvas.new()
    docker.recorder.bind_canvas(_canvas)
    SaSettings.recorder_settle_seconds = 2.0
    docker.record_button.button_pressed = true
    var want := "Recording: 0 frames. A frame is taken 2 seconds after each change."
    assert_eq(docker.status.text, want, "The start says the delay the recorder waits")
    docker.record_button.button_pressed = false

    SaSettings.recorder_settle_seconds = 1.0
    docker.record_button.button_pressed = true
    assert_true(docker.status.text.ends_with("taken 1 second after each change."), "one second is singular")
    docker.record_button.button_pressed = false

    SaSettings.recorder_settle_seconds = 0.5
    docker.record_button.button_pressed = true
    assert_true(docker.status.text.ends_with("taken 0.5 seconds after each change."), "and half of one reads 0.5")
    docker.record_button.button_pressed = false


func test_a_frame_written_reads_as_counted() -> void:
    var docker := _detached()
    docker.recorder.frame_count = 1
    docker.recorder.bytes_written = 37 * 1024
    docker.recorder.frame_written.emit(scratch_dir.path_join("frame_00001.jpg"), 1)
    assert_eq(docker.status.text, "Recording: 1 frame, 37 KB.", "One 37 KB frame reads as one frame of 37 KB")


func test_the_video_is_being_made_while_ffmpeg_runs() -> void:
    var docker := _detached()
    var video := scratch_dir.path_join("timelapse.mp4")
    docker.watch_video(4242, video)
    assert_eq(docker.status.text, "Making the video...", "Make Video says it is under way")
    assert_eq(docker.video_path, ProjectSettings.globalize_path(video), "and holds the real path, not a Godot one")
    var real := docker.video_path.is_absolute_path() and not docker.video_path.contains(":/" + "/")
    assert_true(real, "which a file manager can open")
    assert_false(docker.video_timer.is_stopped(), "The timer asks after the process")
    docker.poll_video()
    assert_eq(_asked, [4242] as Array[int], "A look asks after ffmpeg's pid")
    assert_eq(docker.status.text, "Making the video...", "and a running ffmpeg changes nothing")
    assert_false(docker.video_timer.is_stopped(), "so the timer goes on")


func test_an_ended_ffmpeg_with_its_file_says_video_done() -> void:
    var docker := _detached()
    var video := scratch_dir.path_join("timelapse.mp4")
    docker.watch_video(4242, video)
    _write(ProjectSettings.globalize_path(video), 1258291)
    _alive = false
    docker.poll_video()
    var want := "Video done: %s, 1.2 MB." % ProjectSettings.globalize_path(video)
    assert_eq(docker.status.text, want, "An ended ffmpeg with its file says where the video is and its size")
    assert_true(docker.video_timer.is_stopped(), "and the timer stops")
    assert_eq(docker.video_pid, -1, "with no process left to ask after")


func test_an_ended_ffmpeg_without_its_file_says_so() -> void:
    var docker := _detached()
    var video := scratch_dir.path_join("timelapse.mp4")
    var folder := ProjectSettings.globalize_path(scratch_dir)
    var want := "ffmpeg did not make the video. Its frames are still in %s." % folder

    docker.watch_video(4242, video)
    _alive = false
    docker.poll_video()
    assert_eq(docker.status.text, want, "No file at all is no video, and the frames are named where they are")
    assert_true(docker.video_timer.is_stopped(), "and the timer stops")

    docker.watch_video(4243, video)
    _write(ProjectSettings.globalize_path(video), 0)
    docker.poll_video()
    assert_eq(docker.status.text, want, "An empty file is no video either")


func test_the_timer_stops_when_the_docker_leaves() -> void:
    var docker := _detached()
    docker.watch_video(4242, scratch_dir.path_join("timelapse.mp4"))
    assert_false(docker.video_timer.is_stopped(), "A video being made has the timer running")
    docker.get_parent().remove_child(docker)
    assert_true(docker.video_timer.is_stopped(), "and a docker taken off the tree stops it")
    docker.free()
