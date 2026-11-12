## Symmetry for painting: horizontal, vertical and radial, on the document
## rather than on a brush, so every tool that paints through SaPaintContext
## gets it.
##
## A dab is round, so a mirrored or rotated dab is the same dab at another
## centre, and the whole feature is a map from one point to the points it
## stands for. The paint context asks for that map per region and dispatches
## one target per image, each with its own dirty rectangle, so hard rule 2
## holds for every one of them. The canvas overlay draws the axes from the
## same object.
##
## **The axes stand on two handles placed anywhere.** The painter drags them, so
## the axis is the line through two points and can lean at any angle. What is kept is that line's midpoint, `center`, the way it
## turns, `angle`, and half its length, `reach`. Both mirrors and the radial
## spokes are built from those three, so they share one centre and one angle,
## and at angle nought every output is the upright cross.
class_name SaSymmetry
extends RefCounted

## Announced from every setter, so the overlay and the bar follow whoever
## changed it, the way a field the UI mirrors should.
signal changed

## The most images one dab may become. Twelve axes was the phase page's
## warning, and radial six with both mirrors is twenty-four.
const MAX_RADIAL: int = 12

## The shortest half length the handles keep, in document pixels, so the two
## are never one point with no line through them.
const MIN_REACH: float = 1.0

## The step a held Shift turns the axis by, fifteen degrees.
const SNAP_STEP: float = PI / 12.0

## What a point is on, as `hit` answers: one of the two handles by its place in
## `handles()`, a line, or nothing.
const HIT_NONE: int = -1
const HIT_LINE: int = 2

## Across the axis that runs straight down at angle nought: left becomes right.
var mirror_horizontal: bool = false:
    set(value):
        if mirror_horizontal != value:
            mirror_horizontal = value
            changed.emit()
## Across the axis at right angles to that one: top becomes bottom.
var mirror_vertical: bool = false:
    set(value):
        if mirror_vertical != value:
            mirror_vertical = value
            changed.emit()
## Copies about the centre, or nought for none. Two is a point mirror.
var radial: int = 0:
    set(value):
        var clamped := 0 if value < 2 else mini(value, MAX_RADIAL)
        if radial != clamped:
            radial = clamped
            changed.emit()
## How many copies a radial switch makes. Krita's default is six.
var radial_count: int = 6
## Where the axes cross, in document pixels, the midpoint of the two handles.
## The canvas centre until moved.
var center: Vector2 = Vector2.ZERO:
    set(value):
        if center != value:
            center = value
            changed.emit()
## How far the axes are turned, in radians, clockwise on screen. Nought is the
## upright axis, kept between minus and plus a half turn because a line turned
## by a half turn is the same line.
var angle: float = 0.0:
    set(value):
        var wrapped := wrapf(value, -PI, PI)
        if angle != wrapped:
            angle = wrapped
            changed.emit()
## Half the distance between the handles, in document pixels. The document
## sets it to a quarter of the canvas's shorter side.
var reach: float = 64.0:
    set(value):
        var kept := maxf(value, MIN_REACH)
        if reach != kept:
            reach = kept
            changed.emit()


func is_active() -> bool:
    return mirror_horizontal or mirror_vertical or radial >= 2


## Along the horizontal mirror's axis, straight down at angle nought.
func axis_direction() -> Vector2:
    return Vector2.DOWN.rotated(angle)


## Along the vertical mirror's axis and radial's first spoke, straight right at
## angle nought.
func across_direction() -> Vector2:
    return Vector2.RIGHT.rotated(angle)


## Every point *point* stands for, the original first, with no repeats.
func images(point: Vector2) -> PackedVector2Array:
    var out := PackedVector2Array([point])
    # A mirror reflects across its line, so the normal it is handed is the
    # other mirror's direction.
    if mirror_horizontal:
        _append_reflected(out, across_direction())
    if mirror_vertical:
        _append_reflected(out, axis_direction())
    if radial >= 2:
        var base := out.duplicate()
        for k in range(1, radial):
            var turn := TAU * float(k) / float(radial)
            for p in base:
                _append_unique(out, center + (p - center).rotated(turn))
    return out


