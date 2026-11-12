## The stretch of path one update of a noise stroke paints: the points the pen's
## curve answered since the last update, what the dynamics answered at each,
## and the storage buffer the kernel reads them from.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The kernel runs once an update over this stretch's rectangle, and a texel
## takes the tip at its nearest point of the path, so the stroke is the tip
## dragged and never stamps. The points go to the kernel in a storage buffer,
## because a push constant has no room, written in place once an update.
##
## A pen's wobble would turn short segments by tens of degrees, so a point is
## taken only a [method step_for] on from the last and the rest are held back,
## and a round tip holds back a half width so a turn is drawn round its inside.
## Each texel is painted once across updates, which is why the next stretch
## carries the last segment of this one back as its first. The reasons are in
## the module's README, under "How a stroke is laid".
extends RefCounted

const NoiseHeldPathScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_held_path.gd")
const NoiseReturnsScript = preload("res://modules/sara-noise-brush-engine/build_up/noise_returns.gd")

## The floats one point takes, the kernel's `NOISE_POINT_FLOATS`, and where
## each value sits among them, the kernel's `NOISE_POINT_*`. The lean is the
## unit vector the pen leans along times the share Thickness Lean answered
## there, signed, so the kernel's height grows towards where it points. The
## side is one, or minus one past a reversal of the held path, which counts the
## across on the other side so a streak keeps its line when the pen goes back.
## The place is the length of path from the press in document pixels, which
## the along is not once a Drift row slides the field with the pen, and is what
## the build-up measures how far back the pen came over its paint by.
const FLOATS: int = 26
const AT: int = 0
const ALONG: int = 2
const PRESSURE: int = 3
const HALF_EXTENT: int = 4
const ROTATION: int = 6
const FADE: int = 8
const FALLOFF: int = 10
const SHIFT: int = 12
const BAND: int = 13
const THICKNESS: int = 14
const MIRROR: int = 15
const COLOUR: int = 16
const DIRECTION: int = 20
const LEAN: int = 22
const SIDE: int = 24
const PLACE: int = 25

## What the last update laid of the first segment, the kernel's `first_laid`:
## nothing, at the stroke's first stretch, the whole segment, which the kernel
## leaves alone, or, for a tip that carries a trail, none of it left alone and
## each texel painted only where the stretch gives it more than is laid. A
## trail that starts past the stroke's first point is the last with the texels
## behind its own first point left alone as well, since the stretches before
## read them from the path behind it, which this one does not hold.
const FIRST_NOTHING: float = 0.0
const FIRST_SEGMENT: float = 1.0
const FIRST_REPAINT: float = 2.0
const FIRST_REPAINT_CUT: float = 3.0

## The fewest points the buffer is made for, so a stroke of short updates
## makes one buffer and keeps it.
const MIN_CAPACITY: int = 64

## The wobble a pen reports at every sample that a step is made long enough
## to ride out, in document pixels.
const WOBBLE: float = 1.0

## What the held path's plan of the update under way was made for: nothing,
## while it must be made again, an open stroke or a closing one.
const PLAN_NONE: int = -1
const PLAN_OPEN: int = 0
const PLAN_CLOSING: int = 1

## The points of the update under way, [constant FLOATS] a point, oldest first,
## and the box their tips reach merged into one.
var points: PackedFloat32Array = PackedFloat32Array()
var box: Rect2 = Rect2()
## What the last [method write] sent: how many points, what of the first
## segment was painted before, and whether the newest point's front was left to
## the next update. The kernel's three numbers of the stretch.
var count: int = 0
var first_laid: float = FIRST_NOTHING
var open_end: bool = false
## The length of path the last [method write] sent past the newest point the
## write before it sent, and its newest point's major radius, both in document
## pixels, which the height the stroke pushes ahead of itself is measured by.
var walked: float = 0.0
var newest_radius: float = 0.0
## The frame a Grain or a Picture is read in for the whole stroke: the first
## point taken, its along, and the first heading the path has, nought until the
## pen leaves the press. `noise_canvas_place` in `noise_fields.gmacs` reads it.
var field_origin: Vector2 = Vector2.ZERO
var field_along: float = 0.0
var field_axis: Vector2 = Vector2.ZERO

