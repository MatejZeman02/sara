## The path a round tip holds back behind the pen: every point the stretch
## took since the end the body laid, the pivots its turns are drawn round, and
## the polyline the body paints from them, which the stretch sends.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Held back a half width.** An update paints the body up to the newest point
## it took at least a tip's radius of path behind the newest point of all, so a
## half width or up to one step more, and holds the rest back, which the front
## shows under the pen (`noise_front.gd`). The body ends on a point the pen
## took, never between two, so a straight stroke is drawn through the same
## points as an unheld one, only an update later. So when the path turns, the
## texels within a half width before the joint are still bare, and the update
## that paints them knows where the path went. Without the hold, the update that
## ends on the joint paints the first leg up to it while the turn is still to
## come, the wash only ever raises a texel, and the second leg's streaks cross
## the first leg's on the inside of the turn. The kernel needs nothing new for
## it: the line ends where the hold starts, and its open end leaves the texels
## in front of that end to the next update, as it leaves the newest point's.
##
## **A turn is drawn round a pivot.** Points the path turns at the same way one
## after another, each by more than twice what a wobble turns a step by, are
## one turn, and the body paints it as an arc, the fillet between the two legs
## where they meet. A texel on the inside takes its across from its distance to
## the arc's centre, the pivot, so each streak keeps its distance from the
## pivot round the turn rather than meeting the other leg's at a mitre. The arc
## leaves the first leg a tangent's length T before the joint and joins the
## second T after it, T the tip's radius times the tangent of half the turn and
## never more than the radius. Up to 90 degrees the arc's own radius is the
## tip's, so the pivot is the inside corner, the point a half width in from both
## legs. Past 90 degrees T stays a half width, so the swing starts inside the
## band the update held back, and the arc tightens: the pivot moves along the
## inside bisector from the inside corner, 1.41 half widths from the joint at 90
## degrees, to 1.15 at 120, 1.02 at 160 and one half width at 180.
##
## **The outside reaches the turning point.** The arc's outer edge alone stops
## short of the joint by the arc's distance from it, more the sharper the turn
## and nothing at the mitre a turn past [constant MOST_TURN] keeps, so a
## hairpin's point would go blunt and the shape would jump there. A round tip
## paints a half width round every point the pen passed, so the arc carries a
## spur at its middle, out to the point the pen turned at and back, and the
## turn's outside is the round tip's outline round that point at every angle.
## The spur lies outside the arc, so a texel on the inside still finds its
## nearest point on the arc and keeps its distance from the pivot. A texel near
## the spur takes its across from its distance to the spur, so the streaks on
## the outside run out along it to the turning point and round its cap. Points
## are taken a step apart, so the point the pen turned at may lie up to a step
## past the one taken there, and the spur reaches where the legs a point further
## out either side meet when that lies out past the joint within a step of it.
##
## **A pen that goes back along its own line is not a turn.** A run of turns
## whose second leg leaves at more than [constant REVERSAL] to the way the
## first leg came in is the pen scrubbing to and fro, and an arc there would
## draw each streak round a half circle, a row of loops where a scrub should
## read as paint dragged back and forth. Such a run keeps its joint and a spur
## out to where the pen turned, as an arc's does, and every point from the
## turning point on counts its across on the other side of the path, the
## point's [constant NoiseStretchScript.SIDE]. Across is a texel's signed
## distance from the path, which changes sign with the heading, so without it a
## streak on the first leg's left would lie on the second leg's right and the
## two legs' streaks cross at the turn. With it a streak keeps its line out and
## back. The angle is read over the legs and not at the point where the pen
## turned, since a point is taken a step from the last and the turn read there
## is off by up to a few degrees.
##
## **What a point of the arc carries.** Each point of the arc takes what the
## path had at its place along the path, so along runs from the first leg's at
## the arc's start to the second leg's at its end, but where it lies and its
## heading, which is the arc's own. A turn whose arc would start before the end
## the body already laid or before the arc before it ends, or would end past
## the next turn or the newest point, keeps its joint, the mitre its two legs
## make where they meet.
extends RefCounted

const NoiseStretchScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_stretch.gd")

## The most a run of points may turn and still be drawn round one pivot, short
## of the half turn whose two legs never meet.
const MOST_TURN: float = PI * 17.0 / 18.0
## The least angle between the leg a run of turns leaves on and the leg it came
## in on, both read over the legs, that is a reversal rather than a turn: past
## the corner suite's hairpin of 160 degrees, which keeps its arc, and short of
## the scrub of 165 degrees, a pen coming back 15 degrees off its own line.
const REVERSAL: float = PI * 162.0 / 180.0
## How far a chord of an arc may stray from the arc, in pixels, and the widest
## a chord may turn.
const SAGITTA: float = 0.1
const MOST_CHORD: float = PI / 12.0
## Two places on the path closer than this, in pixels, are one.
const SAME: float = 0.001

## What the last [method plan] found: the polyline the body paints, the box
## its tips reach, what of its first segment was painted before, and whether
## it paints anything at all. Then the front, the polyline from the end the
## body laid to the newest point, and its box.
var line := PackedFloat32Array()
var reach: Rect2 = Rect2()
var first_laid: float = NoiseStretchScript.FIRST_NOTHING
var paints: bool = false
var front := PackedFloat32Array()
var front_reach: Rect2 = Rect2()
## Whether the body has laid any of the stroke.
var has_laid: bool = false

## The points kept, oldest first, a [constant NoiseStretchScript.FLOATS] each,
## the box each one's tip reaches, and the length of path up to each.
var _points := PackedFloat32Array()
var _boxes: Array[Rect2] = []
var _places := PackedFloat64Array()
## The pivots decided on, oldest first, the first point whose turn is still to
## be decided, and the place on the path a pivot may start from, past the last
## turn decided.
var _pivots: Array[Pivot] = []
var _next: int = 1
var _free: float = 0.0
## The side the path's across is counted on at its first point kept, and the
## places of the reversals decided since, from each of which on it is the
## other side.
var _side: float = 1.0
var _reversals := PackedFloat64Array()
var _tips := PackedVector2Array()
## The last segment the body laid, its two points and their boxes, and the
## place on the path the newer lies at.
var _laid := PackedFloat32Array()
var _laid_boxes: Array[Rect2] = []
var _laid_at: float = 0.0
## What [method plan] read and decided, which [method commit] keeps: every
## point, with the update's own, the pivots, the next point to decide, the
## place a pivot may start from, and the place the body paints to.
var _all := PackedFloat32Array()
var _all_boxes: Array[Rect2] = []
var _all_places := PackedFloat64Array()
var _all_pivots: Array[Pivot] = []
var _all_next: int = 1
var _all_free: float = 0.0
var _all_reversals := PackedFloat64Array()
var _all_tips := PackedVector2Array()
var _hold: float = 0.0
## The box of each point of [member line].
var _line_boxes: Array[Rect2] = []
## The polyline [method plan] built, from the end the body laid to the newest
## point, with each point's place on the path and box.
var _vertices := PackedFloat32Array()
var _vertex_places := PackedFloat64Array()
var _vertex_boxes: Array[Rect2] = []


## One turn drawn as an arc: where on the path it starts and ends, its centre,
## the pivot, its radius, the way from the centre to its first point, the
## path's heading into it, how far it turns, and the chords it is drawn in.
class Pivot:
    extends RefCounted

    var start: float
    var end: float
    var centre: Vector2
    var radius: float
    var out: Vector2
    var heading: Vector2
    var turn: float
    var chords: int
    var joint: Vector2

    func _init(
        from: float,
        to: float,
        pivot: Vector2,
        bend: float,
        first: Vector2,
        into: Vector2,
        by: float,
        pieces: int,
        corner: Vector2
    ) -> void:
        start = from
        end = to
        centre = pivot
        radius = bend
        out = first
        heading = into
        turn = by
        chords = pieces
        joint = corner

    ## The point *share* of the way round the arc.
    func at(share: float) -> Vector2:
        return centre + out.rotated(turn * share)

    ## The arc's heading *share* of the way round it.
    func tangent(share: float) -> Vector2:
        return heading.rotated(turn * share)