## Every region *region* stands for: the same size, around each image of its
## centre, which is exactly right for a round dab.
func regions(region: Rect2) -> Array[Rect2]:
    var out: Array[Rect2] = []
    var half := region.size * 0.5
    for image in images(region.get_center()):
        out.append(Rect2(image - half, region.size))
    return out


## The axes to draw, as pairs of document points clipped to a canvas of *size*.
## A mirror is a whole line through the centre and a spoke starts there.
func axes(size: Vector2) -> Array[PackedVector2Array]:
    var lines: Array[PackedVector2Array] = []
    if mirror_horizontal:
        _append_clipped(lines, axis_direction(), size, false)
    if mirror_vertical:
        _append_clipped(lines, across_direction(), size, false)
    if radial >= 2:
        for k in radial:
            _append_clipped(lines, Vector2.RIGHT.rotated(angle + TAU * float(k) / float(radial)), size, true)
    return lines


## Where the two handles stand, in document pixels. On the horizontal mirror's
## line when it is on, on the vertical one's when only that is, and on the
## centre and the first spoke when only radial is.
func handles() -> PackedVector2Array:
    if mirror_horizontal or mirror_vertical:
        var along := axis_direction() if mirror_horizontal else across_direction()
        return PackedVector2Array([center - along * reach, center + along * reach])
    return PackedVector2Array([center, center + across_direction() * reach])


## What *point* is on, for a canvas of *size*: a handle within *handle_reach*,
## the nearer of two, then a drawn line within *line_reach*, both in document
## pixels, or `HIT_NONE`.
func hit(point: Vector2, handle_reach: float, line_reach: float, size: Vector2) -> int:
    var found := HIT_NONE
    var nearest := handle_reach
    var ends := handles()
    for index in ends.size():
        var distance := point.distance_to(ends[index])
        if distance <= nearest:
            nearest = distance
            found = index
    if found != HIT_NONE:
        return found
    for line in axes(size):
        if point.distance_to(Geometry2D.get_closest_point_to_segment(point, line[0], line[1])) <= line_reach:
            return HIT_LINE
    return HIT_NONE


## Puts handle *index* at *to*, clamped to a canvas of *size*, with the other
## where it stands, so the axis turns and stretches about the far handle.
## *snap* turns it by whole `SNAP_STEP`s. With radial alone the first handle is
## the centre, which moves the spokes without turning them, and the second the
## end of the first spoke, which turns them.
func move_handle(index: int, to: Vector2, size: Vector2, snap: bool) -> void:
    var at := to.clamp(Vector2.ZERO, size)
    if not (mirror_horizontal or mirror_vertical):
        if index == 0:
            center = at
        else:
            _turn_about(center, at, Vector2.RIGHT, 1.0, snap, false)
        return
    var base := Vector2.DOWN if mirror_horizontal else Vector2.RIGHT
    # The way from the first handle to the second, whichever was grabbed.
    var toward := 1.0 if index == 1 else -1.0
    _turn_about(handles()[1 - index], at, base, toward, snap, true)


## Back to rest on a canvas of *size*: the centre in the middle, upright, and
## the handles a quarter of the shorter side either way.
func reset_axes(size: Vector2) -> void:
    center = size * 0.5
    angle = 0.0
    reach = minf(size.x, size.y) * 0.25


## Moves the axes to the middle of a canvas that changed size to *size*, when
## they stood at *old_middle*, the middle of the old one, or would stand outside
## the new one. A new document, an opened file and a crop all change the size,
## and keeping the centre of the canvas before them would mirror a 500 pixel
## sketch that follows a 4000 pixel one about a point 1500 pixels past its
## edge.
## Axes moved and still inside are kept, turn and all, ones put back stand
## upright, a same size skips. The document's setter calls it, and the rule is
## the axes' own, so it lives with them.
func follow_canvas(old_middle: Vector2, size: Vector2) -> void:
    if old_middle.is_equal_approx(size * 0.5):
        return
    if center.is_equal_approx(old_middle) or not Rect2(Vector2.ZERO, size).has_point(center):
        reset_axes(size)


