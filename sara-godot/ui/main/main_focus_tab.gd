## Tab, which hides every open docker and brings the same ones back, and the
## Window menu's Focus Mode row that does the same from a press.
##
## The decision and the memory of what was open are `SaFocusMode`'s. This is
## the path from the key or the row to it: the docker table handed over, where
## each open docker stands for the outlines, the host met again on the way
## back, and the menu's ticks and the usage tally told what changed. It was a
## run of `MainDockers` until it was given a class of its own, so the path a
## frame trace names is one file.
##
## **What the trace sees of a Tab.** `tab dockers` is the hide or the show of
## every docker, inside the key's step. A docker shown again lays out its
## controls in the frame's deferred calls, after the step has returned, and
## that is where a deep stack's Layers docker spent 86 ms of a show on a
## large document. `tab layout` measures those calls, so the time is named
## rather than left in the frame's rest.
##
## A `RefCounted` built and held by `MainDockers`, which keeps the focus mode's
## node as its child: nothing here is connected to a signal, so nothing keeps
## it alive past the dockers.
class_name MainFocusTab
extends RefCounted

## The row that turns focus mode on and off, the first under the Dockers heading.
const ROW := &"focus_mode"

## The chord Focus Mode's row shows when the input map binds nothing to
## `toggle_dockers`, which it does not by default: the router reads a bare Tab as
## a keycode, because a modified Tab has to stay focus traversal, and the
## Shortcuts page shows the same word for the same reason.
const KEY := "Tab"

## Tab's memory of which dockers were open, and the corner message that says
## the mode is on. `MainDockers` adds it as its child, and Main adds that node
## to itself last so the message draws over everything else in the window.
var focus_mode := SaFocusMode.new()

## The store, whose reflow meets the host as it is now on the way back.
var _store: DockerLayoutStore

## The docker table, `MainDockers.get_docker_config`.
var _dockers: Callable

## Writes the tick of the docker row at an index, `(index, on)`.
var _tick: Callable

## The node whose window the dockers stand in.
var _host: Node


func _init(store: DockerLayoutStore, dockers: Callable, tick: Callable, host: Node) -> void:
    _store = store
    _dockers = dockers
    _tick = tick
    _host = host


## Focus Mode's row, a tick row ticked while the dockers are hidden, so the menu
## says the mode is on when every docker row under it reads off.
func add_row(menu: SaChoicePopup) -> void:
    var chord := SaMenu.action_chord(&"toggle_dockers")
    if chord.is_empty():
        chord = KEY
    menu.add_row(ROW, tr("Focus Mode"), true, SaFocusMode.active, "", chord)
    var button := menu.label_button(ROW)
    if button != null:
        button.tooltip_text = tr("Hides every open docker to give the painting the window, and brings back the same ones.")


## A press on the row, after the box was put back: the toggle, then the tick
## from the mode once it has decided, since a Tab with every docker closed
## enters nothing. Asked of *menu* again rather than through a box held from
## before the press, which a rebuild of the list since would have left behind.
func row_pressed(menu: SaChoicePopup) -> void:
    toggle()
    var after := menu.check_box(ROW)
    if after != null:
        after.set_pressed_no_signal(SaFocusMode.active)


## Tab. The way back shows what was open rather than every docker, and each menu
## row is ticked to its own docker's state rather than all to one.
func toggle() -> void:
    var dockers: Array = _dockers.call()
    var began := SaFrameTrace.now()
    _time_the_layout(began)
    var changed: Array = focus_mode.toggle(dockers, _where_they_stand(dockers), SaDockerPin.pinned_ids())
    SaFrameTrace.spent("tab dockers", began)
    # The way back meets the host as it is now, which a resize under Tab changed.
    _store.reflow_to_host()
    for i in dockers.size():
        var win: Window = dockers[i]["node"] as Window
        if win != null and changed.has(dockers[i]["id"]):
            _tick.call(i, win.visible)
            SaUsageTally.docker(dockers[i]["id"], SaUsageTally.SHOWN if win.visible else SaUsageTally.HIDDEN)
    # Nothing is saved and nothing forks: the dockers Tab hid are still the
    # layout, and `SaFocusMode` gives back the same ones.


## Names the deferred calls a shown docker lays out its controls in. Queued
## before the toggle, so the first call runs ahead of every call the toggle
## queues, once the step has returned, and queues the second behind them all.
## The span runs from the first to the second, which is the layout and nothing
## of the step, and the trace counts it outside the step rather than inside it.
## Off, it costs nothing: *began* is nought and nothing is queued.
static func _time_the_layout(began: int) -> void:
    if began <= 0:
        return
    var opened := func() -> void:
        var from := SaFrameTrace.now()
        (func() -> void: SaFrameTrace.spent("tab layout", from)).call_deferred()
    opened.call_deferred()


## Where each open docker stands, docker id to a rectangle in the host window's
## space, for the focus mode to outline once it has hidden them. An embedded
## docker stands where its window says. A docker let out is a window of the
## operating system, and its place in the host's space is the cursor package's
## to compute, the same arithmetic the ring is clipped by.
func _where_they_stand(dockers: Array) -> Dictionary:
    var stood: Dictionary = {}
    var host := _host.get_window() if _host != null and _host.is_inside_tree() else null
    for config: Dictionary in dockers:
        var window: Window = config.get("node") as Window
        if window == null or not window.visible or host == null:
            continue
        if window.is_embedded():
            stood[config.get("id", "")] = Rect2(Vector2(window.position), Vector2(window.size))
        else:
            stood[config.get("id", "")] = SaCursorPolicy.rect_in(host, window)
    return stood
