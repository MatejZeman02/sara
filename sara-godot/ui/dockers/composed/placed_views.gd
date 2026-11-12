## The views of the elements the library places in one docker, in the library's
## order, each in a holder of its own: the whole of a docker of your own, and
## what a shipped docker draws after its own elements.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Each view is built through `SaSettings.build_element_view`, which is the
## whole of what this column knows about where an element comes from: it names
## no other docker's class, and a module's element is placed here the way the
## Toolbox's tools are. A view is a second view of the same state as at home,
## so the column keeps no state of an element's own and a rebuild loses
## nothing.
##
## **An element waits for its view.** A module may register its element's view
## after the boot built this column, so each placed element has a holder of its
## own, empty until the view can be built, and `element_view_registered` fills
## it when the view arrives. Connected in `_init` rather than `_ready`, so a
## column a suite builds detached hears it too. An element whose switch is off
## keeps its holder, hidden, so turning it on again needs no rebuild.
##
## Built by `SaComposedDockers` for a shipped docker, which hands it to
## `DockerWindow.place_column`, and by `ComposedDocker` for its own column.
@tool
extends VBoxContainer

## One record per placed element, in order: {"category", "element", "holder"},
## the holder being the container its view is built into.
var _holders: Array[Dictionary] = []

## What [method hold] was handed last, so a second hand of the same list builds
## nothing again.
var _held: Array = []


func _init() -> void:
    name = "Placed"
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    SaSettings.element_view_registered.connect(_on_view_registered)


## Puts *elements* in the column in place of what it held, each as the library
## keeps it: {"category", "element", "visible"}.
func hold(elements: Array) -> void:
    if elements == _held:
        return
    _held = elements.duplicate(true)
    for record: Dictionary in _holders:
        var old: Control = record["holder"]
        remove_child(old)
        old.queue_free()
    _holders.clear()
    for entry: Dictionary in elements:
        var category := String(entry["category"])
        var element := String(entry["element"])
        var holder := MarginContainer.new()
        holder.name = ("%s %s" % [category, element]).validate_node_name()
        holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        holder.visible = bool(entry.get("visible", true))
        add_child(holder)
        _holders.append({"category": category, "element": element, "holder": holder})
        _fill(holder, category, element)


## The view in each holder, in order, and null where an element still waits
## for its view. For the state dump and the suites.
func views() -> Array[Control]:
    var out: Array[Control] = []
    for record: Dictionary in _holders:
        var holder: Control = record["holder"]
        out.append(holder.get_child(0) as Control if holder.get_child_count() > 0 else null)
    return out


## Builds the view of *element* into *holder* when the door can build one.
func _fill(holder: Control, category: String, element: String) -> void:
    if holder.get_child_count() > 0:
        return
    var view := SaSettings.build_element_view(category, element)
    if view == null:
        return
    view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    holder.add_child(view)


func _on_view_registered(category: String, element: String) -> void:
    for record: Dictionary in _holders:
        if record["category"] == category and record["element"] == element:
            _fill(record["holder"], category, element)
