## The presets docker's cells, marked with the engine each preset was written
## for.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A second engine turns a stamp
## preset applied to it into a silent half copy, so the grid says which engine
## each preset is for and dims the ones the tool in front of the painter will not
## take. Dimmed rather than hidden, so a painter sees the preset exists and why it
## will not apply, and a press on one is what brings the corner notice naming
## both engines.
##
## A class of its own rather than more lines in the docker, because it owns one
## decision, which cell belongs to which engine, and the two things that decision
## needs arrive as `Callable`s, the way the chooser takes its settings.
##
## **No engine line under a cell.** The tooltip names the engine on every
## tile, and the brush editor names the loaded preset's at its top. A line under
## some tiles and not others came and went with each pick, and a cell that
## gained one moved its neighbours.
##
## It writes the whole tooltip, so it is also where the description and the
## licence line go: a second owner of that text would be a second spelling of one
## sentence.
##
## **No tooltip opens over a moving list.** While the list's [SaDragScroll]
## says it follows a drag or glides, every cell's tooltip is empty, and the
## engine, whose timer still runs out under a pointer the drag holds or one the
## list slides beneath, finds nothing to show. The text comes back a tooltip's
## whole delay after the list stands, so the first tooltip after a drag waits
## at least as long as one for a fresh hover. The engine leaves no way to call
## off its timer, which is why the text and not the timer is held.
extends RefCounted

## How far a cell of another engine is dimmed. Far enough to read as not this
## tool's, near enough that its picture and its name still read.
const FOREIGN_ALPHA: float = 0.45

## The meta a cell keeps its whole tooltip under, which is what it shows again
## once the list stands.
const TIP_META := &"sa_preset_tip"

var chooser: SaBrushPresetsChooser = null

## Answers the `SaPresetStore` the grid lists, or null when there is no bar.
var store_source: Callable = Callable()

## Answers the engines the tool in front of the painter takes, a list of ids,
## or a single id from a host that knows of one engine only. The Brush takes
## every engine it paints with, so its cells dim nothing.
var engine_source: Callable = Callable()

## Whether the cells' tooltips are held back, because the list moves or stood
## for less than a tooltip's delay.
var hushed: bool = false
## The list's drag helper once one is found, whose moves hush the tooltips.
var _mover: SaDragScroll = null
## Counts the list's moves, so a return of the text queued when one ended is
## dropped when another has begun since.
var _moves: int = 0


func _init(host_chooser: SaBrushPresetsChooser, store: Callable, engine: Callable) -> void:
    chooser = host_chooser
    store_source = store
    engine_source = engine
    chooser.grid.child_entered_tree.connect(mark)
    _find_mover()


## Marks *cell* with its preset's engine, and dims it when the tool takes another.
##
## On the grid's `child_entered_tree` rather than after the host rebinds, because
## the chooser rebuilds its cells on a search, a tag and a thumbnail choice
## without telling its host, and a mark made once would be gone on the next
## keystroke. The chooser builds a cell whole before it adds it, so the name and
## the button are there to read.
##
## The docker marks the cells it keeps again when the engine in hand changes,
## which is what moves the dim from one engine's tiles to the other's.
func mark(cell: Node) -> void:
    _find_mover()
    var store := _store()
    var control := cell as Control
    var label := cell.get_node_or_null("Name") as Label
    var button := cell.get_node_or_null("Icon") as Button
    if store == null or control == null or label == null or button == null:
        return
    var wrote := store.engine_for(label.text)
    var takes := _takes()
    var tip := tr("%s, a %s preset") % [label.text, SaPresetMeta.engine_name(wrote)]
    # The picture and the name are dimmed rather than the cell, so the star on
    # the picture stays at full strength. `self_modulate` on the
    # picture dims what the button draws and leaves its children alone.
    var strength := Color.WHITE
    if is_foreign(wrote, takes):
        tip = (
            tr("%s, a %s preset. This tool takes %s presets, so it will not apply")
            % [label.text, SaPresetMeta.engine_name(wrote), _names(takes)]
        )
        strength = Color(1.0, 1.0, 1.0, FOREIGN_ALPHA)
    button.self_modulate = strength
    label.modulate = strength
    # The picture of an eraser is empty on purpose, since it takes paint from a
    # layer that holds none, and an empty tile reads as a fault, so it says so.
    # Whether it erases is the store's, which reads it with the engine, the
    # sentence and the provenance off one load, and drops it when the preset is
    # written again, since a save over a name can make a brush an eraser.
    if store.erases(label.text):
        tip += "\n" + tr("An eraser draws nothing on a thumbnail")
    # What the preset lays and what it is for comes first, since that is what a
    # painter hovering a cell wonders, and the engine and where it came from
    # follow. A preset with no description opens on the engine's line as it did.
    var description := SaPresetStore.description_said(store.about_for(label.text))
    if not description.is_empty():
        tip = description + "\n" + tip
    # The bundle and its licence on a line of its own under the engine's. The
    # cell already shows the preset's name, so the tooltip is where a painter who
    # wonders whether they may ship a picture painted with it reads the answer,
    # and the sentence is the store's so the docker's line under the grid cannot
    # spell it differently. Empty for a preset whose file says nothing.
    var provenance := store.provenance_for(label.text)
    if not provenance.is_empty():
        tip += "\n" + provenance
    # The bundle's own sentence under it, what the whole bundle holds, which
    # only a bundle whose table declares one carries.
    var bundle_about := store.origin_for(label.text)[5]
    if not bundle_about.is_empty():
        tip += "\n" + bundle_about
    control.set_meta(TIP_META, tip)
    _show_tip(control)


