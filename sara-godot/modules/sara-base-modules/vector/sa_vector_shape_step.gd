## The door's `shape` step: one object made on the active vector layer, or on a
## new one above the active layer when that is not a vector layer, from a kind
## and its numbers, the way the Shape tool's drag makes it.
##
## `{"shape": {"kind": "rect", "rect": [x, y, w, h], "radius": 12, "fill":
## [r, g, b, a], "stroke": [r, g, b, a], "stroke_width": 6}}`, or for an
## ellipse `"kind": "ellipse"` with `"centre": [x, y]` and `"radii": [rx, ry]`
## in place of `rect`. Numbers are document pixels. `fill` null or missing
## means no fill, and `stroke` missing or a width of 0 means no stroke. The
## answer is one line, `{"shape": {"id": "rect-1", "layer": "Vector 1"}}`, or
## its `error`.
##
## The harness reaches this through the `shape_step` role, so it names no
## file of this module.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends RefCounted

const VectorObject := preload("res://modules/sara-base-modules/vector/sa_vector_object.gd")
const VectorPlace := preload("res://modules/sara-base-modules/vector/sa_vector_place.gd")


static func capture(document: SaDocument, context: SaContext, spec: Dictionary) -> String:
    var made: Variant = made_from(spec)
    if made is String:
        return JSON.stringify({"shape": {"error": made}})
    if document == null:
        return JSON.stringify({"shape": {"error": "no document is open"}})
    var object: VectorObject = made
    var layer := VectorPlace.place(document, context, object)
    if layer == null:
        return JSON.stringify({"shape": {"error": "no vector layer could be made"}})
    return JSON.stringify({"shape": {"id": object.id, "layer": layer.shown_name()}})


## The object *spec* names, or the reason it names none as a String.
static func made_from(spec: Dictionary) -> Variant:
    var kind := String(spec.get("kind", "rect"))
    var box := Rect2()
    if kind == "rect":
        var numbers: Array = spec.get("rect", [])
        if numbers.size() != 4:
            return 'a rect takes "rect": [x, y, w, h]'
        box = Rect2(float(numbers[0]), float(numbers[1]), float(numbers[2]), float(numbers[3])).abs()
    elif kind == "ellipse":
        var centre: Array = spec.get("centre", [])
        var radii: Array = spec.get("radii", [])
        if centre.size() != 2 or radii.size() != 2:
            return 'an ellipse takes "centre": [x, y] and "radii": [rx, ry]'
        var half := Vector2(absf(float(radii[0])), absf(float(radii[1])))
        box = Rect2(Vector2(float(centre[0]), float(centre[1])) - half, half * 2.0)
    else:
        return "kind is rect or ellipse, not %s" % kind
    if box.size.x <= 0.0 or box.size.y <= 0.0:
        return "a shape needs a width and a height"
    var object := VectorObject.new(VectorObject.Kind.RECT if kind == "rect" else VectorObject.Kind.ELLIPSE, box)
    object.radius = maxf(float(spec.get("radius", 0.0)), 0.0)
    var fill: Variant = spec.get("fill")
    object.filled = fill is Array
    if object.filled:
        object.fill = _colour(fill)
    var stroke: Variant = spec.get("stroke")
    var width := float(spec.get("stroke_width", 6.0 if stroke is Array else 0.0))
    object.stroke_width = maxf(width, 0.0) if stroke is Array else 0.0
    if stroke is Array:
        object.stroke = _colour(stroke)
    if not object.filled and object.stroke_width <= 0.0:
        return "a shape with no fill and no stroke draws nothing"
    return object


static func _colour(values: Array) -> Color:
    var alpha := float(values[3]) if values.size() > 3 else 1.0
    return Color(float(values[0]), float(values[1]), float(values[2]), alpha)
