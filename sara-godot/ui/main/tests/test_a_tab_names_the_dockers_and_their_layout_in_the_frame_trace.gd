## A Tab goes through `MainFocusTab`, and a traced frame names
## the hide or the show of the dockers and the layout the shown ones run in the
## frame's deferred calls, so a slow Tab says where its time went.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The windows sit in an embedded viewport, as `test_focus_mode_leaves_the_layout_as_it_was.gd`'s
## do, and the store over them writes to a scratch file. The trace's peaks keep
## every part a drawn frame named, under the line's 5 ms as well, so the suite
## reads them rather than a line a quick machine would leave bare.
extends "res://tests/test_framework.gd"

const HOST := Vector2i(1200, 800)

const STANDS := {
    "ColorDocker": Vector2i(20, 80),
    "LayersDocker": Vector2i(600, 80),
}

var _root: Node = null
var _host: Control = null
var _table: Array = []
var _ticks: Array = []
var _tab: MainFocusTab = null
var _file: String = SaDataRoot.path("test_focus_tab.cfg")


func before_each() -> void:
    SaFocusMode.leave()
    # A start and a stop leave the peaks of an earlier suite behind.
    SaFrameTrace.start()
    SaFrameTrace.stop()
    DirAccess.remove_absolute(_file)
    _root = Node.new()
    _root.name = "U663TabHost"
    EventBus.add_child(_root)
    var viewport := SubViewport.new()
    viewport.size = HOST
    viewport.gui_embed_subwindows = true
    _root.add_child(viewport)
    _host = Control.new()
    _host.set_anchors_preset(Control.PRESET_FULL_RECT)
    viewport.add_child(_host)
    _table = []
    for docker_id: String in STANDS:
        var window := Window.new()
        window.name = docker_id
        window.size = Vector2i(200, 150)
        _host.add_child(window)
        window.position = STANDS[docker_id]
        window.visible = true
        _table.append({"id": docker_id, "name": docker_id, "node": window})
    var store := DockerLayoutStore.new()
    store.path = _file
    store.dockers_provider = func() -> Array: return _table
    store.save_allowed = func() -> bool: return true
    _root.add_child(store)
    _ticks = []
    _tab = MainFocusTab.new(store, func() -> Array: return _table, func(i: int, on: bool) -> void: _ticks.append([i, on]), _host)
    _root.add_child(_tab.focus_mode)


func after_each() -> void:
    SaFrameTrace.stop()
    SaFocusMode.leave()
    _tab = null
    if _root != null:
        _root.free()
        _root = null
    DirAccess.remove_absolute(_file)


func _open() -> Array:
    var open: Array = []
    for config: Dictionary in _table:
        if (config["node"] as Window).visible:
            open.append(config["id"])
    return open


## Lets the deferred calls run and a frame draw, which hands the frame's parts
## to the trace's peaks.
func _a_frame() -> void:
    await (Engine.get_main_loop() as SceneTree).process_frame
    await (Engine.get_main_loop() as SceneTree).process_frame
    RenderingServer.force_draw(false)


## The way there hides both, the way back shows both, and each docker's row is
## ticked to its own window's state each time.
func test_a_tab_hides_the_open_dockers_and_the_next_brings_the_same_ones_back() -> void:
    _tab.toggle()
    assert_true(SaFocusMode.active, "The first Tab enters focus mode")
    assert_eq(_open(), [], "and every docker is hidden")
    assert_eq(_ticks, [[0, false], [1, false]], "and each row is ticked off: %s" % [_ticks])
    _ticks = []
    _tab.toggle()
    assert_false(SaFocusMode.active, "The second Tab leaves it")
    assert_eq(_open(), STANDS.keys(), "and the same dockers are back")
    assert_eq(_ticks, [[0, true], [1, true]], "and each row is ticked on: %s" % [_ticks])


## A traced Tab names its dockers' hide or show and the layout after it, each
## a part of its own, which would otherwise sit in the frame's rest.
func test_a_traced_tab_names_tab_dockers_and_tab_layout() -> void:
    SaFrameTrace.start(func(_line: String) -> void: pass)
    _tab.toggle()
    await _a_frame()
    assert_true(SaFrameTrace.peaks.has("tab dockers"), "The hide is named: %s" % [SaFrameTrace.peaks])
    assert_true(SaFrameTrace.peaks.has("tab layout"), "and the deferred layout after it: %s" % [SaFrameTrace.peaks])
    _tab.toggle()
    await _a_frame()
    assert_true(SaFrameTrace.peaks.has("tab layout"), "and the show names its layout too")


## Untraced, a Tab queues nothing for the trace: the clock reads nought and the
## layout's bracket is never queued.
func test_an_untraced_tab_names_nothing() -> void:
    _tab.toggle()
    await _a_frame()
    assert_eq(SaFrameTrace.peaks.size(), 0, "No trace, no part: %s" % [SaFrameTrace.peaks])
    assert_true(SaFocusMode.active, "and the Tab did its work all the same")