## The points carried from the updates before, oldest first, with the box each
## one's tip reaches, and how far the tip of the update that carried them
## reaches in pixels. The newest two at least, which is all a round tip needs.
var _kept := PackedFloat32Array()
var _kept_boxes: Array[Rect2] = []
var _kept_reach: float = 0.0
## Whether the points carried still start at the stroke's first point.
var _kept_from_start: bool = true
## The box of each point of the update under way, and how far the farthest tip
## that is not round reaches, in pixels, nought while every tip is.
var _boxes: Array[Rect2] = []
var _reach: float = 0.0
## Whether the newest point's front still waits to be painted.
var _deferred: bool = false
var _buffer: SaCompute.Buffer = null
var _capacity: int = 0
## The newest point held back, less than a step from the last one taken, with
## its box and its tip's reach, empty while none is.
var _held := PackedFloat32Array()
var _held_box: Rect2 = Rect2()
var _held_reach: float = 0.0
## Whether a point of the stroke has been taken, and the newest one taken:
## where it lies, its along as the pen's walk read it and as the stretch sends
## it. And the path the pen walked since it, through every point held back,
## with the last point added, which that walk is measured on from.
var _taken: bool = false
var _taken_at: Vector2 = Vector2.ZERO
var _taken_walk: float = 0.0
var _taken_along: float = 0.0
var _wandered: float = 0.0
var _added_at: Vector2 = Vector2.ZERO
## The half extents of the newest point taken and the box its tip reaches,
## which a point held back past it is drawn at, in the front and at the lift.
var _taken_extent: Vector2 = Vector2.ZERO
var _taken_box: Rect2 = Rect2()
## The points taken within a tip's radius of path behind the newest, oldest
## first, and the length of path taken up to each, which the heading is
## measured over.
var _trace := PackedVector2Array()
var _trace_length := PackedFloat64Array()
## The length of path up to the newest point taken and up to each point of the
## update under way, in pixels.
var _taken_place: float = 0.0
var _places := PackedFloat64Array()
## The path a round tip holds back, and what its plan of the update under way
## was made for, one of the PLAN_ numbers.
var _path: NoiseHeldPathScript = NoiseHeldPathScript.new()
## The path sent so far, which a pen coming back over it builds up on.
var returns: NoiseReturnsScript = NoiseReturnsScript.new()
var _planned: int = PLAN_NONE


## Forgets the stroke before, at a press and a lift.
func clear() -> void:
    points = PackedFloat32Array()
    box = Rect2()
    count = 0
    first_laid = FIRST_NOTHING
    open_end = false
    walked = 0.0
    newest_radius = 0.0
    field_origin = Vector2.ZERO
    field_along = 0.0
    field_axis = Vector2.ZERO
    _kept = PackedFloat32Array()
    _kept_boxes = []
    _kept_reach = 0.0
    _kept_from_start = true
    _boxes = []
    _reach = 0.0
    _deferred = false
    _held = PackedFloat32Array()
    _taken = false
    _taken_extent = Vector2.ZERO
    _taken_box = Rect2()
    _wandered = 0.0
    _trace = PackedVector2Array()
    _trace_length = PackedFloat64Array()
    _taken_place = 0.0
    _places = PackedFloat64Array()
    _path.clear()
    returns.clear()
    _planned = PLAN_NONE


## Adds a point to the update under way: *values*, [constant FLOATS] floats at
## the slots above, and *reach*, the box its tip covers in document pixels.
## *tip_reach* is how far that tip reaches from the point in pixels when it is
## not round, so its coverage is the greatest over the path and not the
## nearest point's, and nought when it is. A point less than [method step_for]
## from the last one taken is held back rather than added, the newest in place
## of the one before.
func add(values: PackedFloat32Array, reach: Rect2, tip_reach: float = 0.0) -> void:
    assert(values.size() == FLOATS, "A point is %d floats" % FLOATS)
    var at := Vector2(values[AT], values[AT + 1])
    if _taken:
        _wandered += at.distance_to(_added_at)
    _added_at = at
    if _taken and at.distance_to(_taken_at) < step_for(values):
        _held = values
        _held_box = reach
        _held_reach = tip_reach
        if _taken_place == 0.0 and at.distance_to(_taken_at) < 0.5 * step_for(values):
            _press_harder(values, reach.position - at)
        return
    _take(values, reach, tip_reach)


