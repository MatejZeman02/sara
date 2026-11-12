## The path a stroke takes between two pen samples: a centripetal Catmull-Rom
## through the samples either side, or the straight line where a curve has no
## business being.
##
## A fast stroke arrives as samples far apart, and the straight walk between
## them showed its corners on a quick curve. The curve through four samples
## needs the one after a segment before it can draw that segment, so this class
## holds the last three samples and answers a segment one sample late. The last
## segment of a stroke is answered at pen up, with the end point repeated as
## the sample after it, and the first with the start repeated as the one
## before.
##
## The answer is a polyline rather than a function, because the walk that
## places dabs is `SaStrokeDistance`'s, which asks along straight segments and
## carries its accumulator across them. Chords walked one after another place
## dabs at the same spacing a single segment would, so a straight stroke,
## whose curve is one chord, paints exactly the dabs it always did.
##
## A segment stays straight in two places. A stroke of two samples has nothing
## either side to bend towards. And a corner the fan turns, where the drawing
## angle sensor fans a flat tip round a turn: the fan is drawn at a point where
## the stroke changes direction at once, and a curve through that point would
## round off the very corner the fan was asked to fill.
class_name SaStrokeCurve
extends RefCounted

## How far the polyline may stray from the curve, in document pixels. A tenth
## of a pixel is below anything a dab can show, and a gentle segment is one or
## two chords at that.
const CHORD_TOLERANCE: float = 0.1

## The most chords one segment is cut into. A segment so bent that it wants
## more is a hook in the pen's path, and the dabs along it are already closer
## together than the chords.
const MAX_CHORDS: int = 64


## One pen sample, as the walk interpolates it.
class Sample:
    extends RefCounted

    var position: Vector2
    var pressure: float
    var tilt: Vector2

    func _init(at: Vector2, raw_pressure: float, at_tilt: Vector2) -> void:
        position = at
        pressure = raw_pressure
        tilt = at_tilt


## One segment ready to walk, from *start* to *end*.
##
## The path is a polyline from the start to the end at equal steps of the
## curve's parameter, so chord *i* ends at parameter `i / (size - 1)`, and the
## pressure and tilt follow that same parameter linearly between the two
## samples.
class Span:
    extends RefCounted

    var start: Sample
    var end: Sample
    var path: PackedVector2Array

    func _init(from: Sample, to: Sample, points: PackedVector2Array) -> void:
        start = from
        end = to
        path = points

    func pressure_at(parameter: float) -> float:
        return lerpf(start.pressure, end.pressure, parameter)

    func tilt_at(parameter: float) -> Vector2:
        return start.tilt.lerp(end.tilt, parameter)

    ## The parameter chord *index* ends at.
    func parameter_at(index: int) -> float:
        return float(index) / float(path.size() - 1)


## The samples the next segment needs, oldest first, four at most: the one
## before the segment, its start, its end, and the newest, which is the sample
## after it.
var _samples: Array[Sample] = []


func is_empty() -> bool:
    return _samples.is_empty()


func clear() -> void:
    _samples.clear()


## Opens the stroke at its first sample, which is the press.
func begin(at: Vector2, pressure: float, tilt: Vector2) -> void:
    _samples.clear()
    _samples.append(Sample.new(at, pressure, tilt))


## Takes the next sample and answers the segment it completes, or null.
##
## A sample where the pen has not moved replaces the last one's pressure and
## tilt, which is what the straight walk did with a segment of no length: it
## painted nothing and the next segment began at the newer pressure.
##
## *fan_degrees* is the fan step the brush asks for, 0 for none.
func feed(at: Vector2, pressure: float, tilt: Vector2, fan_degrees: float) -> Span:
    var sample := Sample.new(at, pressure, tilt)
    if not _samples.is_empty() and _samples[_samples.size() - 1].position.is_equal_approx(at):
        _samples[_samples.size() - 1] = sample
        return null
    _samples.append(sample)
    if _samples.size() > 4:
        _samples.pop_front()
    var count := _samples.size()
    if count < 3:
        return null
    # The segment waiting for this sample is the one ending just before it.
    var before: Sample = _samples[count - 4] if count == 4 else null
    return _span(before, _samples[count - 3], _samples[count - 2], sample, fan_degrees)


