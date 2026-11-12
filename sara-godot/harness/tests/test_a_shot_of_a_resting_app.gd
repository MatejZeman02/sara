## A shot after a long quiet wait writes its file rather than nothing.
##
## `shoot` opened with `await RenderingServer.frame_post_draw`, which resumes
## only once something has queued a redraw. Low-processor mode is on,
## so a scenario step reached after a long `wait` could sit with nothing
## queuing a frame at all, and the await never resumed: no PNG, no warning, no
## `SaCapture:` line. `scripts/sara_shot.py --scenario` reproduced it twice, and
## `scenarios/a-shot-of-a-resting-app.json` is the running-app proof, where
## `--out` holds the two shots the fixed tree writes. This suite is the
## synchronous half: `force_draw` needs no signal to wait for, so a call with
## nothing pending still writes, which the removed `await` is what this test
## would have hung on before the fix.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true


func test_a_shot_writes_its_file_with_nothing_queuing_a_redraw() -> void:
    var out_dir := SaDataRoot.path("f1_resting_shot_test")
    var absolute := ProjectSettings.globalize_path(out_dir)
    DirAccess.make_dir_recursive_absolute(absolute)
    var target := absolute.path_join("resting.png")
    if FileAccess.file_exists(target):
        DirAccess.remove_absolute(target)

    # EventBus rather than `tree.root` directly: the root window is still
    # setting up its own children while a suite runs, and `add_child` on it
    # fails right where `test_cursor_modes.gd` routes around the same thing.
    var capture := SaCapture.new(out_dir)
    EventBus.add_child(capture)

    var was_low := OS.low_processor_usage_mode
    OS.low_processor_usage_mode = true
    # Nothing between here and the call below asks for a redraw, which is the
    # state a scenario's long `wait` leaves the app in once that mode has
    # taken hold, and is exactly what the old await hung on.
    capture.run.shoot("resting")
    OS.low_processor_usage_mode = was_low

    assert_true(FileAccess.file_exists(target), "the resting frame is captured rather than left unasked for")

    capture.free()
    if FileAccess.file_exists(target):
        DirAccess.remove_absolute(target)
    DirAccess.remove_absolute(absolute)