## Writes a point held back at the spot of the newest one taken, *values*, onto
## that point when the pen pressed harder there, everything the dynamics
## answered but where it lies, its along and its heading. The newest point
## taken is still to be sent, or its front still waits for the next update, so
## the stroke paints the spot at the greatest pressure the pen gave it. *corner*
## is where the held point's box starts from the point, which the taken point's
## box now reaches as well.
func _press_harder(values: PackedFloat32Array, corner: Vector2) -> void:
    var into := points if not points.is_empty() else _kept
    _planned = PLAN_NONE
    if maxf(values[HALF_EXTENT], values[HALF_EXTENT + 1]) > maxf(_taken_extent.x, _taken_extent.y):
        _taken_extent = Vector2(values[HALF_EXTENT], values[HALF_EXTENT + 1])
        _taken_box = _taken_box.merge(Rect2(_taken_at + corner, _held_box.size))
    if into.is_empty():
        _path.press_harder(values, Rect2(_taken_at + corner, _held_box.size))
        return
    var newest := into.size() - FLOATS
    if values[PRESSURE] <= into[newest + PRESSURE]:
        return
    for slot in range(PRESSURE, DIRECTION):
        into[newest + slot] = values[slot]
    var reach := Rect2(_taken_at + corner, _held_box.size)
    if not points.is_empty():
        points = into
        _boxes[-1] = _boxes[-1].merge(reach)
        box = box.merge(reach)
    else:
        _kept = into
        _kept_boxes[-1] = _kept_boxes[-1].merge(reach)


## Writes *values*, a point laid before the stroke's first speed answered again
## at that speed, onto the point of the update under way that lies within a
## pixel of it: everything the dynamics answered and its along, the drift's
## slide being one of them, but not where it lies nor its heading. *reach* is
## the box its tip covers now. Nothing for a point an update has sent already,
## which keeps what it was sent with, nor from a point held back beside one
## taken that pressed lighter, which [method add] wrote nothing from either.
func restate(values: PackedFloat32Array, reach: Rect2) -> void:
    var at := Vector2(values[AT], values[AT + 1])
    @warning_ignore("integer_division")
    for index in points.size() / FLOATS:
        var start := index * FLOATS
        if at.distance_to(Vector2(points[start + AT], points[start + AT + 1])) > 1.0:
            continue
        if values[PRESSURE] < points[start + PRESSURE]:
            return
        for slot in range(ALONG, DIRECTION):
            points[start + slot] = values[slot]
        for slot in range(LEAN, PLACE):
            points[start + slot] = values[slot]
        _boxes[index] = _boxes[index].merge(reach)
        box = box.merge(reach)
        _planned = PLAN_NONE
        return


## The shortest step between two points the stretch takes, in document
## pixels, for a point of *values*: the farthest along the path a point that
## lies [constant WOBBLE] nearer a texel at the tip's edge than its neighbours
## can take that texel from them. Nought for a tip that paints nothing.
static func step_for(values: PackedFloat32Array) -> float:
    return sqrt(2.0 * maxf(0.0, maxf(values[HALF_EXTENT], values[HALF_EXTENT + 1])) * WOBBLE)


## Whether the update under way has anything to paint: a new point, or, when
## the stroke is *closing*, the end cap the last update left. A press alone
## waits for a second point unless the stroke is closing. At the close it
## first takes the point held back, when that lies half a step on, since the
## lift is the last the stretch hears of the pen.
func is_waiting(closing: bool) -> bool:
    if closing and not _held.is_empty():
        var held := _held
        var reach := _held_reach_box()
        _held = PackedFloat32Array()
        if Vector2(held[AT], held[AT + 1]).distance_to(_taken_at) >= 0.5 * step_for(held):
            _take(_at_taken_size(held), reach, _held_reach)
    if _round():
        _plan(closing)
        return _path.paints
    if points.is_empty():
        return closing and _deferred
    return closing or not _kept.is_empty() or points.size() > FLOATS


## The rectangle the update under way reaches, in document pixels: its new
## points' boxes and the newest painted point's, which the texels left in front
## of it are inside, or all the carried points' when the tip carries a trail.
func region() -> Rect2:
    if _round():
        if _planned == PLAN_NONE:
            _plan(false)
        return _path.reach
    var out := box
    var have := not points.is_empty()
    var first := 0 if _repaints() else maxi(0, _kept_boxes.size() - 1)
    for at in range(first, _kept_boxes.size()):
        out = _kept_boxes[at] if not have else out.merge(_kept_boxes[at])
        have = true
    return out


