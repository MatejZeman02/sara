## A chunk and the paint around it as one texture, the source a neighbourhood
## pass reads.
##
## A blur or a sharpen reads a few texels past the one it writes, so the chunk
## it writes is read with a margin of its neighbours' paint around it.
## `pad_chunk.gmacs` writes that margin in one dispatch rather than a clear, a
## copy of the chunk and a copy of each neighbour, ten dispatches whose CPU
## cost would be most of an Apply and of a filter preview. This class owns that
## kernel, the texture it writes and the edge fill after it.
##
## Past the document's edge the margin reads the nearest texel inside it, once
## a canvas is named, rather than transparent, which would make an opaque
## layer's edge an edge against nothing, a bright rim under a sharpen and a
## dark one under a blur.
## On a panorama, whose left edge meets its right, the margin past either reads
## the other instead, so a blur of the sky has no line where it was cut.
class_name SaChunkPadding
extends RefCounted

## Bit of the push constant's `held` that says the chunk itself is there, after
## one bit for each of the eight neighbours.
const CENTRE_BIT: int = 8

## The padded source the last [method build] wrote, the chunk's side plus the
## margin on either side, kept from one build to the next while the size and
## format stay.
var texture: SaTexture = null
var _pad: SaCompute = null
var _clamp: SaCompute = null


## The padding of the chunk at *grid_pos* for *work*, a rectangle in its own
## pixels, grown by *reach*, at *format*. *center* stands for the chunk over
## *work* alone, and *neighbour* answers the texture of the chunk at a grid
## position or null, read over the part of the grown rectangle that falls on
## it. Everything else reads as transparent, and past *canvas*, the document's
## size or zero for none, as the nearest texel inside it.
##
## **Across the seam.** On an axis *wrapping* joins, x for a panorama, the
## padding past the canvas's edge reads the texels at its far side, the
## position taken modulo the canvas's size, which need not be a multiple of the
## chunk's side. That part is a dispatch of its own with the far side's chunks
## bound, all read through *neighbour*, the chunk itself among them when the
## canvas is one chunk across. An axis that does not wrap clamps as above.
##
## The dispatches cover *work* grown by the margin between
## them, each texel once, and nothing more. A texture of another format than
## *format* is not read, since one set binds every image at one storage format.
##
## *edge* is the chunk's side in texels, 512 on a layer at twice the
## document's resolution, and then *work*, *reach* and *canvas* are in those
## texels too.
func build(
    center: SaTexture,
    neighbour: Callable,
    grid_pos: Vector2i,
    work: Rect2i,
    reach: int,
    format: int,
    canvas: Vector2i,
    edge: int = SaChunk.SIZE,
    wrapping: SaProjection.Wrap = SaProjection.Wrap.NONE
) -> SaTexture:
    var side := Vector2i(edge, edge)
    var padded := side + Vector2i(reach, reach) * 2
    if texture == null or texture.format != format or texture.size != padded:
        texture = SaTexture.new(padded, format)
    var margin := Vector2i(reach, reach)
    var area := Rect2i(work.position, work.size + margin * 2)
    # The document texel the padded texture's first texel stands for.
    var first := grid_pos * edge - margin
    var period := period_of(canvas, wrapping)
    var columns := _runs(first.x + area.position.x, first.x + area.end.x, period.x, grid_pos.x, edge)
    var rows := _runs(first.y + area.position.y, first.y + area.end.y, period.y, grid_pos.y, edge)
    for row: Vector4i in rows:
        for column: Vector4i in columns:
            var piece := Rect2i(column.x - first.x, row.x - first.y, column.y - column.x, row.y - row.x)
            var shift := Vector2i(column.z, row.z)
            if shift == Vector2i.ZERO:
                _gather(center, neighbour, grid_pos, work, piece, margin, format, edge)
                continue
            # The far side's chunks around the one the piece lands on, read
            # whole, since none of them is the chunk *work* is part of.
            var around := Vector2i(column.w, row.w)
            var found: Variant = neighbour.call(around)
            var far: SaTexture = found if found is SaTexture else null
            if far != null and far.size != side:
                far = null
            var shifted := around * edge - first - shift
            _gather(far, neighbour, around, Rect2i(Vector2i.ZERO, side), piece, shifted, format, edge)
    _clamp_edge(area, first, canvas, period)
    return texture


## How far apart the copies of the canvas lie along each axis *wrapping* joins,
## the canvas's own size there, and nought along an axis that does not wrap. A
## *canvas* of zero, no document named, joins nothing.
static func period_of(canvas: Vector2i, wrapping: SaProjection.Wrap) -> Vector2i:
    if canvas.x <= 0 or canvas.y <= 0:
        return Vector2i.ZERO
    if wrapping == SaProjection.Wrap.X:
        return Vector2i(canvas.x, 0)
    if wrapping == SaProjection.Wrap.XY:
        return canvas
    return Vector2i.ZERO


## The run from *start* to *end* along an axis whose canvas is *period* long and
## joins its far edge, cut wherever it crosses an edge of the canvas. Each piece
## is a Vector3i of its start, its end and the shift, a whole number of periods,
## that brings it onto the canvas, nought for the piece on it. A *period* of
## nought is an axis that does not wrap, and the run comes back whole.
static func across(start: int, end: int, period: int) -> Array[Vector3i]:
    var pieces: Array[Vector3i] = []
    if period <= 0:
        pieces.append(Vector3i(start, end, 0))
        return pieces
    var at := start
    while at < end:
        var turn := floori(float(at) / period)
        var stop := mini(end, (turn + 1) * period)
        pieces.append(Vector3i(at, stop, -turn * period))
        at = stop
    return pieces


