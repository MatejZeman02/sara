## Whether Sara listens to the system's mouse and pen, and the gate that keeps
## them out while a client holds the lock from the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A lesson where the painter and a client both work on the canvas needs the
## client's hand to be the only pointer for a while: a press of the painter's
## mouse in the middle of a client's drag would end the drag or start a stroke
## of its own. While the lock is held, a mouse or pen event the operating
## system sent is dropped before any tool or widget hears it, and an event
## Sara's own code made, the door's above all, goes on as before. Touch and
## the keyboard are left alone, and so is a mouse event Godot made from a
## finger, which is touch's.
##
## **Whose an event is, is read off when it comes.** The display server hands
## the system's events to Godot in `DisplayServer.process_events`, between one
## iteration of the main loop and the next, and with accumulated input off
## `Input.parse_input_event` delivers an event inside the call that made it. So
## an event that arrives inside an iteration was made by code that runs in it,
## and one that arrives between two came from the system. An iteration begins
## at the tree's `physics_frame` or `process_frame`, and it ends at the tree's
## delete flush, after the deferred calls, the timers and the tweens, which
## [class FrameEnd] hears by being freed there. Marking the door's own events
## instead was turned down: a dozen drivers of the harness make them, through
## `Input` and through `Window.push_input`, and a driver added later would
## forget the mark and find its events dropped.
##
## **What still sees the system's pointer.** `Input` itself, so
## `Input.get_mouse_button_mask` and the display server's pointer place keep
## reading the hand. The ring reads that place, so it follows the mouse while
## the canvas takes nothing from it. A popup closes on a press outside it in
## the engine's own code, before any script hears the press. A minimized Sara
## draws no frame and runs no delete flush, so the lock holds only while a
## window is drawn, which is when there is a pointer to drop.
##
## One lock for the process, because the system's pointer is one.
class_name SaPointerLock
extends RefCounted

## The name of each window's gate, so a reader of the tree knows it.
const GATE_NAME := "SaPointerLockGate"

## Whether the lock is held. Written by [method lock] and [method unlock] only.
static var held: bool = false

## Who holds the lock, the words the status line shows after its own, or an
## empty string while it is free.
static var holder: String = ""

## How many of the system's events the gates have dropped since the lock was
## taken, for the step's verdict and a suite. Counted by [class Gate] alone,
## because an event the canvas's window signal turned away reaches a gate next
## and would be counted twice.
static var dropped: int = 0

## Whether the main loop is inside an iteration, which is when an event can
## only be one Sara's own code made.
static var _in_frame: bool = true

## The gates put in the windows, one each.
static var _gates: Array[Gate] = []

## Whether accumulated input was on when the lock was taken, put back by
## [method unlock].
static var _accumulated: bool = false


## Drops every mouse, pen and touchpad event its window hears from the system
## while the lock is held, ahead of the window's other nodes.
##
## Its window's last child, because the engine hands `_input` to a viewport's
## nodes from the last in tree order to the first, and setting the event
## handled stops the rest of them and the GUI after them.
class Gate:
    extends Node

    func _init() -> void:
        name = GATE_NAME
        process_mode = Node.PROCESS_MODE_ALWAYS

    func _input(event: InputEvent) -> void:
        if SaPointerLock.drops(event):
            SaPointerLock.dropped += 1
            get_viewport().set_input_as_handled()

    ## Moves this to the end of its window's children when a node came after it.
    func stay_last() -> void:
        var parent := get_parent()
        if parent != null and get_index() != parent.get_child_count() - 1:
            parent.move_child(self, -1)


## A node made at the start of an iteration and queued for deletion, whose
## freeing at the tree's delete flush says the iteration's code has run.
class FrameEnd:
    extends Node

    func _notification(what: int) -> void:
        if what == NOTIFICATION_PREDELETE:
            SaPointerLock.frame_ended()


## Takes the lock for *by*, which the status line names, and puts a gate in
## every window there is and in every window made while it is held. Taking it
## again only renames the holder.
static func lock(by: String) -> void:
    holder = by
    if held:
        EventBus.pointer_lock_changed.emit(true, holder)
        return
    held = true
    dropped = 0
    _accumulated = Input.is_using_accumulated_input()
    # An accumulated event waits in `Input` until the next flush, which is the
    # display server's, and would be read as the system's.
    Input.set_use_accumulated_input(false)
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.physics_frame.connect(frame_began)
        tree.process_frame.connect(frame_began)
        tree.node_added.connect(_on_node_added)
        _gate(tree.root)
        for window: Node in tree.root.find_children("*", "Window", true, false):
            _gate(window as Window)
    frame_began()
    EventBus.pointer_lock_changed.emit(true, holder)


## Lets the lock go and takes the gates out. Nothing happens when it is free.
static func unlock() -> void:
    if not held:
        return
    held = false
    holder = ""
    Input.set_use_accumulated_input(_accumulated)
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.physics_frame.disconnect(frame_began)
        tree.process_frame.disconnect(frame_began)
        tree.node_added.disconnect(_on_node_added)
    for gate: Gate in _gates:
        if is_instance_valid(gate):
            gate.free()
    _gates.clear()
    _in_frame = true
    EventBus.pointer_lock_changed.emit(false, "")


## Whether *event* is dropped: the lock is held, the event came from the system,
## and it is the mouse's, the pen's or the touchpad's.
static func drops(event: InputEvent) -> bool:
    if not held or _in_frame:
        return false
    if event is InputEventMouse:
        if event.device == InputEvent.DEVICE_ID_EMULATION:
            return false
    elif not event is InputEventGesture:
        return false
    return true


## An iteration of the main loop has begun: what arrives from here on is made
## by code, until [method frame_ended]. Its end is queued at once, and the gates
## are put back at the end of their windows.
static func frame_began() -> void:
    _in_frame = true
    FrameEnd.new().queue_free()
    for gate: Gate in _gates:
        if is_instance_valid(gate):
            gate.stay_last()


## The iteration's code has run, and until the next begins an event can only be
## the system's. A suite calls it to stand where the display server hands its
## events over.
static func frame_ended() -> void:
    _in_frame = false


## Puts a gate in *window* unless it has one.
static func _gate(window: Window) -> void:
    var home := _home_in(window)
    if home == null or home.has_node(GATE_NAME):
        return
    var gate := Gate.new()
    home.add_child(gate)
    _gates.append(gate)


## Where a gate stands in *window*: its last child in tree order, so its
## `_input` runs before every other. A window still readying its children
## refuses one, which is the main window while a scene's `_ready` runs, and
## then the gate goes into that window's last child, the same place in the
## order.
static func _home_in(window: Window) -> Node:
    if window == null or window.is_node_ready():
        return window
    var count := window.get_child_count()
    return window.get_child(count - 1) if count > 0 else null


## Gates a window made while the lock is held, once the window is in the tree,
## since a node that is still being added refuses a child.
static func _on_node_added(node: Node) -> void:
    if node is Window:
        _gate.call_deferred(node)
