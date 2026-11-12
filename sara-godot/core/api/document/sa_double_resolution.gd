## A document's Double Resolution switch: while it is on, every paint layer
## made in the document is made at twice its density, as New Layer at Double
## Resolution makes one.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The painter-chosen half of adaptive resolution, made a habit
## rather than a menu row. The switch belongs to the painting and not to the
## app, so two documents open side by side each keep their own, and the top
## bar's toggle shows the one in front. `SaLayerOps.add` asks
## [method scale_for] whenever its caller left the scale to the document, which
## is Layer > New, the Layers docker's button and its menu, a module's
## `SaContext.create_layer` and the door's layer step.
##
## **Turning it on raises every paint layer that holds no chunk yet**, since
## there is nothing to resample, so a fresh document's first layer takes the
## detail at once. A layer with paint is never resampled here, and turning the
## switch off leaves every layer as it is. The turn is no step of the history,
## as the symmetry switches are not: it changes what the next layer is made at,
## and a raised layer that holds nothing looks the same at either density.
##
## **Kept in the `.sad` header under [constant HEADER_KEY]**, written only while
## it is on, so a file from before it, which has no key, opens with it off.
class_name SaDoubleResolution
extends RefCounted

## Announced whenever the switch moves, so a toggle that shows it can follow.
signal changed(on: bool)

## The `.sad` header's key, a bool.
const HEADER_KEY := "double_resolution"

## The density a paint layer is made at while the switch is on, the one
## `layer_new_double` asks for.
const SCALE := 2.0

## Whether new paint layers are made at [constant SCALE]. Written by
## [method turn] and [method read_header] only.
var on := false


## The density a layer like *layer* is made at now: [constant SCALE] for a
## paint layer while the switch is on, and 1.0 otherwise. A group, a generated
## ground, an adjustment, an effect and a scene layer store no paint of their
## own, so they keep 1.0 whatever the switch says.
func scale_for(layer: SaLayer) -> float:
    return SCALE if on and paints(layer) else 1.0


## Moves the switch to *wanted* for *document*. Turning it on raises each paint
## layer of *document* that holds no chunk yet to [constant SCALE]. Answers
## the layers it raised, empty when the switch already stood there.
func turn(document: SaDocument, wanted: bool) -> Array[SaLayer]:
    var raised: Array[SaLayer] = []
    if wanted == on:
        return raised
    on = wanted
    if document != null:
        if on:
            for child in document.get_children():
                var layer := child as SaLayer
                if layer != null and paints(layer) and layer.chunks.is_empty() and layer.resolution_scale < SCALE:
                    layer.resolution_scale = SCALE
                    raised.append(layer)
        document.modified = true
    changed.emit(on)
    return raised


## The switch as the `.sad` header holds it under [constant HEADER_KEY].
func to_header() -> bool:
    return on


## Takes what [method to_header] wrote. A header without the key, which is
## every file written before it, and a value of the wrong type read as off.
func read_header(raw: Variant) -> void:
    var wanted: bool = raw if raw is bool else false
    if wanted != on:
        on = wanted
        changed.emit(on)


## Whether *layer* holds paint of its own, the kind of layer the switch makes
## at [constant SCALE]. A frame layer holds chunks like paint but is no paint
## layer: a frame arrives at the document's size, so its layer stays at the
## document's density, and at twice it every frame would land nowhere. A
## drawn layer stays there too, since its chunks are a cache of its recipe.
static func paints(layer: SaLayer) -> bool:
    return (
        layer != null
        and not layer.is_group
        and not layer.is_generated()
        and not layer.is_adjustment()
        and not layer.is_effect()
        and not layer.is_scene()
        and not layer.is_drawn()
        and not SaFrameLayer.holds(layer)
    )