## Forgets the stroke before, at a press and a lift.
func clear() -> void:
    line = PackedFloat32Array()
    reach = Rect2()
    first_laid = NoiseStretchScript.FIRST_NOTHING
    paints = false
    front = PackedFloat32Array()
    front_reach = Rect2()
    has_laid = false
    _points = PackedFloat32Array()
    _boxes = []
    _places = PackedFloat64Array()
    _pivots = []
    _next = 1
    _free = 0.0
    _side = 1.0
    _reversals = PackedFloat64Array()
    _tips = PackedVector2Array()
    _laid = PackedFloat32Array()
    _laid_boxes = []
    _laid_at = 0.0


## Whether the path holds any point not yet handed on.
func is_empty() -> bool:
    return _points.is_empty()


## Starts again from a tip that carried a trail, whose update laid the stroke
## up to its newest point: *pair*, the newest two points it sent, with
## *boxes*, the newer lying *at* along the path.
func restart(pair: PackedFloat32Array, boxes: Array[Rect2], at: float) -> void:
    clear()
    var newest := pair.size() - NoiseStretchScript.FLOATS
    _points = pair.slice(newest)
    _boxes = [boxes[-1]]
    _places = PackedFloat64Array([at])
    _next = 1
    _free = at
    _side = pair[newest + NoiseStretchScript.SIDE]
    _laid_at = at
    if pair.size() >= 2 * NoiseStretchScript.FLOATS:
        _laid = pair.duplicate()
        _laid_boxes = boxes.duplicate()
        has_laid = true


## What a tip that carries a trail takes over: the last segment the body laid
## and every point kept past it.
func unlaid() -> PackedFloat32Array:
    var out := _laid.duplicate()
    for index in _places.size():
        if _unlaid(index):
            out.append_array(_point(_points, index))
    return out


## The box of each point [method unlaid] answers.
func unlaid_boxes() -> Array[Rect2]:
    var out := _laid_boxes.duplicate()
    for index in _places.size():
        if _unlaid(index):
            out.append(_boxes[index])
    return out


## Whether point *index* kept lies past the end the body laid.
func _unlaid(index: int) -> bool:
    return not has_laid or _places[index] > _laid_at + SAME


## Writes *values* onto the newest point kept, everything the dynamics
## answered but where it lies, its along and its heading, and widens its box by
## *box*, when the pen pressed harder there than the point holds.
func press_harder(values: PackedFloat32Array, box: Rect2) -> void:
    if _points.is_empty():
        return
    var newest := _points.size() - NoiseStretchScript.FLOATS
    if values[NoiseStretchScript.PRESSURE] <= _points[newest + NoiseStretchScript.PRESSURE]:
        return
    for slot in range(NoiseStretchScript.PRESSURE, NoiseStretchScript.DIRECTION):
        _points[newest + slot] = values[slot]
    _boxes[-1] = _boxes[-1].merge(box)


