## The Brush Presets panel's Random button, which loads one of the presets the
## panel shows.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It picks at random from what the filters leave. A painter who has narrowed the grid
## with the search, the tags or Starred presses this and gets one of the cells
## the grid shows, loaded through the docker's `apply_preset`, the path a click
## on a cell takes, so Recent Presets records it and the grid marks it.
##
## **What it draws from.** The grid's own `visible_names()`, less the cells
## dimmed for the tool in hand, which is `SaPresetPick.lit_names`, the door's
## Random step's reading of the same grid. A press on a dimmed cell loads
## nothing and brings the corner notice naming the two engines, so a pick of one
## here would be a press that does nothing. Less the preset in hand as well,
## which also leaves out the cell the grid adds only because the filters hide
## the preset in hand, since that cell is always the preset in hand.
##
## A class of its own beside the docker, which stands at its line budget, and
## a button rather than a helper the docker holds, because it keeps its own
## state, whether it can be pressed and the tooltip that says why not.
class_name SaRandomPresetButton
extends Button

var docker: BrushPresetsDocker = null

## The draw, randomised once, so two presses in one frame differ.
var _rng := RandomNumberGenerator.new()

## Whether a `sync` is waiting for the end of the frame, so a grid that adds
## its cells one by one is read once.
var _sync_queued: bool = false


func _init(host: BrushPresetsDocker, parent: Node) -> void:
    docker = host
    name = "ChooserRandom"
    text = tr("Random")
    focus_mode = Control.FOCUS_NONE
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _rng.randomize()
    parent.add_child(self)
    pressed.connect(press)
    # The chooser rebuilds its grid on a search, a tag or Starred without
    # telling its host, and every rebuild that changes which cells stand
    # sorts the grid again, so the sort is the one signal that hears them all.
    docker.chooser.grid.sort_children.connect(queue_sync)
    docker.chooser.search_field.text_changed.connect(queue_sync.unbind(1))


func _ready() -> void:
    for heard: Signal in [EventBus.preset_loaded, EventBus.tool_changed, EventBus.preset_store_changed]:
        if not heard.is_connected(_on_heard):
            heard.connect(_on_heard)
    queue_sync()


func _on_heard(_what: Variant = null, _also: Variant = null) -> void:
    queue_sync()


## Reads the grid again at the end of the frame, once however often it is asked.
func queue_sync() -> void:
    if _sync_queued:
        return
    _sync_queued = true
    sync.call_deferred()


## The presets a press can load now, in the order the grid shows them: the
## cells the grid shows, less the dimmed ones and less the preset in hand.
func candidates() -> Array[String]:
    if docker == null or docker.chooser == null:
        return [] as Array[String]
    var lit := SaPresetPick.lit_names(docker, docker.chooser.visible_names())
    lit.erase(_in_hand())
    return lit


## Dims the button when a press would have nothing to load, with a tooltip that
## says why, the way Save As... and Delete say theirs.
func sync() -> void:
    _sync_queued = false
    var shown := docker.chooser.visible_names() if docker != null and docker.chooser != null else [] as Array[String]
    var can := not candidates().is_empty()
    disabled = not can
    if can:
        tooltip_text = tr("Load a random preset from those shown now.")
    elif shown.is_empty():
        tooltip_text = tr("No preset is shown, so there is none to pick. Clear the search or the tags.")
    elif shown.size() == 1 and shown[0] == _in_hand():
        tooltip_text = tr("Only the preset in hand is shown, so there is no other to pick.")
    else:
        tooltip_text = tr("The tool in hand takes none of the presets shown.")


## Loads one of `candidates()` as a click on its cell would, and answers its
## name, or empty when there was none to load or the load failed.
func press() -> String:
    var offered := candidates()
    var found := "" if offered.is_empty() else offered[_rng.randi_range(0, offered.size() - 1)]
    if not found.is_empty() and not docker.apply_preset(found):
        found = ""
    sync()
    return found


func _in_hand() -> String:
    var source := docker.chooser.loaded_source
    return str(source.call()) if source.is_valid() else ""
