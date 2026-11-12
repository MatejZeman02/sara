## Where a rectangle of a given size goes among the rectangles that stand over
## its host, the nearest place none of them covers.
##
## Pure arithmetic over rectangles in one unit, whatever the caller's unit is,
## which is why it is a class of its own: the corner notice owns a panel, a clock
## and what stands over it right now, and this owns the question "given these
## rectangles, where is the nearest place a rectangle of this size is covered by
## none of them". A suite asks it without a window, which a suite cannot build
## with subwindows off.
class_name SaClearSlot
extends RefCounted

## How far up the line may climb looking for a place, as the share of the host's
## height it has to stay below. Past the middle it would no longer be a corner
## notice, and the home place is the better answer to a screen with no room.
const CLIMB_FLOOR: float = 0.5


## The bottom centre of a host of size *host* for a line of size *want*, which
## is where the line goes when nothing stands there.
static func home_slot(host: Vector2, want: Vector2, margin: float) -> Rect2:
    return Rect2(Vector2((host.x - want.x) * 0.5, host.y - want.y - margin), want)


## Where a line of size *want* goes in a host of size *host*: the bottom centre
## when no rectangle of *covering* is in the way, and otherwise the nearest
## place in the rows above it that none is.
##
## Rows are tried a half line apart, from the bottom up to `CLIMB_FLOOR`. In a
## row, the free stretches between the rectangles that reach it are the
## candidates, and the one whose fitting position is nearest the centre wins. A
## host with no such place gets the bottom centre, which is what it always did.
## Rectangles are in the host's own units, and *gap* is kept clear on both sides
## of each.
static func clear_slot(host: Vector2, want: Vector2, covering: Array[Rect2], margin: float, gap: float = 0.0) -> Rect2:
    var found: Variant = find_slot(host, want, covering, margin, gap)
    return found if found != null else home_slot(host, want, margin)


## `clear_slot`, or null when no row of the host has a stretch as wide as the
## line, which is the cue to wrap it.
static func find_slot(host: Vector2, want: Vector2, covering: Array[Rect2], margin: float, gap: float = 0.0) -> Variant:
    var step := maxf(want.y * 0.5, 1.0)
    var y := host.y - want.y - margin
    while y >= host.y * CLIMB_FLOOR:
        var x := _clear_x(host.x, want, y, covering, gap)
        if not is_nan(x):
            return Rect2(Vector2(x, y), want)
        y -= step
    return null


## The widest free stretch in any row a line of height *height* is tried in, or
## 0 when there is none.
static func widest_room(host: Vector2, height: float, covering: Array[Rect2], margin: float, gap: float = 0.0) -> float:
    var step := maxf(height * 0.5, 1.0)
    var y := host.y - height - margin
    var widest := 0.0
    while y >= host.y * CLIMB_FLOOR:
        for stretch in _free_stretches(host.x, height, y, covering, gap):
            widest = maxf(widest, stretch.y - stretch.x)
        y -= step
    return widest


## The left edge for a line of size *want* in the row that starts at *y*, nearest
## the centre and clear of every rectangle reaching the row, or NAN when no
## stretch of the row is wide enough.
static func _clear_x(host_width: float, want: Vector2, y: float, covering: Array[Rect2], gap: float) -> float:
    var centre := host_width * 0.5 - want.x * 0.5
    var best := NAN
    for stretch in _free_stretches(host_width, want.y, y, covering, gap):
        if stretch.y - stretch.x < want.x:
            continue
        var x := clampf(centre, stretch.x, stretch.y - want.x)
        if is_nan(best) or absf(x - centre) < absf(best - centre):
            best = x
    return best


## The stretches of the row that starts at *y* and is *height* tall which no
## rectangle reaches, as left and right edges, with *gap* kept off both sides of
## every rectangle that does and off the host's own edges.
static func _free_stretches(host_width: float, height: float, y: float, covering: Array[Rect2], gap: float) -> Array[Vector2]:
    var spans: Array[Vector2] = []
    for rect in covering:
        if rect.position.y < y + height + gap and rect.end.y + gap > y:
            spans.append(Vector2(rect.position.x - gap, rect.end.x + gap))
    spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
    var free: Array[Vector2] = []
    var edge := gap
    for span in spans:
        if span.x > edge:
            free.append(Vector2(edge, span.x))
        edge = maxf(edge, span.y)
    if edge < host_width - gap:
        free.append(Vector2(edge, host_width - gap))
    return free