## Works out what the update paints with *added*, the points taken since the
## last [method commit], *boxes* and *places* theirs, and the stroke *closing*
## or not, into [member line] and the members after it. Nothing is kept until
## [method commit].
func plan(added: PackedFloat32Array, boxes: Array[Rect2], places: PackedFloat64Array, closing: bool) -> void:
    _all = _points.duplicate()
    _all.append_array(added)
    _all_boxes = _boxes.duplicate()
    _all_boxes.append_array(boxes)
    _all_places = _places.duplicate()
    _all_places.append_array(places)
    line = PackedFloat32Array()
    reach = Rect2()
    _line_boxes = []
    front = PackedFloat32Array()
    front_reach = Rect2()
    paints = false
    first_laid = NoiseStretchScript.FIRST_SEGMENT if has_laid else NoiseStretchScript.FIRST_NOTHING
    if _all_places.is_empty():
        return
    var last := _all_places.size() - 1
    var base := _laid_at if has_laid else _all_places[0]
    var undecided := _decide(closing, base)
    _hold = _all_places[last]
    if not closing:
        _hold = minf(_all_places[last] - _radius(_all, last), undecided)
    _hold = maxf(_hold, base)
    _polyline(base)
    _lay_line(closing, base)
    if has_laid:
        front = _point(_laid, 0)
    front.append_array(_vertices)
    front_reach = _vertex_boxes[0]
    for box: Rect2 in _vertex_boxes:
        front_reach = front_reach.merge(box)


## Keeps what the last [method plan] decided and the end it laid, once the
## stretch has sent its line.
func commit() -> void:
    _points = _all
    _boxes = _all_boxes
    _places = _all_places
    _pivots = _all_pivots
    _next = _all_next
    _free = _all_free
    _reversals = _all_reversals
    _tips = _all_tips
    @warning_ignore("integer_division")
    var count := line.size() / NoiseStretchScript.FLOATS
    if count >= 2:
        _laid = line.slice((count - 2) * NoiseStretchScript.FLOATS)
        _laid_boxes = _line_boxes.slice(count - 2)
        _laid_at = _hold
        has_laid = true
    _forget()


## Drops the points and pivots no update reads again: every point before the
## newest at or behind the laid end and before the one ahead of the first whose
## turn is still to be decided, but one.
func _forget() -> void:
    var keep := maxi(0, mini(_next - 1, _below(_places, _laid_at)) - 1)
    if keep > 0:
        _points = _points.slice(keep * NoiseStretchScript.FLOATS)
        _boxes = _boxes.slice(keep)
        _places = _places.slice(keep)
        _next -= keep
    var live: Array[Pivot] = []
    for pivot: Pivot in _pivots:
        if pivot.end > _laid_at:
            live.append(pivot)
    _pivots = live


## Decides the turns of the points from the first still to be decided on,
## each run of them drawn round a pivot or left as it is, the stroke *closing*
## or not, with *base* the place the body laid to. Answers the place from which
## the path is still undecided, where a run of turns may go on with the next
## point, or infinity.
func _decide(closing: bool, base: float) -> float:
    _all_pivots = _pivots.duplicate()
    _all_free = _free
    _all_reversals = _reversals.duplicate()
    _all_tips = _tips.duplicate()
    var last := _all_places.size() - 1
    var at := maxi(_next, 1)
    while at < last:
        var turn := _turn(at)
        if absf(turn) < _least_turn(at):
            at += 1
            continue
        var first := at
        var newest := at
        var total := turn
        var next := at + 1
        var closed := closing
        var bound := -1
        while next < last:
            var more := _turn(next)
            if absf(more) >= _least_turn(next):
                if not _joins(first, newest, next, total, more):
                    closed = true
                    bound = next
                    break
                total += more
                newest = next
            elif _past(first, newest, total, next):
                closed = true
                bound = next
                break
            next += 1
        if not closed and _past(first, newest, total, last):
            closed = true
            bound = last
        if not closed:
            _all_next = first
            return _all_places[first] - _radius(_all, first)
        var pivot: Pivot = null
        if _reverses(first, newest, bound):
            _all_reversals.append(_all_places[first])
            var joint := _at(_all, first)
            var into := (joint - _at(_all, first - 1)).normalized()
            var away := (_at(_all, newest + 1) - _at(_all, newest)).normalized()
            _all_tips.append(_turning_point(first, newest, joint, into, away))
        else:
            pivot = _pivot(first, newest, base, bound)
        if pivot != null:
            _all_pivots.append(pivot)
            _all_free = pivot.end
        else:
            _all_free = maxf(_all_free, _all_places[newest])
        at = next
    _all_next = at
    return INF


