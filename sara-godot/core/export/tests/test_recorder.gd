## The timelapse recorder: a frame after the canvas settles, and no more.
extends "res://tests/test_framework.gd"

## Readbacks and the conversion kernel need a RenderingDevice.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_timelapse")

var _problems: Array[String] = []
var _host: Node = null


func before_each() -> void:
    _problems.clear()
    SaProblems.announce = false
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: _problems.append(line))
    _problems.clear()
    _host = Node.new()
    EventBus.add_child(_host)
    _wipe()


func after_each() -> void:
    SaProblems.detach_sink()
    SaProblems.announce = true
    _wipe()
    if _host != null:
        _host.free()
        _host = null


func _wipe() -> void:
    var dir := DirAccess.open(scratch_dir)
    if dir == null:
        return
    for file_name in dir.get_files():
        dir.remove(file_name)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_dir))


## A canvas with an easel and no viewport, the way the tonemap suite builds one.
func _canvas(space: SaColorSpace = null) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(64, 64)
    canvas.ensure_easel()
    if space != null:
        canvas.document.reset_to_default(Vector2i(64, 64), space)
    # Out of the tree nothing runs the easel's frame, so the composite the
    # readback needs is asked for by hand.
    canvas.easel.request_full_composite()
    canvas.easel.process_pending_composite()
    return canvas


func _recorder(canvas: SaCanvas) -> SaRecorder:
    var recorder := SaRecorder.new()
    _host.add_child(recorder)
    recorder.bind_canvas(canvas)
    recorder.start(scratch_dir)
    return recorder


func test_two_edits_inside_the_quiet_period_are_one_frame() -> void:
    var canvas := _canvas()
    var recorder := _recorder(canvas)
    assert_true(recorder.recording, "Recording")
    assert_eq(recorder.frame_count, 0, "with no frames yet")

    canvas.document.document_changed.emit()
    canvas.document.document_changed.emit()
    assert_eq(recorder.frame_count, 0, "Edits alone write nothing, hard rule 1 is about the readback")
    recorder._on_settled()
    assert_eq(recorder.frame_count, 1, "The quiet period ending writes one frame for both")
    assert_true(FileAccess.file_exists(scratch_dir.path_join("frame_00001.jpg")), "and it is on disk")

    recorder._on_settled()
    assert_eq(recorder.frame_count, 1, "Settling again with nothing new writes nothing")
    canvas.document.document_changed.emit()
    recorder._on_settled()
    assert_eq(recorder.frame_count, 2, "and the next edit is the next frame")
    recorder.stop()
    assert_false(recorder.recording, "Stopped")
    canvas.free()


func test_the_cap_stops_the_recording_and_says_so() -> void:
    var canvas := _canvas()
    var recorder := _recorder(canvas)
    recorder.cap_bytes = 1
    var reasons: Array[String] = []
    recorder.stopped.connect(func(reason: String) -> void: reasons.append(reason))

    recorder.capture_frame()
    assert_eq(reasons, ["cap"], "One frame is over a one-byte cap, so recording stops for the cap")
    assert_false(recorder.recording, "and stays stopped")
    assert_eq(_problems.size(), 1, "and the painter is told")
    assert_true(_problems[0].contains("cap"), "why: %s" % _problems[0])
    canvas.free()


## A timelapse should look like the screen looked. A linear document stores
## its mid grey decoded, 0.214, and the screen shows it encoded as 0.5, so
## the frame has to hold 0.5 and not the stored number.
func test_a_linear_document_is_encoded_for_the_frame() -> void:
    var canvas := _canvas(SaColorSpace.linear_srgb())
    var recorder := _recorder(canvas)
    var background: SaLayer = SaLayerOps.new(canvas.document).layers()[0]
    @warning_ignore("static_called_on_instance")
    var stored := SaExport.get_texture_image_float(background.get_field(Vector2i.ZERO)).get_pixel(32, 32)
    assert_almost_eq(stored.r, SaTransferFunction.srgb().decode(0.5), 0.01, "The document stores the grey decoded")

    var image := recorder.display_image(canvas)
    assert_not_null(image, "A frame can be taken")
    assert_almost_eq(image.get_pixel(32, 32).r, 0.5, 0.02, "and the frame holds the encoded 0.5 the screen shows")

    var plain := _canvas()
    var plain_image := recorder.display_image(plain)
    assert_almost_eq(plain_image.get_pixel(32, 32).r, 0.5, 0.02, "the same 0.5 an sRGB document stores and shows")
    canvas.free()
    plain.free()


func test_frames_continue_the_numbering_a_folder_already_has() -> void:
    var canvas := _canvas()
    var first := _recorder(canvas)
    first.capture_frame()
    first.capture_frame()
    first.stop()

    var second := SaRecorder.new()
    _host.add_child(second)
    second.bind_canvas(canvas)
    second.start(scratch_dir)
    assert_eq(second.frame_count, 2, "A new recording into the same folder counts what is there")
    second.capture_frame()
    assert_true(FileAccess.file_exists(scratch_dir.path_join("frame_00003.jpg")), "and continues after it")
    canvas.free()


