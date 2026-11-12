## Draws a closed path's paint into a layer's chunks at its exact coverage,
## through `vector_fill.gmacs`, dispatching only the tiles the path reaches.
##
## The renderer every drawn shape shares, the vector layer's objects, a text
## layer's glyphs and a third party's module alike, which reach it as they
## reach any of `core/api`. The path is flattened and resolved once per density
## (`SaVectorOutline`), binned per chunk on the CPU into the chunk's 16 by 16
## tiles, uploaded chunk relative in 32-bit floats, and drawn by one dispatch a
## chunk with one workgroup a tile. Binning runs only when a shape is drawn,
## never during a stroke, and nothing is read back.
##
## A chunk is allocated only where the path covers a tile, so a path drawn over
## empty canvas leaves the layer as sparse as its paint (hard rule 3), and a
## tile the path does not reach is never dispatched (hard rule 2).
@tool
class_name SaVectorFill
extends RefCounted

const SHADER := "vector_fill"
## Texels along a tile's side, the kernel's workgroup.
const TILE := 16

## The tiles the last [method draw] dispatched, each in the layer's texels:
## the chunk's place times its texel size plus the tile's own. For a layer at
## the document's resolution that is document pixels.
var drawn_tiles: Array[Rect2i] = []

var _compute: SaCompute = null
## The buffers of the last draw, held until the next one, since a buffer let go
## of while its dispatch is pending is one the dispatch finds invalid.
var _held: Array[SaCompute.Buffer] = []
## The buffers of the last [method draw_region] into each chunk, by its
## place, held until that chunk is drawn again.
var _held_at: Dictionary[Vector2i, Array] = {}
## The path [method draw_region] drew last and its outline, which the next
## chunk of the same path, or the next redraw of a shape that did not change,
## takes as it is rather than resolving it again. A path is not changed once
## it is drawn.
var _outline_of: SaVectorPath = null
var _outline: SaVectorOutline = null


## A fill dispatches *kernel* when it is given one, which is how fills made
## for each letter of a text layer share a single pipeline, a pipeline per fill
## being slower than the letter. With none the fill makes its own on first use.
func _init(kernel: SaCompute = null) -> void:
    _compute = kernel


## The kernel a fill dispatches, for another fill to share.
static func make_kernel() -> SaCompute:
    return SaCompute.new(SHADER)


## Paints *path* into *layer* in *paint*, a straight colour in the document's
## space whose alpha is its opacity, with the path's own (0, 0) at the
## document pixel *origin*. *draw_seed* is folded into the stochastic rounding
## of a half precision chunk, so the same draw lays the same bits.
func draw(layer: SaLayer, path: SaVectorPath, paint: Color, origin: Vector2i = Vector2i.ZERO, draw_seed: int = 0) -> void:
    drawn_tiles.clear()
    _held.clear()
    if path.is_empty() or GlobalShaderCompiler.get_rd() == null:
        return
    if _compute == null:
        _compute = SaCompute.new(SHADER)
    var outlines: Dictionary[int, SaVectorOutline] = {}
    var side := roundi(SaChunk.SIZE * layer.resolution_scale)
    var outline := _outline_at(outlines, path, side)
    if outline.edge_count() == 0:
        return
    for grid in _grids_under(outline, origin, side):
        var chunk: SaChunk = layer.chunks.get(grid, null)
        var texels := chunk.pixel_size() if chunk != null else side
        var at := _outline_at(outlines, path, texels) if texels != side else outline
        var scale := float(texels) / SaChunk.SIZE
        var bins := Bins.new(at.edges, origin.x * scale - grid.x * texels, origin.y * scale - grid.y * texels, texels)
        if bins.tile_count() == 0:
            continue
        chunk = layer.get_or_create_chunk(grid)
        _dispatch(chunk.albedo(), bins, paint, draw_seed)
        for t in bins.tile_count():
            var tile := Vector2i(bins.tiles[t * Bins.INTS], bins.tiles[t * Bins.INTS + 1])
            drawn_tiles.append(Rect2i(grid * texels + tile * TILE, Vector2i(TILE, TILE)))