## Whether point *next* lies so far past *newest*, the newest point of the
## run of turns from *first* turning by *total*, that no point from it on can
## join the run, and the run's arc ends before it.
func _past(first: int, newest: int, total: float, next: int) -> bool:
    var gap := _all_places[next] - _all_places[newest]
    return gap >= _tangent(total, _radius(_all, first)) + _radius(_all, next)


## Whether point *next*, turning by *more*, carries on the run of turns from
## *first* to *newest*, turning by *total*: it turns the same way by more than
## a wobble does, it lies within the two turns' tangents of the run's newest
## point, and the run's arc with it still covers every point of the run. A run
## turned past [constant MOST_TURN] draws no arc, since it is a pen going back
## along its line, so it takes a point that turns it up to as far past the half
## turn, and the reversal is read over the whole run rather than its first
## part drawn round a pivot.
func _joins(first: int, newest: int, next: int, total: float, more: float) -> bool:
    if absf(more) < _least_turn(next) or signf(more) != signf(total):
        return false
    var radius := _radius(_all, first)
    var gap := _all_places[next] - _all_places[newest]
    if gap >= _tangent(total, radius) + _tangent(more, _radius(_all, next)):
        return false
    if absf(total + more) > MOST_TURN:
        return absf(total + more) <= 2.0 * PI - MOST_TURN
    var corner := _corner(first, next)
    if corner == Vector2.INF:
        return false
    var tangent := _tangent(total + more, radius)
    return corner.x <= tangent and corner.y <= tangent


## Whether the run of turns from point *first* to point *newest*, with no
## point but *bound* turning after it, the newest point at -1, is the pen going
## back along its line: the leg after it leaves within [constant REVERSAL] of
## the heading the first point came in on. That heading is the one the stretch
## gave the point, over a tip's radius of the path behind it, and the leg after
## is read from the first point past the run to the farthest within a tip's
## radius of it, or from the run's newest point where no second one is kept.
func _reverses(first: int, newest: int, bound: int) -> bool:
    var at := first * NoiseStretchScript.FLOATS + NoiseStretchScript.DIRECTION
    var into := Vector2(_all[at], _all[at + 1])
    if into.length_squared() <= 0.0:
        into = _at(_all, first) - _at(_all, first - 1)
    var after := newest + 1
    var furthest := _all_places[after] + _radius(_all, after)
    var far := after
    var end := _all_places.size() - 1 if bound < 0 else bound
    while far < end and _all_places[far + 1] <= furthest:
        far += 1
    var away := _at(_all, far) - _at(_all, after)
    if far == after:
        away = _at(_all, after) - _at(_all, newest)
    if into.length_squared() <= 0.0 or away.length_squared() <= 0.0:
        return false
    return absf(into.angle_to(away)) > REVERSAL


## The pivot the run of turns from point *first* to point *newest* is drawn
## round, or null where it cannot be: an arc that would start before *base* or
## the arc before it, or end past point *bound*, the newest point at -1.
func _pivot(first: int, newest: int, base: float, bound: int) -> Pivot:
    var into := _at(_all, first) - _at(_all, first - 1)
    var away := _at(_all, newest + 1) - _at(_all, newest)
    var turn := into.angle_to(away)
    var corner := _corner(first, newest)
    if corner == Vector2.INF or absf(turn) > MOST_TURN:
        return null
    var radius := _radius(_all, first)
    var tangent := _tangent(turn, radius)
    if corner.x > tangent or corner.y > tangent:
        return null
    var start := _all_places[first] - (tangent - corner.x)
    var end := _all_places[newest] + (tangent - corner.y)
    if start < maxf(_all_free, base) or start < _all_places[0]:
        return null
    if end > _all_places[_all_places.size() - 1 if bound < 0 else bound]:
        return null
    var heading := into.normalized()
    var joint := _at(_all, first) + corner.x * heading
    var bend := tangent / tan(0.5 * absf(turn))
    var from := joint - tangent * heading
    var centre := from + bend * heading.rotated(signf(turn) * 0.5 * PI)
    var tip := _turning_point(first, newest, joint, heading, away.normalized())
    var chord := MOST_CHORD
    if bend > 0.5 * SAGITTA:
        chord = minf(chord, 2.0 * acos(1.0 - SAGITTA / bend))
    # An even count, so the arc's middle, where the spur leaves it, is a point of it.
    var chords := 2 * maxi(1, ceili(0.5 * absf(turn) / chord))
    return Pivot.new(start, end, centre, bend, from - centre, heading, turn, chords, tip)


