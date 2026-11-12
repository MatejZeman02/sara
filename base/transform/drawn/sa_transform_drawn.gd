## A drawn layer under the Transform tool, one whose recipe takes a move, which
## is the text layer's: the box drags its pixels as it drags paint, and Enter
## puts them back and hands the move to the recipe, which draws its letters
## again at the new place, sharp, as one step whose undo puts the recipe back.
##
## **The drag is the lift's own.** The lift cuts the cache out of the layer's
## chunks into the stroke layer like any paint, so the preview is the same
## picture a paint layer's would be and costs no second path. Enter and Escape
## both put the chunks back first, so the only change that outlives the
## gesture is the recipe's, the one `SaDrawnLayer` draws from and the `.sad`
## keeps. A move resampled into the chunks would be gone at the next edit or
## open, which draw the recipe back where it was.
##
## **Only a move.** A scale, a turn, a skew, a perspective, a mesh and a part
## of the layer under a selection are not built yet, so each is refused with
## the drawn kind's sentence, said once a gesture, and the box stays where the
## last move put it.
class_name SaTransformDrawn
extends RefCounted

## What the undo menu calls the move, the name a layer's live transform gives
## the same gesture on a smart layer.
const ACTION_NAME := "Transform Layer"

var _layer: SaLayer
## Whether this gesture has said its refusal, so a drag of a handle says it
## once rather than on every motion.
var _said := false


func _init(layer: SaLayer) -> void:
    _layer = layer


## The move for *layer*, or null when the Transform tool lifts it as paint or
## refuses it as a drawn layer that takes no move, a vector layer, or a locked
## one, whose own line the lift says.
static func of(layer: SaLayer) -> SaTransformDrawn:
    if layer == null or layer.recipe == null or layer.is_locked:
        return null
    return SaTransformDrawn.new(layer) if _takes_moves(layer) else null


## Whether *layer*'s recipe takes a move, asked of a copy so the layer's own
## stays as it is.
static func _takes_moves(layer: SaLayer) -> bool:
    var held: Variant = layer.recipe.get_script()
    var script: Script = held if held is Script else null
    if script == null or not script.can_instantiate():
        return false
    var made: Variant = script.call(&"new")
    if not made is SaDrawnRecipe:
        return false
    var trial: SaDrawnRecipe = made
    trial.from_json(layer.recipe.to_json())
    return trial.take_map(Transform2D(0.0, Vector2.ONE))


## Whether *map* moves the box and does nothing else.
static func is_move(map: Transform2D) -> bool:
    return map.x.is_equal_approx(Vector2.RIGHT) and map.y.is_equal_approx(Vector2.DOWN)


## Says in the corner that the gesture asked more of the layer than a move,
## once a gesture.
func refuse() -> void:
    if _said:
        return
    _said = true
    EventBus.corner_notice.emit(SaContext.reshape_refusal_line(_layer))


## Hands the move *by*, in document pixels, to the recipe and draws the layer
## again where it was and where it lands, as one step. True when the recipe
## moved. Called once the lift has put the chunks back.
func land(by: Vector2) -> bool:
    if by.is_zero_approx() or not is_instance_valid(_layer):
        return false
    var layer := _layer
    var move := func(recipe: SaDrawnRecipe) -> void:
        var was := recipe.bounds()
        if recipe.take_map(Transform2D(0.0, by)):
            SaDrawnLayer.redraw(layer, [was, recipe.bounds()])
    return SaDrawnLayer.edit(layer, ACTION_NAME, move)