## Paints *path* into *chunk* over *region* alone, what a drawn layer's
## recipe is asked for: *region* in document pixels, inside the chunk whose
## square holds its corner and a whole number of tiles there, so a tile is
## dispatched only where it lies inside *region* and no pixel outside it
## changes. *paint*, *origin* and *draw_seed* are [method draw]'s.
func draw_region(
    chunk: SaChunk, region: Rect2i, path: SaVectorPath, paint: Color, origin: Vector2i = Vector2i.ZERO, draw_seed: int = 0
) -> void:
    drawn_tiles.clear()
    if chunk == null or path.is_empty() or GlobalShaderCompiler.get_rd() == null:
        return
    if _compute == null:
        _compute = SaCompute.new(SHADER)
    var texels := chunk.pixel_size()
    var scale := float(texels) / SaChunk.SIZE
    if path != _outline_of or _outline == null or _outline.density != scale:
        _outline_of = path
        _outline = SaVectorOutline.of(path, scale)
    var outline := _outline
    if outline.edge_count() == 0:
        return
    var grid := Vector2i(floori(region.position.x / float(SaChunk.SIZE)), floori(region.position.y / float(SaChunk.SIZE)))
    var local := Rect2i(Vector2i(Vector2(region.position - grid * SaChunk.SIZE) * scale), Vector2i(Vector2(region.size) * scale))
    @warning_ignore("integer_division")
    var rows := Vector2i(local.position.y / TILE, ceili(local.end.y / float(TILE)) - 1)
    var bins := Bins.new(outline.edges, origin.x * scale - grid.x * texels, origin.y * scale - grid.y * texels, texels, rows)
    bins.keep_within(local)
    if bins.tile_count() == 0:
        return
    # Each chunk keeps its last buffers, since a redraw dispatches into several
    # chunks in turn and the earlier ones are still pending.
    var held := _held.size()
    _dispatch(chunk.albedo(), bins, paint, draw_seed)
    _held_at[grid] = _held.slice(held)
    _held.resize(held)
    for t in bins.tile_count():
        var tile := Vector2i(bins.tiles[t * Bins.INTS], bins.tiles[t * Bins.INTS + 1])
        drawn_tiles.append(Rect2i(grid * texels + tile * TILE, Vector2i(TILE, TILE)))


## The outline of *path* for chunks *texels* across, made once per draw.
static func _outline_at(outlines: Dictionary[int, SaVectorOutline], path: SaVectorPath, texels: int) -> SaVectorOutline:
    if not outlines.has(texels):
        outlines[texels] = SaVectorOutline.of(path, float(texels) / SaChunk.SIZE)
    return outlines[texels]


## Every chunk place the outline's box reaches with its own (0, 0) at
## *origin*, chunks *side* texels across. A texel of slack each way, since the
## box is held in 32-bit floats and a tile the outline misses costs nothing.
static func _grids_under(outline: SaVectorOutline, origin: Vector2i, side: int) -> Array[Vector2i]:
    var scale := float(side) / SaChunk.SIZE
    var box := outline.bounds
    var first := Vector2i(
        floori((box.position.x + origin.x * scale - 1.0) / side), floori((box.position.y + origin.y * scale - 1.0) / side)
    )
    var last := Vector2i(floori((box.end.x + origin.x * scale + 1.0) / side), floori((box.end.y + origin.y * scale + 1.0) / side))
    var grids: Array[Vector2i] = []
    for y in range(first.y, last.y + 1):
        for x in range(first.x, last.x + 1):
            grids.append(Vector2i(x, y))
    return grids


func _dispatch(target: SaTexture, bins: Bins, paint: Color, draw_seed: int) -> void:
    var tiles := SaCompute.Buffer.new(bins.tiles.to_byte_array())
    var segments := bins.segments if not bins.segments.is_empty() else PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
    var edges := SaCompute.Buffer.new(segments.to_byte_array())
    _held.append_array([tiles, edges])
    _compute.use_storage_format(target.format)
    _compute.set_image("canvas", target)
    _compute.set_storage("tiles", tiles.rid)
    _compute.set_storage("edges", edges.rid)
    _compute.set_params({"paint": paint, "seed": draw_seed, "tile_count": bins.tile_count()})
    _compute.dispatch_kernel(SHADER, bins.tile_count(), 1, 1)


