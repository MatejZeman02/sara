## The transform mode strip: where its six cells sit over a box, which one a
## press landed on, and the lines each cell draws.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Cut out of `ui/canvas/selection_overlay.gd` when the rule that a tool's
## engine lives with the tool reached the strip. The overlay drew the cells and
## answered for where they were, and the transform tool called back into its
## `mode_strip_pick` to learn what a press had hit: one skeleton class holding a
## module's engine and a module reaching up into the skeleton, which is the
## shape the magic wand was fixed for.
##
## The tool asks here for the cells and hands them to the overlay as a preview
## entry, so the strip is drawn by a file that knows nothing of a mode and
## hit-tested by the one that knows nothing of a painter.
##
## **Glyphs rather than words.** A word needs a font, a font needs a size in a
## space that scales with the zoom, and six words in a row beside a box is a
## strip as wide as the box is. The six shapes are what each mode does to a
## square, which is the same thing the tooltip on the options row says at
## length.
class_name SaTransformModeStrip
extends RefCounted

## The side of one cell, in screen pixels.
const MODE_CELL := 22.0

## The gap between two cells, in screen pixels.
const MODE_GAP := 3.0

## How far the strip floats above the box's top edge, in screen pixels. Enough
## that the strip does not sit on the top-middle handle, which is the tool's
## `HANDLE_SIDE`, 9 screen pixels of square centred on that edge.
const MODE_LIFT := 12.0

## How many cells the strip offers, which is the transform tool's
## `Mode.size()`. A number, because that enum is not a `class_name` and this is
## the module both files live in: `cells` marks the picked one by index and
## draws the same count whether the tool grows a seventh mode or not.
const MODE_COUNT := 6

## The cells whose glyph draws more than an outline, by the tool's mode index.
const FREEHAND_CELL := 3
const MIRRORED_CELL := 4
const CAGE_CELL := 5

## What each cell says when the pointer rests on it, by the tool's mode index:
## the Mode row's tooltip a mode at a time, since a glyph shows what a mode
## makes of a square and not which handle does it.
const TIPS: Array[String] = [
    "Normal. A handle scales the picture, Shift keeps its proportions and Ctrl with an edge handle shears it.",
    (
        "Perspective. A corner moves its neighbour too, the mirror way along the edge you drag it along, so a "
        + "top corner dragged out widens the top on both sides. Shift and a corner moves the one corner. A side "
        + "handle dragged along its side moves the opposite side the other way, skewing the picture, and dragged "
        + "across moves its side alone. Shift and a side handle moves the one side."
    ),
    "Shear. Every handle leans the picture over and none scales it, a corner leaning the edge it sits on.",
    "Freehand. The nine points of the grid are what you drag, each bending the picture around it.",
    "Mirrored. A corner or a side moves the opposite one the other way, so the picture keeps its centre.",
    (
        "Cage. Click points round the subject and click the first one again to close the cage, then drag its "
        + "points and the picture inside follows while what is outside stays. Escape clears an unclosed cage."
    ),
]


## Where the six cells sit, in the overlay's own pixels, which are the
## document's.
##
## *per_pixel* is document pixels per screen pixel, so a strip written in screen
## pixels is the same size at every zoom. The transform tool has that number as
## `1.0 / _view_zoom()` and hands the same one in when it asks which cell a press
## landed on, which is what keeps the picture and the press from drifting apart:
## there is one description of where the strip is and both callers read it.
##
## Anchored to the quad's own bounding box rather than to its top edge, because
## a sheared or warped quad has no top edge a strip can sit parallel to, and a
## strip that leans with the box is harder to hit than one that does not.
static func boxes(quad: PackedVector2Array, per_pixel: float) -> Array[Rect2]:
    var placed: Array[Rect2] = []
    if quad.size() < 4 or per_pixel <= 0.0:
        return placed
    var bounds := Rect2(quad[0], Vector2.ZERO)
    for point: Vector2 in quad:
        bounds = bounds.expand(point)
    var cell := MODE_CELL * per_pixel
    var gap := MODE_GAP * per_pixel
    var at := Vector2(bounds.position.x, bounds.position.y - MODE_LIFT * per_pixel - cell)
    for index in MODE_COUNT:
        placed.append(Rect2(at + Vector2(float(index) * (cell + gap), 0.0), Vector2(cell, cell)))
    return placed


## Which cell of the strip *at* is on, or -1 for none.
##
## Given the same *per_pixel* the cells were built with, so the tool that answers
## a press and the tool that drew the strip cannot disagree about where it is.
static func pick(quad: PackedVector2Array, per_pixel: float, at: Vector2) -> int:
    var placed := boxes(quad, per_pixel)
    for index in placed.size():
        if placed[index].has_point(at):
            return index
    return -1


