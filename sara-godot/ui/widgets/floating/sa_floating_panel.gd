## A panel that opens under a control and floats over the window that control
## is in, inside that window rather than as an operating system window.
##
## A `PopupPanel` is a `Window`, so with embedded subwindows off it is an
## operating system window. Sara draws its cursor ring in the main window, so a
## separate window has the system pointer over it and nothing of Sara's, the
## recorder captures the main window and so a note taken with the list open
## records what is behind it, and a pen under Windows Ink reaches a second
## window as a mouse.
##
## **Where it goes while it is open depends on the window's dockers.** A window
## that embeds its subwindows, which is the default, draws every floating
## docker on a canvas of its own above the window's controls, and routes every
## press over a docker to that docker before any control of the window is
## asked. A control of the window cannot be seen over a docker at any z, nor
## pressed there with the docker's `mouse_passthrough` on, which a scenario
## measured. So there the panel is held in a borderless embedded window of its
## own, the frame, kept above the dockers. So is a panel opened from a docker,
## which is itself embedded and has other dockers over it. That frame is inside the main window's
## viewport, so the recorder sees it and a pen reaches it, and the cursor policy
## treats it as it treats a docker. A window that does not embed has no docker
## in it to cover the panel, and there the panel is the window's last child,
## drawn last and asked first.
##
## Closed, it goes back to the node it was opened from, so whatever it holds
## stays in that node's tree and is freed with it.
##
## A press outside it and outside the control it opened under closes it and is
## taken, so the press that dismisses a list does not also paint. A press on
## that control is left to it, because the control is what closes a list it
## opened, and a panel that closed itself first would have the control open it
## again.
##
## A panel that has to leave the window's bounds cannot be one of these.
class_name SaFloatingPanel
extends PanelContainer

## After the panel has closed, by any of the ways it can.
signal closed

## Under the note overlay at 4095 and the cursor ring at 4096, so a note and the
## brush ring both draw over an open panel held in the window itself.
const Z_INDEX := 4000

## The node the panel was a child of when it opened, which it returns to.
var _home: Node = null

## The control it opened under, whose own clicks it leaves alone.
var _anchor: Control = null

## The embedded window an open panel is held in, when its window embeds its
## dockers, and the window that frame sits in.
var _frame: Window = null
var _host: Window = null

## The node that takes a dismissing press in the host's own tree.
var _guard: Guard = null

## A press or a key has just closed the panel from the host's input signal, and
## the guard takes it before a control or the canvas does. Cleared at the frame's
## end, since a press that landed on a docker never reaches the guard.
var _dismissing: bool = false


## Sits in the host window while a frame is open. The host's input signal fires
## before any routing but cannot mark an event handled, so the press it closed
## the panel with would go on to the canvas. This node's `_input` is where that
## press can still be stopped.
class Guard:
    extends Node

    ## Answers whether an event is the one to take.
    var takes: Callable

    func _init(asks: Callable) -> void:
        takes = asks
        name = "SaFloatingGuard"

    func _input(event: InputEvent) -> void:
        if takes.call(event):
            get_viewport().set_input_as_handled()


## *content* is what the panel shows, and *node_name* what a scenario finds it by.
func _init(content: Control = null, node_name: String = "") -> void:
    if content != null:
        add_child(content)
    if not node_name.is_empty():
        name = node_name
    visible = false
    top_level = true
    z_as_relative = false
    z_index = Z_INDEX
    mouse_filter = MOUSE_FILTER_STOP
    var style := StyleBoxFlat.new()
    SaTheme.bind(style, {"bg_color": "bg_panel", "border_color": "border_secondary"})
    style.set_border_width_all(1)
    style.set_corner_radius_all(SaUI.px(4))
    style.set_content_margin_all(float(SaUI.px(6)))
    add_theme_stylebox_override("panel", style)
    set_process_input(false)


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        _release_frame()


## Whether the panel is showing.
func is_open() -> bool:
    return visible


