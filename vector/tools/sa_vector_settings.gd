## What the Shape tool and the Object tool share: the shape a drag makes, its
## fill and stroke, and which objects are picked.
##
## One resource on both descriptors, so an object drawn with the Shape tool is
## still picked when the painter turns to the Object tool, and the objects list
## on the Tool Options docker is one row the two tools show alike.
##
## **The colours are the painter's pair, Krita's way**: the stroke takes the
## foreground and the fill the background, so black on white, the default pair,
## draws a comic panel's border and a balloon's paper without a colour picked.
@tool
extends Resource

const VectorObject := preload("res://modules/sara-base-modules/vector/sa_vector_object.gd")
const VectorRecipe := preload("res://modules/sara-base-modules/vector/sa_vector_recipe.gd")

## The layer type a vector layer is registered under.
const TYPE := &"vector"

## What a drag of the Shape tool makes, a `VectorObject.Kind`.
@export var kind: int = VectorObject.Kind.RECT
## A rectangle's corner radius in document pixels.
@export var corner_radius: float = 0.0
## Whether a new object is filled, in the background colour.
@export var fill_on: bool = true
## Whether a new object is stroked, in the foreground colour.
@export var stroke_on: bool = true
## A new object's stroke width in document pixels.
@export var stroke_width: float = 6.0
## Whether each new object is put on a vector layer of its own above the
## active layer. Off by default, so a page of panels is one layer.
@export var new_layer_each: bool = false

## The ids of the picked objects on the active layer.
var picked: PackedStringArray = PackedStringArray()
## The module's context, whose `create_layer` makes a vector layer when a press
## lands on a layer that is not one, handed in by the module at its registration.
## Held weakly, because the context holds the registries that hold the tools'
## descriptors that hold this, and a cycle of references is never freed.
var context: WeakRef = null


## *layer*'s recipe when it is a vector layer's, or null.
static func recipe_of(layer: SaLayer) -> VectorRecipe:
    if layer == null or not layer.is_drawn() or layer.layer_type != TYPE:
        return null
    return layer.recipe as VectorRecipe
