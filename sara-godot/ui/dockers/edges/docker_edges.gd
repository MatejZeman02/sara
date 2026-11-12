## A docker's four edges, each a resize handle of Sara's own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Embedded, the engine never resizes a borderless window by its edge, and
## every docker is borderless. Without these strips an edge drag that moves
## anything is the ALT and right button gesture pressed near the edge, which
## grows about the centre: the far edge comes too and the width takes twice the
## pointer's travel. Let out, a docker is a window of its own with no frame, and
## the window system's own resize, Super and the middle button under GNOME,
## reaches it knowing only `min_size`, with no host to stop at and no word to
## the layout store.
##
## So each edge is a thin strip along the inside of the docker that moves that
## edge alone, by `rect_for` below, floored at `DockerDragHandle.minimum_size_of`
## and capped at `DockerDragHandle.resize_host_of`, the grip's own two answers,
## with the pointer in the edge's resize shape and `docker_layout_changed`
## emitted on the release, as the grip does. `attach` turns the window's own
## resize off, so the window system cannot make a second one beside it, and
## `Hold` keeps it off where the engine's switch does not reach.
##
## **Its own folder, and `docker_window.gd` takes no line.** The window stands
## near the thousand-line limit, so the edges are put on a docker from outside
## it: `MainDockers` attaches them to every docker it builds, a module's as well
## as a built-in, because both arrive there.
class_name SaDockerEdges

const DragHandle = preload("res://ui/dockers/docker_drag_handle.gd")

## The sides an edge moves, as bits, so the arithmetic reads one mask.
const LEFT: int = 1
const TOP: int = 2
const RIGHT: int = 4
const BOTTOM: int = 8

## How thick each strip is, in logical units, which the window's own
## `content_scale_factor` scales as it does the grip's twelve. A third of the
## grip: thick enough to find with a pen, thin enough that a scroll bar pinned
## to the docker's right edge keeps most of its width.
const THICKNESS: float = 4.0

## Each edge by the name a scenario writes, and the node it is built as.
const SIDE_NAMES: Dictionary = {"left": LEFT, "top": TOP, "right": RIGHT, "bottom": BOTTOM}
const NODE_NAMES: Dictionary = {LEFT: "EdgeLeft", TOP: "EdgeTop", RIGHT: "EdgeRight", BOTTOM: "EdgeBottom"}