## Whether the panel is held in an embedded window of its own right now.
func in_frame() -> bool:
    return _frame != null and is_instance_valid(_frame) and get_parent() == _frame


## Opens the panel under *anchor*, or closes it when it is open. What a button
## that owns a panel calls on its press, which the panel's own dismissal leaves
## to the button.
func toggle_under(anchor: Control) -> void:
    if is_open():
        close()
    else:
        open_under(anchor)


## The panel as numbers, for a capture and a suite: whether it is open, whether
## it is a window of its own, which it never is, whether it is held in a frame,
## and where it is in its anchor's window.
func report() -> Dictionary:
    var rect := window_rect()
    return {
        "open": is_open(),
        "is_window": (self as Node) is Window,
        "in_frame": in_frame(),
        "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
    }


## Where the panel is in its anchor's window, the frame's rectangle when it is
## held in one.
func window_rect() -> Rect2:
    if in_frame():
        return Rect2(Vector2(_frame.position), Vector2(_frame.size))
    return get_global_rect()


## Shows the panel under *anchor*, inside the window *anchor* is in, or in place
## when *anchor* is in no tree, which is a suite's detached bar.
func open_under(anchor: Control) -> void:
    _anchor = anchor
    if not visible:
        _home = get_parent()
        if _home != null and not _home.tree_exiting.is_connected(_on_home_exiting):
            _home.tree_exiting.connect(_on_home_exiting)
    var host: Window = anchor.get_window() if anchor != null and anchor.is_inside_tree() else null
    if host != null and (host.gui_embed_subwindows or host.is_embedded()):
        _hold_in_frame(host)
    elif host != null:
        _move_under(host)
        host.move_child(self, -1)
    visible = true
    set_process_input(true)
    place()
    if in_frame():
        _frame.visible = true


## Puts the panel under its anchor at the size its content asks for, inside the
## visible rectangle of its anchor's window. Called on open, and by an owner
## whose content changed while the panel was showing.
##
## Under the anchor when there is room and above it when there is more, by
## `SaPopupRect.under`, the rule a dropdown's list already opens by. Sideways it
## starts at the anchor's left edge, and ends at its right edge instead when that
## is what keeps it on screen, which is the case for a button at the right end
## of the top bar.
func place() -> void:
    reset_size()
    if _anchor == null or not _anchor.is_inside_tree() or not is_inside_tree():
        return
    var room := Rect2i(_anchor.get_viewport_rect())
    var anchor_rect := _anchor.get_global_rect()
    var wanted := Vector2i(get_combined_minimum_size().ceil())
    var at := SaPopupRect.under(anchor_rect, wanted, room)
    var x := at.position.x
    if room.size.x > 0 and x + wanted.x > room.end.x:
        x = maxi(room.position.x, int(anchor_rect.end.x) - wanted.x)
    if in_frame():
        position = Vector2.ZERO
        _frame.position = Vector2i(x, at.position.y)
        _frame.size = wanted
    else:
        position = Vector2(x, at.position.y)


## Hides the panel and sends it home. The move waits for the frame's end, since
## a close comes from inside an input callback, where a node leaving its parent
## is a node another list may still be walking.
func close() -> void:
    if not visible:
        return
    visible = false
    set_process_input(false)
    if _frame != null and is_instance_valid(_frame):
        _frame.visible = false
    _go_home.call_deferred()
    closed.emit()


## For the guard: whether *event* is the one that just closed the panel from
## the host's input signal, which the guard then takes.
func takes(event: InputEvent) -> bool:
    if not _dismissing:
        return false
    var button := event as InputEventMouseButton
    var key := event as InputEventKey
    if (button != null and button.pressed) or (key != null and key.pressed):
        _dismissing = false
        return true
    return false