## [method across], with each piece that is shifted cut again wherever what it
## reads would span more than the three chunks a dispatch binds, which a canvas
## narrower than the halo or a chunk held past the canvas can ask for. Each is a
## Vector4i: the start, the end, the shift and the chunk the reads centre on,
## *own* for a piece on the canvas.
static func _runs(start: int, end: int, period: int, own: int, edge: int) -> Array[Vector4i]:
    var runs: Array[Vector4i] = []
    for piece: Vector3i in across(start, end, period):
        if piece.z == 0:
            runs.append(Vector4i(piece.x, piece.y, 0, own))
            continue
        var at := piece.x
        while at < piece.y:
            var low := floori(float(at + piece.z) / edge)
            var stop := mini(piece.y, (low + 3) * edge - piece.z)
            runs.append(Vector4i(at, stop, piece.z, low + 1))
            at = stop
    return runs


## One dispatch of `pad_chunk` over *piece*, in the padded texture's pixels,
## reading the chunk at *around* and its eight neighbours. *margin* takes a
## padded texel to the centre chunk's own pixels, and *center* is read over
## *work* of it alone.
func _gather(
    center: SaTexture,
    neighbour: Callable,
    around: Vector2i,
    work: Rect2i,
    piece: Rect2i,
    margin: Vector2i,
    format: int,
    edge: int
) -> void:
    if piece.size.x <= 0 or piece.size.y <= 0:
        return
    var side := Vector2i(edge, edge)
    var reads := Rect2i(piece.position - margin, piece.size)
    var bound: Array[SaTexture] = []
    var held := 0
    for dy: int in [-1, 0, 1]:
        for dx: int in [-1, 0, 1]:
            var step := Vector2i(dx, dy)
            if step == Vector2i.ZERO:
                continue
            var part := reads.intersection(Rect2i(step * edge, side))
            var found: SaTexture = null
            if part.size.x > 0 and part.size.y > 0:
                var near: Variant = neighbour.call(around + step)
                found = near if near is SaTexture else null
            var usable := found != null and found.size == side and found.format == format
            if usable:
                held |= 1 << bound.size()
            bound.append(found if usable else null)
    if center != null and center.format == format:
        held |= 1 << CENTRE_BIT
    if _pad == null:
        _pad = SaCompute.new("pad_chunk")
    _pad.use_storage_format(format)
    _pad.set_texture(0, texture.rid)
    # A binding nothing is held at still needs an image, and the one written
    # is never read at the others.
    _pad.set_texture(1, center.rid if held & (1 << CENTRE_BIT) else texture.rid)
    for index in range(bound.size()):
        _pad.set_texture(index + 2, bound[index].rid if bound[index] != null else texture.rid)
    var values := PackedFloat32Array([piece.position.x, piece.position.y, piece.size.x, piece.size.y, margin.x, margin.y])
    values.append_array(PackedFloat32Array([side.x, side.y, work.position.x, work.position.y, work.size.x, work.size.y]))
    values.append_array(PackedFloat32Array([held, 0.0]))
    _pad.set_push_constant_float_array(values)
    _pad.dispatch_kernel("pad_chunk", SaCompute.groups_for(piece.size.x), SaCompute.groups_for(piece.size.y), 1)


## Fills the part of *area*, in the padded texture's pixels, that lies past
## *canvas* with the nearest texel inside it. *first* is the document pixel the
## padded texture's first texel stands for. Nothing is dispatched when *area*
## lies inside the document, which is every chunk but the ones along its edge,
## or when the area misses the document entirely.
##
## An axis *period* names wraps and is never clamped: the inside spans the whole
## of *area* along it, so on a panorama the top and bottom clamp and the seam
## keeps what was read across it, the corners past both the far side's edge
## continued.
func _clamp_edge(area: Rect2i, first: Vector2i, canvas: Vector2i, period: Vector2i = Vector2i.ZERO) -> void:
    if canvas.x <= 0 or canvas.y <= 0:
        return
    var inside := Rect2i(-first, canvas)
    if period.x > 0:
        inside = Rect2i(area.position.x, inside.position.y, area.size.x, inside.size.y)
    if period.y > 0:
        inside = Rect2i(inside.position.x, area.position.y, inside.size.x, area.size.y)
    if inside.encloses(area):
        return
    var held := inside.intersection(area)
    if held.size.x <= 0 or held.size.y <= 0:
        return
    if _clamp == null:
        _clamp = SaCompute.new("clamp_edge")
    _clamp.use_storage_format(texture.format)
    _clamp.set_texture(0, texture.rid)
    var values := PackedFloat32Array([area.position.x, area.position.y, area.size.x, area.size.y])
    values.append_array(PackedFloat32Array([held.position.x, held.position.y, held.size.x, held.size.y]))
    _clamp.set_push_constant_float_array(values)
    _clamp.dispatch_kernel("clamp_edge", SaCompute.groups_for(area.size.x), SaCompute.groups_for(area.size.y), 1)


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # The texture first, while the device is still there, then the
        # computes, whose own PREDELETE frees their pipelines.
        texture = null
        _pad = null
        _clamp = null
