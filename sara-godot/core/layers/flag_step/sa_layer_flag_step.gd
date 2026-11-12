## A row's paint padlock, its alpha padlock or its clip, set on every picked
## row as one history step, named as the More menu names it.
##
## A flag written with no step of its own would leave the painter's next
## Ctrl+Z taking the paint laid before it and leaving the lock or the clip on.
## The row's buttons and the menu's clip row come here, so a press is one step whatever
## the number of rows it reached, and one Ctrl+Z gives every one of them back.
##
## In `core` rather than beside the docker, because the Layer menu's chords for
## the two locks and for Clip to Layer Below write the same step over the picked
## set, and `core` never names `ui`. Nothing in it was the docker's: it reads a
## document and its layers alone.
class_name SaLayerFlagStep
extends RefCounted

## The step's name for each flag, the words the menu's own steps carry.
const NAMES := {&"paint": "Layer Lock", &"alpha": "Layer Alpha Lock", &"clip": "Clip to Layer Below"}

var _document: SaDocument


func _init(document: SaDocument) -> void:
    _document = document


## Sets *which* to *wanted* on each of *layers* and writes one step for the rows
## it changed. A row that already holds *wanted* is left out of the step, so an
## undo never flips a row the press did not. A document with no history, which
## only a suite builds, takes the flags alone.
func write(layers: Array[SaLayer], which: StringName, wanted: bool) -> void:
    if _document == null or not NAMES.has(which):
        return
    var changed: Array[SaLayer] = []
    for layer in layers:
        if layer != null and is_instance_valid(layer) and read(layer, which) != wanted:
            changed.append(layer)
    if changed.is_empty():
        return
    _apply(changed, which, wanted)
    if _document.history != null:
        var step_name: String = NAMES[which]
        _document.history.commit_pair(step_name, _apply.bind(changed, which, wanted), _apply.bind(changed, which, not wanted))


## The flag *which* on *layer*.
static func read(layer: SaLayer, which: StringName) -> bool:
    match which:
        &"paint":
            return layer.is_locked
        &"alpha":
            return layer.alpha_locked
        _:
            return layer.clip_to_below


## Both sides of the step. The clip goes through the stack, which marks the
## clipped layer's chunks for the compositor, and the locks announce the
## document once, as `SaLayerOps` does for a single lock.
func _apply(layers: Array[SaLayer], which: StringName, value: bool) -> void:
    for layer in layers:
        if not is_instance_valid(layer):
            continue
        match which:
            &"paint":
                layer.is_locked = value
            &"alpha":
                layer.alpha_locked = value
            _:
                SaLayerStack.set_clip_to_below(_document, layer, value)
    if which != &"clip":
        _document.modified = true
        _document.document_changed.emit()