## A press outside the panel and outside its anchor closes it, and Escape does,
## when the panel is the window's own child.
##
## `_input` rather than `gui_input`, because the press that has to close the
## panel lands on some other control, which is the one `gui_input` would reach.
## Held in a frame, the panel only sees what the frame is sent, and the host's
## input signal below is what closes it.
func _input(event: InputEvent) -> void:
    if not visible or in_frame():
        return
    var key := event as InputEventKey
    if key != null and key.pressed and key.keycode == KEY_ESCAPE:
        close()
        get_viewport().set_input_as_handled()
        return
    var button := event as InputEventMouseButton
    if button == null or not button.pressed:
        return
    if get_global_rect().has_point(button.position):
        return
    if _anchor != null and is_instance_valid(_anchor) and _anchor.get_global_rect().has_point(button.position):
        return
    close()
    get_viewport().set_input_as_handled()


## The host's input signal, which fires for every event the window receives and
## before a docker is sent one. The event is in the window's own pixels, so it
## is taken to the logical space the frame and the anchor are measured in.
func _on_host_input(raw: InputEvent) -> void:
    if not visible or _host == null:
        return
    var key := raw as InputEventKey
    if key != null and key.pressed and key.keycode == KEY_ESCAPE:
        _dismiss()
        return
    var button := raw as InputEventMouseButton
    if button == null or not button.pressed:
        return
    var at := (raw.xformed_by(_host.get_final_transform().affine_inverse()) as InputEventMouseButton).position
    if in_frame() and window_rect().has_point(at):
        return
    if _anchor != null and is_instance_valid(_anchor) and _anchor.get_global_rect().has_point(at):
        return
    _dismiss()


func _dismiss() -> void:
    close()
    _dismissing = true
    _forget_dismissal.call_deferred()


func _forget_dismissal() -> void:
    _dismissing = false


## Makes the frame in *host* the first time the panel opens there, with the
## guard beside it, and moves the panel into it.
func _hold_in_frame(host: Window) -> void:
    if _frame == null or not is_instance_valid(_frame) or _host != host:
        _release_frame()
        _host = host
        _frame = Window.new()
        # A new `Window` is visible before it is in any tree.
        _frame.visible = false
        _frame.name = "SaFloatingFrame"
        _frame.borderless = true
        _frame.unresizable = true
        _frame.transient = true
        _frame.always_on_top = true
        _frame.transparent_bg = true
        _frame.wrap_controls = false
        host.add_child(_frame)
        SaUI.apply_to_window(_frame)
        _guard = Guard.new(takes)
        host.add_child(_guard)
        host.window_input.connect(_on_host_input)
    _move_under(_frame)


## Frees the frame and the guard and lets go of the host's input signal. The
## panel must already be out of the frame, or it would be freed with it.
func _release_frame() -> void:
    if _host != null and is_instance_valid(_host) and _host.window_input.is_connected(_on_host_input):
        _host.window_input.disconnect(_on_host_input)
    if _frame != null and is_instance_valid(_frame):
        if get_parent() == _frame:
            _frame.remove_child(self)
        _frame.queue_free()
    if _guard != null and is_instance_valid(_guard):
        _guard.queue_free()
    _frame = null
    _guard = null
    _host = null


func _move_under(parent: Node) -> void:
    if get_parent() == parent:
        return
    if get_parent() != null:
        get_parent().remove_child(self)
    parent.add_child(self)


func _go_home() -> void:
    if visible:
        return
    if _home != null and is_instance_valid(_home) and get_parent() != _home:
        _move_under(_home)
    _release_frame()


## The node the panel came from is leaving the tree while the panel is open in
## the window. The panel closes, and goes home once the frame is over, or is
## freed when its home was freed, since what it holds belonged to that home.
func _on_home_exiting() -> void:
    if get_parent() == _home:
        return
    visible = false
    set_process_input(false)
    _leave_the_window.call_deferred()


func _leave_the_window() -> void:
    if get_parent() != null and get_parent() != _home:
        get_parent().remove_child(self)
    _release_frame()
    if _home != null and is_instance_valid(_home):
        if get_parent() == null:
            _home.add_child(self)
        return
    # Queued, not freed at once: a release build knows no `free` on self and
    # fails to compile the class. The panel is out of every tree by
    # now, so the frame's end frees it with nothing left to reach it.
    queue_free()
