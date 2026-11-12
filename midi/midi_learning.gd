## Map to MIDI: a chord, a click on what to drive, and a move of the control
## that drives it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Ctrl+Alt+M by default, because Ctrl+Shift+M is Add Layer Mask and nothing
## else held this chord, and the Shortcuts page rebinds it.
##
## Private to this module, held by the facade, which asks it about every message
## before the bindings see one. Three steps, [enum Step]: waiting for a click,
## waiting for a control, and off.
##
## **The click picks, it does not press.** While learning, a node of this
## class's own sits last in every window and hears the left press in its
## `_input`, ahead of the window's controls, and takes it and the release after
## it, so no preset is chosen, no row selected and no slider moved. With
## subwindows embedded the root forwards a press on a docker or a dialog to that
## window before any root node hears it, so the node that takes it has to be in
## that window, the reason the note overlay gives for the same shape.
##
## **What a click can pick** is the drive's to say, [method
## SaControlDrive.target_at]: in the app a slider that names its value is a
## dial, a brush preset's cell is that preset, and a filter's row in the
## Filters docker is that filter. Anything else is refused in the corner and
## the learning goes on waiting.
extends RefCounted

const Bindings := preload("midi_bindings.gd")

## Where the learning stands.
enum Step { OFF, CLICK, CONTROL }

## The name of the node that hears a window's clicks while learning.
const CATCHER_NAME := "SaMidiLearning"

## Where the learning stands. Written here alone.
var step: Step = Step.OFF

## What the click picked, `{kind, target, label}`, empty until it picked.
var picked: Dictionary = {}

## The last line the learning said in the corner. Kept because a notice is
## silent where none is installed, a suite's host, and the dump reads it too.
var said: String = ""

var _bindings: Bindings = null

## The window whose windows hear the clicks, none for a learning a suite drives
## by hand.
var _root: Window = null

## The nodes hearing each window's clicks, one a window, freed when learning ends.
var _catchers: Array[Node] = []

## Whether the release after a taken press is still owed a swallow, because a
## button acts on the release.
var _swallow_release: bool = false


func _init(bindings: Bindings, root: Window = null) -> void:
    _bindings = bindings
    _root = root


## Starts learning, or leaves it when it is on, which is what a second press of
## the chord means.
func toggle(listen_turned_on: bool = false) -> void:
    if step == Step.OFF:
        start(listen_turned_on)
    else:
        stop(TranslationServer.translate("MIDI mapping left."))


## Waits for a click. *listen_turned_on* says the chord turned Listen on, which
## the corner says too, since it opens every controller.
func start(listen_turned_on: bool = false) -> void:
    step = Step.CLICK
    picked = {}
    _swallow_release = false
    _attach_everywhere()
    var line := TranslationServer.translate(
        "Map to MIDI: click a slider, a brush preset or a filter in the Filters docker. Escape leaves."
    )
    if listen_turned_on:
        line = TranslationServer.translate("Listen is on now.") + " " + line
    _say(line)


## Leaves learning, saying *line* when it is not empty.
func stop(line: String = "") -> void:
    step = Step.OFF
    picked = {}
    _swallow_release = false
    _detach_everywhere()
    if not line.is_empty():
        _say(line)


## The click on *control*: what it drives is picked and a control is waited
## for, or it drives nothing and the learning goes on waiting, as it was. True
## when it picked something.
func pick(control: Control) -> bool:
    if step == Step.OFF:
        return false
    return _picked(_bindings.drive.target_of(control))


## What the click picked, *target* as the drive answered it, or nothing.
func _picked(target: Dictionary) -> bool:
    if target.is_empty():
        _say(
            TranslationServer.translate(
                "That cannot be mapped to MIDI. Click a slider, a button, a brush preset or a filter's row, or press Escape."
            )
        )
        return false
    picked = target
    step = Step.CONTROL
    if String(target["kind"]) == Bindings.DIAL:
        _say(TranslationServer.translate("Now move the knob or fader that should turn %s.") % Bindings.target_text(target))
    elif String(target["kind"]) == Bindings.BUTTON:
        _say(
            (
                TranslationServer.translate(
                    "Now press the key or pad, or move a knob or pedal past halfway, that should press %s."
                )
                % Bindings.target_text(target)
            )
        )
    else:
        _say(TranslationServer.translate("Now press the key or pad that should choose %s.") % Bindings.target_text(target))
    return true


## A control change heard on *device*. Taken, and true, while a control is
## waited for: it binds a dial and is refused for anything else.
func heard_control(device: String, channel: int, controller: int) -> bool:
    return _heard_dial_control(device, Bindings.control_key(Bindings.CONTROL, channel, controller))


## A pitch bend heard on *device*, which is a fader on a channel. Taken as a
## control change is, and binds the fader by its channel.
func heard_bend(device: String, channel: int) -> bool:
    if step == Step.CONTROL and String(picked["kind"]) == Bindings.BUTTON:
        _say(
            (
                TranslationServer.translate("A pitch bend cannot press %s. Press a key or pad, or press Escape.")
                % Bindings.target_text(picked)
            )
        )
        return true
    return _heard_dial_control(device, Bindings.control_key(Bindings.BEND, channel, 0))


