## The field of a layer a brush lays its paint into: `albedo`, or for a layer
## type that works its `albedo` out of other fields, the first colour field it
## does not, so a Colourise layer's strokes land in its scribbles and its
## resolve hook shows the flats.
##
## A layer type whose `albedo` is worked out of no colour field of its own, a
## simulated layer among them, keeps `albedo` as the brush's field, which is
## where every stroke landed before a type could name another. The walk that
## fills a layer, `SaChunkWalk`, already paints every colour field nobody
## works out, so it needs no door.
class_name SaPaintedField
extends RefCounted


## The id of the field *layer*'s strokes land in.
static func of(layer: SaLayer) -> StringName:
    if layer == null or not layer.has_derived:
        return SaFieldSpec.ALBEDO
    var albedo := SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
    if albedo == null or not albedo.is_derived():
        return SaFieldSpec.ALBEDO
    for spec in layer.schema:
        if spec != null and spec.is_color and not spec.is_derived():
            return spec.id
    return SaFieldSpec.ALBEDO
