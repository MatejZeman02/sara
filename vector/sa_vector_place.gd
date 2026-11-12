## Puts a new object on a vector layer as one undo step, the Shape tool's
## release and the door's `shape` step alike, so the two cannot place an object
## differently.
##
## **The layer is the active one when it is a vector layer** and unlocked.
## Otherwise a vector layer is made above the active one in the same step, so a
## painter drawing a panel border over their paint never adds a layer by hand,
## and one Ctrl+Z takes the border and the layer it made together.
@tool
extends RefCounted

const VectorObject := preload("res://modules/sara-base-modules/vector/sa_vector_object.gd")
const VectorSettings := preload("res://modules/sara-base-modules/vector/tools/sa_vector_settings.gd")

## The step's name, after the kind of object it placed.
const RECT_TITLE := "Rectangle"
const ELLIPSE_TITLE := "Ellipse"


## Places *object* on *document*'s active vector layer, or on one made above
## the active layer through *context*, gives it an id no object of the document has,
## and answers the layer, or null when no vector layer could be had. With
## *own_layer* the object always gets a layer made for it.
static func place(document: SaDocument, context: SaContext, object: VectorObject, own_layer: bool = false) -> SaLayer:
    if document == null or object == null:
        return null
    object.id = VectorSettings.VectorRecipe.new_id(object.kind, VectorSettings.VectorRecipe.ids_in(document))
    if object.name.is_empty():
        object.name = _name_of(object)
    var title := TranslationServer.translate(ELLIPSE_TITLE if object.kind == VectorObject.Kind.ELLIPSE else RECT_TITLE)
    var holder: Array[SaLayer] = [null if own_layer else target(document)]
    document.history.as_one(title, _placed.bind(document, context, object, title, holder))
    return holder[0] if holder[0] != null and VectorSettings.recipe_of(holder[0]) != null else null


## The active layer when a new object can go on it, or null when one has to be made.
static func target(document: SaDocument) -> SaLayer:
    var layer := document.active_layer if document != null else null
    if layer == null or layer.is_locked or VectorSettings.recipe_of(layer) == null:
        return null
    return layer


static func _placed(
    document: SaDocument, context: SaContext, object: VectorObject, title: String, holder: Array[SaLayer]
) -> void:
    if holder[0] == null:
        if context == null or not context.layer_types.has(VectorSettings.TYPE):
            return
        holder[0] = context.create_layer(VectorSettings.TYPE, document)
    SaDrawnLayer.edit(holder[0], title, func(recipe: SaDrawnRecipe) -> void: recipe.call("add", object))


## A name the objects list shows, the kind and the number its id ends in.
static func _name_of(object: VectorObject) -> String:
    var number := object.id.get_slice("-", 1)
    var noun := TranslationServer.translate(ELLIPSE_TITLE if object.kind == VectorObject.Kind.ELLIPSE else RECT_TITLE)
    return "%s %s" % [noun, number]
