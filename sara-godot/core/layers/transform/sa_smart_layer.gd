## A smart layer: one the painter made smart, which keeps its paint as it was
## painted and is drawn through a live transform for as long as it stays
## smart, an identity map included. A layer is smart only when the painter
## asks, and the untransformed placement is what is kept, so many transforms
## lose no quality and a reset goes back to where the paint was painted.
##
## **The marker** is `SaLiveTransform.smart`, set in the constructor of the
## layer's transform, so it is never true on a layer with no transform and
## the history, which swaps transforms, swaps it with them. A tool dragged
## back onto the paint, or the door's `"none"`, hands `SaLiveTransform.put`
## no map, and a smart layer takes the identity instead of losing its
## transform, [method held]. A layer some step put a map on with no marker,
## a scenario's layer step, is smart until a map of nought takes the
## transform off.
##
## **The source** is the layer's own chunks, which no change of the map
## writes. Every map is resampled from them by the transform's cache, so a
## chain of transforms draws what one transform to its last map draws. Two
## smart layers can hold one, `SaSharedSource`.
##
## **The three commands.** Make Smart Layer puts an identity transform with
## the marker on, Reset Transform puts the identity back with the crop off,
## and Convert to Ordinary Layer is `SaLiveTransform.bake`, which writes the
## picture in and takes the transform off, the marker with it. Each is one
## history step. A bake allocates only chunks inside the canvas, so a part
## of the source the map showed outside it is dropped by Convert, and its
## undo gives it back.
##
## **Saved** in the layer's `.sad` entry: the map under `SaLiveTransform.KEY`,
## the crop under `SaLiveCrop.KEY`, the marker under [constant KEY] and the
## layer whose entry holds a shared source under `SaSharedSource.KEY`, and the
## file a linked layer reads under `SaLinkedFile.ENTRY`. A file whose entry
## holds a map and no marker opens smart, since it was saved by a build where
## any transformed layer kept its map, and a file with neither key opens
## ordinary.
class_name SaSmartLayer
extends RefCounted

## The key a smart layer's `.sad` entry keeps its marker under.
const KEY := "smart"
## The name Make Smart Layer takes in the history and in the corner.
const MAKE := "Make Smart Layer"
## The name Reset Transform takes in the history and in the corner.
const RESET := "Reset Transform"


## Whether *layer* is smart: it carries a live transform.
static func is_smart(layer: SaLayer) -> bool:
    return SaLiveTransform.of(layer) != null


## Whether *layer* was made smart and so keeps a transform at rest.
static func is_marked(layer: SaLayer) -> bool:
    var live := SaLiveTransform.of(layer)
    return live != null and live.smart


## The transform *layer* is to be drawn through for *map*, a `Basis` or null,
## given *before*, the one it has: a new one at *map*, keeping *before*'s crop,
## marker and source, and for null none, or the identity with the crop off
## when *before* carries the marker, so a smart layer stays smart.
static func held(before: SaLiveTransform, map: Variant) -> SaLiveTransform:
    var smart := before != null and before.smart
    var source: SaSharedSource = before.source if before != null else null
    if map is Basis:
        var basis: Basis = map
        return SaLiveTransform.new(basis, before.crop if before != null else null, smart, source)
    return SaLiveTransform.new(Basis.IDENTITY, null, true, source) if smart else null


## Layer > Make Smart Layer: puts the identity transform with the marker on
## *layer*, or the map it carries with the marker added, as one history step,
## and answers whether it did. A layer that cannot be made smart says why in
## the corner and is left as it was.
static func make(document: SaDocument, layer: SaLayer) -> bool:
    if is_marked(layer):
        SaProblems.refuse(MAKE, TranslationServer.translate("'%s' is a smart layer already.") % layer.name)
        return false
    var why := SaLiveTransform.refusal(document, layer, Basis.IDENTITY)
    if not why.is_empty():
        SaProblems.refuse(MAKE, TranslationServer.translate("The layer cannot be made smart. %s") % why)
        return false
    var before := SaLiveTransform.of(layer)
    var map := before.matrix if before != null else Basis.IDENTITY
    var after := SaLiveTransform.new(map, before.crop if before != null else null, true, SaSharedSource.of(layer))
    SaLiveTransform.put_step(document, layer, after, MAKE)
    return true


## Layer > Reset Transform: draws smart *layer* where its paint was painted,
## the identity with the crop off, as one history step, and answers whether
## it did. The layer stays smart and the undo gives the map back. An ordinary
## layer, or one whose transform cannot change, says why in the corner.
static func reset(document: SaDocument, layer: SaLayer) -> bool:
    if not is_smart(layer):
        var plain := "'%s' is not a smart layer, so it has no transform to reset."
        var named := String(layer.name) if layer != null else ""
        SaProblems.refuse(RESET, TranslationServer.translate(plain) % named)
        return false
    var why := SaLiveTransform.refusal(document, layer, Basis.IDENTITY)
    if not why.is_empty():
        SaProblems.refuse(RESET, TranslationServer.translate("The transform cannot be reset. %s") % why)
        return false
    var after := SaLiveTransform.new(Basis.IDENTITY, null, true, SaSharedSource.of(layer))
    if not SaLiveTransform.changed_from(layer, after):
        return false
    SaLiveTransform.put_step(document, layer, after, RESET)
    return true


## Writes *layer*'s map into its header entry *layer_dict*, with its crop when
## it has one and its marker when it carries one, and nothing for an ordinary
## layer, so a file of ordinary layers is the file it was.
static func write_header(layer: SaLayer, layer_dict: Dictionary[String, Variant]) -> void:
    var live := SaLiveTransform.of(layer)
    if live == null:
        return
    layer_dict[SaLiveTransform.KEY] = live.floats()
    if live.crop.any():
        layer_dict[SaLiveCrop.KEY] = live.crop.numbers()
    if live.smart:
        layer_dict[KEY] = true
    SaSharedSource.write_header(layer, layer_dict)
    SaLinkedFile.write_header(layer, layer_dict)


## Gives *layer* the transform *layer_data* keeps, marked smart, when the entry
## holds a map or the marker, with its crop when it keeps one, and none when it
## holds neither, which reads a file saved before either key as it was.
static func read_header(layer: SaLayer, layer_data: Dictionary[String, Variant]) -> void:
    var read: Variant = SaLiveTransform.map_of(layer_data.get(SaLiveTransform.KEY, null))
    var marked: bool = layer_data.get(KEY, false) == true
    if not read is Basis and not marked:
        return
    var map: Basis = read if read is Basis else Basis.IDENTITY
    if absf(map.determinant()) > 1.0e-12:
        layer.live_transform = SaLiveTransform.new(map, SaLiveCrop.read(layer_data.get(SaLiveCrop.KEY, null)), true)
        SaSharedSource.read_header(layer, layer_data)
        SaLinkedFile.read_header(layer, layer_data)