## The tooltip *cell* keeps, or none while [member hushed]. On the cell as well
## as on its button, because the name under the picture ignores the mouse and a
## pointer resting on it is over the cell.
func _show_tip(cell: Control) -> void:
    var button := cell.get_node_or_null("Icon") as Control
    var tip := "" if hushed else String(cell.get_meta(TIP_META, ""))
    cell.tooltip_text = tip
    if button != null:
        button.tooltip_text = tip


## Connects to the drag helper of the scroll the grid sits in, once there is
## one. Asked again as each cell is marked, because the boot gives a docker's
## scroll its helper as the scroll enters the tree, after this was built.
func _find_mover() -> void:
    if _mover != null or chooser == null:
        return
    var node: Node = chooser.grid.get_parent()
    while node != null and not node is ScrollContainer:
        node = node.get_parent()
    if node == null or not node.has_meta(SaDragScroll.TAKEN_META):
        return
    _mover = node.get_meta(SaDragScroll.TAKEN_META) as SaDragScroll
    _mover.busy_changed.connect(_on_list_moves)
    if _mover.busy:
        _on_list_moves(true)


## Holds every cell's tooltip back as the list starts to move, and gives them
## back a tooltip's delay after it stands, when it has not moved again.
func _on_list_moves(moving: bool) -> void:
    _moves += 1
    if moving:
        _hush(true)
        return
    var tree := chooser.get_tree() if chooser != null else null
    if tree == null:
        _hush(false)
        return
    var delay := float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5))
    # A connection rather than an await, so a docker closed in the meantime
    # takes the call with it.
    tree.create_timer(delay).timeout.connect(_on_stood.bind(_moves))


## The list has stood a tooltip's delay since its move numbered *move* ended.
func _on_stood(move: int) -> void:
    if move == _moves:
        _hush(false)


func _hush(on: bool) -> void:
    if hushed == on or chooser == null or not is_instance_valid(chooser):
        return
    hushed = on
    for cell: Node in chooser.grid.get_children():
        if cell is Control and cell.has_meta(TIP_META):
            _show_tip(cell as Control)


## Whether a preset of *wrote* is one a tool taking the engines *takes* refuses.
## A named engine that is none of them, and nothing else, which is
## `SaPresetStore.refusal`'s rule over each engine the tool paints with.
static func is_foreign(wrote: StringName, takes: Array[StringName]) -> bool:
    return not String(wrote).is_empty() and not takes.is_empty() and not takes.has(wrote)


## The engines' names as a sentence reads them, "Stamp or Noise".
func _names(engines: Array[StringName]) -> String:
    var words := PackedStringArray()
    for engine: StringName in engines:
        words.append(SaPresetMeta.engine_name(engine))
    return tr(" or ").join(words)


## Every cell's engine, whether it is dimmed and what its tooltip says, and the
## line the corner notice is showing, which is where a refused apply says why.
func report() -> Dictionary:
    var store := _store()
    var cells: Dictionary = {}
    for cell: Node in chooser.grid.get_children() if chooser != null else []:
        var label := cell.get_node_or_null("Name") as Label
        if label == null or cell.is_queued_for_deletion() or store == null:
            continue
        cells[label.text] = {
            "engine": String(store.engine_for(label.text)),
            "dimmed": (cell.get_node("Icon") as Control).self_modulate.a < 1.0,
            "tooltip": String(cell.get_meta(TIP_META, (cell as Control).tooltip_text)),
        }
    var notice := SaMessage.notice_widget()
    return {
        "takes": ", ".join(PackedStringArray(_takes())),
        "cells": cells,
        "notice": notice.label.text if notice != null and notice.showing() else "",
    }


## `{"presets_docker": {"foreign": {"name": "Grain", "engine": "noise"}}}`: a
## preset of an engine Sara does not ship, written from the live settings with the
## engine the step names in place of theirs. The one way a scenario can hold the
## presets of two engines before a second engine exists.
##
## `{"foreign": {"name": "Grain", "remove": true}}` takes it away again, straight
## from the store. The bar's own delete step loads a preset first and deletes
## whatever is loaded, and a load of this one is refused, so that step would
## delete the preset the brush was already on.
static func write_foreign(presets: ToolOptionsPresets, spec: Dictionary) -> String:
    var live := presets.settings_source.call() as Resource if presets != null and presets.settings_source.is_valid() else null
    if live == null:
        return "SaCapture: no settings resource to write a preset of another engine from"
    if bool(spec.get("remove", false)):
        var gone := presets.preset_store.delete_preset(String(spec.get("name", "")))
        if gone:
            EventBus.preset_store_changed.emit(String(spec.get("name", "")), false)
        return "SaCapture: preset '%s' removed %s" % [spec.get("name", ""), gone]
    var engine := StringName(String(spec.get("engine", "")))
    var metadata := {SaPresetMeta.ENGINE_META: engine}
    var stored := presets.preset_store.save_preset(String(spec.get("name", "")), live, PackedStringArray(), metadata)
    if stored.is_empty():
        return "SaCapture: the %s preset would not save" % engine
    EventBus.preset_store_changed.emit(stored, true)
    return "SaCapture: preset '%s' written as a %s preset" % [stored, engine]


func _store() -> SaPresetStore:
    return store_source.call() as SaPresetStore if store_source.is_valid() else null


func _takes() -> Array[StringName]:
    var takes: Array[StringName] = []
    var answered: Variant = engine_source.call() if engine_source.is_valid() else null
    if answered is Array:
        takes.assign(answered)
    elif answered != null and not str(answered).is_empty():
        takes.append(StringName(str(answered)))
    return takes
