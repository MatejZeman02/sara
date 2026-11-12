## What the fold baked into its caches at the last rebuild, masks, effects and
## the nodes each cache holds, by instance id.
##
## A cache holds what its layers showed when the fold ran, so a change to a
## mask or an effect layer baked into one moves nothing the canvas draws until
## the fold runs again. `SaDocument.mask_moved` and `SaEffectLayer.refresh` ask
## the fold which kind they have, and the fold asks this ledger. A write of an
## attached filter's parameters asks which caches baked the record's node, so
## that those alone fold again and only over what the node draws. It knows no fold and no document: the fold hands it each step it
## composites into a cache, and empties it when a rebuild starts or the caches
## go.
class_name SaFoldLedger
extends RefCounted

## Every mask a folded step read: a layer's, a group's and an attached
## filter's, a clipping base's and those clipped to it among them.
var masks: Dictionary[int, bool] = {}
## Every effect layer folded into a cache, which only an isolated group away
## from the active layer does.
var effects: Dictionary[int, bool] = {}
## What each cache baked, by the cache's instance id: the instance ids of the
## node and the layer of every step folded into it, as a set. The two differ
## for an isolated group's step, whose layer is the group's own cache, so a
## cache that baked another cache names it here.
var baked: Dictionary[int, Dictionary] = {}


## Forgets everything, for a rebuild that is about to fold afresh and for a
## fold whose caches are freed.
func forget() -> void:
    masks = {}
    effects = {}
    baked = {}


## Notes what the step *atom*, one of `SaLayerStack`'s entries, reads when it
## is folded into *cache*: the node's mask and its filters', the layer's, which
## for a group's cache is the group's, and the layer itself when it is an
## effect layer. With a *cache*, the step's node and layer are noted as baked
## into it. A clipping base's step reads the same of the base and of every
## step clipped to it, since the group draws each as it shows.
func note(atom: Dictionary, cache: SaLayer = null) -> void:
    for part in SaLayerStack.parts_of(atom):
        var layer: SaLayer = part[SaLayerStack.LAYER]
        var node: SaLayer = part.get(SaLayerStack.NODE, layer)
        if cache != null:
            var held: Dictionary = baked.get_or_add(cache.get_instance_id(), {})
            held[node.get_instance_id()] = true
            held[layer.get_instance_id()] = true
        if layer.is_effect():
            effects[layer.get_instance_id()] = true
        var read: Array[SaMask] = [layer.mask, node.mask]
        for record: SaAttachedFilter in node.filters:
            read.append(record.mask)
        for mask in read:
            if mask != null:
                masks[mask.get_instance_id()] = true


## Whether the last rebuild baked *mask* into a cache.
func folds(mask: SaMask) -> bool:
    return mask != null and masks.has(mask.get_instance_id())


## Whether the last rebuild baked *effect* into a cache.
func folds_effect(effect: SaLayer) -> bool:
    return effect != null and effects.has(effect.get_instance_id())


## Whether the last rebuild baked into *cache* a step whose node or layer is
## one of *ids*, a set of instance ids.
func bakes(cache: SaLayer, ids: Dictionary[int, bool]) -> bool:
    if cache == null:
        return false
    var held: Dictionary = baked.get(cache.get_instance_id(), {})
    for id: int in ids:
        if held.has(id):
            return true
    return false
