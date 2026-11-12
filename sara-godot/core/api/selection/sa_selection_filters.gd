## The Select menu's operations on the whole selection: invert, feather,
## border, grow and shrink. A sibling of `SaSelection` because these read
## across chunk seams and that file is what stores.
##
## A feather is a box blur run along each axis in turn, a grow is a dilate and a
## shrink an erode, each a running max or min run the same way, and a border is
## the dilate less the erode. Each pass writes fresh chunks from the old ones,
## because a kernel cannot read the texel it is overwriting, and reads its
## neighbour across the seam through the `before` and `after` bindings, with a 1
## by 1 zero where there is no neighbour so the picture ends where the selection
## does. The passes run over the selection's bounds grown by the radius and
## nothing else, which is hard rule 2 for an operation that is about the edge.
##
## On a document whose kind wraps, every one of the four reads across the
## canvas's own seam as well, the one [Seam] finds, so a feather, a grow, a
## border or a shrink of a region that reaches one edge carries on from the
## other, and the seam is no edge to it.
class_name SaSelectionFilters
extends RefCounted

## What a filter pass does with the texels in its window.
enum Op { BLUR, DILATE, ERODE }

## Wider than this and a texel's window would reach past the neighbour into
## the chunk beyond, which the kernels do not read.
const MAX_RADIUS: int = 120


## Everything selected becomes unselected and the other way round, over the
## canvas. What inverts to nothing is dropped, because a
## selection of nothing clips every dab to nothing with no ants to say so. With
## no selection everything was selected already, so that invert changes
## nothing, and a whole selection inverts to no selection as one undo step.
##
## Whether a whole one went is measured afterwards on the GPU, four ints back,
## the read `SaSelection.measure_bounds` makes for the wand. This is a menu
## command and not a stroke, so hard rule 1 is not in it.
static func invert(selection: SaSelection, canvas_size: Vector2i) -> void:
    if not selection.active:
        return
    var canvas := Rect2i(Vector2i.ZERO, canvas_size)
    # A chunk the selection does not hold was fully unselected, so its inverse
    # is a chunk that is fully selected and no kernel has anything to do there.
    # The walk asks for a chunk immediately before dispatching it, so making
    # that one here and answering null is the whole of the else branch. A
    # chunk the selection holds is inverted in place, so it is asked for
    # through `own_chunk`, which copies it first inside a change.
    var chunk_at := func(grid_pos: Vector2i) -> SaChunk:
        if selection.chunks.has(grid_pos):
            return selection.own_chunk(grid_pos)
        selection.chunks[grid_pos] = selection.make_chunk(1.0)
        return null
    selection.walk().run("invert", canvas, chunk_at, _region_push)
    if selection.measure_bounds().size == Vector2i.ZERO:
        selection.drop_inverted_whole(canvas_size)
        return
    selection.bounds = canvas
    selection.changed.emit()


## The radius in pixels a stored feather fraction means on a document whose
## `SaDocument.brush_side` is *side*.
##
## The selection tools keep their Feather as a fraction of that side, the
## scheme the brush radius already uses, so one setting is one visible softness
## whatever the document was upgraded to, and a crop, which keeps the side,
## keeps the softness in pixels. The clamp is the kernel's reach and not a
## preference, so a large canvas stops getting softer at `MAX_RADIUS` rather
## than at the fraction's own ceiling.
static func feather_radius(fraction: float, side: float) -> int:
    return clampi(roundi(fraction * side), 0, MAX_RADIUS)