## Where the pen turned in the run of turns from point *first* to point
## *newest*, whose legs meet at *joint*, coming in along *into* and leaving
## along *away*. A point is taken a step on from the last, so the pen's own
## turning point can lie up to a step past the one taken there, where the legs
## a point further out either side meet. That is where it turned when it lies
## out past *joint*, within a step of it, and *joint* otherwise.
func _turning_point(first: int, newest: int, joint: Vector2, into: Vector2, away: Vector2) -> Vector2:
    if first < 2 or newest + 2 >= _all_places.size():
        return joint
    var before := _at(_all, first - 1)
    var coming := (before - _at(_all, first - 2)).normalized()
    var after := _at(_all, newest + 1)
    var going := (_at(_all, newest + 2) - after).normalized()
    var across := coming.cross(going)
    if coming == Vector2.ZERO or going == Vector2.ZERO or absf(across) < 1e-6:
        return joint
    var on := (after - before).cross(going) / across
    var met := before + on * coming
    if on < -SAME or (after - met).dot(going) < -SAME:
        return joint
    var outward := (into - away).normalized()
    var step := NoiseStretchScript.step_for(_point(_all, first))
    if (met - joint).dot(outward) <= 0.0 or met.distance_to(joint) > step:
        return joint
    return met


## Where the legs into point *first* and out of point *newest* meet: in x how
## far the joint lies on from point *first*, and in y how far point *newest*
## lies on from the joint. Vector2.INF where either leg has no length, the legs
## never meet, or a point lies on the wrong side of the joint.
func _corner(first: int, newest: int) -> Vector2:
    var into := _at(_all, first) - _at(_all, first - 1)
    var away := _at(_all, newest + 1) - _at(_all, newest)
    if into.length_squared() <= 0.0 or away.length_squared() <= 0.0:
        return Vector2.INF
    into = into.normalized()
    away = away.normalized()
    var across := into.cross(away)
    if absf(across) < 1e-6:
        return Vector2.INF
    var on := (_at(_all, newest) - _at(_all, first)).cross(away) / across
    var joint := _at(_all, first) + on * into
    var past := (_at(_all, newest) - joint).dot(away)
    if on < -SAME or past < -SAME:
        return Vector2.INF
    return Vector2(maxf(on, 0.0), maxf(past, 0.0))


## The polyline from the end the body laid, *base* along the path, to the
## newest point: the laid end, every point kept past it that no arc passes,
## and the points of each arc.
func _polyline(base: float) -> void:
    _vertices = PackedFloat32Array()
    _vertex_places = PackedFloat64Array()
    _vertex_boxes = []
    if has_laid:
        _vertex(_point(_laid, 1), base, _laid_boxes[1])
    else:
        _vertex(_point(_all, 0), _all_places[0], _all_boxes[0])
    var passed := -INF
    var next := 0
    for index in _all_places.size():
        var place := _all_places[index]
        while next < _all_pivots.size() and _all_pivots[next].start <= place:
            _arc(_all_pivots[next], base)
            passed = maxf(passed, _all_pivots[next].end)
            next += 1
        if place > passed and place > base:
            _reversal_vertex(index, place)


