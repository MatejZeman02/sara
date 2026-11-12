## No frame of the boot holds the window longer than 300 ms.
##
## The longest boot frame read 559 and 705 ms on a slow machine. Three stages were
## over, each now spread over frames of its own: the built-in dockers' windows
## a slice a frame, the modules' scripts waited for a frame at a time rather
## than collected in one, and the tool options of the bar and the docker wired
## a frame each after the machine holds its tools rather than both on the
## machine's first tool change. The figures themselves are the running app's,
## `scenarios/no-boot-frame-holds-the-window-past-three-hundred-milliseconds.json`.
## This suite pins the deferrals.
extends "res://tests/test_framework.gd"

static var scratch_path: String = SaDataRoot.path("test_no_boot_frame_holds_the_window.cfg")


## The main canvas's two fields `Main` reads when it wires the dockers, with no
## GPU behind them.
class StandInCanvas:
    extends Control

    var canvas: SaCanvas = null
    var tool_machine := ToolMachine.new()


func after_each() -> void:
    if FileAccess.file_exists(scratch_path):
        DirAccess.remove_absolute(scratch_path)


func _make_main() -> Node:
    var main: Main = load("res://ui/main/main.gd").new()
    main.name = "Main"
    main.is_test_environment = true
    main.dockers.layout_store.path = scratch_path
    var stand_in := StandInCanvas.new()
    stand_in.name = "MainCanvas"
    main.add_child(stand_in)
    main._ensure_children_initialized()
    return main


func test_a_long_boot_frame_is_kept_with_every_other() -> void:
    SaBootMarks.boot_frame()
    OS.delay_usec(SaBootMarks.LONG_FRAME_USEC + 20000)
    SaBootMarks.boot_frame()
    var t := SaBootMarks.table()
    assert_true(t.has("long_boot_frames"), "a frame over the line is kept")
    var kept: Array = t["long_boot_frames"]
    var last: Dictionary = kept[-1]
    assert_true(float(last["ms"]) >= SaBootMarks.LONG_FRAME_USEC / 1000.0, "with how long it held: %s" % last)
    assert_true(float(last["from_ms"]) > 0.0, "and when it began")

    SaBootMarks.boot_frame()
    assert_eq((SaBootMarks.table()["long_boot_frames"] as Array).size(), kept.size(), "a short frame is not kept")


func test_the_built_in_dockers_register_a_slice_at_a_time() -> void:
    var registry := SaUIRegistry.new()
    var dockers := MainDockers.new(registry)
    assert_false(dockers.register_builtin_dockers(1), "a one microsecond slice stops before the last docker")
    assert_eq(registry.list_dockers().size(), 1, "having registered one, so every call moves on")

    var calls := 1
    while not dockers.register_builtin_dockers(1) and calls < 1000:
        calls += 1
    var all := registry.list_dockers().size()
    assert_true(all > 10, "every built-in is registered in the end: %d" % all)
    assert_eq(calls + 1, all, "one a call at that slice")
    assert_true(dockers.register_builtin_dockers(1), "and a call after the last registers nothing and says so")
    assert_eq(registry.list_dockers().size(), all, "nothing twice")
    dockers.free()


func test_no_slice_registers_every_built_in_at_once() -> void:
    var registry := SaUIRegistry.new()
    var dockers := MainDockers.new(registry)
    assert_true(dockers.register_builtin_dockers(), "the default registers them all in one call")
    assert_true(registry.list_dockers().size() > 10, "every built-in")
    dockers.free()


func test_the_tool_options_are_wired_after_the_tools_are_bound() -> void:
    var main := _make_main()
    var machine: ToolMachine = main.main_canvas.tool_machine
    var docker := main.dockers.registered_docker_node(&"ToolOptionsDocker") as ToolOptionsDocker
    assert_true(docker != null, "the boot built the Tool Options docker")

    main._wire_the_dockers()
    assert_eq(main.tool_options_bar.target_tool_machine, null, "the dockers' stage leaves the bar following no machine")
    assert_eq(docker.target_tool_machine, null, "and the docker too, so the first tool change builds neither")

    main._wire_the_tool_options()
    assert_eq(main.tool_options_bar.target_tool_machine, machine, "the stage after the tools are bound wires the bar")
    assert_eq(docker.target_tool_machine, machine, "and the docker")
    assert_eq(docker.peer_bar, main.tool_options_bar, "with the bar as its peer")
    main.free()
    machine.free()
