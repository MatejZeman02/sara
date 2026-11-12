## What a gathered node the chain keeps between composites still owes: the
## chunk last copied to each grid position and the positions marked as changed
## since. One stands beside every kept
## [SaNeighbourhoodPass.Whole], and [method owed] is what
## [method SaNeighbourhoodPass.Runner.gather] copies.
##
## Its own file because keeping is the chain's policy and not the door's. The
## gather in `core/api/filter` copies what it is told, and a one-shot tells it
## everything.
class_name SaGatherLedger
extends RefCounted

# Grid position -> the RID of the chunk last copied there.
var _copied: Dictionary[Vector2i, RID] = {}
# The grid positions changed since the last gather, as a set.
var _stale: Dictionary[Vector2i, bool] = {}


## Notes that the chunks at *positions*, a dictionary keyed by grid position,
## changed since the last gather, so the next copies them again.
func mark(positions: Dictionary[Vector2i, bool]) -> void:
    for grid_pos: Vector2i in positions:
        _stale[grid_pos] = true


## Whether the last gather copied exactly *held*, grid position -> the chunk a
## gather copies there, the same positions from the same textures, so a gather
## over it owes only what was marked since.
func covers(held: Dictionary[Vector2i, SaTexture]) -> bool:
    if held.size() != _copied.size():
        return false
    for grid_pos: Vector2i in held:
        if _copied.get(grid_pos, RID()) != (held[grid_pos] as SaTexture).rid:
            return false
    return true


## The positions of *held*, grid position -> the chunk a gather copies there,
## that are owed a copy: every one when *anew* or when a position last copied
## is not in *held*, since the gather clears such a cell only when it copies
## everything, and otherwise the ones marked since, new to the set, or whose
## chunk is another texture now. A position new to the set was a cleared cell
## the copy wholly overwrites, so a stroke that reaches one more chunk copies
## that chunk and not the node. Remembers *held* as copied and forgets the marks.
func owed(held: Dictionary[Vector2i, SaTexture], anew: bool) -> Array:
    var every := anew
    for grid_pos: Vector2i in _copied:
        if every:
            break
        every = not held.has(grid_pos)
    var out: Array = []
    var copied: Dictionary[Vector2i, RID] = {}
    for grid_pos: Vector2i in held:
        var rid: RID = (held[grid_pos] as SaTexture).rid
        if every or _stale.has(grid_pos) or _copied.get(grid_pos, RID()) != rid:
            out.append(grid_pos)
        copied[grid_pos] = rid
    _copied = copied
    _stale.clear()
    return out