## The points of *pivot*'s arc past *base* along the path, with the spur out
## to the joint and back at its middle.
func _arc(pivot: Pivot, base: float) -> void:
    @warning_ignore("integer_division")
    var middle := pivot.chords / 2
    for chord in pivot.chords + 1:
        var share := float(chord) / pivot.chords
        var place := lerpf(pivot.start, pivot.end, share)
        if place <= base:
            continue
        var at := pivot.at(share)
        _arc_vertex(pivot, share, place, at)
        if chord == middle and at.distance_to(pivot.joint) > SAME:
            _arc_vertex(pivot, share, place, pivot.joint)
            _arc_vertex(pivot, share, place, at)


## A point of *pivot*'s polyline lying at *at*, *place* along the path, with
## what the path had there and the heading the arc has *share* of the way
## round it.
func _arc_vertex(pivot: Pivot, share: float, place: float, at: Vector2) -> void:
    var values := _along_path(place)
    var heading := pivot.tangent(share)
    values[NoiseStretchScript.AT] = at.x
    values[NoiseStretchScript.AT + 1] = at.y
    values[NoiseStretchScript.DIRECTION] = heading.x
    values[NoiseStretchScript.DIRECTION + 1] = heading.y
    _vertex(values, place, _box_along_path(place, at))


## The line the body paints: the last segment it laid and the polyline past
## it up to its newest point at or before the place it holds back from, which
## becomes that place. A closing stroke paints to the newest point, and paints
## even when that is the laid end, whose cap the updates before held back.
func _lay_line(closing: bool, base: float) -> void:
    if has_laid:
        line = _point(_laid, 0)
        _line_boxes = [_laid_boxes[0]]
    var held := base
    for index in _vertex_places.size():
        if index > 0 and _vertex_places[index] > _hold + SAME:
            break
        _append(_point(_vertices, index), _vertex_boxes[index])
        held = _vertex_places[index]
    _hold = held
    paints = closing or _hold > base + SAME


## Adds *values*, with its *box*, to [member line]. The box of the point
## before the laid end, which the line starts with, is left out of [member
## reach], since the kernel leaves the segment up to the laid end alone.
func _append(values: PackedFloat32Array, box: Rect2) -> void:
    line.append_array(values)
    _line_boxes.append(box)
    reach = box if reach.size == Vector2.ZERO else reach.merge(box)


## Adds point *index* kept, lying *place* along the path, to the polyline,
## and where a reversal starts there and the pen turned past it, the spur out
## to where it turned: the point on the outgoing leg's side, then the
## turning point on the returning leg's, so the stretch out to the turning point
## counts its across as the first leg does and the stretch back as the second.
func _reversal_vertex(index: int, place: float) -> void:
    var values := _point(_all, index)
    var box := _all_boxes[index]
    var at := _at(_all, index)
    for reversal in _all_reversals.size():
        if absf(_all_reversals[reversal] - place) > SAME or _all_tips[reversal].distance_to(at) <= SAME:
            continue
        var tip := _all_tips[reversal]
        var side := _side_at(place)
        _vertex_on(values, place, box, -side)
        values = values.duplicate()
        values[NoiseStretchScript.AT] = tip.x
        values[NoiseStretchScript.AT + 1] = tip.y
        _vertex_on(values, place, _shifted(box, at, tip), side)
        return
    _vertex(values, place, box)


## Adds *values* to the polyline, lying *place* along the path, with *box*,
## counting its across on the side the reversals up to it leave.
func _vertex(values: PackedFloat32Array, place: float, box: Rect2) -> void:
    _vertex_on(values, place, box, _side_at(place))


## Adds *values* to the polyline, lying *place* along the path, with *box*,
## counting its across on *side*.
func _vertex_on(values: PackedFloat32Array, place: float, box: Rect2, side: float) -> void:
    values[NoiseStretchScript.SIDE] = side
    _vertices.append_array(values)
    _vertex_places.append(place)
    _vertex_boxes.append(box)