## The tip of the cell *at* is on, translated, or empty for none, asked with
## the *per_pixel* `pick` is asked with, so the tip is the one a press there
## would pick.
static func tip(quad: PackedVector2Array, per_pixel: float, at: Vector2) -> String:
    var cell := pick(quad, per_pixel, at)
    if cell < 0 or cell >= TIPS.size():
        return ""
    return String(TranslationServer.translate(TIPS[cell]))


## The strip as the overlay draws it: one entry per cell, `{"box", "on",
## "glyph"}`, where a glyph is the polylines to draw inside the box, in the
## order they are drawn.
##
## The overlay reads boxes with a shape in them and knows nothing of a mesh or
## a mode, which is why the strip can live in this module and the overlay in
## the skeleton.
static func cells(quad: PackedVector2Array, picked: int, per_pixel: float) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var placed := boxes(quad, per_pixel)
    for index in placed.size():
        var box: Rect2 = placed[index]
        out.append({"box": box, "on": index == picked, "glyph": _glyph(index, box)})
    return out


## What each mode does to a square, as the polylines to draw inside *box*.
##
## The warp's two grid lines come first and its square is drawn over them. The
## order is not free: the ink of a picked cell is not opaque, so a polyline
## over another of the same colour lands darker than one beside it, and
## swapping two of these moves the texels where they meet, which a shot of the
## strip compared against its recorded one reads as a difference.
static func _glyph(index: int, box: Rect2) -> Array[PackedVector2Array]:
    var out: Array[PackedVector2Array] = []
    if index == FREEHAND_CELL:
        out.append_array(_grid_lines(box))
    out.append(_outline(index, box))
    if index == MIRRORED_CELL:
        out.append(_diagonal(box))
    return out


## The shape each mode makes of a square, as a closed outline inside *box*.
static func _outline(index: int, box: Rect2) -> PackedVector2Array:
    var inset := box.size * 0.24
    var inner := Rect2(box.position + inset, box.size - inset * 2.0)
    var lean := inner.size.x * 0.28
    var points := PackedVector2Array()
    match index:
        1:
            # Perspective: a trapezoid, narrow at the top the way a plane laid
            # away from the eye is.
            points.append(Vector2(inner.position.x + lean, inner.position.y))
            points.append(Vector2(inner.end.x - lean, inner.position.y))
            points.append(Vector2(inner.end.x, inner.end.y))
            points.append(Vector2(inner.position.x, inner.end.y))
        2:
            # Shear: a parallelogram, the top edge slid over the bottom one.
            points.append(Vector2(inner.position.x + lean, inner.position.y))
            points.append(Vector2(inner.end.x, inner.position.y))
            points.append(Vector2(inner.end.x - lean, inner.end.y))
            points.append(Vector2(inner.position.x, inner.end.y))
        CAGE_CELL:
            # Cage: a hexagon with one point pulled out, the outline a cage is.
            for step in 6:
                var turn := TAU * float(step) / 6.0
                var reach := 0.62 if step == 0 else 0.5
                points.append(inner.get_center() + Vector2(cos(turn), sin(turn)) * inner.size * reach)
        MIRRORED_CELL:
            # Mirrored: the top left and the bottom right corners pulled out
            # the same distance either way, a quad symmetric about its centre.
            points.append(inner.position - Vector2(lean, lean) * 0.5)
            points.append(Vector2(inner.end.x, inner.position.y))
            points.append(inner.end + Vector2(lean, lean) * 0.5)
            points.append(Vector2(inner.position.x, inner.end.y))
        _:
            # Normal and the warp share the square. The warp's grid is drawn
            # over it, which is what tells the two apart.
            points.append(inner.position)
            points.append(Vector2(inner.end.x, inner.position.y))
            points.append(inner.end)
            points.append(Vector2(inner.position.x, inner.end.y))
    points.append(points[0])
    return points


## The mirrored glyph's diagonal, the line the two moved corners share, which
## is what tells its outline from a square seen at a slant.
static func _diagonal(box: Rect2) -> PackedVector2Array:
    var inset := box.size * 0.24
    var inner := Rect2(box.position + inset, box.size - inset * 2.0)
    return PackedVector2Array([inner.position, inner.end])


## The warp glyph's cross, the two lines that make its square a nine-point mesh.
static func _grid_lines(box: Rect2) -> Array[PackedVector2Array]:
    var inset := box.size * 0.24
    var inner := Rect2(box.position + inset, box.size - inset * 2.0)
    var centre := inner.get_center()
    return [
        PackedVector2Array([Vector2(inner.position.x, centre.y), Vector2(inner.end.x, centre.y)]),
        PackedVector2Array([Vector2(centre.x, inner.position.y), Vector2(centre.x, inner.end.y)]),
    ]
