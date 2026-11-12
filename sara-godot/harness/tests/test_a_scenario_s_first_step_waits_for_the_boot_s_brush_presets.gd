## A scenario's first step waits for the brush presets the boot
## holds back.
##
## The boot reads the presets in slices of a few milliseconds a frame and loads
## the first brush slot at their end, so the frames that takes are a time and
## not a count. A recorded scenario's first stroke came 27 frames after it
## on one machine and before it on a busy one, where the stroke began in the
## Brush's own defaults and went on in Paint, 2 runs in 12. The capture's settle
## now ends when the hold does, and these cases read that through the capture's
## own `_process`, since a suite runs no frames.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## Two steps that do nothing and a wait longer than any case runs, so a capture
## that ran its steps too soon still never reaches its end, which quits the run.
const STEPS: Array = [{"ping": true}, {"ping": true}, {"wait": 1000}]

static var scratch_dir: String = SaDataRoot.path("test_d14_the_held_presets")
static var shot_dir: String = SaDataRoot.path("test_d14_the_capture")

var _host: Node = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    ScratchFolder.clear(shot_dir)
    _host = Node.new()
    EventBus.add_child(_host)


func after_each() -> void:
    if is_instance_valid(_host):
        EventBus.remove_child(_host)
        _host.free()
    _host = null
    ScratchFolder.clear(scratch_dir)
    ScratchFolder.clear(shot_dir)


## A capture in the tree over [constant STEPS], driven by hand from here on.
## Its warp probe is marked as run, so the first step moves no painter's
## pointer.
func _capture() -> SaCapture:
    var capture := SaCapture.new(shot_dir, STEPS.duplicate(true))
    _host.add_child(capture)
    capture.set_process(false)
    capture.run.pointer_warp_probed = true
    return capture


## Frames of the capture's loop, the settle's among them.
func _frames(capture: SaCapture, count: int) -> void:
    for _i in count:
        capture._process(0.0)


func test_the_first_step_waits_past_the_settle_while_the_boot_holds_the_presets() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var bar := ToolOptionsBar.new()
    bar.name = "ToolOptionsBar"
    _host.add_child(bar)
    var presets := bar.preset_box
    presets.hold_scan()
    bar.preset_store.dir = scratch_dir
    bar.preset_store.save_preset("Ink", StampSettingsScript.new())
    bar.target_tool_machine = machine

    var capture := _capture()
    _frames(capture, SaCapture.SETTLE_FRAMES + 60)
    assert_eq(capture.run.step_index, 0, "Held, no step runs however many frames pass the settle")

    presets.scan()
    assert_false(presets.scan_held, "The scan releases the hold")
    _frames(capture, 1)
    assert_eq(capture.run.step_index, 1, "and the first step runs in the next frame")
    _frames(capture, 1)
    assert_eq(capture.run.step_index, 2, "and the one after it in the frame after that")

    Fixtures.teardown(surface, machine)


func test_with_no_bar_in_the_tree_the_first_step_runs_after_the_settle() -> void:
    var capture := _capture()
    _frames(capture, SaCapture.SETTLE_FRAMES)
    assert_eq(capture.run.step_index, 0, "The settle's frames run no step")
    _frames(capture, 1)
    assert_eq(capture.run.step_index, 1, "and the frame after them runs the first, with nothing held to wait for")
