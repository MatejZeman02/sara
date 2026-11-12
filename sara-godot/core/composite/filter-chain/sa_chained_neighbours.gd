## The chunks around one that a neighbourhood pass gathers, as the records before
## it in the same chain left them, for a chain where one of those records reads
## the whole node.
##
## A neighbourhood pass reads its own chunk out of the scratch the records before
## it wrote, and the chunks beside it as the node stores them. After a record
## that reads a texel alone that costs nothing, since such a record changes a
## texel where it stands. After a record that reads the whole node it draws a
## line at every chunk edge, because such a record moves paint: Mirror then a
## ripple on one Effect Layer showed each chunk's edge reading the next chunk's
## unmirrored paint. So for such a chain the records before the pass are run
## again over the strip of each neighbour its halo reads, here, and the pass
## reads those strips instead.
##
## Only the strips, each grown by the reach of the records before, and only for
## the eight chunks around, which is what the padding gathers on a canvas that
## does not wrap. A canvas that wraps reads its far side as the node stores it,
## as an unchained pass does. A chain of two neighbourhood passes and no
## whole-node record keeps that reading too, the one approximation it has.
##
## Its own file because it is one thing the chain keeps, the strips and where
## they stand. The copies and the dispatch are the chain's, handed over, so it
## dispatches nothing of its own.
class_name SaChainedNeighbours
extends RefCounted

## The strips, one chunk per neighbour, held at the neighbour's place beside
## the chunk the gather is for, so the same eight are reused from one chunk to
## the next. Held at the neighbour's own grid position, every gather dropped
## the strips the one before made and made its own, each freeing a texture,
## which drops every uniform set `SaCompute` has cached: showing a large
## painting's group freed 684 that way.
var _halo := SaFilterHalo.new()
## The positions [member _halo] holds a strip for in the current gather, by
## grid position, each the place beside the gather's chunk it is held at.
var _made: Dictionary[Vector2i, Vector2i] = {}
## True while the records before a pass run over a strip, so a pass among them
## reads its neighbours as stored rather than starting a gather of its own.
var _busy: bool = false
var _copy: Callable
var _clear: Callable


## A keeper whose copies and clears are *copy* and *clear*, the chain's own,
## which take `(source, from, target, covered)` and `(target, area)`.
func _init(copy: Callable, clear: Callable) -> void:
    _copy = copy
    _clear = clear


## What the pass at *index* of *passes* reads its neighbours from, by grid
## position, when it works *work* of the chunk at *grid_pos*, *side* texels
## across at *format*. *neighbour* is how the node stores them, answered back
## as it is when no record before the pass reads the whole node. Otherwise each
## strip is copied from *neighbour* and *run* runs the records before over it,
## called as `run(before, grid_pos, region, texture)`.
func around(
    passes: Array, index: int, grid_pos: Vector2i, work: Rect2i, side: int, format: int, neighbour: Callable, run: Callable
) -> Callable:
    var before := passes.slice(0, index)
    if _busy or side != SaChunk.SIZE or not _reads_whole(before):
        return neighbour
    var recorded: SaNeighbourhoodPass = passes[index][0]
    var margin := Vector2i.ONE * recorded.halo_at(side)
    var read := Rect2i(grid_pos * side + work.position - margin, work.size + margin * 2)
    var chunk := Rect2i(Vector2i.ZERO, Vector2i(side, side))
    var strips: Dictionary[Vector2i, Rect2i] = {}
    for dy: int in [-1, 0, 1]:
        for dx: int in [-1, 0, 1]:
            var at := grid_pos + Vector2i(dx, dy)
            var part := read.intersection(Rect2i(at * side, chunk.size))
            if at != grid_pos and part.size.x > 0 and part.size.y > 0:
                var local := Rect2i(part.position - at * side, part.size)
                strips[at] = local.grow(_reach(before, side)).intersection(chunk)
    _made.clear()
    for at: Vector2i in strips:
        _made[at] = at - grid_pos
    _busy = true
    for at: Vector2i in strips:
        var strip: Rect2i = strips[at]
        var texture := _halo.take(_made[at], format)
        var found: Variant = neighbour.call(at)
        var stored: SaTexture = found if found is SaTexture else null
        if stored != null and stored.size == texture.size:
            _copy.call(stored, strip.position, texture, strip)
        else:
            _clear.call(texture, strip)
        run.call(before, at, strip, texture)
    _busy = false
    return _answer.bind(neighbour)


## The strip at *grid_pos* when this gather made one, and *neighbour*'s answer
## there otherwise.
func _answer(grid_pos: Vector2i, neighbour: Callable) -> SaTexture:
    if _made.has(grid_pos):
        return _halo.layer.get_field(_made[grid_pos])
    var stored: Variant = neighbour.call(grid_pos)
    return stored if stored is SaTexture else null


## Whether any of *passes* reads the whole node.
static func _reads_whole(passes: Array) -> bool:
    for pair: Array in passes:
        var held: Variant = pair[0]
        var recorded: SaNeighbourhoodPass = held if held is SaNeighbourhoodPass else null
        if recorded != null and recorded.whole():
            return true
    return false


## How far *passes* read past a texel, their halos added, so a strip run
## through them is computed far enough out for its own texels to be right.
static func _reach(passes: Array, side: int) -> int:
    var reach := 0
    for pair: Array in passes:
        var held: Variant = pair[0]
        var recorded: SaNeighbourhoodPass = held if held is SaNeighbourhoodPass else null
        if recorded != null:
            reach += recorded.halo_at(side)
    return reach