## Softens the edge over *radius* pixels each way. A box blur along each axis
## in turn, so the profile is a tent rather than a gaussian, which is close
## enough for an edge and costs two passes.
##
## **The radius may carry a fraction.** The texel one past its whole part on
## either side counts by the fraction, so 2.5 lays an edge between the ones 2
## and 3 lay, and the selection's box grows by the whole texels that reaches.
## A whole radius sums as it always did. The Select menu's Feather hands in
## whole pixels through [method feather_radius], and the harness's `select`
## step hands on what the scenario asked for.
##
## **On a document whose kind wraps, the blur reads across the seam.** The
## caller hands in the document's *wrapping*, and the texels past one edge are
## the other edge's, so a selection that reaches the seam softens there as it
## does in the canvas's middle, and the part of the reach past the edge is
## folded onto the far side rather than cut off. A flat canvas leaves it at
## [constant SaProjection.Wrap.NONE], and the blur reads past its edge the
## edge's own texels, so a selection that meets the edge keeps its coverage
## there and one that stops short of it fades over the radius.
static func feather(
    selection: SaSelection, radius: float, canvas_size: Vector2i, wrapping: SaProjection.Wrap = SaProjection.Wrap.NONE
) -> void:
    if not selection.active or radius <= 0.0:
        return
    var r := minf(radius, MAX_RADIUS)
    var seam := Seam.new(canvas_size, wrapping)
    var reach := selection.bounds.grow(ceili(r))
    var held := SaTyped.chunks(selection.chunks)
    var across := _pass(selection, held, Op.BLUR, r, reach, true, seam)
    selection.chunks = _pass(selection, across, Op.BLUR, r, reach, false, seam)
    selection.bounds = Seam.hull(seam.fold(reach))
    selection.changed.emit()


## Replaces the selection with a band *radius* pixels each way around its
## edge: the selection dilated less the selection eroded. On a document whose
## kind wraps both read across the seam, as [method feather] does.
static func border(
    selection: SaSelection, radius: int, canvas_size: Vector2i, wrapping: SaProjection.Wrap = SaProjection.Wrap.NONE
) -> void:
    if not selection.active or radius <= 0:
        return
    var r := mini(radius, MAX_RADIUS)
    var seam := Seam.new(canvas_size, wrapping)
    var reach := selection.bounds.grow(r)
    var held := SaTyped.chunks(selection.chunks)
    var dilated := _pass(selection, _pass(selection, held, Op.DILATE, r, reach, true, seam), Op.DILATE, r, reach, false, seam)
    var eroded := _pass(selection, _pass(selection, held, Op.ERODE, r, reach, true, seam), Op.ERODE, r, reach, false, seam)
    var band: Dictionary[Vector2i, SaChunk] = {}
    var chunk_at := func(grid_pos: Vector2i) -> SaChunk:
        if not dilated.has(grid_pos):
            return null
        var chunk := selection.make_chunk()
        band[grid_pos] = chunk
        return chunk
    var bindings := func(grid_pos: Vector2i) -> Dictionary[int, Variant]:
        return {
            SaSelection.BINDING_BEFORE: _field_of(dilated, grid_pos),
            SaSelection.BINDING_AFTER: _field_of(eroded, grid_pos),
        }
    var pieces := seam.fold(reach)
    for each: Rect2i in pieces:
        selection.walk().run("combine", each, chunk_at, _region_push, bindings)
    selection.chunks = band
    selection.bounds = Seam.hull(pieces)
    selection.changed.emit()


## Moves the edge *radius* pixels outward, so a wand selection that stopped at
## the opaque core of a soft stroke takes in its fringe. A running max along
## each axis in turn, so the window is a square the way Feather's is, and a
## square corner stays square rather than rounding off. With no selection
## everything is selected already, and there is nothing to grow. On a document
## whose kind wraps the max reads across the seam, so an edge that reaches it
## moves outward on the far side, as [method feather] does.
static func grow(
    selection: SaSelection, radius: int, canvas_size: Vector2i, wrapping: SaProjection.Wrap = SaProjection.Wrap.NONE
) -> void:
    if not selection.active or radius <= 0:
        return
    var r := mini(radius, MAX_RADIUS)
    var seam := Seam.new(canvas_size, wrapping)
    var reach := selection.bounds.grow(r)
    var held := SaTyped.chunks(selection.chunks)
    selection.chunks = _pass(selection, _pass(selection, held, Op.DILATE, r, reach, true, seam), Op.DILATE, r, reach, false, seam)
    selection.bounds = Seam.hull(seam.fold(reach))
    selection.changed.emit()


