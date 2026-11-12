## What a system's frame would do for Sara's borderless main window: a drag on
## the top bar's empty part moves it, a double click there maximises and
## restores it, the window's outermost pixels resize it, and the last windowed
## rectangle is kept for the next restore and the next start.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The project opens the main window borderless, so the system draws no title
## bar and no edges, and before this nothing took their place: the maximise
## button's restore left a window of the screen's size at the screen's corner
## that could be neither moved nor resized.
##
## **The system does the move.** `DisplayServer.window_start_drag` hands the
## drag to the compositor or to Windows, so snapping, tiling and the passage to
## another screen are the system's own. The resize is
## `DisplayServer.window_start_resize` with the edge under the pointer, except
## on Windows, where the engine sends `SC_SIZE` and a window without
## `WS_THICKFRAME`, which a borderless one is, ignores it, so there the edge
## moves the window's rectangle itself from the pointer's place on the screen.
##
## **Read every frame, written when it settles.** The mode, the place and the
## size are asked of the display server each frame, which costs a few calls,
## because a window moved by the system, by Win+arrow or by the maximise button
## announces nothing a node hears. The profile is written once a change has
## held still for `SETTLE_SECONDS`, since the settings file is saved on each
## write and a drag is a hundred of them.
##
## **No window flag is written.** A flag written to a shown
## borderless window on Windows can hide it, so this asks
## for a mode, a size, a place and a minimum size, and nothing else.
##
## A `CanvasLayer` so the eight edge strips sit over every control of the main
## window, the canvas included, at the outermost `REACH` logical pixels only,
## and under the embedded dockers, which the engine draws above every layer.
class_name SaTopBarWindowFrame
extends CanvasLayer

## Above the bars and the canvas, below the boot cover's 1024 and the embedded
## windows the engine draws on its own canvas over every layer.
const LAYER := 512

## How deep the resize strips reach in from the window's edge, in logical
## pixels: the outermost pixels only, so a stroke begun at the canvas's edge
## still paints.
const REACH := 5.0

## How far a corner's strip runs along each of its two sides, in logical pixels.
const CORNER := 16.0

## How far a press on the bar travels before it becomes a move, in logical
## pixels, so a double click is never taken for the start of a drag.
const DRAG_START := 4.0

## The smallest window that keeps both bars and a canvas worth painting on, in
## logical pixels.
const MIN_SIZE := Vector2i(960, 600)

## The share of the screen a first restore takes, centred on it.
const FIRST_RESTORE_SHARE := 0.75

## How long the window's rectangle holds still before the profile is written.
const SETTLE_SECONDS := 0.5

## The resize edges, in `DisplayServer.WindowResizeEdge`'s order and numbers,
## each with the cursor its strip shows.
const CURSORS := {
    DisplayServer.WINDOW_EDGE_TOP_LEFT: Control.CURSOR_FDIAGSIZE,
    DisplayServer.WINDOW_EDGE_TOP: Control.CURSOR_VSIZE,
    DisplayServer.WINDOW_EDGE_TOP_RIGHT: Control.CURSOR_BDIAGSIZE,
    DisplayServer.WINDOW_EDGE_LEFT: Control.CURSOR_HSIZE,
    DisplayServer.WINDOW_EDGE_RIGHT: Control.CURSOR_HSIZE,
    DisplayServer.WINDOW_EDGE_BOTTOM_LEFT: Control.CURSOR_BDIAGSIZE,
    DisplayServer.WINDOW_EDGE_BOTTOM: Control.CURSOR_VSIZE,
    DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT: Control.CURSOR_FDIAGSIZE,
}

## No edge under the point.
const NO_EDGE := -1

## The bar whose empty part moves the window.
var _bar: Control

## The strips, by edge.
var _edges: Dictionary = {}

## The press on the empty bar that has not yet become a move, and where it was.
var _armed: bool = false
var _pressed_at: Vector2 = Vector2.ZERO

## The mode the last frame read, and whether a windowed rectangle is owed to
## the window: after a restore, and at a start the profile says was windowed.
var _last_mode: int = -1
var _restore_owed: bool = false

## What the profile holds, and the state read that differs from it with the
## time it was first read, so a write waits for the window to hold still.
var _kept: Dictionary = {}
var _pending: Dictionary = {}
var _pending_since: float = 0.0