## One edge of one docker: the strip, its drag and the rectangle the drag asks for.
class Edge:
    extends Control

    var _window: Window = null
    var _sides: int = 0
    var _is_resizing: bool = false
    var _start: Rect2i = Rect2i()
    var _anchor: Vector2 = Vector2.ZERO

    func _init(window: Window, sides: int) -> void:
        _window = window
        _sides = sides
        name = NODE_NAMES[sides]
        mouse_filter = Control.MOUSE_FILTER_STOP
        mouse_default_cursor_shape = Control.CURSOR_HSIZE if sides & (LEFT | RIGHT) else Control.CURSOR_VSIZE
        gui_input.connect(_on_gui_input)

    ## Pinned in `_ready` rather than in `_init`, the grip's reason: an anchor set
    ## before the strip has a parent recomputes its offsets against nothing.
    func _ready() -> void:
        match _sides:
            LEFT:
                set_anchors_preset(Control.PRESET_LEFT_WIDE)
            TOP:
                set_anchors_preset(Control.PRESET_TOP_WIDE)
            RIGHT:
                set_anchors_preset(Control.PRESET_RIGHT_WIDE)
            _:
                set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
        offset_left = -THICKNESS if _sides == RIGHT else 0.0
        offset_right = THICKNESS if _sides == LEFT else 0.0
        offset_top = -THICKNESS if _sides == BOTTOM else 0.0
        offset_bottom = THICKNESS if _sides == TOP else 0.0

    func _on_gui_input(event: InputEvent) -> void:
        if _window == null:
            return
        if event is InputEventMouseButton or event is InputEventScreenTouch:
            # The left button or a touch alone. ALT and the right button never
            # reach here, `DockerDragHandle` takes them in `_input` first.
            if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
                return
            if event.is_pressed():
                _is_resizing = true
                _start = Rect2i(_window.position, _window.size)
                _anchor = DragHandle.pointer_in_parent_space_of(_window)
            elif _is_resizing:
                _is_resizing = false
                if EventBus:
                    EventBus.docker_layout_changed.emit()
            accept_event()
        elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and _is_resizing:
            var drag := DragHandle.pointer_in_parent_space_of(_window) - _anchor
            var rect := rect_for(_start, drag, _sides, DragHandle.minimum_size_of(_window), DragHandle.resize_host_of(_window))
            # The size first, for the reason the grip gives: a position written
            # while the window is still the old size can be clamped at the host.
            _window.size = rect.size
            _window.position = rect.position
            accept_event()

    ## The rectangle a drag of *drag* on the edges in *sides* asks for, from a
    ## docker that stood at *start*. Each edge moved takes the drag along its own
    ## axis and the edges not in *sides* stay where they were, so the left edge
    ## dragged moves the left and keeps the right, which is what the corner grip
    ## does with its two and what the ALT-right gesture, grown about the centre,
    ## does not.
    ##
    ## The size along a moved axis is floored at *minimum*, the minimum winning.
    ## The height is capped where the moved edge would leave *host*. The width is
    ## capped at the host's, and the moved edge stops on the host's edge, after
    ## which the edge across gives the rest, `SaDockerEdges.widened`, so a
    ## docker against the window's right edge still widens by its right edge. An
    ## empty *host* is no cap.
    static func rect_for(start: Rect2i, drag: Vector2, sides: int, minimum: Vector2i, host: Rect2i) -> Rect2i:
        var step := Vector2i(drag.round())
        var bounded := host.has_area()
        var rect := start
        if sides & (LEFT | RIGHT):
            var wanted := start.size.x + step.x if sides & RIGHT else start.size.x - step.x
            if bounded:
                var across := SaDockerEdges.widened(start.position.x, start.end.x, wanted, minimum.x, host, (sides & RIGHT) != 0)
                rect.position.x = across.x
                rect.size.x = across.y
            else:
                rect.size.x = maxi(wanted, minimum.x)
                if sides & LEFT:
                    rect.position.x = start.end.x - rect.size.x
        if sides & BOTTOM:
            var room := host.end.y - start.position.y if bounded else start.size.y + step.y
            rect.size.y = clampi(start.size.y + step.y, minimum.y, maxi(room, minimum.y))
        elif sides & TOP:
            var room := start.end.y - host.position.y if bounded else start.size.y - step.y
            rect.size.y = clampi(start.size.y - step.y, minimum.y, maxi(room, minimum.y))
            rect.position.y = start.end.y - rect.size.y
        return rect

    ## The edge's half of the `docker_resize` step: a press at *start*, one motion
    ## *by* away and a release, through the handler a hand goes through, with the
    ## pointer supplied the way the grip's `capture_drag` supplies it.
    func capture_drag(start: Vector2, by: Vector2) -> void:
        DragHandle.capture_pointer = start
        var press := InputEventMouseButton.new()
        press.button_index = MOUSE_BUTTON_LEFT
        press.pressed = true
        _on_gui_input(press)
        DragHandle.capture_pointer = start + by
        _on_gui_input(InputEventMouseMotion.new())
        var release := InputEventMouseButton.new()
        release.button_index = MOUSE_BUTTON_LEFT
        release.pressed = false
        _on_gui_input(release)
        DragHandle.capture_pointer = null


