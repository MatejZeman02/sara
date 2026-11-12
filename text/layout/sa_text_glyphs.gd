## A glyph's outline as SVG path data in thousandths of an em, read from the
## font once and drawn from the text afterwards.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Path data rather than the font's points**, because the `.sad` keeps every
## glyph a text layer uses, so the layer draws as painted on a machine without
## the font, the way a PDF carries a subset of its fonts. SVG's own `M`, `L`,
## `Q`, `C` and `Z` say it in a form the vector layers and SVG out read too.
## TrueType's implied points between two quadratic controls are written out,
## so a reader needs no font format to draw it.
##
## The units are thousandths of an em with y down, so a glyph is the same text
## at every size and the layer scales it by its size over a thousand.
extends RefCounted

const Fonts = preload("res://modules/sara-base-modules/text/fonts/sa_text_fonts.gd")

## Units of the path data in an em.
const UNITS := 1000.0
## The point tags `font_get_glyph_contours` gives.
const ON_CURVE := 1
const CUBIC_CONTROL := 2

## Every outline read this process, by font and glyph, since a page of one
## font asks for each letter many times.
static var _read: Dictionary[String, String] = {}


## The outline of *glyph* in the font *font_rid*, as path data, empty for a
## glyph with no ink, a space.
static func outline_of(font_rid: RID, glyph: int) -> String:
    var key := "%d:%d" % [font_rid.get_id(), glyph]
    if _read.has(key):
        return _read[key]
    var server := TextServerManager.get_primary_interface()
    var contours: Dictionary = server.font_get_glyph_contours(font_rid, Fonts.READ_SIZE, glyph)
    var points: PackedVector3Array = contours.get("points", PackedVector3Array())
    var ends: PackedInt32Array = contours.get("contours", PackedInt32Array())
    var scale := UNITS / Fonts.READ_SIZE
    var parts := PackedStringArray()
    var start := 0
    for end in ends:
        parts.append(_contour(points.slice(start, end + 1), scale))
        start = end + 1
    var data := " ".join(parts).strip_edges()
    _read[key] = data
    return data


## One closed contour of tagged *points* as path data, each point times *scale*.
static func _contour(points: PackedVector3Array, scale: float) -> String:
    var count := points.size()
    if count < 2:
        return ""
    var first := -1
    for i in count:
        if int(points[i].z) == ON_CURVE:
            first = i
            break
    # A contour of quadratic controls alone starts at the point implied
    # between its first two.
    var begin: Vector2
    var order: Array[int] = []
    if first < 0:
        begin = (_at(points, 0) + _at(points, 1)) * 0.5 * scale
        for i in count:
            order.append((i + 1) % count)
    else:
        begin = _at(points, first) * scale
        for i in range(1, count + 1):
            order.append((first + i) % count)
    var out := PackedStringArray(["M%s" % _xy(begin)])
    var controls: Array[Vector3] = []
    for i in order:
        var tag := int(points[i].z)
        var p := _at(points, i) * scale
        if tag == ON_CURVE:
            out.append(_ended(controls, p))
            controls.clear()
        elif tag == CUBIC_CONTROL:
            controls.append(Vector3(p.x, p.y, tag))
        else:
            if not controls.is_empty() and int(controls[-1].z) != CUBIC_CONTROL:
                var mid := (Vector2(controls[-1].x, controls[-1].y) + p) * 0.5
                out.append("Q%s %s" % [_xy(Vector2(controls[-1].x, controls[-1].y)), _xy(mid)])
                controls.clear()
            controls.append(Vector3(p.x, p.y, tag))
    if first < 0 and not controls.is_empty():
        out.append(_ended(controls, begin))
    out.append("Z")
    return " ".join(out)


## The piece that ends at *p* after the *controls* before it: a line with
## none, a quadratic with one, a cubic with two.
static func _ended(controls: Array[Vector3], p: Vector2) -> String:
    match controls.size():
        0:
            return "L%s" % _xy(p)
        1:
            return "Q%s %s" % [_xy(Vector2(controls[0].x, controls[0].y)), _xy(p)]
        _:
            var a := Vector2(controls[0].x, controls[0].y)
            var b := Vector2(controls[1].x, controls[1].y)
            return "C%s %s %s" % [_xy(a), _xy(b), _xy(p)]


static func _at(points: PackedVector3Array, i: int) -> Vector2:
    return Vector2(points[i].x, points[i].y)


## A point as the path data writes it, three decimals of a unit, which is a
## millionth of an em.
static func _xy(p: Vector2) -> String:
    return "%s,%s" % [_number(p.x), _number(p.y)]


static func _number(value: float) -> String:
    var text := "%.3f" % value
    text = text.rstrip("0").rstrip(".")
    return "0" if text == "-0" or text.is_empty() else text


## Adds the outline *data* to *path*, scaled by *scale* document pixels a unit
## and placed with its origin at *origin*. Path data this class did not write
## is read as far as it holds `M`, `L`, `Q`, `C` and `Z` with absolute numbers.
static func add_to(path: SaVectorPath, data: String, origin: Vector2, scale: float) -> void:
    var numbers := PackedFloat64Array()
    var command := ""
    for token in _tokens(data):
        if token in ["M", "L", "Q", "C", "Z"]:
            _emit(path, command, numbers, origin, scale)
            command = token
            numbers.clear()
        else:
            numbers.append(token.to_float())
    _emit(path, command, numbers, origin, scale)


static func _emit(path: SaVectorPath, command: String, n: PackedFloat64Array, origin: Vector2, scale: float) -> void:
    var p := func(i: int) -> Vector2: return origin + Vector2(n[i], n[i + 1]) * scale
    match command:
        "M":
            if n.size() >= 2:
                path.move_to(p.call(0))
        "L":
            if n.size() >= 2:
                path.line_to(p.call(0))
        "Q":
            if n.size() >= 4:
                path.quad_to(p.call(0), p.call(2))
        "C":
            if n.size() >= 6:
                path.cubic_to(p.call(0), p.call(2), p.call(4))
        "Z":
            path.close()


## *data* cut into its commands and its numbers.
static func _tokens(data: String) -> PackedStringArray:
    var spaced := data
    for command: String in ["M", "L", "Q", "C", "Z"]:
        spaced = spaced.replace(command, " %s " % command)
    spaced = spaced.replace(",", " ")
    var out := PackedStringArray()
    for part in spaced.split(" ", false):
        out.append(part)
    return out


## The box round every point of *data*, in its own units, controls included,
## which hold the curve.
static func box_of(data: String) -> Rect2:
    var box := Rect2()
    var first := true
    var numbers := PackedFloat64Array()
    for token in _tokens(data):
        if token in ["M", "L", "Q", "C", "Z"]:
            continue
        numbers.append(token.to_float())
        if numbers.size() == 2:
            var p := Vector2(numbers[0], numbers[1])
            box = Rect2(p, Vector2.ZERO) if first else box.expand(p)
            first = false
            numbers.clear()
    return box