## Whether this frame acts on the window at all. A suite's bar, a display
## server with no windows and a system that owns the window, Android's, leave
## the window alone.
var _live: bool = false


## *bar* is the top bar, whose empty part moves the window and whose child
## this is. *live* says the bar is the running app's own, whose window this
## may size, place and keep, and false leaves the window alone, which a suite
## building a bar inside the test runner's window asks.
func _init(bar: Control, live: bool) -> void:
    name = "WindowFrame"
    layer = LAYER
    _bar = bar
    _live = live
    for edge: int in CURSORS:
        var strip := Edge.new(edge, self)
        _edges[edge] = strip
        add_child(strip)
    visible = false


func _ready() -> void:
    _live = _live and DisplayServer.get_name() != "headless" and OS.get_name() != "Android"
    _kept = SaSettings.main_window.duplicate()
    get_viewport().size_changed.connect(_lay)
    _lay()
    if not _live:
        set_process(false)
        set_process_input(false)
        return
    DisplayServer.window_set_min_size(SaUI.to_physical_v(MIN_SIZE))
    _last_mode = DisplayServer.window_get_mode()
    # A window that was windowed when Sara last closed opens windowed, on
    # the rectangle it held. The project starts it maximised, which is also
    # what a profile that never closed one gets.
    if not _kept.is_empty() and not bool(_kept.get("maximized", true)):
        _restore_owed = true
        if _last_mode != DisplayServer.WINDOW_MODE_WINDOWED:
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _exit_tree() -> void:
    _keep_now()


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        _keep_now()


func _process(_delta: float) -> void:
    var mode := DisplayServer.window_get_mode()
    if mode != _last_mode:
        if mode == DisplayServer.WINDOW_MODE_WINDOWED:
            _restore_owed = true
        _last_mode = mode
    var windowed := mode == DisplayServer.WINDOW_MODE_WINDOWED
    visible = windowed
    if windowed and _restore_owed:
        _restore_owed = false
        place(restore_rect(_kept, _usable_rects(), DisplayServer.window_get_current_screen()))
        return
    if _restore_owed:
        return
    _note(_read())


## The window as the profile keeps it, or empty while it is minimised, which
## changes nothing worth keeping.
func _read() -> Dictionary:
    var mode := DisplayServer.window_get_mode()
    var screen := DisplayServer.window_get_current_screen()
    if mode == DisplayServer.WINDOW_MODE_WINDOWED:
        var rect := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
        return {"maximized": false, "rect": rect, "screen": screen}
    if mode == DisplayServer.WINDOW_MODE_MINIMIZED:
        return {}
    return {"maximized": true, "rect": _kept.get("rect", Rect2i()), "screen": int(_kept.get("screen", screen))}


## Takes a state read, and writes it once it has held still, or at once when
## the window was maximised or restored, which is one change and not a drag.
func _note(now: Dictionary) -> void:
    if now.is_empty() or same(now, _kept):
        _pending = {}
        return
    var clock := Time.get_ticks_msec() / 1000.0
    if now != _pending:
        var flipped := bool(now["maximized"]) != bool(_kept.get("maximized", true))
        _pending = now
        _pending_since = clock
        if not flipped:
            return
    elif clock - _pending_since < SETTLE_SECONDS:
        return
    _keep(now)


## Writes whatever is owed, for a quit that comes before the change settled.
func _keep_now() -> void:
    if _live and not _pending.is_empty() and not same(_pending, _kept):
        _keep(_pending)


func _keep(state: Dictionary) -> void:
    _kept = state.duplicate()
    _pending = {}
    SaSettings.main_window = state.duplicate()


## Whether two kept states say the same, an empty one being a maximised
## window, which is what a profile that never closed one opens as.
static func same(a: Dictionary, b: Dictionary) -> bool:
    var a_max := bool(a.get("maximized", true))
    var b_max := bool(b.get("maximized", true))
    if a_max != b_max:
        return false
    return a.get("rect", Rect2i()) == b.get("rect", Rect2i()) and int(a.get("screen", -1)) == int(b.get("screen", -1))