## Sends the update under way to the buffer as one polyline, the carried
## points first, and carries what the next needs. *closing* paints the end
## cap, which the stroke's last update does. *cover* is the colour every point
## paints in, nought or one, while the stroke paints coverage into a mask, and
## below nought otherwise.
func write(closing: bool, cover: float) -> void:
    if _round():
        _write_held(closing, cover)
        return
    var repaints := _repaints()
    @warning_ignore("integer_division")
    var added := points.size() / FLOATS
    var line := _kept
    var boxes := _kept_boxes
    var from_start := _kept_from_start
    if not repaints and _kept.size() > 2 * FLOATS:
        line = _kept.slice(_kept.size() - 2 * FLOATS)
        boxes = _kept_boxes.slice(_kept_boxes.size() - 2)
        from_start = false
    first_laid = FIRST_NOTHING
    if repaints:
        first_laid = FIRST_REPAINT if from_start else FIRST_REPAINT_CUT
    elif line.size() >= 2 * FLOATS:
        first_laid = FIRST_SEGMENT
    line = line.duplicate()
    line.append_array(points)
    boxes = boxes.duplicate()
    boxes.append_array(_boxes)
    @warning_ignore("integer_division")
    count = line.size() / FLOATS
    open_end = not closing and count > 1
    _colour(line, cover)
    _send(line)
    _measure(line, added)
    if not points.is_empty():
        var from := maxi(0, count - 2)
        var reach := maxf(_reach, _kept_reach)
        if reach > 0.0:
            from = _trail_start(line, reach)
        _kept = line.slice(from * FLOATS)
        _kept_boxes = boxes.slice(from)
        _kept_from_start = from_start and from == 0
        _kept_reach = _reach
        if _round() and not closing:
            _path.restart(_kept.slice(_kept.size() - 2 * FLOATS), _kept_boxes.slice(_kept_boxes.size() - 2), _taken_place)
            _kept = PackedFloat32Array()
            _kept_boxes = []
    _deferred = open_end
    points = PackedFloat32Array()
    box = Rect2()
    _boxes = []
    _places = PackedFloat64Array()
    _reach = 0.0


## [method write] for a round tip: sends the line its held path planned, and
## carries the path on.
func _write_held(closing: bool, cover: float) -> void:
    _plan(closing)
    var line := _path.line.duplicate()
    first_laid = _path.first_laid
    @warning_ignore("integer_division")
    count = line.size() / FLOATS
    open_end = not closing and count > 1
    _colour(line, cover)
    _send(line)
    _measure(line, count - 2 if first_laid == FIRST_SEGMENT else count)
    _path.commit()
    if closing:
        _path.clear()
    _deferred = open_end
    points = PackedFloat32Array()
    box = Rect2()
    _boxes = []
    _places = PackedFloat64Array()
    _planned = PLAN_NONE


## Plans the held path's update for a stroke *closing* or not, unless the plan
## made last still stands.
func _plan(closing: bool) -> void:
    var want := PLAN_CLOSING if closing else PLAN_OPEN
    if _planned == want:
        return
    _path.plan(points, _boxes, _places, closing)
    _planned = want


## Paints every point of *line* in *cover*, nought or one, while the stroke
## paints coverage into a mask, and leaves it as it is below nought.
func _colour(line: PackedFloat32Array, cover: float) -> void:
    if cover < 0.0:
        return
    @warning_ignore("integer_division")
    for at: int in line.size() / FLOATS:
        for channel: int in 3:
            line[at * FLOATS + COLOUR + channel] = cover