## What the path held *place* along it, between the two points kept round
## there, and the nearer one's mirror and side.
func _along_path(place: float) -> PackedFloat32Array:
    var index := _below(_all_places, place)
    if index >= _all_places.size() - 1:
        return _point(_all, index)
    var span := _all_places[index + 1] - _all_places[index]
    var share := (place - _all_places[index]) / span if span > 0.0 else 0.0
    return _between(_all, index, index + 1, share)


## The box a tip at *at*, *place* along the path, reaches: the two kept
## points' round there, each moved to *at*.
func _box_along_path(place: float, at: Vector2) -> Rect2:
    var index := _below(_all_places, place)
    var box := _shifted(_all_boxes[index], _at(_all, index), at)
    if index < _all_places.size() - 1:
        box = box.merge(_shifted(_all_boxes[index + 1], _at(_all, index + 1), at))
    return box


## The side the across of a point *place* along the path is counted on: the
## first point's, turned over at every reversal up to it.
func _side_at(place: float) -> float:
    var side := _side
    for reversal: float in _all_reversals:
        if reversal <= place + SAME:
            side = -side
    return side


## The newest of *places* at or before *place* along the path, or the first.
static func _below(places: PackedFloat64Array, place: float) -> int:
    var index := 0
    while index < places.size() - 1 and places[index + 1] <= place:
        index += 1
    return index


## The turn the path makes at point *index* of every point, in radians, the
## sign saying which way.
func _turn(index: int) -> float:
    var into := _at(_all, index) - _at(_all, index - 1)
    var away := _at(_all, index + 1) - _at(_all, index)
    if into.length_squared() <= 0.0 or away.length_squared() <= 0.0:
        return 0.0
    return into.angle_to(away)


## The least turn at point *index* drawn round a pivot: twice what a wobble of
## the pen turns the step there by, so a pen's wobble is never one.
func _least_turn(index: int) -> float:
    var wobble := NoiseStretchScript.WOBBLE
    return 2.0 * wobble / maxf(NoiseStretchScript.step_for(_point(_all, index)), wobble)


## How far before and after the joint the arc of a turn by *turn* at a tip
## of *radius* leaves and joins the legs: the radius times the tangent of half
## the turn, and never more than the radius.
static func _tangent(turn: float, radius: float) -> float:
    return minf(radius * tan(0.5 * minf(absf(turn), MOST_TURN)), radius)


## The major radius of point *index* of *points*.
static func _radius(points: PackedFloat32Array, index: int) -> float:
    var at := index * NoiseStretchScript.FLOATS + NoiseStretchScript.HALF_EXTENT
    return maxf(points[at], points[at + 1])


## Point *index* of *points*.
static func _point(points: PackedFloat32Array, index: int) -> PackedFloat32Array:
    return points.slice(index * NoiseStretchScript.FLOATS, (index + 1) * NoiseStretchScript.FLOATS)


## Where point *index* of *points* lies.
static func _at(points: PackedFloat32Array, index: int) -> Vector2:
    var at := index * NoiseStretchScript.FLOATS + NoiseStretchScript.AT
    return Vector2(points[at], points[at + 1])


## Every value *share* of the way from point *from* to point *to* of
## *points*, and the nearer point's mirror and side.
static func _between(points: PackedFloat32Array, from: int, to: int, share: float) -> PackedFloat32Array:
    var out := _point(points, from)
    var other := _point(points, to)
    for slot in NoiseStretchScript.FLOATS:
        out[slot] = lerpf(out[slot], other[slot], share)
    var nearer := (from if share < 0.5 else to) * NoiseStretchScript.FLOATS
    for slot: int in [NoiseStretchScript.MIRROR, NoiseStretchScript.SIDE]:
        out[slot] = points[nearer + slot]
    return out


## *box*, the box of a tip at *from*, moved to a tip at *to*.
static func _shifted(box: Rect2, from: Vector2, to: Vector2) -> Rect2:
    return Rect2(box.position + (to - from), box.size)