## The rectangle a restored window takes: the kept one while some screen
## still shows any of it, the kept screen tried first, and otherwise a share of
## the usable part of *screen*, centred on it. A kept rectangle no screen
## touches is a monitor that is gone, and a window put there could not be
## reached, the rule `SecondaryWorkspaceHost.placement` keeps for the second
## workspace.
static func restore_rect(kept: Dictionary, usable: Array[Rect2i], screen: int) -> Rect2i:
    var rect: Rect2i = kept.get("rect", Rect2i())
    if rect.size.x > 0 and rect.size.y > 0:
        var kept_screen := int(kept.get("screen", -1))
        if kept_screen >= 0 and kept_screen < usable.size() and usable[kept_screen].intersects(rect):
            return rect
        for each in usable:
            if each.intersects(rect):
                return rect
    if usable.is_empty():
        return Rect2i()
    var on := usable[clampi(screen, 0, usable.size() - 1)]
    var size := Vector2i((Vector2(on.size) * FIRST_RESTORE_SHARE).round())
    @warning_ignore("integer_division")
    return Rect2i(on.position + (on.size - size) / 2, size)


func _usable_rects() -> Array[Rect2i]:
    var usable: Array[Rect2i] = []
    for screen in DisplayServer.get_screen_count():
        usable.append(DisplayServer.screen_get_usable_rect(screen))
    return usable


## Sizes and places the window. The place is a request Wayland ignores, since
## a client there never learns or chooses where its window is, and the
## compositor puts it.
static func place(rect: Rect2i) -> void:
    if rect.size.x <= 0 or rect.size.y <= 0:
        return
    DisplayServer.window_set_size(rect.size)
    DisplayServer.window_set_position(rect.position)


## Each strip's rectangle in a window of *size* logical pixels, by edge. The
## corners are listed first, so where a corner and a side meet the corner wins.
static func strip_rects(size: Vector2) -> Dictionary:
    var far := size - Vector2(REACH, REACH)
    var along := Vector2(CORNER, CORNER)
    return {
        DisplayServer.WINDOW_EDGE_TOP_LEFT: Rect2(Vector2.ZERO, along),
        DisplayServer.WINDOW_EDGE_TOP_RIGHT: Rect2(Vector2(size.x - CORNER, 0), along),
        DisplayServer.WINDOW_EDGE_BOTTOM_LEFT: Rect2(Vector2(0, size.y - CORNER), along),
        DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT: Rect2(size - along, along),
        DisplayServer.WINDOW_EDGE_TOP: Rect2(Vector2(CORNER, 0), Vector2(size.x - 2 * CORNER, REACH)),
        DisplayServer.WINDOW_EDGE_BOTTOM: Rect2(Vector2(CORNER, far.y), Vector2(size.x - 2 * CORNER, REACH)),
        DisplayServer.WINDOW_EDGE_LEFT: Rect2(Vector2(0, CORNER), Vector2(REACH, size.y - 2 * CORNER)),
        DisplayServer.WINDOW_EDGE_RIGHT: Rect2(Vector2(far.x, CORNER), Vector2(REACH, size.y - 2 * CORNER)),
    }


## The edge a press at *point* would resize from, in a window of *size*
## logical pixels, or `NO_EDGE`. None while the window is maximised, and a
## corner's strip is only its outer `REACH`, so the inner part of the square
## stays the canvas's.
static func edge_at(point: Vector2, size: Vector2, maximized: bool) -> int:
    if maximized:
        return NO_EDGE
    var strips := strip_rects(size)
    for edge: int in strips:
        var rect: Rect2 = strips[edge]
        if rect.has_point(point) and Edge.takes(edge, point - rect.position, rect.size):
            return edge
    return NO_EDGE


## *rect* resized from *edge* by the pointer's travel *moved*, never below
## *least*, the far side staying where it was. Windows' resize, which the
## system does not run for a window with no thick frame.
static func resized(rect: Rect2i, edge: int, moved: Vector2i, least: Vector2i) -> Rect2i:
    var left := rect.position.x
    var top := rect.position.y
    var right := rect.end.x
    var bottom := rect.end.y
    if edge in [DisplayServer.WINDOW_EDGE_LEFT, DisplayServer.WINDOW_EDGE_TOP_LEFT, DisplayServer.WINDOW_EDGE_BOTTOM_LEFT]:
        left = mini(left + moved.x, right - least.x)
    if edge in [DisplayServer.WINDOW_EDGE_RIGHT, DisplayServer.WINDOW_EDGE_TOP_RIGHT, DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT]:
        right = maxi(right + moved.x, left + least.x)
    if edge in [DisplayServer.WINDOW_EDGE_TOP, DisplayServer.WINDOW_EDGE_TOP_LEFT, DisplayServer.WINDOW_EDGE_TOP_RIGHT]:
        top = mini(top + moved.y, bottom - least.y)
    if edge in [DisplayServer.WINDOW_EDGE_BOTTOM, DisplayServer.WINDOW_EDGE_BOTTOM_LEFT, DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT]:
        bottom = maxi(bottom + moved.y, top + least.y)
    return Rect2i(left, top, right - left, bottom - top)