## Keeps a let-out docker's window at the size Sara gave it, as the Wayland
## compositor is told. Godot 4.7.2 turns `unresizable` into the window's size
## hints under X11 and into a window with no sizing frame under Windows, but
## `DisplayServerWayland.window_set_flag` only stores the bit, so the compositor
## still offers its own resize. Mutter takes a window whose minimum and maximum
## are one size as one it does not resize, so this holds both at the window's
## size whenever they differ from it.
##
## Measured with `WAYLAND_DEBUG` on Godot 4.7.2: a write of the minimum or the
## maximum alone is stored and sent to nobody, and both go out with the next
## change of size. So `held` changes the size by a pixel and back in one frame,
## which sends the two and no other size. Every write of `size`, the edges',
## the grip's and the layout's, sends the window's own minimum and maximum
## again, so Sara's writes go through untouched and this holds the window once
## more on the next frame.
class Hold:
    extends Node

    var _window: Window = null

    func _init(window: Window) -> void:
        _window = window
        name = "EdgeHold"

    func _process(_delta: float) -> void:
        held()

    ## Holds the window's minimum and maximum at its size, if it is a window of
    ## its own under Wayland, and answers whether they are held. The minimum is
    ## cleared first, so neither write is ever refused for crossing the other.
    func held() -> bool:
        if _window == null or _window.is_embedded() or not _window.visible:
            return false
        if DisplayServer.get_name() != "Wayland":
            return false
        var id := _window.get_window_id()
        if id == DisplayServer.INVALID_WINDOW_ID:
            return false
        var held_size := _window.size
        if DisplayServer.window_get_min_size(id) == held_size and DisplayServer.window_get_max_size(id) == held_size:
            return true
        DisplayServer.window_set_min_size(Vector2i(), id)
        DisplayServer.window_set_max_size(held_size, id)
        DisplayServer.window_set_min_size(held_size, id)
        DisplayServer.window_set_size(held_size + Vector2i(0, 1), id)
        DisplayServer.window_set_size(held_size, id)
        return false


## Gives *window* its four edges, once, and turns its own resize off. True when
## the window has them afterwards.
##
## The strips go into the docker's content beside the grip and under it, so the
## grip keeps its corner and every control of the column lies beneath them. A
## docker not built yet takes its edges when it is, which is when `Control/Resizer`
## exists. A window that is not a `DockerWindow` is left alone, a dialog among them.
static func attach(window: Window) -> bool:
    if not (window is DockerWindow):
        return false
    var grip := window.get_node_or_null("Control/Resizer") as Control
    if grip == null:
        if not window.is_node_ready():
            window.ready.connect(func() -> void: attach(window), CONNECT_ONE_SHOT)
        return false
    var content := grip.get_parent()
    if content.has_node(String(NODE_NAMES[LEFT])):
        return true
    for side: int in [LEFT, TOP, RIGHT, BOTTOM]:
        var edge := Edge.new(window, side)
        content.add_child(edge)
        content.move_child(edge, grip.get_index())
    content.add_child(Hold.new(window))
    # The engine never resizes a borderless docker embedded, and this takes the
    # same resize away from the window system once the docker is let out, by the
    # size hints under X11 and the missing sizing frame under Windows, and by
    # `Hold` under Wayland. Sara's own writes of `size` still take, the
    # edges', the grip's and the layout's.
    window.unresizable = true
    return true


## Where a docker's left edge goes and how wide it is, as `Vector2i(x, width)`,
## when one of its sides is dragged to *wanted* wide. *start_x* and *start_end*
## are its left and right edges before the drag, and *keep_left* says the right
## side is the one dragged. The width is floored at *minimum*, the minimum
## winning, and capped at *host*'s width, and the dragged side stops on the
## host's edge, after which the side not dragged gives the rest.
##
## **The far side gives.** A docker that stands near the window's edge would
## otherwise stop growing as soon as its dragged side met the host, too narrow
## to read its rows. The cap keeps every edge on the host, and what moves is
## the side that gives once one edge is there.
static func widened(start_x: int, start_end: int, wanted: int, minimum: int, host: Rect2i, keep_left: bool) -> Vector2i:
    var width := clampi(wanted, minimum, maxi(host.size.x, minimum))
    if keep_left:
        return Vector2i(maxi(mini(start_x, host.end.x - width), host.position.x), width)
    return Vector2i(mini(maxi(start_end - width, host.position.x), host.end.x - width), width)


## The rectangle a drag on the edges in *sides* asks for, `Edge.rect_for`, so a
## suite can read the arithmetic without a window.
static func edge_rect(start: Rect2i, drag: Vector2, sides: int, minimum: Vector2i, host: Rect2i = Rect2i()) -> Rect2i:
    return Edge.rect_for(start, drag, sides, minimum, host)


