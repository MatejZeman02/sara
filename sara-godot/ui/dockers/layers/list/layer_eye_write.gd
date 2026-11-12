## What the Layers docker's eye writes, one press or a sweep of presses.
##
## The list flips each layer as the press or the sweep reaches it, through
## `show_now`, and hands what the sweep changed to `commit` when it ends. That
## is one undo step for the whole sweep when Preferences'
## `visibility_in_history` asks for one, and no step at all otherwise, as in
## Photoshop: the flips have marked the document changed already, and a save
## keeps the eyes as they stand.
##
## Static, so the step's two closures hold the document and the layers and
## never the list, which the history outlives. Its own file beside the list, as
## `layer_pick.gd` is, because the list stands near its limit.
class_name SaLayerEyeWrite
extends RefCounted


## The undo step for *layers*, each of which the list has set to *wanted*
## already and which stood at *previous* before. Nothing when the setting
## keeps the eye out of the history.
static func commit(document: SaDocument, layers: Array[SaLayer], previous: Array[bool], wanted: bool) -> void:
    if layers.is_empty() or not SaSettings.visibility_in_history:
        return
    document.history.commit_pair(
        "Layer Visibility",
        func() -> void: _apply_all(document, layers, wanted),
        func() -> void: _undo_all(document, layers, previous)
    )


## The effects `SaLayerOps.set_visible` bundles into one flip, repeated here
## rather than called there: that path would commit its own step per layer
## when the setting is on, which is the shape a sweep's single step cannot be
## built from.
static func show_now(document: SaDocument, layer: SaLayer, value: bool) -> void:
    layer.visible = value
    document.modified = true
    document.fold.debt.owe_shown(document, layer)


static func _apply_all(document: SaDocument, layers: Array[SaLayer], value: bool) -> void:
    for layer in layers:
        if is_instance_valid(layer):
            show_now(document, layer, value)


static func _undo_all(document: SaDocument, layers: Array[SaLayer], previous: Array[bool]) -> void:
    for i in layers.size():
        if is_instance_valid(layers[i]):
            show_now(document, layers[i], previous[i])
