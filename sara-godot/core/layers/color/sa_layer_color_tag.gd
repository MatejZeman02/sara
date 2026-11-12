## A row's colour, Photoshop's list of them, and the step that gives it to every
## picked row at once.
##
## A painter gives a row its colour on a right click in the Layers docker, as
## in Photoshop. The colour is the layer's, `SaLayer.color_tag`, saved in
## the `.sad`, and nothing that paints reads it.
##
## In `core` rather than beside the docker, because the Layer menu and the door
## can set it over the picked set too, and `core` never names `ui`. The hues
## are here for the same reason, and how strongly a row is tinted by one is the
## docker's.
class_name SaLayerColorTag
extends RefCounted

## No Colour first, then Photoshop's seven in its order.
const IDS: Array[StringName] = [&"", &"red", &"orange", &"yellow", &"green", &"blue", &"violet", &"gray"]

## The words of each, in the order of `IDS`. Grey is spelt the British way the
## rest of the app is, and its id keeps Photoshop's.
const WORDS: Array[String] = ["No Colour", "Red", "Orange", "Yellow", "Green", "Blue", "Violet", "Grey"]

## Each colour at full strength, in the order of `IDS`, No Colour transparent.
## Close to the ones Photoshop tints its rows with, a step more saturated so
## they still read once the docker thins them over a dark theme.
const HUES: Array[Color] = [
    Color(0, 0, 0, 0),
    Color(0.86, 0.27, 0.27),
    Color(0.93, 0.55, 0.2),
    Color(0.92, 0.82, 0.25),
    Color(0.36, 0.72, 0.36),
    Color(0.3, 0.55, 0.9),
    Color(0.62, 0.42, 0.85),
    Color(0.55, 0.55, 0.55),
]

## The name of the history step, the words the menu's row reads.
const STEP := "Layer Colour"

var _document: SaDocument


func _init(document: SaDocument) -> void:
    _document = document


## *id* when it is one of `IDS`, and No Colour for anything else, which is a
## file from a build that knew a colour this one does not.
static func known(id: StringName) -> StringName:
    return id if IDS.has(id) else &""


## The full strength hue of *id*, transparent for No Colour.
static func hue(id: StringName) -> Color:
    return HUES[maxi(IDS.find(known(id)), 0)]


## The words of *id*, untranslated.
static func words(id: StringName) -> String:
    return WORDS[maxi(IDS.find(known(id)), 0)]


## Gives each of *layers* the colour *id* and writes one step for the rows it
## changed, each undone to the colour it had, so a set of three rows in three
## colours comes back as it was. False when no row changed. A document with no
## history, which only a suite builds, takes the colours alone.
func write(layers: Array[SaLayer], id: StringName) -> bool:
    if _document == null or not IDS.has(id):
        return false
    var changed: Array[SaLayer] = []
    var before: Array[StringName] = []
    var after: Array[StringName] = []
    for layer in layers:
        if layer != null and is_instance_valid(layer) and layer.color_tag != id and not changed.has(layer):
            changed.append(layer)
            before.append(layer.color_tag)
            after.append(id)
    if changed.is_empty():
        return false
    _apply(changed, after)
    if _document.history != null:
        _document.history.commit_pair(STEP, _apply.bind(changed, after), _apply.bind(changed, before))
    return true


## Both sides of the step: each layer its colour, and the document announced
## once so every list showing it redraws its rows.
func _apply(layers: Array[SaLayer], colors: Array[StringName]) -> void:
    for index in layers.size():
        if is_instance_valid(layers[index]):
            layers[index].color_tag = colors[index]
    _document.modified = true
    _document.document_changed.emit()