## Answers the stroke's last segment at pen up, or null when there is none,
## and empties the window.
func finish(fan_degrees: float) -> Span:
    var count := _samples.size()
    var span: Span = null
    if count >= 2:
        var before: Sample = _samples[count - 3] if count >= 3 else null
        span = _span(before, _samples[count - 2], _samples[count - 1], null, fan_degrees)
    _samples.clear()
    return span


func _span(before: Sample, from: Sample, to: Sample, after: Sample, fan_degrees: float) -> Span:
    var straight := PackedVector2Array([from.position, to.position])
    if before == null and after == null:
        return Span.new(from, to, straight)
    var p0 := before.position if before != null else from.position
    var p3 := after.position if after != null else to.position
    if _fans(p0, from.position, to.position, fan_degrees) or _fans(from.position, to.position, p3, fan_degrees):
        return Span.new(from, to, straight)
    return Span.new(from, to, chords(p0, from.position, to.position, p3))


## Whether the fan turns a flat tip at *corner*, on the way in from *from* and
## out towards *to*. A repeated end point has no direction and turns nothing.
static func _fans(from: Vector2, corner: Vector2, to: Vector2, fan_degrees: float) -> bool:
    if fan_degrees <= 0.0 or from.is_equal_approx(corner) or corner.is_equal_approx(to):
        return false
    var turn := SaStrokeDistance.fan_angles((corner - from).angle(), (to - corner).angle(), fan_degrees)
    return not turn.is_empty()


## The *p1* to *p2* span of the curve through the four points, as a polyline
## from *p1* to *p2* in as few equal steps of the parameter as keep it within
## [constant CHORD_TOLERANCE] of the curve.
##
## The count comes from how far the curve bows off the straight line at three
## points along it. A polyline of *n* chords sits about `1 / n^2` of that bow
## off the curve, so the square root finds the count. Collinear samples bow
## nowhere, and the answer is the straight segment, one chord.
static func chords(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) -> PackedVector2Array:
    var bow := 0.0
    var along := (p2 - p1).normalized()
    for quarter: float in [0.25, 0.5, 0.75]:
        var off := spline(p0, p1, p2, p3, quarter) - p1
        bow = maxf(bow, absf(off.cross(along)))
    var count := clampi(ceili(sqrt(bow / CHORD_TOLERANCE)), 1, MAX_CHORDS)
    var points := PackedVector2Array([p1])
    for i in range(1, count):
        points.append(spline(p0, p1, p2, p3, float(i) / float(count)))
    points.append(p2)
    return points


## Centripetal Catmull-Rom at *t* in the *p1* to *p2* span, in the Barry and
## Goldman form.
##
## Centripetal, the square root in the knot spacing, because a uniform spline
## loops back on itself where samples bunch, which is every place a painter
## slows down. A repeated end point is a knot interval of nothing, and the
## pyramid then takes the point itself for that level, which pulls the end of
## the curve straight towards its neighbour rather than dividing by zero.
static func spline(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
    var t1 := sqrt(p0.distance_to(p1))
    var t2 := t1 + sqrt(p1.distance_to(p2))
    var t3 := t2 + sqrt(p2.distance_to(p3))
    if t2 <= t1:
        return p1
    var at := t1 + (t2 - t1) * t
    var a1 := _knot(p0, p1, 0.0, t1, at)
    var a2 := _knot(p1, p2, t1, t2, at)
    var a3 := _knot(p2, p3, t2, t3, at)
    var b1 := _knot(a1, a2, 0.0, t2, at)
    var b2 := _knot(a2, a3, t1, t3, at)
    return _knot(b1, b2, t1, t2, at)


static func _knot(a: Vector2, b: Vector2, ta: float, tb: float, at: float) -> Vector2:
    if tb <= ta:
        return a
    return a.lerp(b, (at - ta) / (tb - ta))
