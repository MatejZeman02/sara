## The Exposure docker's Bake, Attach and Layer toggle, the filter dialog's way
## of applying, as one remembered choice with it.
##
## The stops and their words are the dialog's own, `SaFilterDialogWindow.WAYS`
## and `WAY_LABELS`, and so is the preference: a hand's pick here writes
## `SaSettings.filter_way` as one on the dialog does, so the next filter opens
## on it and this toggle on the dialog's. A way the active layer refuses is
## dimmed with `SaFilterApply.way_refusal`'s sentence, and the thumb settles on
## the first open way without writing the preference, the dialog's rule, so it
## is back on the remembered way as soon as that way opens.
##
## A stop slider of its own rather than one `SaMake.stops` made, because the
## dims and the settle are this choice's and are asked every frame the docker
## is shown, which a row reaching into a plain toggle would do from outside.
##
## No class name, as no class of a module has one that a copy of its folder
## would collide with: the row reaches this file by its path beside it.
extends SaStopSlider

## What each way's tooltip says, in `SaFilterDialogWindow.WAYS`'s order.
const TIPS: Array[String] = [
    "Writes the exposure into the active layer's pixels, or every paint layer of a group.",
    "Attaches the exposure to the active layer instead, where it stays editable until it is flattened.",
    "Adds an adjustment layer holding the exposure above the active layer, which adjusts everything under it.",
]


func _init() -> void:
    # Following its width, so a language longer than English shows the picked
    # way alone rather than widening the docker past its Apply button.
    super(_choices(), true)
    name = "ExposureWayToggle"
    # The kind `SaMake.stops` marks its toggles with, so the walker prints this.
    set_meta(SaMake.KIND_META, SaMake.Kind.STOPS)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # Written before the connection, so opening on the remembered way is not
    # heard as a pick.
    value = StringName(SaInHand.Settings.read(&"filter_way"))
    picked.connect(_on_picked)


## Dims each way *layer* refuses, Bake over the whole picture when *every*,
## Attach and Layer with the first line of *problem* for a filter that cannot
## be attached, and Layer when *types* is false, no module registering the
## adjustment layer. Then puts the thumb on the remembered way when it is open,
## and off a dimmed way otherwise. A dim is written only where it changed,
## since this runs every frame the docker is shown and a dim redraws.
func settle(layer: SaLayer, every: bool, problem: String, types: bool) -> void:
    for id: StringName in SaFilterDialogWindow.WAYS:
        var why := SaFilterApply.way_refusal(layer, id, every) if layer != null else tr("There is no active layer.")
        if why.is_empty() and id != SaFilterDialogWindow.WAYS[0]:
            why = problem
        if why.is_empty() and id == &"layer" and not types:
            why = tr("No module registers the adjustment layer.")
        if String(dimmed.get(id, "")) != why:
            dim(id, why)
    var open := SaFilterDialogWindow.WAYS.filter(func(id: StringName) -> bool: return not dimmed.has(id))
    var wanted := StringName(SaInHand.Settings.read(&"filter_way"))
    if open.has(wanted):
        if value != wanted:
            value = wanted
    elif not open.is_empty() and not open.has(value):
        value = open[0]


## Whether the thumb stands on a way a hand could pick.
func is_open() -> bool:
    return not dimmed.has(value)


## The three ways as the toggle takes them, each with its word and its tooltip.
## The words stay English, because the toggle translates its own labels.
static func _choices() -> Array:
    var choices: Array = []
    for index in SaFilterDialogWindow.WAYS.size():
        var tip := TranslationServer.translate(TIPS[index])
        choices.append({"id": SaFilterDialogWindow.WAYS[index], "label": SaFilterDialogWindow.WAY_LABELS[index], "tooltip": tip})
    return choices


## A hand's pick becomes the way every filter opens on.
func _on_picked(id: Variant) -> void:
    SaInHand.Settings.write(&"filter_way", String(id))
