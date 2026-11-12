## The line an effect layer's first record is drawn about, held on the canvas
## so a painter can drag it.
##
## The mirror layer has a line the painter places on the canvas the way the
## symmetry axes are placed. This is that
## line's geometry, for any filter that answers the two methods of the guide
## protocol, so neither `render` nor `ui` names the Mirror. `guide_line(values,
## canvas)` answers `[point, angle]`, the point in document pixels and the angle
## in radians, and `guide_values(values, canvas, point, angle)` answers the
## record's values for a line at that point and angle, the record's own units.
##
## The line has two handles, either side of its point and one arm from it, a
## fixed fraction of the canvas. A drag of a handle turns the line about the
## other, which stands where it was, so the line keeps its arm and nothing
## jumps when the pointer lets go. A drag on the line moves its point by the
## pointer's travel and keeps its angle. Both write through the record while
## the pointer moves, so the canvas shows the reflection follow, and the
## release is one `Edit Filter` step whose undo puts back what the press found.
class_name SaEffectGuide
extends RefCounted

## What a press took: one of the two handles, the line between them, or nothing.
const HIT_NONE: int = -1
const HIT_LINE: int = 2
## The method names of the protocol.
const LINE_METHOD := &"guide_line"
const VALUES_METHOD := &"guide_values"
## A handle's distance from the line's point, as a fraction of the canvas's
## shorter side.
const ARM_FRACTION: float = 0.15
## Holding Shift turns the line in steps of this many degrees.
const SNAP_DEGREES: float = 15.0

## The record the line is, the first of the layer's.
var record: SaAttachedFilter = null

var _document: SaDocument = null
var _filter: SaFilter = null
var _grip: int = HIT_NONE
var _before: Dictionary = {}
var _press: Vector2 = Vector2.ZERO
var _start: Vector2 = Vector2.ZERO
var _pivot: Vector2 = Vector2.ZERO


func _init(document: SaDocument = null, effect_record: SaAttachedFilter = null, filter: SaFilter = null) -> void:
    _document = document
    record = effect_record
    _filter = filter


## The line of the document's active layer, or null when that is not an effect
## layer whose first record's filter answers the protocol in *registry*.
static func of(document: SaDocument, registry: SaFilterRegistry) -> SaEffectGuide:
    if document == null or registry == null:
        return null
    var layer := document.active_layer
    if layer == null or not is_instance_valid(layer) or not layer.is_effect() or layer.filters.is_empty():
        return null
    var first := layer.filters[0]
    var filter := registry.get_filter(first.key) if first != null else null
    if filter == null or not filter.has_method(LINE_METHOD) or not filter.has_method(VALUES_METHOD):
        return null
    return SaEffectGuide.new(document, first, filter)


## The line's point in document pixels.
func point() -> Vector2:
    var line := _line(record.parameters)
    return line[0]


## The line's angle in radians, clockwise on the canvas.
func angle() -> float:
    var line := _line(record.parameters)
    return line[1]


## Where the two handles stand, in document pixels.
func handles() -> PackedVector2Array:
    var origin := point()
    var along := Vector2.from_angle(angle()) * arm()
    return PackedVector2Array([origin - along, origin + along])


## The handles' distance from the line's point, in document pixels.
func arm() -> float:
    var canvas := _document.canvas_size
    return float(mini(canvas.x, canvas.y)) * ARM_FRACTION


## The line as a segment from edge to edge of the canvas, or empty when it
## misses the canvas altogether.
func segment() -> PackedVector2Array:
    var origin := point()
    var along := Vector2.from_angle(angle())
    var size := Vector2(_document.canvas_size)
    var first := -INF
    var last := INF
    for axis in 2:
        if is_zero_approx(along[axis]):
            if origin[axis] < 0.0 or origin[axis] > size[axis]:
                return PackedVector2Array()
            continue
        var near: float = (0.0 - origin[axis]) / along[axis]
        var far: float = (size[axis] - origin[axis]) / along[axis]
        first = maxf(first, minf(near, far))
        last = minf(last, maxf(near, far))
    if first > last:
        return PackedVector2Array()
    return PackedVector2Array([origin + along * first, origin + along * last])


## What *at* is on: a handle within *handle_reach*, the nearer of two, then the
## line within *line_reach*, both in document pixels, or `HIT_NONE`.
func hit(at: Vector2, handle_reach: float, line_reach: float) -> int:
    var found := HIT_NONE
    var nearest := handle_reach
    var ends := handles()
    for index in ends.size():
        var distance := at.distance_to(ends[index])
        if distance <= nearest:
            nearest = distance
            found = index
    if found != HIT_NONE:
        return found
    var drawn := segment()
    if drawn.size() == 2 and at.distance_to(Geometry2D.get_closest_point_to_segment(at, drawn[0], drawn[1])) <= line_reach:
        return HIT_LINE
    return HIT_NONE


## Takes hold of *grip*, a result of [method hit], with the pointer at *at*,
## and keeps what the record holds, for the undo.
func press(grip: int, at: Vector2) -> void:
    _grip = grip
    _before = record.parameters.duplicate(true)
    _press = at
    _start = point()
    _pivot = handles()[1 - grip] if grip == 0 or grip == 1 else Vector2.ZERO


## Follows the pointer to *at*, writing the record so the canvas redraws under
## it. *snap* turns a handle in whole [constant SNAP_DEGREES].
func drag(at: Vector2, snap: bool) -> void:
    if _grip == HIT_NONE:
        return
    var size := Vector2(_document.canvas_size)
    var to := _start
    var turn := angle()
    if _grip == HIT_LINE:
        to = (_start + at - _press).clamp(Vector2.ZERO, size)
    else:
        # The handle at index 1 sits ahead of the point along the line, and
        # the one at index 0 behind it.
        var toward := 1.0 if _grip == 1 else -1.0
        var away := (at - _pivot) * toward
        if away.length() > 1.0:
            turn = away.angle()
            if snap:
                turn = deg_to_rad(snappedf(rad_to_deg(turn), SNAP_DEGREES))
        to = _pivot + toward * Vector2.from_angle(turn) * arm()
    var values: Dictionary = _filter.call(VALUES_METHOD, record.parameters, _document.canvas_size, to, turn)
    if _same_line(values, record.parameters):
        return
    record.replace_parameters(values)
    _document.modified = true
    _document.invalidate_all_allocated_chunks()
    _document.update_caches()


## Lets go of the line. One history step when it moved, whose undo puts back
## what the press found, and answers whether it made one.
func release() -> bool:
    var grip := _grip
    _grip = HIT_NONE
    if grip == HIT_NONE or _same_line(record.parameters, _before):
        return false
    return SaFilterOps.new(_document).set_parameters(record, record.parameters, UndoRedo.MERGE_DISABLE, _before)


## Whether a press has hold of the line and has not let go.
func is_held() -> bool:
    return _grip != HIT_NONE


## Whether *first* and *second* put the line in the same place, which two
## dictionaries may do while differing, one having written keys the other left
## to their defaults.
func _same_line(first: Dictionary, second: Dictionary) -> bool:
    var one := _line(first)
    var other := _line(second)
    var one_point: Vector2 = one[0]
    var other_point: Vector2 = other[0]
    var one_angle: float = one[1]
    var other_angle: float = other[1]
    return one_point.distance_to(other_point) < 1.0e-4 and absf(angle_difference(one_angle, other_angle)) < 1.0e-6


func _line(values: Dictionary) -> Array:
    var answer: Array = _filter.call(LINE_METHOD, values, _document.canvas_size)
    return answer