## Moves the edge *radius* pixels inward, a running min the way [method grow]
## is a running max. The canvas edge counts as unselected, so a selection that
## reaches it shrinks away from it too, Select All included. On a document whose
## kind wraps the seam is no edge: the min reads across it, so a selection that
## runs over the seam keeps it, and only an edge that ends the canvas counts.
##
## The vertical pass runs over the canvas less *radius* at every side that
## ends it, and a fresh chunk is zero wherever no pass wrote. That is what
## makes such an edge read as unselected on all four sides alike: Select All
## fills its last row and column of chunks past the canvas, so a read across
## the right edge of a flat canvas that is not a multiple of 256 finds ones
## there, where a read across the left edge finds no chunk and so a zero. A
## read across a seam takes the first column's texels instead, never the ones
## past the canvas. The horizontal pass covers the whole canvas the selection
## spans, because a texel kept by the vertical pass reads rows up to *radius*
## above and below it.
##
## What is left is measured on the GPU, four ints back, because an erode can
## take any part of the shape and the old box says nothing about which. A
## chunk the measure no longer reaches holds only zeros and goes, and a shrink
## past the middle of every part leaves no chunk at all and so no selection,
## dropped the way the wand drops one, inside the caller's undo step.
static func shrink(
    selection: SaSelection, radius: int, canvas_size: Vector2i, wrapping: SaProjection.Wrap = SaProjection.Wrap.NONE
) -> void:
    if not selection.active or radius <= 0 or selection.chunks.is_empty():
        return
    var before := selection.hold()
    var r := mini(radius, MAX_RADIUS)
    var seam := Seam.new(canvas_size, wrapping)
    # An erode writes nothing outside what was selected, so neither pass runs
    # past the old box.
    var across := selection.bounds.intersection(Rect2i(Vector2i.ZERO, canvas_size))
    var kept := across.intersection(seam.inset(r))
    var held := SaTyped.chunks(selection.chunks)
    selection.chunks = _pass(selection, _pass(selection, held, Op.ERODE, r, across, true, seam), Op.ERODE, r, kept, false, seam)
    var left := selection.measure_bounds()
    for grid_pos: Vector2i in selection.chunks.keys():
        if not left.intersects(SaSelection.chunk_rect(grid_pos)):
            selection.chunks.erase(grid_pos)
    selection.bounds = left
    if not selection.drop_if_empty(before):
        selection.changed.emit()


