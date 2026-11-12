## A transform tool's session on a layer's live transform, which `SaTransform`
## holds in place of a lift when the tool opens on a smart layer, one that
## carries a live transform already, with no selection.
##
## **Nothing is lifted and nothing is resampled.** The box is the layer's paint
## in its own pixels, the map starts as the one `SaLiveTransform` draws the
## layer through, and each frame's map is drawn by that live transform's cache
## through `SaLiveTransform.preview`, which writes no history step. So the
## layer's chunks never change while the hand moves, and the session ends in
## one `SaLiveTransform.put` from the map it opened on to the last one drawn.
##
## **A refused map leaves the last one drawn.** A perspective whose horizon
## crosses the canvas is refused by the layer's transform, so the frame keeps
## what it showed and Enter puts that, rather than a map nobody saw.
##
## A cut from the pass by responsibility: the pass owns the lift's chunks and
## kernels, and this owns the two maps a live session is between and the rules
## of drawing and putting them, which share nothing with a lift but the box.
class_name SaTransformLive
extends RefCounted

var _document: SaDocument
## The layer the session is open on.
var _layer: SaLayer
## The map the layer was drawn through when the session opened, a `Basis`, or
## null for a layer drawn where it was painted. Escape draws it again.
var _from: Variant = null
## The last map the session drew, which Enter puts. Null for none.
var _drawn: Variant = null


func _init(document: SaDocument, layer: SaLayer, map: Variant) -> void:
    _document = document
    _layer = layer
    _from = map
    _drawn = map


## A session on *layer* over *box*, its paint in its own pixels, or null when the
## layer takes no live transform or has no paint, with the sentence why in the
## corner for the first.
static func open(document: SaDocument, layer: SaLayer, box: Rect2i) -> SaTransformLive:
    var live := SaLiveTransform.of(layer)
    var why := SaLiveTransform.refusal(document, layer, live.matrix if live != null else Basis.IDENTITY)
    if not why.is_empty():
        SaProblems.refuse(
            SaTransform.ACTION_NAME, TranslationServer.translate("The transform tool cannot open on this layer. %s") % why
        )
        return null
    if not box.has_area():
        return null
    if live == null:
        return SaTransformLive.new(document, layer, null)
    return SaTransformLive.new(document, layer, live.matrix)


## The layers the tool acts on in *document*, the picked set or the active
## layer alone, and the live map each rests at, the identity for none, which
## the tool compares each frame with what its Tool Options rows were last
## told. A map put while no session is open, by the door's layer step, an undo
## or a switch of layer, reaches Width, Height and Angle on the next frame.
## Without it the rows read 100 % over a sky the layer step had halved and
## turned. A pick of several is read too, since the rows then stand at
## the identity of the set's plain box.
static func under(document: SaDocument) -> Array:
    var out: Array = []
    if document == null:
        return [0, Basis.IDENTITY]
    var acted: Array[SaLayer] = document.picked.acted_on(document) if document.picked != null else []
    if acted.is_empty():
        return [0, Basis.IDENTITY]
    for layer: SaLayer in acted:
        var live := SaLiveTransform.of(layer)
        out.append_array([layer.get_instance_id(), live.matrix if live != null else Basis.IDENTITY])
    return out


## The map *map*, a `Basis` or null, as the pass holds one over *box*: the
## affine part, and the nine numbers row by row when it is a perspective,
## which are empty otherwise.
static func resting(map: Variant, box: Rect2i) -> Array:
    if not map is Basis:
        return [Transform2D.IDENTITY, PackedFloat32Array()]
    var basis: Basis = map
    var h := PackedFloat32Array(SaLiveTransform.new(basis).floats())
    var w := h[8]
    for i in 9:
        h[i] /= w
    if not is_zero_approx(h[6]) or not is_zero_approx(h[7]):
        return [SaHomography.affine_part(h, box, Transform2D.IDENTITY), h]
    return [Transform2D(Vector2(h[0], h[3]), Vector2(h[1], h[4]), Vector2(h[2], h[5])), PackedFloat32Array()]


## The map the pass stands at, from the layer's paint to the canvas, the
## homography when there is one and *matrix* otherwise, or null for the
## identity, which takes the transform off.
static func map_at(matrix: Transform2D, homography: PackedFloat32Array) -> Variant:
    var h := homography
    if h.size() != 9:
        h = PackedFloat32Array([matrix.x.x, matrix.y.x, matrix.origin.x, matrix.x.y, matrix.y.y, matrix.origin.y, 0.0, 0.0, 1.0])
    var map: Basis = SaLiveTransform.map_of(Array(h))
    if map.is_equal_approx(Basis.IDENTITY):
        return null
    return map


## The map the session opened on as the pass holds one over *box*, the way
## [method resting] gives any map.
func at_rest(box: Rect2i) -> Array:
    return resting(_from, box)


## Whether the layer's transform refuses the homography *h*, nine numbers row
## by row, so the pass keeps the map it had.
func refuses(h: PackedFloat32Array) -> bool:
    return not SaLiveTransform.refusal(_document, _layer, SaLiveTransform.map_of(Array(h))).is_empty()


## Whether *map* is off the map the session opened on.
func has_moved(map: Variant) -> bool:
    return not same(map, _from)


## Draws the layer through *map* unless it is the one already drawn or the
## layer's transform refuses it.
func draw(map: Variant) -> void:
    if not same(map, _drawn) and SaLiveTransform.preview(_document, _layer, map):
        _drawn = map


## Ends the session as one history step from the map it opened on to the last
## one drawn, which the layer is shown at the step's start, and as none when
## the two are one map.
func put() -> bool:
    if same(_from, _drawn):
        return false
    SaLiveTransform.preview(_document, _layer, _from)
    return SaLiveTransform.put(_document, _layer, _drawn)


## Draws the layer at the map the session opened on, which is Escape.
func restore() -> void:
    if not same(_drawn, _from):
        SaLiveTransform.preview(_document, _layer, _from)


## Whether *a* and *b*, each a `Basis` or null, are one map.
static func same(a: Variant, b: Variant) -> bool:
    if a == null or b == null:
        return a == null and b == null
    return (a as Basis).is_equal_approx(b)
