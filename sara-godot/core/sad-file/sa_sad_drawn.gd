## A drawn layer's entry in a `.sad`: its recipe's JSON under [constant KEY],
## and none of its chunks, which `SaEffectLayer.stored_chunks` leaves out and
## the registry's rebind draws again from the recipe once the file is open.
##
## **Why a version.** A build before this one reads the entry as a layer with
## no chunks and shows it empty, then saves it back without the recipe, which
## loses the shapes. So a document with a drawn layer is stamped
## [constant VERSION], and an older build refuses it by name.
##
## A layer whose type no registered module draws keeps the JSON it came with,
## `SaDrawnLayer.KEPT`, and is written back with it unchanged, so a file
## opened on a build without the module loses nothing.
class_name SaSadDrawn
extends RefCounted

## What a document with a drawn layer is written as.
const VERSION := SaSadSharedSource.VERSION + 2
## The key of the recipe in a layer's entry.
const KEY := "drawn"


## Whether *layer*'s entry carries a recipe.
static func keeps_recipe(layer: SaLayer) -> bool:
    return layer != null and (layer.is_drawn() or layer.has_meta(SaDrawnLayer.KEPT))


## Writes *layer*'s recipe into its header *entry*, and nothing for a layer
## with none.
static func write_header(layer: SaLayer, entry: Dictionary[String, Variant]) -> void:
    if layer.is_drawn():
        entry[KEY] = layer.recipe.to_json()
    elif layer.has_meta(SaDrawnLayer.KEPT):
        entry[KEY] = layer.get_meta(SaDrawnLayer.KEPT)


## Keeps what [method write_header] wrote on *layer*, for the rebind to hand
## the recipe its type's script makes.
static func read_header(layer: SaLayer, entry: Dictionary[String, Variant]) -> void:
    var saved: Variant = entry.get(KEY)
    if saved is Dictionary:
        layer.set_meta(SaDrawnLayer.KEPT, saved)