func _lay() -> void:
    var strips := strip_rects(get_viewport().get_visible_rect().size)
    for edge: int in strips:
        var rect: Rect2 = strips[edge]
        var strip: Edge = _edges[edge]
        strip.position = rect.position
        strip.size = rect.size


## A press, a drag and a double click on the bar's empty part, heard before the
## GUI so the row slot's drag-to-scroll and the canvas never see them. ALT is
## left to the bar's own gesture, which opens its line in Preferences.
func _input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if not button.pressed:
            if _armed:
                _armed = false
                get_viewport().set_input_as_handled()
            return
        if button.alt_pressed or not empty_at(button.position):
            return
        get_viewport().set_input_as_handled()
        if button.double_click:
            _armed = false
            SaTopBarWindowButtons.toggle_maximized()
            return
        _armed = true
        _pressed_at = button.position
        return
    var motion := event as InputEventMouseMotion
    if motion == null or not _armed:
        return
    get_viewport().set_input_as_handled()
    if motion.position.distance_to(_pressed_at) < DRAG_START:
        return
    _armed = false
    # Windowed only. Windows will not move a maximised window this way, and a
    # compositor that unmaximises on a drag would race the restore this frame
    # puts the window on.
    if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
        DisplayServer.window_start_drag()


## Whether a press at *point*, in the main window's logical pixels, lands on
## the bar where it holds no control. A control is anything shown that stops
## a press, and a row slot whose controls overflow it is one too, since a drag
## on its gaps scrolls it. No open menu either, whose press outside it closes
## it and does nothing more.
func empty_at(point: Vector2) -> bool:
    if _bar == null or not _bar.is_visible_in_tree() or not _bar.get_global_rect().has_point(point):
        return false
    # The top edge and its corners lie over the bar, and they resize.
    if visible and edge_at(point, get_viewport().get_visible_rect().size, false) != NO_EDGE:
        return false
    for sub in get_viewport().get_embedded_subwindows():
        if sub is Popup and sub.visible:
            return false
    return not _taken_at(_bar, point)


func _taken_at(node: Node, point: Vector2) -> bool:
    for child in node.get_children():
        if child == self or child is Window:
            continue
        var control := child as Control
        if control == null:
            continue
        if not control.visible or not control.get_global_rect().has_point(point):
            continue
        if control.mouse_filter == Control.MOUSE_FILTER_STOP:
            return true
        if control is SaRowSlot and _overflows(control as SaRowSlot):
            return true
        if _taken_at(control, point):
            return true
    return false


static func _overflows(slot: SaRowSlot) -> bool:
    var bar := slot.scroll.get_h_scroll_bar()
    return bar.max_value > bar.page + 0.5


## A point on the bar's empty part, in the main window's logical pixels, found
## from the bar's right end along its middle, or an empty array when the bar
## holds controls all the way along. For a hand that has to press where a
## press moves the window.
func empty_point() -> Array:
    var rect := _bar.get_global_rect()
    var y := rect.position.y + rect.size.y / 2.0
    var x := rect.end.x - 1.0
    while x > rect.position.x:
        if empty_at(Vector2(x, y)):
            return [x, y]
        x -= 8.0
    return []