## One pass of *op* over *source*, horizontal or vertical, into fresh chunks
## covering every chunk *reach* touches. The neighbours are found across the
## *seam*, and *reach*, which may pass the canvas's edge, is folded onto the
## canvas by it, or cut at the edge of a flat one.
##
## The horizontal pass is cut *radius* rows, rounded up, past the top and the
## bottom of a flat canvas rather than at them. It runs first in every caller,
## and the vertical pass reads that many rows above and below each texel it
## writes, or a row the horizontal pass never wrote would read as unselected
## there, and a selection that runs past the canvas would fade at its top and
## bottom, where the horizontal pass reads the selection past the left and the
## right as it holds it. A shrink cuts its reach at the canvas before it comes here, so it
## keeps counting the canvas's edge as unselected.
##
## A blur reads past a flat canvas's edge the edge's own texels, through
## [SaFeatherEdge], so a selection that meets the edge stays whole there rather
## than fading against it, and one that stops short of it still fades. A
## dilate and an erode read what the selection holds, which a border needs.
static func _pass(
    selection: SaSelection,
    source: Dictionary[Vector2i, SaChunk],
    op: Op,
    radius: float,
    reach: Rect2i,
    horizontal: bool,
    seam: Seam
) -> Dictionary[Vector2i, SaChunk]:
    var out: Dictionary[Vector2i, SaChunk] = {}
    var kernel := "filter_h" if horizontal else "filter_v"
    var step := Vector2i(1, 0) if horizontal else Vector2i(0, 1)
    # A pass writes fresh chunks because a kernel cannot read the texel it is
    # overwriting, so the chunk the walk dispatches into is made here and kept
    # by the caller. There is nothing to skip: every position the reach touches
    # gets one.
    var chunk_at := func(grid_pos: Vector2i) -> SaChunk:
        var chunk := selection.make_chunk()
        out[grid_pos] = chunk
        return chunk
    var axis := 0 if horizontal else 1
    # `w` or `h` is where this chunk's row or column meets the next chunk's, and
    # `x` or `y` where the one before's ends, which differ from a whole chunk
    # only at a seam of a canvas that wraps and are handed in for every chunk.
    # A blur carries the selection on past a flat canvas's edge as it stands
    # there, and a dilate or an erode reads past it what the selection holds.
    var edge := SaFeatherEdge.new(source, seam._canvas, axis, op == Op.BLUR and seam.is_flat(axis))
    var push := func(grid_pos: Vector2i, local: Rect2i, start: Vector2i) -> PackedFloat32Array:
        var params := _region_push(grid_pos, local, start)
        params[7] = float(radius)
        params[8] = float(op)
        params[2 + axis] = float(edge.length(grid_pos, seam.length(grid_pos, axis)))
        params[axis] = float(seam.length(seam.beside(grid_pos, -step), axis))
        params[3 - axis] = float(edge.after_length(grid_pos))
        return params
    # The neighbours across the seam, which is why the bindings are answered per
    # stop rather than once: a 1 by 1 zero stands in where there is no
    # neighbour, so the picture ends where the selection does.
    var beside := func(grid_pos: Vector2i, by: int) -> SaTexture:
        if edge.is_past(grid_pos, by):
            return edge.strip(grid_pos, by)
        return _field_of(source, seam.beside(grid_pos, step * by))
    var bindings := func(grid_pos: Vector2i) -> Dictionary[int, Variant]:
        return {
            SaSelection.BINDING_BEFORE: beside.call(grid_pos, -1),
            SaSelection.BINDING_SELF: _field_of(source, grid_pos),
            SaSelection.BINDING_AFTER: beside.call(grid_pos, 1),
        }
    for each: Rect2i in seam.fold(reach, Vector2i(0, ceili(radius)) if horizontal else Vector2i.ZERO):
        selection.walk().run(kernel, each, chunk_at, push, bindings)
    return out


static func _field_of(chunks: Dictionary[Vector2i, SaChunk], grid_pos: Vector2i) -> SaTexture:
    var chunk: SaChunk = chunks.get(grid_pos, null)
    return chunk.field(SaSelection.FIELD) if chunk != null else null


## The push constant for a kernel that runs over a region: the shape words
## unused, the dispatch's own origin in slots 5 and 6, and the region's end in
## the last two. The shape [SaChunkWalk] hands every stop.
static func _region_push(_grid_pos: Vector2i, local: Rect2i, start: Vector2i) -> PackedFloat32Array:
    return PackedFloat32Array(
        [
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            float(start.x),
            float(start.y),
            0.0,
            0.0,
            0.0,
            float(local.end.x),
            float(local.end.y),
        ]
    )


