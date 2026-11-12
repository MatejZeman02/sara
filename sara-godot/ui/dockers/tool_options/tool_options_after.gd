## The redraw a tool switch or a preset load leaves the two option surfaces, the
## Tool Options docker and the bar, for the frame after it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A pick puts its settings on the tool in the frame it is made, and the tool is
## what the next press paints with. The rows only show those settings, and
## filling them again in the pick's own frame held a filter or a noise pick past
## 50 ms, 10 to 15 ms of it the bar's sync and up to 12 ms each the docker's after
## the switch and after the load. So each surface holds one of these and
## hands it that sync under a key, and the frame is `PresetPickAfter`'s, the
## Brush Presets docker's own hold for the same pick.
##
## **A hidden surface waits until it is shown.** Rows nobody sees are not drawn,
## so the work is kept until the surface's next `visibility_changed` and then
## waits for the frame after that like any other.
##
## **Out of the tree, at once**, as `PresetPickAfter` does, so a surface a suite
## builds and never adds to a tree reads the new values straight away. The
## surface comes with each ask, so this holds no reference back to it.
extends RefCounted

const PresetPickAfter := preload("res://ui/dockers/presets/preset_pick_after.gd")

## The frame the shown surface's work runs in.
var _after := PresetPickAfter.new()

## Work asked while the surface was hidden, a `Callable` for each key.
var _hidden: Dictionary[StringName, Callable] = {}

## How many frames after the ask the work runs in, so each surface takes a
## frame of its own after the Brush Presets docker's redim.
var _later: int = 1


func _init(later: int = 1) -> void:
    _later = later


## Runs *work* in the frame the constructor named after this one while *surface*
## is shown, once however often *key* is asked for before then, and at once out
## of the tree.
func ask(key: StringName, surface: Node, work: Callable) -> void:
    if surface == null or not surface.is_inside_tree():
        _hidden.erase(key)
        _after.ask(key, work, null)
        return
    if _shown(surface):
        _after.ask(key, work, surface.get_tree(), _later)
        return
    if _hidden.is_empty():
        surface.visibility_changed.connect(_on_visibility_changed.bind(surface), CONNECT_ONE_SHOT)
    _hidden[key] = work


## Whether work under *key* still waits, for its frame or for its surface.
func waits(key: StringName) -> bool:
    return _hidden.has(key) or _after.waits(key)


## Runs every key still waiting now, shown or not, for a suite that reads what
## the work left.
func settle_all() -> void:
    var held := _hidden.duplicate()
    _hidden.clear()
    for key: StringName in held:
        (held[key] as Callable).call()
    _after.settle_all()


## Shown again, so the held work goes to the frame after. Hidden again before
## that, it waits for the next change.
func _on_visibility_changed(surface: Node) -> void:
    if _hidden.is_empty() or not is_instance_valid(surface) or not surface.is_inside_tree():
        return
    if not _shown(surface):
        surface.visibility_changed.connect(_on_visibility_changed.bind(surface), CONNECT_ONE_SHOT)
        return
    var held := _hidden.duplicate()
    _hidden.clear()
    for key: StringName in held:
        _after.ask(key, held[key], surface.get_tree(), _later)


## Whether a painter sees *surface*, a window by its own flag and a control by
## its whole line of parents.
static func _shown(surface: Node) -> bool:
    if surface is Window:
        return (surface as Window).visible
    if surface is CanvasItem:
        return (surface as CanvasItem).is_visible_in_tree()
    return true