## The front the stroke shows under the pen, the end cap the closing update
## would paint now: the newest two points the last update sent, or the press
## still waiting, and the point held back where one is, which the front ends
## on. A round tip's runs from the end its body laid through the path it holds
## back, the held path's front. Empty while nothing is taken. The held point takes the along it would be
## taken at and the heading of the point before it.
##
## The point the front ends on takes *pressure*, the pen's now, so the cap is
## the pen's now. A pen held exactly still sends samples the stroke's curve
## folds into its last one, which is swept only once the pen moves, so no point
## is taken or held for them and the end point would keep the pressure it was
## taken at. Its other numbers stay that point's, so a size or a Strength that
## follows the pressure shows at the pen's new pressure once the pen moves.
func front_line(pressure: float) -> PackedFloat32Array:
    var line := _kept if points.is_empty() else points
    if _round():
        _plan(false)
        line = _path.front.duplicate()
    else:
        line = line.slice(maxi(0, line.size() - 2 * FLOATS))
    if line.is_empty():
        return line
    if not _held.is_empty():
        var held := _at_taken_size(_held)
        var newest := line.size() - FLOATS
        held[ALONG] = _along_for(_held[ALONG], Vector2(_held[AT], _held[AT + 1]).distance_to(_taken_at))
        held[PLACE] = _taken_place + Vector2(_held[AT], _held[AT + 1]).distance_to(_taken_at)
        held[DIRECTION] = line[newest + DIRECTION]
        held[DIRECTION + 1] = line[newest + DIRECTION + 1]
        line.append_array(held)
    line[line.size() - FLOATS + PRESSURE] = pressure
    return line


## What of the front's first segment the body painted already: the segment
## up to the newest point, or for a round tip up to the end the body laid, once
## an update has sent the stroke on with its end left open, and nothing while
## the press waits.
func front_first_laid() -> float:
    if _round():
        return FIRST_SEGMENT if _path.has_laid else FIRST_NOTHING
    return FIRST_SEGMENT if points.is_empty() and _deferred else FIRST_NOTHING


## The box the front reaches in document pixels: the newest point's tip and
## the held point's, and the press's while it waits, or a round tip's held path
## and the held point.
func front_box() -> Rect2:
    var out := Rect2()
    if _round():
        _plan(false)
        out = _path.front_reach
    elif not points.is_empty():
        out = box
    elif not _kept_boxes.is_empty():
        out = _kept_boxes[-1]
    if not _held.is_empty():
        out = _held_reach_box() if out.size == Vector2.ZERO else out.merge(_held_reach_box())
    return out


## Binds the buffer to *compute*'s `stretch`.
func bind(compute: SaCompute) -> void:
    compute.set_storage("stretch", _buffer.rid)
    returns.bind(compute)


## Takes *values* into the update under way. Its along grows from the last
## point taken's by the share of the pen's walk since that is the chord between
## the two, which is all of it when no point was held back between them.
func _take(values: PackedFloat32Array, reach: Rect2, tip_reach: float) -> void:
    var at := Vector2(values[AT], values[AT + 1])
    var walk: float = values[ALONG]
    var point := values.duplicate()
    var chord := 0.0
    if _taken:
        chord = at.distance_to(_taken_at)
        point[ALONG] = _along_for(walk, chord)
    if tip_reach > 0.0 and _round() and not _path.is_empty():
        _kept = _path.unlaid()
        _kept_boxes = _path.unlaid_boxes()
        _kept_from_start = not _path.has_laid
        _path.clear()
    if not _taken:
        field_origin = at
        field_along = point[ALONG]
    var heading := _heading(at, chord, maxf(values[HALF_EXTENT], values[HALF_EXTENT + 1]))
    if heading != Vector2.ZERO and field_axis == Vector2.ZERO:
        field_axis = heading
    if heading != Vector2.ZERO:
        point[DIRECTION] = heading.x
        point[DIRECTION + 1] = heading.y
        # The press, still waiting for this point, takes the first chord's
        # heading as well, so the stroke's start reads along its path.
        if _trace.size() == 2 and _kept.is_empty() and points.size() == FLOATS:
            points[DIRECTION] = heading.x
            points[DIRECTION + 1] = heading.y
    _taken_place += chord
    point[PLACE] = _taken_place
    _places.append(_taken_place)
    _planned = PLAN_NONE
    _taken = true
    _taken_at = at
    _taken_walk = walk
    _taken_along = point[ALONG]
    _taken_extent = Vector2(point[HALF_EXTENT], point[HALF_EXTENT + 1])
    _taken_box = reach
    _wandered = 0.0
    _held = PackedFloat32Array()
    box = reach if points.is_empty() else box.merge(reach)
    _boxes.append(reach)
    _reach = maxf(_reach, tip_reach)
    points.append_array(point)


