## Vector layers: a layer of objects drawn on the GPU at their exact coverage,
## rectangles and ellipses, drawn as exact coverage in float.
##
## Everything comes in through the door a stranger's module uses (hard rule 6):
## the layer type, a drawn layer whose recipe is `sa_vector_recipe.gd`, the
## Shape tool that draws an object and the Object tool that picks, moves and
## resizes one, their rows on the Tool Options docker with the objects list
## among them, and the role the harness's `shape` step reaches the module by,
## so the harness names no file of this folder.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule

const VectorRecipe := preload("res://modules/sara-base-modules/vector/sa_vector_recipe.gd")
const VectorObject := preload("res://modules/sara-base-modules/vector/sa_vector_object.gd")
const VectorSettings := preload("res://modules/sara-base-modules/vector/tools/sa_vector_settings.gd")
const StateVectorShape := preload("res://modules/sara-base-modules/vector/tools/state_vector_shape.gd")
const StateVectorObject := preload("res://modules/sara-base-modules/vector/tools/state_vector_object.gd")
const ObjectsList := preload("res://modules/sara-base-modules/vector/ui/sa_vector_objects_list.gd")
const ShapeStep := preload("res://modules/sara-base-modules/vector/sa_vector_shape_step.gd")

const SHAPE_ICON := "res://modules/sara-base-modules/vector/icons/vector_shape.svg"
const OBJECT_ICON := "res://modules/sara-base-modules/vector/icons/vector_object.svg"


func get_id() -> StringName:
    return &"vector"


func get_name() -> String:
    return "Vector Layers"


func register(ctx: SaContext) -> void:
    var layer := SaLayerTypeDescriptor.drawn_layer(VectorSettings.TYPE, VectorRecipe)
    layer.display_name = "Vector Layer"
    layer.experimental = true
    layer.hint = "Rectangles and ellipses kept as shapes, sharp, movable and resizable, drawn with the Shape tool."
    ctx.register_layer_type(layer)

    var settings := VectorSettings.new()
    settings.context = weakref(ctx)

    var shape := SaToolDescriptor.create(&"vector_shape", StateVectorShape)
    shape.display_name = "Shape"
    shape.experimental = true
    shape.icon_name = SHAPE_ICON
    shape.category = &"vector"
    shape.cursor_shape = Control.CURSOR_CROSS
    shape.reads_keys = [KEY_SHIFT, KEY_ALT]
    shape.shared_settings = settings
    shape.options = shape_options()
    ctx.register_tool(shape)

    var object := SaToolDescriptor.create(&"vector_object", StateVectorObject)
    object.display_name = "Object"
    object.experimental = true
    object.icon_name = OBJECT_ICON
    object.category = &"vector"
    object.cursor_shape = Control.CURSOR_ARROW
    object.reads_keys = [KEY_SHIFT]
    object.shared_settings = settings
    object.options = [objects_option()]
    ctx.register_tool(object)

    ctx.register_role(&"shape_step", ShapeStep)


## The Shape tool's rows: the kind, the corner radius, whether a new object is
## filled and stroked and how wide, whether it gets a layer of its own, and the
## objects list.
static func shape_options() -> Array[SaOptionSpec]:
    var kinds := SaOptionSpec.make_enum(
        &"vector_kind",
        "Shape",
        [VectorObject.Kind.RECT, VectorObject.Kind.ELLIPSE],
        ["Rectangle", "Ellipse"],
        {"property": ^"kind", "tooltip": "The shape a drag draws."}
    )
    var corner := (
        SaOptionSpec
        . make_float(
            &"vector_corner_radius",
            "Corner Radius",
            0.0,
            2000.0,
            1.0,
            {
                "property": ^"corner_radius",
                "soft_max": 200.0,
                "decimals": 0,
                "suffix": " px",
                "tooltip": "Rounds a new rectangle's corners by this many pixels.",
                "enabled_when": &"vector_kind",
                "enabled_when_values": [VectorObject.Kind.RECT],
            }
        )
    )
    var fill := SaOptionSpec.make(
        &"vector_fill",
        "Fill",
        SaOptionSpec.Kind.BOOL,
        {"property": ^"fill_on", "tooltip": "Fills a new shape with the background colour."}
    )
    var stroke := SaOptionSpec.make(
        &"vector_stroke",
        "Stroke",
        SaOptionSpec.Kind.BOOL,
        {"property": ^"stroke_on", "tooltip": "Strokes a new shape's outline in the foreground colour."}
    )
    var width := (
        SaOptionSpec
        . make_float(
            &"vector_stroke_width",
            "Stroke Width",
            0.5,
            500.0,
            0.5,
            {
                "property": ^"stroke_width",
                "soft_max": 60.0,
                "decimals": 1,
                "trim_trailing_zeros": true,
                "suffix": " px",
                "tooltip": "How wide a new shape's stroke is, centred on its outline.",
                "enabled_when": &"vector_stroke",
                "enabled_when_values": [true],
            }
        )
    )
    var own_layer := (
        SaOptionSpec
        . make(
            &"vector_new_layer",
            "New Layer for Each Shape",
            SaOptionSpec.Kind.BOOL,
            {
                "property": ^"new_layer_each",
                "bar": false,
                "tooltip": "Puts each new shape on a vector layer of its own, Photoshop's way, rather than on the active one.",
            }
        )
    )
    return [kinds, corner, fill, stroke, width, own_layer, objects_option()]


## The objects list, one row both tools declare, so it is one control on the
## docker whichever of the two is active.
static func objects_option() -> SaOptionSpec:
    return (
        SaOptionSpec
        . make_custom(
            &"vector_objects",
            "Objects",
            ObjectsList.build,
            ObjectsList.bind,
            {
                "property": ^"objects_listing",
                "on_tool": true,
                "bar": false,
                "tooltip": "The active vector layer's objects, top first.",
            }
        )
    )
