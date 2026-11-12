## No boot frame holds the window over 300 ms on Windows.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Seven boots of `perf-boot.json` under Windows held one frame 301.5 to
## 313.4 ms warm and 452.3 cold, the frame that loaded the main script and the
## main scene, ran `Main._init` and `_ready` and built the canvas. The next
## longest, 256 to 266 ms, built the Tool Options docker's controls for every
## tool, and was the longest on Linux at 186 to 207 ms. The canvas is a frame
## of its own after the main scene's now, and the docker's controls a slice a
## frame, the brush's alone in the first.
##
## The boot is driven here a frame at a time: `SteppedMain` waits on the
## suite's own signal where the boot waits on the engine's frame, and writes
## down what was built by the end of each frame. The figures themselves are the
## running app's, `scenarios/perf-boot.json` read by `scripts/sara_perf.py`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The boot builds a real canvas, which needs a RenderingDevice.
const REQUIRES_GPU := true

static var scratch_layout: String = SaDataRoot.path("test_d11_docker_layout.cfg")
static var scratch_picture: String = SaDataRoot.path("test_d11_last_session.webp")


## A Main whose frames are the suite's to give. Each wait for the next frame
## writes down what the boot has built by then and waits for `step`.
class SteppedMain:
    extends "res://ui/main/main.gd"

    signal step

    ## One entry per frame the boot has ended: whether the canvas was built,
    ## how many tools the Tool Options docker had built controls for, and
    ## whether the docker was following the machine.
    var ended: Array[Dictionary] = []

    func _next_frame() -> void:
        var docker := dockers.registered_docker_node(SaDockerIds.TOOL_OPTIONS) as ToolOptionsDocker
        var tools: int = docker.options._built_tools.size() if docker != null else 0
        var bound := docker != null and docker.target_tool_machine != null
        ended.append({"canvas": main_canvas != null, "docker_tools": tools, "docker_bound": bound})
        await step


## A Main that never entered the tree leaves two holds behind when it is
## freed, and both are let go of here. The boot registered its modules in
## `ModuleLoader`, where the stamp brush's `SaMakerCurve` goes on hearing every
## pressure curve a later suite saves, and the brush in hand stays in
## `SaCursorPolicy`, which only a canvas leaving the tree gives back. Between
## them they kept the boot's brush settings, with the five pattern kernels the
## Tool Options docker compiled for its chooser, to the engine's exit: the
## curve suite's saves started settle timers on the stale curve, which no frame
## of the run ever fires, and once a later suite's canvas gave the cursor back
## those timers were the last hold, let go of after the shader compiler was
## freed. The whole run then ended in five script errors.
func after_each() -> void:
    ModuleLoader.unload_all()
    SaCursorPolicy.clear_tool_cursor()
    for path: String in [scratch_layout, scratch_picture]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## `main_init` is marked in `_init` and `bootstrap_begin` in `_ready`, which
## `SaBoot` runs in the frame that loaded the main script. The canvas is the
## frame after.
func test_main_init_and_the_canvas_fall_in_different_frames() -> void:
    var main := _stepped_main()
    main._ready()
    assert_eq(main.ended.size(), 1, "_ready ended its frame and returned")
    assert_eq(main.main_canvas, null, "having built no canvas in the frame main_init fell in")
    assert_false(main.ended[0]["canvas"], "and the frame said so as it ended")

    main.step.emit()
    assert_eq(main.ended.size(), 2, "the next frame ended in turn")
    assert_true(main.ended[1]["canvas"], "having built the canvas")
    assert_true(main.main_canvas != null and main.main_canvas.canvas != null, "a real one, with its SaCanvas")

    var frames := _run_to_the_end(main)
    assert_true(main._booted, "the rest of the boot ran to its end, %d frames" % frames)
    main.free()


## The docker is handed the machine in the frame its last tool's controls were
## built in, so the slices cost no frame of their own after them, and not
## before, so its first sync finds every row.
func test_the_docker_follows_the_machine_once_every_tool_has_controls() -> void:
    var main := _stepped_main()
    main._ready()
    _run_to_the_end(main)
    var tools: int = main.main_canvas.tool_machine.registry.list_descriptors().size()
    var bound_at := -1
    for index in main.ended.size():
        if main.ended[index]["docker_bound"]:
            bound_at = index
            break
    assert_true(bound_at > 0, "the docker was bound during the boot")
    if bound_at > 0:
        assert_eq(main.ended[bound_at]["docker_tools"], tools, "with every tool's controls built by the end of that frame")
        assert_true(main.ended[bound_at - 1]["docker_tools"] < tools, "and some still to build at the end of the frame before")
    main.free()


func test_a_slice_builds_the_dockers_controls_a_tool_at_a_time() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var docker := ToolOptionsDocker.new()
    var rebuilt: Array[int] = [0]
    docker.options.binding.tools_changed.connect(func(was_rebuilt: bool) -> void: rebuilt[0] += 1 if was_rebuilt else 0)
    var tools := machine.registry.list_descriptors().size()
    assert_true(tools > 2, "the fixture's registry holds several tools: %d" % tools)

    assert_false(docker.options.binding.build_a_slice(machine, 1), "a one microsecond slice stops before the last tool")
    assert_eq(docker.options._built_tools.size(), 1, "having built one, so every call moves on")
    assert_eq(docker.options.binding._machine, machine, "and it follows the machine from the first slice")
    var calls := 1
    while not docker.options.binding.build_a_slice(machine, 1) and calls <= tools:
        calls += 1
    assert_eq(calls + 1, tools, "one tool a call at that slice")
    assert_eq(docker.options._built_tools.size(), tools, "every tool has its controls in the end")
    assert_true(rebuilt[0] > 0, "and the docker heard that controls came")

    var keys := docker.options._entries.keys()
    var announced := rebuilt[0]
    docker.options.binding.follow(machine)
    assert_eq(docker.options._entries.keys(), keys, "follow after the last slice builds nothing")
    assert_eq(rebuilt[0], announced, "and announces nothing")

    var followed := ToolOptionsDocker.new()
    followed.options.binding.follow(machine)
    assert_eq(keys, followed.options._entries.keys(), "the slices built the controls one follow builds, in its order")
    var whole := ToolOptionsDocker.new()
    assert_true(whole.options.binding.build_a_slice(machine, 0), "and no slice builds every tool in one call")
    assert_eq(whole.options._entries.keys(), keys, "the same controls")
    docker.free()
    followed.free()
    whole.free()
    Fixtures.teardown(surface, machine)


func _stepped_main() -> SteppedMain:
    var main := SteppedMain.new()
    main.name = "Main"
    main.is_test_environment = true
    main.dockers.layout_store.path = scratch_layout
    main.last_session_path = scratch_picture
    return main


## Gives the boot frames until it has finished, and says how many it took.
func _run_to_the_end(main: SteppedMain) -> int:
    var frames := main.ended.size()
    while not main._booted and frames < 1000:
        main.step.emit()
        frames += 1
    return frames
