## The active tier's scratch textures, one slot per touched chunk of the
## composite pass in hand, a class of its own because they are state
## with one rule of their own: who gets which texture, and when a texture is
## given back. `SaCompositeWalk` holds them, since only the walk reads them.
##
## A single reused texture cannot be pre-cleared for more than one chunk at a
## time, since the second chunk's clear would land on top of the first chunk's
## own paint, so every touched chunk gets its own slot and the clears share one
## compute list. A pass is walked in runs of `SaCompositor.SCRATCH_RUN` chunks,
## so no pool ever holds more slots than that.
##
## Allocation only. The compositor clears whatever it is handed, through
## `clear_scratch_batch`, before anything reads it.
class_name SaScratchPools
extends RefCounted

## Where the active layer and the live stroke over it meet, per slot. A slot
## is as fine as the stroke it holds, twice a chunk across under a layer at
## 2.0, so the stroke and the layer meet at the layer's own detail and the
## display chunks of `SaDetailView` show them at it.
var stroke: Array[SaTexture] = []
## One pool per isolated group level around the active layer: the intermediate
## target each scope composites into before it joins its parent.
var scopes: Array = []
## One scratch per depth of isolated groups a display chunk's walk composites
## afresh from their members, where a cache averaged a layer at 2.0.
var groups: Array[SaTexture] = []
## How many texels along a document pixel every slot has at least: 1 for the
## output's pools, `SaDetailView.DENSITY` for a display chunk's.
var _density: float = 1.0


func _init(density: float = 1.0) -> void:
    _density = density


## The stroke scratch at *slot*, at *format*, *density* texels along a
## document pixel.
func stroke_slot(slot: int, format: int, density: float = 1.0) -> SaTexture:
    return _slot(stroke, slot, format, density)


## The scratch for an isolated group at *depth*, at *format*.
func group_slot(depth: int, format: int) -> SaTexture:
    return _slot(groups, depth, format)


## The scratch at *slot* for scope *level*, at *format*.
func scope_slot(level: int, slot: int, format: int) -> SaTexture:
    while scopes.size() <= level:
        scopes.append([])
    var pool: Array = scopes[level]
    return _slot(pool, slot, format)


## Drops every scope level from *depth* up. A level no pass reaches any more is
## dropped when the pass ends, so a group that stops being isolated hands its
## pool back.
func keep_levels(depth: int) -> void:
    if scopes.size() > depth:
        scopes.resize(depth)


## The texture of *pool* at *slot*, growing the pool and allocating there when
## it has none yet or the format or the density changed.
func _slot(pool: Array, slot: int, format: int, density: float = 1.0) -> SaTexture:
    while pool.size() <= slot:
        pool.append(null)
    var scratch: SaTexture = pool[slot]
    var across := int(SaChunk.SIZE * maxf(density, _density))
    if scratch == null or scratch.format != format or scratch.size.x != across:
        scratch = SaTexture.new(Vector2i(across, across), format)
        pool[slot] = scratch
    return scratch


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # The textures go while the device is still there.
        stroke.clear()
        scopes.clear()
        groups.clear()