func test_ffmpeg_is_asked_rather_than_assumed() -> void:
    var found := SaRecorder.ffmpeg_available()
    assert_true(found or not found, "The check answers without failing: %s" % found)
    var canvas := _canvas()
    var recorder := _recorder(canvas)
    var pid := recorder.make_video(scratch_dir.path_join("timelapse.mp4"))
    assert_eq(pid, -1, "With no frames there is nothing to encode")
    assert_eq(_problems.size(), 1, "and the reason is reported")
    canvas.free()


## The check is a look at `PATH` and not a program run. Running one is what
## put "Could not create child process: ffmpeg -version", with a backtrace on the
## builds that report one, in the console of a machine that has no ffmpeg, once
## per boot, from the Recorder docker's `_ready`, where nothing had gone wrong.
##
## The engine writes every line it prints into `user://logs/godot.log` as it
## prints it, so the suite can read the run's own console and say the check added
## nothing to it. That is the whole of the claim: a check that answered wrongly
## would still have to be silent to pass this, which is why the false answer for
## a program nobody has is asserted beside it.
func test_a_program_that_is_not_there_is_looked_for_and_not_run() -> void:
    var before := _log_text()
    assert_false(SaRecorder.program_available("sara-no-such-program"), "a program nobody has is not found")
    var after := _log_text()
    assert_eq(
        after.length(),
        before.length(),
        "and looking for it writes no line to the engine's log: %s" % after.substr(before.length()).strip_edges()
    )


## The lookup itself, over a `PATH` the test writes: two directories of its own,
## one holding a file of the name asked for and one empty, so the answer is about
## the directories rather than about whichever machine runs the gate.
func test_the_look_answers_about_the_directories_it_is_given() -> void:
    var root := ProjectSettings.globalize_path(SaDataRoot.path("test_recorder_path"))
    var holding := root.path_join("holding")
    var empty := root.path_join("empty")
    DirAccess.make_dir_recursive_absolute(holding)
    DirAccess.make_dir_recursive_absolute(empty)
    var file := FileAccess.open(holding.path_join("sara-probe-program"), FileAccess.WRITE)
    file.store_string("a file of the name, and not a program")
    file.close()

    assert_true(SaRecorder.program_available("sara-probe-program", holding), "a name in the directory asked about is found")
    assert_false(SaRecorder.program_available("sara-probe-program", empty), "and a name in no directory is not")
    assert_true(
        SaRecorder.program_available("sara-probe-program", empty + _path_separator() + holding),
        "the second entry of the list is searched like the first"
    )
    assert_false(SaRecorder.program_available("sara-no-such-program", holding), "another name is another answer")
    assert_false(SaRecorder.program_available("", holding), "and an empty name is nothing to look for")

    DirAccess.remove_absolute(holding.path_join("sara-probe-program"))
    DirAccess.remove_absolute(holding)
    DirAccess.remove_absolute(empty)


## What joins the entries of `PATH`: a semicolon on Windows, where a colon is
## part of a drive letter, and a colon everywhere else.
func _path_separator() -> String:
    return ";" if OS.get_name() == "Windows" else ":"


## Everything the engine has written to its own log so far. A warning, an error
## and a `print` all land there as they happen, which is what makes the console
## of a run readable from inside the run that printed it.
func _log_text() -> String:
    var path := SaTrail.log_path()
    if not FileAccess.file_exists(path):
        return ""
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""


## a changed folder, settle time and cap survive a restart instead of
## resetting to the docker's own defaults each launch.
func test_the_settings_survive_a_save_and_a_load() -> void:
    var path := ProjectSettings.globalize_path(SaDataRoot.path("test_recorder_settings.cfg"))
    var previous_path: String = SaSettings.settings_path
    var previous_directory := SaSettings.recorder_directory
    var previous_settle := SaSettings.recorder_settle_seconds
    var previous_cap := SaSettings.recorder_cap_bytes

    SaSettings.settings_path = path
    SaSettings.recorder_directory = SaDataRoot.path("my_timelapse")
    SaSettings.recorder_settle_seconds = 5.5
    SaSettings.recorder_cap_bytes = 42 * 1048576

    SaSettings.load_settings()

    assert_eq(SaSettings.recorder_directory, SaDataRoot.path("my_timelapse"), "The folder comes back")
    assert_almost_eq(SaSettings.recorder_settle_seconds, 5.5, 0.0001, "and the settle time")
    assert_eq(SaSettings.recorder_cap_bytes, 42 * 1048576, "and the cap")

    SaSettings.settings_path = previous_path
    SaSettings.recorder_directory = previous_directory
    SaSettings.recorder_settle_seconds = previous_settle
    SaSettings.recorder_cap_bytes = previous_cap
    DirAccess.remove_absolute(path)