## Resizes a docker by a drag: one edge of a registered docker when the spec
## names one, `{"docker_resize": {"id": "LayersDocker", "by": [200, 0], "edge": "right"}}`,
## and otherwise the ALT and right button gesture pressed at the corner `from`
## names, or the corner grip when `grip` is true, which `DockerDragHandle.capture_resize`
## drives, `{"docker_resize": {"id": "LayersDocker", "by": [60, 40], "grip": false, "from": "bottom_right"}}`.
##
## An edge's answer is the rectangle either side, the host and the floor the
## drag was held in, the edge's pointer shape, and whether the window system may
## still resize the docker.
##
## The edge is pressed at the middle of its side of the docker's rectangle, in
## the space the docker's `position` is written in, and driven through
## `capture_drag`, because Wayland will not let a capture place the pointer.
static func capture_resize(tree: SceneTree, spec: Dictionary) -> String:
    if not spec.has("edge"):
        return DragHandle.capture_resize(tree, spec)
    var docker_id := String(spec.get("id", ""))
    var window := tree.root.find_child(docker_id, true, false) as Window
    if window == null:
        return "SaCapture: no docker called '%s' to resize" % docker_id
    var edge_name := String(spec["edge"])
    if not SIDE_NAMES.has(edge_name):
        return "SaCapture: docker_resize's edge is left, top, right or bottom, not '%s'" % edge_name
    var by_raw := spec.get("by", [0, 0]) as Array
    if by_raw == null or by_raw.size() < 2:
        return "SaCapture: docker_resize needs a 'by' of two numbers"
    var by := Vector2(float(by_raw[0]), float(by_raw[1]))
    var side: int = SIDE_NAMES[edge_name]
    var edge := window.find_child(String(NODE_NAMES[side]), true, false)
    if edge == null or not edge.has_method("capture_drag"):
        return "SaCapture: docker '%s' has no %s edge to drag" % [docker_id, edge_name]

    var before := Rect2i(window.position, window.size)
    var host := DragHandle.resize_host_of(window)
    var floor_size := DragHandle.minimum_size_of(window)
    var resize_off := _window_system_resize_is_off(window)
    edge.call("capture_drag", _edge_point(before, side), by)
    var after := Rect2i(window.position, window.size)
    var shape := "HSIZE" if int(edge.get("mouse_default_cursor_shape")) == Control.CURSOR_HSIZE else "VSIZE"
    return (
        "SaCapture: docker_resize %s by (%d, %d) edge %s: %s -> %s, host %s, floor %dx%d, cursor %s, window system resize %s"
        % [
            docker_id,
            by.x,
            by.y,
            edge_name,
            _rect_text(before),
            _rect_text(after),
            _rect_text(host),
            floor_size.x,
            floor_size.y,
            shape,
            "off" if resize_off else "on",
        ]
    )


## Whether *window*'s own resize is off, read before the drag, when the docker
## has rested a frame: the flag on the window, and for a docker let out, the
## display server's flag, and under Wayland the minimum and maximum `Hold` keeps
## at its size as well.
static func _window_system_resize_is_off(window: Window) -> bool:
    if not window.unresizable:
        return false
    var id := window.get_window_id()
    if window.is_embedded() or id == DisplayServer.INVALID_WINDOW_ID:
        return true
    if not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, id):
        return false
    if DisplayServer.get_name() != "Wayland":
        return true
    return DisplayServer.window_get_min_size(id) == window.size and DisplayServer.window_get_max_size(id) == window.size


## The middle of *side* of *rect*, where the step presses.
static func _edge_point(rect: Rect2i, side: int) -> Vector2:
    var centre := Vector2(rect.position) + Vector2(rect.size) * 0.5
    match side:
        LEFT:
            return Vector2(rect.position.x, centre.y)
        TOP:
            return Vector2(centre.x, rect.position.y)
        RIGHT:
            return Vector2(rect.end.x, centre.y)
        _:
            return Vector2(centre.x, rect.end.y)


static func _rect_text(rect: Rect2i) -> String:
    return "(%d, %d) %dx%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