## Whether the axes stand where `reset_axes` puts them on a canvas of *size*.
func is_at_rest(size: Vector2) -> bool:
    return (
        center.is_equal_approx(size * 0.5)
        and is_zero_approx(angle)
        and is_equal_approx(reach, maxf(minf(size.x, size.y) * 0.25, MIN_REACH))
    )


## The axes and the switches as the `.sad` header's `symmetry` key holds them.
func to_header() -> Dictionary[String, Variant]:
    return {
        "center": [center.x, center.y],
        "angle": angle,
        "reach": reach,
        "mirror_horizontal": mirror_horizontal,
        "mirror_vertical": mirror_vertical,
        "radial": radial,
    }


## Takes what `to_header` wrote, for a canvas of *size*. A key that is missing
## or malformed reads as rest, and a header with no `symmetry` key at all is
## the axes at rest with every switch off, the likeliest state of a file that
## never recorded them.
func read_header(raw: Variant, size: Vector2) -> void:
    var stored := SaTyped.strings(raw)
    reset_axes(size)
    var at := SaTyped.list(stored.get("center"))
    if at.size() == 2:
        center = Vector2(SaTyped.real(at[0], center.x), SaTyped.real(at[1], center.y))
    angle = SaTyped.float_at(stored, "angle", angle)
    reach = SaTyped.float_at(stored, "reach", reach)
    mirror_horizontal = SaTyped.bool_at(stored, "mirror_horizontal", false)
    mirror_vertical = SaTyped.bool_at(stored, "mirror_vertical", false)
    radial = SaTyped.int_at(stored, "radial", 0)


## Turns the axes about *pivot* so they point at *grabbed*, from *base*, the
## way *toward* says runs from the first handle to the second. *between* says
## the two are the handles, with the centre their midpoint, rather than the
## centre and the end of a spoke. Two points on top of each other say no
## direction, so they leave the axes as they are.
func _turn_about(pivot: Vector2, grabbed: Vector2, base: Vector2, toward: float, snap: bool, between: bool) -> void:
    var span := (grabbed - pivot) * toward
    var length := span.length()
    if length < MIN_REACH:
        return
    var turned := base.angle_to(span)
    if snap:
        turned = snappedf(turned, SNAP_STEP)
    angle = turned
    if between:
        reach = length * 0.5
        center = pivot + base.rotated(turned) * (toward * length * 0.5)
    else:
        reach = length


func _append_reflected(out: PackedVector2Array, normal: Vector2) -> void:
    var base := out.duplicate()
    for p in base:
        _append_unique(out, p + normal * (2.0 * (center - p).dot(normal)))


## The part of the line from the centre along *direction*, both ways or only
## forward when *ray*, that falls on a canvas of *size*, appended to *lines*.
## Nothing is appended when the line misses the canvas.
func _append_clipped(lines: Array[PackedVector2Array], direction: Vector2, size: Vector2, ray: bool) -> void:
    var low := 0.0 if ray else -INF
    var high := INF
    for axis in 2:
        if absf(direction[axis]) < 1e-9:
            if center[axis] < 0.0 or center[axis] > size[axis]:
                return
            continue
        var near := -center[axis] / direction[axis]
        var far := (size[axis] - center[axis]) / direction[axis]
        low = maxf(low, minf(near, far))
        high = minf(high, maxf(near, far))
    if low < high:
        lines.append(PackedVector2Array([center + direction * low, center + direction * high]))


func _append_unique(out: PackedVector2Array, candidate: Vector2) -> void:
    for existing in out:
        if existing.is_equal_approx(candidate):
            return
    out.append(candidate)