## A knob or fader *control* heard on *device*, taken while a control is waited
## for: it binds a dial or a button and is refused for anything else.
func _heard_dial_control(device: String, control: String) -> bool:
    if step != Step.CONTROL:
        return false
    if not String(picked["kind"]) in [Bindings.DIAL, Bindings.BUTTON]:
        _say(
            (
                TranslationServer.translate("A knob or fader cannot choose %s. Press a key or pad, or press Escape.")
                % Bindings.target_text(picked)
            )
        )
        return true
    _bind(device, control)
    return true


## A note heard on *device*, *on* or let go. Taken, and true, while a control is
## waited for: a note on binds a preset, a filter or a button and is refused for a dial,
## and a note off is let go of, since the key's own note on did the binding.
func heard_note(device: String, channel: int, note: int, on: bool) -> bool:
    if step != Step.CONTROL:
        return false
    if not on:
        return true
    if String(picked["kind"]) == Bindings.DIAL:
        _say(
            (
                TranslationServer.translate("A key or pad cannot turn %s. Move a knob or fader, or press Escape.")
                % Bindings.target_text(picked)
            )
        )
        return true
    _bind(device, Bindings.control_key(Bindings.NOTE, channel, note))
    return true


## Every event a window hears while learning. True when it was taken.
func handle(event: InputEvent) -> bool:
    if step == Step.OFF:
        return false
    var key := event as InputEventKey
    if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
        stop(TranslationServer.translate("MIDI mapping left."))
        return true
    var button := event as InputEventMouseButton
    if button == null or button.button_index != MOUSE_BUTTON_LEFT:
        return false
    if not button.pressed:
        var owed := _swallow_release
        _swallow_release = false
        return owed
    return true


## A left press in *window* at *point*, which picks what the drive finds under
## it. Its own function so the press is taken whatever the pick answers.
func press_in(window: Window, point: Vector2) -> void:
    _swallow_release = true
    if step != Step.OFF:
        _picked(_bindings.drive.target_at(window, point))


func _bind(device: String, control: String) -> void:
    var before := _bindings.bind(device, control, picked)
    var bound := [Bindings.control_text(control), device, Bindings.target_text(picked)]
    var line := TranslationServer.translate("%s of %s now drives %s.") % bound
    if not before.is_empty() and before != picked:
        line += " " + TranslationServer.translate("It drove %s before.") % Bindings.target_text(before)
    stop(line)


func _say(line: String) -> void:
    said = line
    SaMessage.notice(line)
    print("SaMidi: %s" % line)


## A catcher in the root and in every window under it, and one in each window
## that opens while learning, a filter's dialog opened by its chord for one.
func _attach_everywhere() -> void:
    if _root == null or not _root.is_inside_tree():
        return
    _attach(_root)
    for window: Window in _windows_under(_root):
        _attach(window)
    var tree := _root.get_tree()
    if not tree.node_added.is_connected(_on_node_added):
        tree.node_added.connect(_on_node_added)


func _detach_everywhere() -> void:
    for catcher: Node in _catchers:
        if is_instance_valid(catcher):
            catcher.queue_free()
    _catchers.clear()
    if _root != null and _root.is_inside_tree() and _root.get_tree().node_added.is_connected(_on_node_added):
        _root.get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(node: Node) -> void:
    if node is Window and step != Step.OFF:
        _attach.call_deferred(node)


## Asked by the catchers kept rather than by a child's name, because a catcher
## let go of is only queued to be freed and a learning started again in the same
## frame still finds it under the window.
func _attach(window: Window) -> void:
    if not is_instance_valid(window) or not window.is_inside_tree():
        return
    for catcher: Node in _catchers:
        if is_instance_valid(catcher) and catcher.get_parent() == window:
            return
    var catcher := Catcher.new(handle, press_in)
    window.add_child(catcher, true)
    _catchers.append(catcher)


## Every window under *node*, internal ones included, because a list a
## dropdown opens is an internal child of the dropdown.
static func _windows_under(node: Node) -> Array[Window]:
    var found: Array[Window] = []
    for child: Node in node.get_children(true):
        if child is Window:
            found.append(child as Window)
        found.append_array(_windows_under(child))
    return found


## The node that hears one window's input while learning, last among the
## window's children so its `_input` comes before every other node's there.
## It holds the learning's two methods rather than the learning, so a learning
## dropped with its catchers still up is freed and they go quiet.
class Catcher:
    extends Node

    var _handle: Callable = Callable()
    var _press: Callable = Callable()

    func _init(handle_event: Callable, press: Callable) -> void:
        _handle = handle_event
        _press = press
        name = CATCHER_NAME

    func _input(event: InputEvent) -> void:
        if is_queued_for_deletion() or not _handle.is_valid() or not bool(_handle.call(event)):
            return
        var button := event as InputEventMouseButton
        if button != null and button.pressed and _press.is_valid():
            _press.call(get_window(), button.position)
        get_viewport().set_input_as_handled()