## *values*, the point held back, at the half extents of the newest point
## taken. A held point is less than a step on, so its own size against the
## taken point's is a pressure that changed at one spot, most often as the pen
## lifts, and drawn with it the stroke's end was a large half and a small one
## with a cut across between them.
func _at_taken_size(values: PackedFloat32Array) -> PackedFloat32Array:
    var held := values.duplicate()
    held[HALF_EXTENT] = _taken_extent.x
    held[HALF_EXTENT + 1] = _taken_extent.y
    return held


## The box the point held back reaches at the newest taken point's size as well
## as at its own.
func _held_reach_box() -> Rect2:
    var shift := Vector2(_held[AT], _held[AT + 1]) - _taken_at
    return _held_box.merge(Rect2(_taken_box.position + shift, _taken_box.size))


## The along a point the pen's walk reached at *walk* takes, *chord* on from
## the last point taken: the walk since that point, or the chord's share of it
## when the pen wandered further than the chord between the two.
func _along_for(walk: float, chord: float) -> float:
    if _wandered > chord:
        return _taken_along + (walk - _taken_walk) * chord / _wandered
    return walk + (_taken_along - _taken_walk)


## The heading of the path at a point taken at *at*, *chord* on from the last
## one taken: the way to it from the point a tip's *radius* of path behind, or
## from the last one taken where that is farther. A wobble of the pen turns it
## by the wobble's share of a radius rather than of a step, and a turn of the
## path turns it over a radius, which keeps along rising at a turn's outer
## edge. Nought for the stroke's first point, which keeps the pen's own.
func _heading(at: Vector2, chord: float, radius: float) -> Vector2:
    var length := 0.0 if _trace.is_empty() else _trace_length[_trace_length.size() - 1] + chord
    _trace.append(at)
    _trace_length.append(length)
    var back := length - maxf(radius, chord)
    var from := _trace[0]
    for at_index in range(_trace.size() - 2, -1, -1):
        if _trace_length[at_index] > back:
            continue
        var span := _trace_length[at_index + 1] - _trace_length[at_index]
        var share := (back - _trace_length[at_index]) / span if span > 0.0 else 0.0
        from = _trace[at_index].lerp(_trace[at_index + 1], share)
        _trace = _trace.slice(at_index)
        _trace_length = _trace_length.slice(at_index)
        break
    var way := at - from
    return way.normalized() if way.length_squared() > 0.0 else Vector2.ZERO


## Whether every tip of the update under way and of the one before is round,
## so the stroke carries the held path rather than a trail.
func _round() -> bool:
    return maxf(_reach, _kept_reach) <= 0.0


## Whether the update under way carries a trail, which is when a tip that is
## not round has been laid and there is a path behind it to carry.
func _repaints() -> bool:
    return maxf(_reach, _kept_reach) > 0.0 and not _kept.is_empty()


## Measures [member walked] and [member newest_radius] on *line*, whose last
## *added* points are the update's own, the first with no point before it at
## the stroke's first stretch.
func _measure(line: PackedFloat32Array, added: int) -> void:
    walked = 0.0
    for at in range(maxi(1, count - added), count):
        walked += _at(line, at).distance_to(_at(line, at - 1))
    var newest := (count - 1) * FLOATS + HALF_EXTENT
    newest_radius = maxf(line[newest], line[newest + 1])


## The first point of *line* worth carrying: the newest two, and every point
## back to the first that lies more than *reach* pixels of path behind the
## newest, so the segment that crosses that distance is whole.
func _trail_start(line: PackedFloat32Array, reach: float) -> int:
    @warning_ignore("integer_division")
    var last := line.size() / FLOATS - 1
    var from := maxi(0, last - 1)
    var behind := 0.0
    var at := last
    while at > 0:
        behind += _at(line, at).distance_to(_at(line, at - 1))
        at -= 1
        from = mini(from, at)
        if behind > reach:
            break
    return from


## Where point *index* of *line* lies, in document pixels.
static func _at(line: PackedFloat32Array, index: int) -> Vector2:
    return Vector2(line[index * FLOATS + AT], line[index * FLOATS + AT + 1])


func _send(line: PackedFloat32Array) -> void:
    returns.send(line)
    if _buffer == null or count > _capacity:
        _capacity = maxi(MIN_CAPACITY, nearest_po2(count))
        var room := PackedFloat32Array()
        room.resize(_capacity * FLOATS)
        _buffer = SaCompute.Buffer.new(room.to_byte_array())
    _buffer.update(line.to_byte_array())
