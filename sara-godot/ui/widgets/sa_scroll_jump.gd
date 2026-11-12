## A press on a scroll bar's track puts the handle's middle under the press, and
## the drag goes on from there.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why not the engine's paging.** `ScrollBar::gui_input`
## (`scene/gui/scroll_bar.cpp`) moves one page towards a press on the track and
## stops, so a painter who pressed the far end of a long list saw it creep a
## page and had to press again and again. The painter expects the handle to
## jump to where they pressed, as it does in GTK's and in Krita's lists.
##
## **A filter ahead of the engine's handler, as [SaScrollPace] is.**
## `Control._call_gui_input` emits `gui_input` before the engine's handler runs,
## so this moves the bar's value on the press and lets the press go on. The
## engine then reads the same press against the handle where it now stands, finds
## it on the handle, and starts its own drag there, so dragging on from the jump
## and dragging the handle itself are both the engine's drag as before. Every
## bar is taken, a `ScrollContainer`'s own two among them, because the theme
## that draws them cannot change what a press does.
##
## **The engine's geometry, which no script can read.** The handle's length
## and the length it travels are private to `ScrollBar`, so `_handle` works
## them out the way `get_grabber_size` and `get_area_size` do: the track's
## length less the track box's margins, the two arrows and the handle box's
## own length, and the handle is the page's share of that plus its box. The
## engine adds a texture box's centre to the handle's box, which no script can
## ask for, and every bar Sara themes draws a flat box, whose centre is nothing.
class_name SaScrollJump
extends RefCounted


## Every `ScrollBar` *tree* holds from here on, and every one it holds already,
## jumps to a press on its track.
##
## Called once, by the boot, before the first window is built. Called twice it
## connects nothing twice.
static func install(tree: SceneTree) -> void:
    if tree == null:
        return
    if not tree.node_added.is_connected(take):
        tree.node_added.connect(take)
    if tree.root != null:
        _take_all(tree.root)


## Makes *node* jump to a press on its track when it is a `ScrollBar`, and does
## nothing otherwise. A bar that leaves the tree and comes back is not
## connected a second time.
static func take(node: Node) -> void:
    var bar := node as ScrollBar
    if bar == null:
        return
    if not bar.gui_input.is_connected(_on_gui_input):
        bar.gui_input.connect(_on_gui_input.bind(bar))


## The value that puts *bar*'s handle's middle at *along*, the press's place
## along the bar in its own coordinates. Clamped by the bar to its ends.
static func value_for(bar: ScrollBar, along: float) -> float:
    var handle := _handle(bar)
    var area: float = handle["area"]
    if area <= 0.0:
        return bar.value
    var ratio := (along - float(handle["before"]) - float(handle["length"]) / 2.0) / area
    return bar.min_value + clampf(ratio, 0.0, 1.0) * (bar.max_value - bar.min_value)


## Where *bar*'s handle stands, as the engine's press handler measures it:
## `before` is the decrement arrow's length, `offset` the handle's start after
## it, `length` the handle's length and `area` the length its start travels.
static func _handle(bar: ScrollBar) -> Dictionary:
    var vertical := bar is VScrollBar
    var axis := 1 if vertical else 0
    var track: float = bar.get_theme_stylebox(&"scroll").get_minimum_size()[axis]
    var grabber_box := bar.get_theme_stylebox(&"grabber")
    var grabber_min: float = grabber_box.get_minimum_size()[axis]
    var before := _arrow(bar, &"decrement", axis)
    var after := _arrow(bar, &"increment", axis)
    var area: float = bar.size[axis] - track - before - after - grabber_min
    var span := bar.max_value - bar.min_value
    var share: float = (maxf(bar.page, 0.0) / span) * area if span > 0.0 else 0.0
    var ratio := (bar.value - bar.min_value) / span if span > 0.0 else 0.0
    return {"before": before, "offset": area * ratio, "length": share + grabber_min, "area": area}


static func _arrow(bar: ScrollBar, name: StringName, axis: int) -> float:
    var icon := bar.get_theme_icon(name)
    return 0.0 if icon == null else float(icon.get_size()[axis])


static func _take_all(node: Node) -> void:
    take(node)
    for child: Node in node.get_children(true):
        _take_all(child)


## A left press on the track, between the arrows and off the handle, moves the
## bar so the handle's middle is under it, and is left for the engine, which
## then finds it on the handle and drags. A press on the handle or an arrow, and
## every other event, is the engine's as before.
static func _on_gui_input(event: InputEvent, bar: ScrollBar) -> void:
    var press := event as InputEventMouseButton
    if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
        return
    if not is_instance_valid(bar):
        return
    var axis := 1 if bar is VScrollBar else 0
    var along: float = press.position[axis]
    var handle := _handle(bar)
    var before: float = handle["before"]
    var after := _arrow(bar, &"increment", axis)
    if along < before or along > bar.size[axis] - after:
        return
    var on_track: float = along - before - float(handle["offset"])
    if on_track >= 0.0 and on_track < float(handle["length"]):
        return
    bar.value = value_for(bar, along)