## One chunk's tiles: the edges of an outline that cross each, cut to it, and
## its backdrop, the winding at the top of its left side.
##
## An edge left of a pixel adds its whole height inside the pixel's row to the
## pixel's winding, wherever left of it the edge lies, so everything left of a
## tile counts as if it stood upright on the tile's left side. Those upright
## pieces sum to the winding along that side, a number that changes only at a
## few heights. The tile carries that number at its top as its backdrop and,
## for each later change, an upright edge on the side from the change down to
## the tile's foot, which adds exactly the change to every pixel below it. An
## edge on the side, or anywhere left of it, counts as left, one rule
## throughout. Level edges were dropped with the outline, and this needs none:
## a level edge moves the winding along a side only through the edges it
## joins, and those are counted where they end.
class Bins:
    extends RefCounted

    ## Ints a tile takes in [member tiles], as `vector_fill.gmacs` reads them.
    const INTS := 5

    ## Column, row, first edge, edge count and backdrop, per tile.
    var tiles: PackedInt32Array = PackedInt32Array()
    ## Four floats an edge, in the chunk's texels.
    var segments: PackedFloat32Array = PackedFloat32Array()

    ## *edges* in the outline's texels, shifted by *dx*, *dy* into those of a
    ## chunk *side* texels across. *rows*, the first and the last row of tiles
    ## wanted, leaves the rows outside it unbinned, since a tile's winding is
    ## made of the edges in its own row alone.
    func _init(edges: PackedFloat64Array, dx: float, dy: float, side: int, rows: Vector2i = Vector2i(0, 1 << 30)) -> void:
        assert(side % TILE == 0, "A chunk's side is a whole number of tiles")
        @warning_ignore("integer_division")
        var across := side / TILE
        var first_row := maxi(rows.x, 0)
        var last_row := mini(rows.y, across - 1)
        var bands: Array[PackedFloat64Array] = []
        bands.resize(across)
        for b in across:
            bands[b] = PackedFloat64Array()
        @warning_ignore("integer_division")
        for i in edges.size() / 4:
            var x0 := edges[i * 4] + dx
            var y0 := edges[i * 4 + 1] + dy
            var x1 := edges[i * 4 + 2] + dx
            var y1 := edges[i * 4 + 3] + dy
            if minf(x0, x1) >= side:
                continue
            var top := minf(y0, y1)
            var bottom := maxf(y0, y1)
            for b in range(maxi(first_row, floori(top / TILE)), mini(last_row, ceili(bottom / TILE) - 1) + 1):
                bands[b].append_array([x0, y0, x1, y1])
        for b in range(first_row, last_row + 1):
            _bin_band(bands[b], b, across)

    func tile_count() -> int:
        @warning_ignore("integer_division")
        return tiles.size() / INTS

    ## Keeps only the tiles lying inside *local*, in the chunk's texels, a
    ## rectangle on the tile lines. The edges stay where they are, since a
    ## kept tile names its own by their place.
    func keep_within(local: Rect2i) -> void:
        var kept := PackedInt32Array()
        for t in tile_count():
            var corner := Vector2i(tiles[t * INTS], tiles[t * INTS + 1]) * TILE
            if local.encloses(Rect2i(corner, Vector2i(TILE, TILE))):
                kept.append_array(tiles.slice(t * INTS, (t + 1) * INTS))
        tiles = kept

    func _bin_band(band: PackedFloat64Array, row: int, across: int) -> void:
        var y_top := float(row * TILE)
        var y_foot := y_top + TILE
        # Per tile, the edges inside it, and the changes the winding along its
        # left side takes, as pairs of a height and a change.
        var pieces: Array[PackedFloat32Array] = []
        var changes: Array[PackedFloat64Array] = []
        pieces.resize(across)
        changes.resize(across)
        for k in across:
            pieces[k] = PackedFloat32Array()
            changes[k] = PackedFloat64Array()
        @warning_ignore("integer_division")
        for i in band.size() / 4:
            var ax := band[i * 4]
            var ay := band[i * 4 + 1]
            var bx := band[i * 4 + 2]
            var by := band[i * 4 + 3]
            var direction := 1 if by > ay else -1
            # The edge's upper and lower end, whichever way it runs.
            var ux := ax if ay < by else bx
            var uy := minf(ay, by)
            var lx := bx if ay < by else ax
            var ly := maxf(ay, by)
            var top := maxf(uy, y_top)
            var foot := minf(ly, y_foot)
            if foot <= top:
                continue
            var tx := _x_at(ux, uy, lx, ly, top)
            var fx := _x_at(ux, uy, lx, ly, foot)
            var low := minf(tx, fx)
            var high := maxf(tx, fx)
            for k in range(maxi(0, floori(low / TILE)), mini(across - 1, ceili(high / TILE) - 1) + 1):
                _cut_into(pieces[k], float(k * TILE), tx, top, fx, foot, direction)
            for k in range(maxi(0, ceili(low / TILE)), across):
                _note_left_part(changes[k], float(k * TILE), tx, top, fx, foot, direction)
        for k in across:
            var sides := _side_of(changes[k], y_top, y_foot, float(k * TILE))
            var backdrop: int = sides[0]
            var steps: PackedFloat32Array = sides[1]
            if pieces[k].is_empty() and steps.is_empty() and backdrop == 0:
                continue
            @warning_ignore("integer_division")
            tiles.append_array([k, row, segments.size() / 4, (pieces[k].size() + steps.size()) / 4, backdrop])
            segments.append_array(pieces[k])
            segments.append_array(steps)

    ## The part of an edge from (*tx*, *top*) down to (*fx*, *foot*) lying on
    ## or left of the tile side at *left*, noted in *out* as the winding it
    ## adds from its upper end and takes away again at its lower end.
    static func _note_left_part(
        out: PackedFloat64Array, left: float, tx: float, top: float, fx: float, foot: float, direction: int
    ) -> void:
        var from := top
        var to := foot
        if tx > left and fx > left:
            return
        if tx > left or fx > left:
            var crossing := top + (left - tx) * (foot - top) / (fx - tx)
            if tx <= left:
                to = crossing
            else:
                from = crossing
        if to <= from:
            return
        out.append_array([from, direction, to, -direction])

    ## The winding along a tile's left side at *left* from its *changes*: the
    ## backdrop it holds just below the band's top, and an upright edge on the
    ## side from each later change down to the band's foot, one for each unit
    ## the winding moves by, which adds that change to every pixel below it.
    static func _side_of(changes: PackedFloat64Array, y_top: float, y_foot: float, left: float) -> Array:
        var heights: Dictionary[float, int] = {}
        for c in range(0, changes.size(), 2):
            heights[changes[c]] = heights.get(changes[c], 0) + int(changes[c + 1])
        var backdrop := 0
        var steps := PackedFloat32Array()
        for y: float in heights:
            var change: int = heights[y]
            if y <= y_top:
                backdrop += change
                continue
            if y >= y_foot or change == 0:
                continue
            for n in absi(change):
                _append(steps, Vector2(left, y), Vector2(left, y_foot), signi(change))
        return [backdrop, steps]

    ## The piece of an edge from (*tx*, *top*) down to (*fx*, *foot*), running
    ## in *direction*, that lies right of the tile side at *left* and inside
    ## the tile, appended to *out*.
    static func _cut_into(
        out: PackedFloat32Array, left: float, tx: float, top: float, fx: float, foot: float, direction: int
    ) -> void:
        var right := left + TILE
        var from_y := top
        var to_y := foot
        if tx == fx:
            if tx <= left or tx >= right:
                return
        else:
            var at_left := top + (left - tx) * (foot - top) / (fx - tx)
            var at_right := top + (right - tx) * (foot - top) / (fx - tx)
            from_y = maxf(top, minf(at_left, at_right))
            to_y = minf(foot, maxf(at_left, at_right))
        if to_y <= from_y:
            return
        var from_x := clampf(_x_at(tx, top, fx, foot, from_y), left, right)
        var to_x := clampf(_x_at(tx, top, fx, foot, to_y), left, right)
        _append(out, Vector2(from_x, from_y), Vector2(to_x, to_y), direction)

    ## The edge from *upper* down to *lower*, appended running the way
    ## *direction* says.
    static func _append(out: PackedFloat32Array, upper: Vector2, lower: Vector2, direction: int) -> void:
        if direction > 0:
            out.append_array([upper.x, upper.y, lower.x, lower.y])
        else:
            out.append_array([lower.x, lower.y, upper.x, upper.y])

    static func _x_at(ux: float, uy: float, lx: float, ly: float, y: float) -> float:
        if ly == uy:
            return ux
        return ux + (lx - ux) * (y - uy) / (ly - uy)
