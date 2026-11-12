## A canvas of odd size still makes a video.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## ffmpeg with libx264 in yuv420p refuses a width or height that is odd and exits
## with 187, so a canvas of 801 by 601 made no video and the docker said only
## that ffmpeg did not. The frames are written by hand as small JPEGs and the
## real ffmpeg is run on them, skipping where there is none.
extends "res://tests/test_framework.gd"

static var scratch_dir: String = SaDataRoot.path("test_odd_video")

var _host: Node = null


func before_each() -> void:
    _host = Node.new()
    EventBus.add_child(_host)
    _wipe()


func after_each() -> void:
    _host.free()
    _host = null
    _wipe()


func _wipe() -> void:
    if not DirAccess.dir_exists_absolute(scratch_dir):
        return
    for file_name: String in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(scratch_dir.path_join(file_name))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_dir))


func _frames(size: Vector2i) -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_dir))
    for i in range(1, 4):
        var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGB8)
        image.fill(Color(0.2 * i, 0.4, 0.6))
        image.save_jpg(scratch_dir.path_join(SaRecorder.FRAME_PATTERN % i), 0.9)


## Starts the recorder over the frames and waits for ffmpeg to end.
func _make(video: String) -> SaRecorder:
    var recorder := SaRecorder.new()
    _host.add_child(recorder)
    recorder.directory = scratch_dir
    recorder.frame_count = 3
    var pid := recorder.make_video(video)
    assert_true(pid >= 0, "ffmpeg is started")
    var waited := 0
    while pid >= 0 and OS.is_process_running(pid) and waited < 200:
        OS.delay_msec(50)
        waited += 1
    return recorder


func test_frames_of_801_by_601_make_a_video() -> void:
    if not SaRecorder.ffmpeg_available():
        skip("ffmpeg is not on PATH")
        return
    _frames(Vector2i(801, 601))
    var video := scratch_dir.path_join("timelapse.mp4")
    var recorder := _make(video)
    var file := FileAccess.open(video, FileAccess.READ)
    assert_not_null(file, "The video is there")
    if file != null:
        assert_true(file.get_length() > 0, "and holds something")
        file.close()
    assert_eq(recorder.video_error(), "", "and ffmpeg had nothing to say")


func test_the_last_line_ffmpeg_says_is_kept_when_it_fails() -> void:
    if not SaRecorder.ffmpeg_available():
        skip("ffmpeg is not on PATH")
        return
    _frames(Vector2i(64, 48))
    # A folder that is not there stands in for any output ffmpeg cannot write.
    var recorder := _make(scratch_dir.path_join("missing").path_join("timelapse.mp4"))
    assert_false(recorder.video_error().is_empty(), "A failed run leaves a line to show")
