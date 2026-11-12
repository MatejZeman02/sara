## A scene layer's live transform: what a layer whose chunks its scene writes
## again each frame needs that a paint layer's transform does not.
##
## **At rest.** A scene layer carries the identity with the smart marker from
## the moment its viewport is attached, [method rest], so the Transform tool
## opens a live session on it as on a smart layer, with the same handles, and
## Enter puts the map rather than resampling the chunks, which the scene would
## write over on its next frame. The identity draws the layer itself and makes
## no cache, [method passes], since a cache would be a second copy of a picture
## redrawn every frame and would show nothing the chunks do not.
##
## **Each frame.** The scene's copy tells the transform where it wrote,
## [method copied], and the next composite resamples the footprint of that
## region alone through the map, hard rule 2, so the scene keeps drawing under
## the transform, and the transform is never folded into the scene's pixels.
##
## **Never baked.** Convert to Ordinary Layer and Edit Smart Layer Contents are
## not offered on a scene layer, [method refuses_bake], because the scene owns
## its chunks and writes them again on its next dirty frame. A map that folds
## the layer flat is refused with the sentence a paint layer's is.
class_name SaSceneTransform
extends RefCounted


## Gives *layer*, a scene layer with no live transform, the identity with the
## smart marker, the transform it rests at. A layer that has one, read from its
## file or put by a step, keeps it.
static func rest(layer: SaLayer) -> void:
    if layer == null or not layer.is_scene() or SaLiveTransform.of(layer) != null:
        return
    layer.live_transform = SaLiveTransform.new(Basis.IDENTITY, null, true)


## Whether *layer* is a scene layer *live* draws where its scene drew it: the
## identity, no crop and no shared source. Such a layer is composited as it is,
## with no cache.
static func passes(layer: SaLayer, live: SaLiveTransform) -> bool:
    if layer == null or live == null or not layer.is_scene():
        return false
    return live.matrix == Basis.IDENTITY and not live.crop.any() and live.source == null


## Where the scene's copy of *regions*, grid position to chunk-local region in
## *layer*'s own pixels, shows in *document*: the regions themselves for a
## layer drawn where its scene drew it, and otherwise their footprints through
## the map, which the transform resamples on the next composite.
static func copied(document: SaDocument, layer: SaLayer, regions: Dictionary[Vector2i, Rect2i]) -> Dictionary[Vector2i, Rect2i]:
    var live := SaLiveTransform.of(layer)
    if live == null or passes(layer, live) or SaLocalView.untransformed(layer):
        return regions
    return live.painted(document, regions, false)


## Whether *layer* turns away a bake of its transform, which a scene layer does.
static func refuses_bake(layer: SaLayer) -> bool:
    return layer != null and layer.is_scene()
