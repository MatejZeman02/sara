## A freeze leaves a line in the log that says where.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Each test reads the lines it caused out of the run's own log, the file
## `SaTrail.log_path()` names, from the length it had before. The engine flushes
## that file after every line in a debug build, which the editor binary the gate
## runs is, so what a test printed is on disk when it reads.
##
## The quit is driven on a Main built as the suites build one, with `_ready`
## left empty so putting it in the tree boots nothing, and its canvas a planted
## one holding unsaved work, so the question is asked and no docker or bar is
## built to reach it. The window manager's
## close request is not driven: on a Main that has not booted it calls the
## engine's quit, which would end the run.
extends "res://tests/test_framework.gd"


## Main with its boot taken out. A Godot 4 override does not chain to the
## parent's `_ready`, so this one in the tree builds no window and no canvas.
class QuietMain:
    extends "res://ui/main/main.gd"

    var planted: SaCanvas = null

    func _ready() -> void:
        pass

    ## The planted canvas, and no dockers and no bar built to reach it.
    func get_canvas() -> SaCanvas:
        return planted


var _host: Node = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "D17TestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


## The quit from the request to the hand-over, with unsaved work and Discard as
## the answer, which is the close that froze on Windows.
func test_the_quit_says_every_stage_in_order() -> void:
    var planted := _planted_canvas()
    var main := QuietMain.new()
    main.name = "Main"
    main.is_test_environment = true
    main.planted = planted
    _host.add_child(main)
    main.autosave = SaAutosave.new()
    main.add_child(main.autosave)

    var from := _log_length()
    main._request_quit()
    var question := _question(main)
    assert_true(question != null, "Unsaved work is asked about")
    if question != null:
        question._answer(SaDocumentFiles.PROMPT_DISCARD)
    var lines := _lines_since(from, SaTrail.TRAIL)

    assert_eq(
        lines,
        PackedStringArray(
            [
                "quit asked",
                "asked whether to save the changes to Untitled before quitting",
                "answered Discard",
                "the recovery copy removed",
                "quit called, and a suite stops short of the engine's quit",
            ]
        ),
        "One line per stage, in the order the quit takes them"
    )
    assert_eq(SaTrail.last(), lines[-1] if not lines.is_empty() else "", "and the last stage is what a stall would name")
    _free_planted(planted)


## A teardown before the quit is a suite freeing a canvas, so it says nothing.
func test_a_teardown_outside_a_quit_is_noted_and_not_printed() -> void:
    var from := _log_length()
    SaTrail.teardown("the sibling suite's teardown")
    assert_eq(SaTrail.last(), "the sibling suite's teardown", "It is noted, for a stall to name")
    assert_eq(_lines_since(from, SaTrail.TRAIL), PackedStringArray(), "and no line is printed")


## Six seconds on the main thread: the watcher speaks while it is held, naming
## what Sara was doing and how long ago that place was written, and the frame
## that comes after says how long it took.
##
## The age grows with the hold here, so it reads as about the
## frame's own length, which is what a place written inside the frame looks
## like. A place left over from a load reads as minutes instead.
##
## The watch is built here rather than through `SaTrail.watch`, which hangs it
## from the root, and the root takes no child while the runner is in its own
## `_ready`. That it leaves after every other node of Sara's is what the
## scenario's log shows.
func test_a_held_main_thread_is_named_while_it_is_held() -> void:
    var watch := SaTrail.Watch.new()
    _host.add_child(watch)
    SaTrail.note("the sibling suite's six second hold")
    var from := _log_length()
    OS.delay_msec(6000)
    var held := _lines_since(from, SaTrail.STALL)
    assert_eq(held.size(), 1, "One line while the thread is held: %s" % "|".join(held))
    if held.size() == 1:
        assert_true(held[0].begins_with("the main thread has been stuck for 5."), "after about five seconds: %s" % held[0])
        assert_true(
            held[0].contains("at the sibling suite's six second hold, noted 5.") and held[0].ends_with(" s ago"),
            "naming what Sara was doing and when it went there: %s" % held[0]
        )

    watch._process(0.0)
    var after := _lines_since(from, SaTrail.STALL)
    assert_eq(after.size(), 2, "The frame that comes says so: %s" % "|".join(after))
    if after.size() == 2:
        assert_true(after[1].begins_with("a frame took 6."), "with its length: %s" % after[1])
        assert_true(
            after[1].contains("at the sibling suite's six second hold, noted 6.") and after[1].ends_with(" s ago"),
            "and the same place, as old as the frame: %s" % after[1]
        )

    watch._process(0.0)
    assert_eq(_lines_since(from, SaTrail.STALL).size(), 2, "A frame on time says nothing")
    watch.finish()
    assert_false(watch._thread.is_started(), "The finish joins the thread")
    _host.remove_child(watch)
    watch.free()


## Main starts the watch at the end of its boot, and a suite's Main, which never
## joins a tree, starts none.
func test_a_main_outside_any_tree_starts_no_watch() -> void:
    var detached := QuietMain.new()
    assert_eq(SaTrail.watch(detached), null, "No tree, so no root to hang it from")
    detached.free()


## The launcher's `--log-file` is followed through `SARA_LOG_FILE`, and without
## it the project's setting is.
func test_the_log_is_found_where_the_launcher_put_it() -> void:
    var asked := OS.get_environment("SARA_LOG_FILE")
    if not asked.is_empty():
        assert_eq(SaTrail.log_path(), asked, "The gate's own log file")
        assert_true(FileAccess.file_exists(asked), "which this run is writing")
    OS.set_environment("SARA_LOG_FILE", "")
    var configured: Variant = ProjectSettings.get_setting("debug/file_logging/log_path")
    assert_eq(SaTrail.log_path(), ProjectSettings.globalize_path(String(configured)), "Without it, the project's")
    OS.set_environment("SARA_LOG_FILE", asked)


func _planted_canvas() -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.easel = SaEasel.new()
    canvas.easel.document = SaDocument.new()
    canvas.easel.document.modified = true
    return canvas


## The canvas first, which lets go of the easel, and the easel before the
## document it lets go of.
func _free_planted(canvas: SaCanvas) -> void:
    var easel := canvas.easel
    var document := easel.document
    canvas.free()
    easel.free()
    document.free()


func _question(main: Node) -> SaMessage:
    for child: Node in main._files.get_children():
        if child is SaMessage:
            return child
    return null


func _log_length() -> int:
    return _log_text().length()


func _log_text() -> String:
    var path := SaTrail.log_path()
    if not FileAccess.file_exists(path):
        return ""
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""


## The lines printed since *from* that open with *prefix*, the prefix taken off.
func _lines_since(from: int, prefix: String) -> PackedStringArray:
    var out := PackedStringArray()
    for line in _log_text().substr(from).split("\n"):
        var trimmed := line.strip_edges()
        if trimmed.begins_with(prefix):
            out.append(trimmed.substr(prefix.length()).strip_edges())
    return out
