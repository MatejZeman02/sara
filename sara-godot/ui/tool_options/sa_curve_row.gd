## The `Kind.CURVE` row: a square graph over a bare `Curve`, and what the two
## say to each other.
##
## `Kind.CURVE_OPTION` is the other kind: a modulated parameter with a sensor
## list and a combine mode, on a page of its own, built by the declaring
## module. `Kind.CURVE` is the bare response curve with no sensors, and the
## brush tip's falloff is its first user.
##
## Its own file rather than four more branches inside
## [`tool_option_controls.gd`](tool_option_controls.gd), because that file owns
## *which control a kind gets and where its value lives* and this owns *what a
## `Curve` and a graph's points are to each other*, which is maths a test wants
## to reach with no control in a tree and no tool behind it. It is also what
## kept the row builder under the length advisory rather than smearing one
## class over two files to get there.
##
## Every method is static for the same reason: there is no state here. The
## points live on the `SaCurveEditor` the row built, and the `Curve` lives on
## the tool's own resource.
class_name SaCurveRow
extends RefCounted

## The side of the square graph, in logical pixels. Smaller than the curve
## option page's own graph, because that one owns a page and this one is a row
## among eighteen on the Tip page.
const SIZE := 160

## How finely the drawn curve is sampled to read a slope off it. A power of two
## plus one, so a control point at a round x lands on a sample rather than
## between two.
const SLOPE_SAMPLES := 257


## The row's control: a graph that stays square however wide the row is.
##
## The `AspectRatioContainer` is not decoration. Both surfaces that place a row
## zero a control's minimum width and let it fill, so a bare `SaCurveEditor`
## would come out as wide as the page and 160 tall, which is a curve nobody can
## read. The container keeps the square and the row keeps its width.
##
## *on_changed* is called with no arguments when the painter moves a point.
static func build(node_name: String, tooltip: String, on_changed: Callable) -> Control:
    var frame := AspectRatioContainer.new()
    frame.name = node_name
    frame.ratio = 1.0
    frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
    frame.alignment_horizontal = AspectRatioContainer.ALIGNMENT_BEGIN
    frame.custom_minimum_size = Vector2(DockerUtils.px(SIZE), DockerUtils.px(SIZE))
    var graph := SaCurveEditor.new()
    graph.name = "Graph"
    graph.custom_minimum_size = Vector2(DockerUtils.px(SIZE), DockerUtils.px(SIZE))
    if on_changed.is_valid():
        graph.curve_changed.connect(on_changed)
    if not tooltip.is_empty():
        frame.tooltip_text = tooltip
        graph.tooltip_text = tooltip
    frame.add_child(graph)
    return frame


## The graph inside a row's frame, or null when *control* is not one.
static func graph_of(control: Control) -> SaCurveEditor:
    if control == null:
        return null
    for child in control.get_children():
        var graph := child as SaCurveEditor
        if graph != null:
            return graph
    return null


## A `Curve`'s points on the graph's own axes, 0 to 1 both ways.
##
## Null answers the identity rather than an empty array, which is what a tool
## declaring the kind with no curve behind it gets: an empty graph reads as a
## broken row, and the diagonal reads as a curve nobody has drawn yet.
static func points_of(curve: Curve) -> PackedVector2Array:
    if curve == null or curve.point_count < 2:
        return PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 1.0)])
    var span := curve.max_value - curve.min_value
    var points := PackedVector2Array()
    for index in curve.point_count:
        var at := curve.get_point_position(index)
        var y := (at.y - curve.min_value) / span if absf(span) > 1e-6 else at.y
        points.append(Vector2(clampf(at.x, 0.0, 1.0), clampf(y, 0.0, 1.0)))
    return points


## The `Curve` the graph's *points* stand for, keeping *like*'s range when it
## has one.
##
## **The tangents are set rather than left at zero**, and that is the whole of
## why this is not four lines. A `Curve` bakes cubic Hermite through the
## tangents it holds, and a fresh point's are both zero, so the two-point curve
## Godot bakes is an S that leaves and arrives flat while the graph beside it
## draws the straight line `SaCurveEditor` computes. The painter would drag one
## shape and paint another, which is the kind of quiet disagreement a row like
## this exists to close.
static func curve_of(points: PackedVector2Array, like: Curve = null) -> Curve:
    var curve := Curve.new()
    if like != null:
        curve.min_value = like.min_value
        curve.max_value = like.max_value
    var span := curve.max_value - curve.min_value
    var slopes := slopes_at(points)
    for index in points.size():
        var at := points[index]
        var point := curve.add_point(Vector2(at.x, curve.min_value + at.y * span))
        curve.set_point_left_mode(point, Curve.TANGENT_FREE)
        curve.set_point_right_mode(point, Curve.TANGENT_FREE)
        curve.set_point_left_tangent(point, slopes[index] * span)
        curve.set_point_right_tangent(point, slopes[index] * span)
    return curve


## The drawn curve's slope at each of *points*, read off its own samples.
##
## By a difference over `SaCurveEditor.sample_curve` rather than by computing
## the Fritsch-Carlson tangents again here. The editor keeps that step private
## and it is the reason the curve is monotone at all, so the choice was between
## the same maths in two files and one sampled read through the door the sensors
## already use. A cubic sampled 257 times gives the slope back to about a
## thousandth, which is finer than a falloff a painter drags by hand.
static func slopes_at(points: PackedVector2Array) -> PackedFloat32Array:
    var slopes := PackedFloat32Array()
    slopes.resize(points.size())
    if points.size() < 2:
        return slopes
    var samples := SaCurveEditor.sample_curve(points, SLOPE_SAMPLES)
    var last := samples.size() - 1
    var step := 1.0 / float(last)
    for index in points.size():
        var i := clampi(int(round(clampf(points[index].x, 0.0, 1.0) * float(last))), 0, last)
        var lo := maxi(i - 1, 0)
        var hi := mini(i + 1, last)
        slopes[index] = (samples[hi] - samples[lo]) / (float(hi - lo) * step) if hi > lo else 0.0
    return slopes