## The main window as numbers, for the door's state: its mode, place, size and
## screen, the screen's usable part, whether the edges are out, a point a drag
## moves it from and what the profile keeps. A shot shows a window and cannot
## say whether it is one the system can move.
static func capture_state(root: Window) -> Dictionary:
    var screen := DisplayServer.window_get_current_screen()
    var usable := DisplayServer.screen_get_usable_rect(screen)
    var position := DisplayServer.window_get_position()
    var size := DisplayServer.window_get_size()
    var kept: Dictionary = SaSettings.main_window
    var frame := root.find_child("WindowFrame", true, false) as SaTopBarWindowFrame
    return {
        "mode": mode_name(DisplayServer.window_get_mode()),
        "position": [position.x, position.y],
        "size": [size.x, size.y],
        "min_size": [DisplayServer.window_get_min_size().x, DisplayServer.window_get_min_size().y],
        "screen": screen,
        "screens": DisplayServer.get_screen_count(),
        "screen_usable": [usable.position.x, usable.position.y, usable.size.x, usable.size.y],
        "display_server": DisplayServer.get_name(),
        "kept": _kept_report(kept),
        "edges_shown": frame != null and frame.visible,
        "bar_empty_at": frame.empty_point() if frame != null else [],
    }


## A window mode as the dump says it.
static func mode_name(mode: int) -> String:
    match mode:
        DisplayServer.WINDOW_MODE_WINDOWED:
            return "windowed"
        DisplayServer.WINDOW_MODE_MINIMIZED:
            return "minimized"
        DisplayServer.WINDOW_MODE_MAXIMIZED:
            return "maximized"
        DisplayServer.WINDOW_MODE_FULLSCREEN:
            return "fullscreen"
        DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
            return "exclusive fullscreen"
    return "mode %d" % mode


static func _kept_report(kept: Dictionary) -> Dictionary:
    if kept.is_empty():
        return {}
    var rect: Rect2i = kept.get("rect", Rect2i())
    return {
        "maximized": bool(kept.get("maximized", true)),
        "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
        "screen": int(kept.get("screen", -1)),
    }


## A press within reach of the edge the window was windowed with.
func resize_from(edge: int) -> void:
    if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
        return
    if OS.get_name() != "Windows":
        DisplayServer.window_start_resize(edge as DisplayServer.WindowResizeEdge)


## One resize strip: a thin control at an edge or a corner of the window, with
## that edge's cursor, that hands a press to the system's resize or, on
## Windows, follows the pointer itself.
class Edge:
    extends Control

    var _edge: int
    var _frame: SaTopBarWindowFrame
    var _from_pointer: Vector2i = Vector2i.ZERO
    var _from_rect: Rect2i = Rect2i()
    var _following: bool = false

    func _init(edge: int, frame: SaTopBarWindowFrame) -> void:
        _edge = edge
        _frame = frame
        name = "Edge%d" % edge
        mouse_filter = Control.MOUSE_FILTER_STOP
        mouse_default_cursor_shape = CURSORS[edge]
        focus_mode = Control.FOCUS_NONE

    ## Whether a corner's square takes *at*, a point inside it: only along its
    ## two outer sides, `REACH` deep. A side's strip is all edge.
    static func takes(edge: int, at: Vector2, square: Vector2) -> bool:
        var left := edge in [DisplayServer.WINDOW_EDGE_TOP_LEFT, DisplayServer.WINDOW_EDGE_BOTTOM_LEFT]
        var top := edge in [DisplayServer.WINDOW_EDGE_TOP_LEFT, DisplayServer.WINDOW_EDGE_TOP_RIGHT]
        var corner := left or top or edge == DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT
        if not corner:
            return true
        var near_x := at.x < REACH if left else at.x >= square.x - REACH
        var near_y := at.y < REACH if top else at.y >= square.y - REACH
        return near_x or near_y

    func _has_point(point: Vector2) -> bool:
        return Rect2(Vector2.ZERO, size).has_point(point) and takes(_edge, point, size)

    func _gui_input(event: InputEvent) -> void:
        var button := event as InputEventMouseButton
        if button != null and button.button_index == MOUSE_BUTTON_LEFT:
            accept_event()
            _following = false
            if not button.pressed:
                return
            _frame.resize_from(_edge)
            if OS.get_name() == "Windows":
                _following = true
                _from_pointer = DisplayServer.mouse_get_position()
                _from_rect = Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
            return
        if event is InputEventMouseMotion and _following:
            accept_event()
            var moved := DisplayServer.mouse_get_position() - _from_pointer
            var rect := SaTopBarWindowFrame.resized(_from_rect, _edge, moved, DisplayServer.window_get_min_size())
            SaTopBarWindowFrame.place(rect)