## Where a canvas whose kind wraps meets its far edge, for a pass that reads
## across it. A flat canvas has no seam, and every answer here is then the
## plain one: the next chunk along, a whole chunk long, and a reach cut at the
## canvas's edge.
class Seam:
    extends RefCounted

    var _canvas: Vector2i
    ## Chunks across and down.
    var _grid: Vector2i
    ## One along an axis whose edges meet, nought along one whose do not.
    var _wraps: Vector2i

    func _init(canvas_size: Vector2i, wrapping: SaProjection.Wrap) -> void:
        var side := float(SaChunk.SIZE)
        _canvas = canvas_size
        _grid = Vector2i(ceili(canvas_size.x / side), ceili(canvas_size.y / side))
        _wraps = Vector2i(1 if wrapping != SaProjection.Wrap.NONE else 0, 1 if wrapping == SaProjection.Wrap.XY else 0)

    ## The chunk *by* away from *grid_pos*, the far end of the row or the
    ## column past the seam of an axis that wraps.
    func beside(grid_pos: Vector2i, by: Vector2i) -> Vector2i:
        var next := grid_pos + by
        for axis in 2:
            if _wraps[axis] != 0:
                next[axis] = posmod(next[axis], _grid[axis])
        return next

    ## How far the row, *axis* 0, or the column, *axis* 1, of the chunk at
    ## *grid_pos* runs before the next chunk's begins: the canvas's edge for the
    ## last column or row of an axis that wraps, and a whole chunk otherwise.
    ##
    ## Never nought, which the kernel reads as the size of the texture bound as
    ## `self`. A chunk the source does not hold is bound as a 1 by 1 zero, so
    ## with a nought a pass over one, which a selection whose box spans a chunk
    ## it does not hold makes, would read the next chunk's selection a texel
    ## along and lay a copy of it where nothing was selected.
    func length(grid_pos: Vector2i, axis: int) -> int:
        if _wraps[axis] == 0 or grid_pos[axis] != _grid[axis] - 1:
            return SaChunk.SIZE
        return _canvas[axis] - grid_pos[axis] * SaChunk.SIZE

    ## Whether the canvas ends along *axis*, 0 across and 1 down, rather than
    ## its edges meeting.
    func is_flat(axis: int) -> bool:
        return _wraps[axis] == 0

    ## The canvas less *by* at every edge that ends it, an axis whose edges
    ## meet keeping its whole length, which is where a shrink can keep a texel.
    func inset(by: int) -> Rect2i:
        var margin := Vector2i(by, by) * (Vector2i.ONE - _wraps)
        return Rect2i(margin, _canvas - margin * 2)

    ## The rectangles on the canvas that *rect* covers, which may pass its
    ## edge: folded across the seam of an axis that wraps and cut at the edge of
    ## one that does not, no two of them in one chunk, since a pass makes one
    ## fresh chunk for each it reaches. *past* is how far beyond the edge of an
    ## axis that does not wrap the cut falls, along each axis.
    func fold(rect: Rect2i, past: Vector2i = Vector2i.ZERO) -> Array[Rect2i]:
        var rects: Array[Rect2i] = []
        for across: Vector2i in _spans(rect.position.x, rect.end.x, 0, past.x):
            for down: Vector2i in _spans(rect.position.y, rect.end.y, 1, past.y):
                rects.append(Rect2i(across.x, down.x, across.y - across.x, down.y - down.x))
        return rects

    ## The smallest rectangle holding every one of *rects*.
    static func hull(rects: Array[Rect2i]) -> Rect2i:
        var out := Rect2i()
        for each: Rect2i in rects:
            out = each if out.size == Vector2i.ZERO else out.merge(each)
        return out

    ## The run from *start* to *end* along *axis*, on the canvas, as pieces of
    ## Vector2i(start, end), or *past* beyond its edge if the axis does not
    ## wrap. Two pieces in one chunk are joined into the span between them.
    func _spans(start: int, end: int, axis: int, past: int) -> Array[Vector2i]:
        var span := _canvas[axis]
        var pieces: Array[Vector2i] = []
        if _wraps[axis] == 0 or end - start >= span:
            var low := maxi(start, -past) if _wraps[axis] == 0 else 0
            var high := mini(end, span + past) if _wraps[axis] == 0 else span
            if high > low:
                pieces.append(Vector2i(low, high))
            return pieces
        var at := start
        while at < end:
            var turn := floori(float(at) / span)
            var stop := mini(end, (turn + 1) * span)
            pieces.append(Vector2i(at - turn * span, stop - turn * span))
            at = stop
        pieces.sort()
        var joined: Array[Vector2i] = []
        for piece: Vector2i in pieces:
            var last := joined.size() - 1
            if last >= 0 and floori((joined[last].y - 1.0) / SaChunk.SIZE) >= floori(float(piece.x) / SaChunk.SIZE):
                joined[last] = Vector2i(joined[last].x, maxi(joined[last].y, piece.y))
            else:
                joined.append(piece)
        return joined
