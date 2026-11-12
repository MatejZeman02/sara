## The descriptor sets one `SaCompute` has built, kept by the bindings that went
## into them.
##
## One of five objects `SaCompute` holds, each a concern with nothing public in
## it, so no caller sees which one answers. Reached by path rather than by a
## `class_name`, the way every half of the compiler is, because a class name
## resolves only after the editor rescans its class cache.
##
## **One set per instance would miss on nearly every dispatch.** `composite_chunk`
## rebinds both bindings for every chunk and the brush rebinds per chunk per dab,
## so "has anything changed since last time" answers yes on almost every dispatch
## and each one would pay a `uniform_set_create` plus a deferred free. The bindings repeat
## constantly, they just never repeat twice in a row, which is the one pattern a
## compare-against-last check cannot see. So a set is keyed by everything that
## went into it and kept, and an LRU holds the count down.
##
## **A bind writes three numbers and nothing else.** What each slot
## holds is its type and two ids, written straight into the key the cache is
## asked with, so the key is never built again for a dispatch and no
## `RDUniform` is made until a set is. Before, a bind that moved made an
## `RDUniform`, copied its ids twice to compare it, and every dispatch after it
## built the key afresh from those objects: 17 µs of GDScript a bind and a
## dispatch over cached sets in one measurement, where the device's own calls take 1.
## The seasons painting's `day` group makes thousands of such dispatches a
## frame, which is what a painter saw as chunks appearing one by one.
##
## **The owner writes nothing here.** `SaCompute` holds one of these and asks it,
## because the cache's own fields are written by the cache, as every private
## member is written by its own class. `refresh` and `gpu_id` are public because
## the dispatch reads them every frame and a test reads them too, and both are
## still set only from inside.
extends RefCounted

## How many sets one instance keeps.
##
## A pass that walks every chunk of a layer, the layer thumbnail above all, builds
## one set a chunk, so the cache has to hold one layer's chunks or the walk evicts
## its own head and misses on every dispatch. 64 holds a 1080p layer, 40 chunks
## of 256, and cycles on a 4K one of 135, where a stroke builds a set for nearly
## every thumbnail dispatch. 512 holds one layer of 512 chunks, a canvas of
## about 8K by 4K. A larger canvas cycles on its thumbnail walk again, which
## costs some frame time and is not wrong. A size that follows the chunk count
## would need this class to see the document, and a set is a descriptor, small
## beside the chunk it binds, so a fixed ceiling is the simpler trade.
const UNIFORM_SET_CACHE_SIZE: int = 512

## The numbers a slot takes in [member _key]: its type plus one, so an empty
## slot reads 0 where a sampler's type is 0 itself, and the ids of its first two
## RIDs.
const SLOT_WIDTH: int = 3

## The `RDUniform`s every instance has made, which only a set the cache did not
## hold makes. A suite reads it to say a run of dispatches over the same
## textures makes none after the first.
static var uniforms_built: int = 0

## The set the next dispatch binds, or an invalid RID when there is none to bind.
var gpu_id: RID

## Whether the bindings have moved since [member gpu_id] was built. True to begin
## with, because nothing has been built yet.
var refresh: bool = true

## The device every set is created on and freed against, or null in a run that
## has none.
var _rd: RenderingDevice = null

## What identifies a set: the shader it was built against at 0, then
## [constant SLOT_WIDTH] numbers a binding slot. Written in place by
## [method put] and by [method rebuild]'s shader, and handed to the dictionary
## as it stands, so a lookup builds nothing.
##
## The shader has to be in it. `use_storage_format` swaps to the F16 build of the
## same kernel, and a set built against one shader is not valid for the other.
## An empty slot reads zeros, so `[a, -, b]` and `[a, b, -]` are different keys
## rather than the same one.
var _key: PackedInt64Array = PackedInt64Array([0])

## Sets already built, keyed by a copy of [member _key] as it stood, in use order
## with the oldest first. A Dictionary keeps its insertion order, so a set moved
## to the end when it is used again leaves the oldest as the first key.
var _sets: Dictionary[PackedInt64Array, Kept] = {}

## The uses counted so far, which [class Kept] stamps. A hit moves its set to
## the young end only once half the cache has been used since its stamp, so a
## walk that finds its sets again pays one lookup a dispatch and not an erase
## and an insert. A set used within the last half is in the young half already,
## and the oldest key stays one nobody has used for half a cache at least.
var _uses: int = 0

## The texture epoch the cache was built against. See SaTexture.epoch.
var _epoch: int = -1


func _init(rd: RenderingDevice) -> void:
    _rd = rd


## Says the bindings have moved, so the next dispatch builds or finds its set
## again. What the owner calls when it reloads its pipelines, because a set is
## created against a specific shader RID.
func mark_dirty() -> void:
    refresh = true


## Takes a uniform of *type* over *first* and *second* as what is bound at
## *binding*. *second* is the empty RID for a slot of one id.
func put(binding: int, type: int, first: RID, second: RID = RID()) -> void:
    var at := 1 + binding * SLOT_WIDTH
    if _key.size() < at + SLOT_WIDTH:
        _key.resize(at + SLOT_WIDTH)
    _key[at] = type + 1
    _key[at + 1] = first.get_id()
    _key[at + 2] = second.get_id()
    refresh = true


## Whether the slot at *binding* holds a uniform of *type* over *first* and
## *second*, which is a bind that would change nothing. *second* is the empty
## RID for a slot of one id, and the texture of a sampled slot, whose first id
## is the sampler.
func holds(binding: int, type: int, first: RID, second: RID = RID()) -> bool:
    var at := 1 + binding * SLOT_WIDTH
    if _key.size() < at + SLOT_WIDTH:
        return false
    return _key[at] == type + 1 and _key[at + 1] == first.get_id() and _key[at + 2] == second.get_id()


## Puts the set for the bindings currently held into [member gpu_id], building it
## only if it is new, and answers how many the device was asked to create, which
## is what `SaCompute.uniform_sets` counts.
##
## [member gpu_id] comes back invalid when the shader did not compile, which the
## dispatch reads as "bind nothing", exactly as an uncached dispatch would.
func rebuild(shader_id: RID) -> int:
    refresh = false
    if not shader_id.is_valid() or _rd == null:
        gpu_id = RID()
        return 0

    # A freed texture takes every uniform set that referenced it, so the whole
    # cache is suspect rather than one entry of it. Dropping it wholesale is the
    # coarse half of the trade: it costs a warm-up frame after a resize or a
    # File > New, and it costs nothing at all during a stroke.
    if _epoch != SaTexture.epoch:
        drop_all()
        _epoch = SaTexture.epoch

    _key[0] = shader_id.get_id()
    _uses += 1
    var kept: Kept = _sets.get(_key)
    if kept != null and _rd.uniform_set_is_valid(kept.rid):
        if (_uses - kept.used) * 2 > UNIFORM_SET_CACHE_SIZE:
            _sets.erase(_key)
            _sets[_key.duplicate()] = kept
        kept.used = _uses
        gpu_id = kept.rid
        return 0

    var built := _rd.uniform_set_create(_uniforms(), shader_id, 0)
    if not built.is_valid():
        gpu_id = RID()
        return 1

    if kept != null:
        _sets.erase(_key)
    _sets[_key.duplicate()] = Kept.new(built, _uses)
    while _sets.size() > UNIFORM_SET_CACHE_SIZE:
        _evict(_oldest())
    gpu_id = built
    return 1


## Lets go of every cached set. The RIDs are queued rather than freed here,
## because a set may still be referenced by a compute list already submitted.
func drop_all() -> void:
    for key: PackedInt64Array in _sets:
        var doomed: RID = _sets[key].rid
        if doomed.is_valid() and _rd != null and _rd.uniform_set_is_valid(doomed):
            GlobalShaderCompiler.queue_free_uniform_set(doomed)
    _sets.clear()
    gpu_id = RID()


## The uniforms [member _key] holds, the array `uniform_set_create` is handed,
## made only when a set is.
func _uniforms() -> Array[RDUniform]:
    var made: Array[RDUniform] = []
    @warning_ignore("integer_division")
    var slots := (_key.size() - 1) / SLOT_WIDTH
    for binding in slots:
        var at := 1 + binding * SLOT_WIDTH
        if _key[at] == 0:
            continue
        var u := RDUniform.new()
        u.uniform_type = (int(_key[at]) - 1) as RenderingDevice.UniformType
        u.binding = binding
        u.add_id(rid_from_int64(_key[at + 1]))
        if _key[at + 2] != 0:
            u.add_id(rid_from_int64(_key[at + 2]))
        made.append(u)
    uniforms_built += made.size()
    return made


## The key used longest ago, the first in insertion order.
func _oldest() -> PackedInt64Array:
    for key: PackedInt64Array in _sets:
        return key
    return PackedInt64Array()


func _evict(key: PackedInt64Array) -> void:
    var kept: Kept = _sets.get(key)
    if kept != null and kept.rid.is_valid() and _rd != null and _rd.uniform_set_is_valid(kept.rid):
        GlobalShaderCompiler.queue_free_uniform_set(kept.rid)
    _sets.erase(key)


## RAII cleanup during runtime destruction, this object's own rather than its
## owner's: `SaCompute` drops its last reference on the way out and this
## notification follows.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if _rd == null:
            return
        # Inlined rather than calling drop_all(). A method call on self from
        # PREDELETE fails with "in base 'null instance'": the script instance is
        # already partway through being torn down by the time this runs. The
        # comment moved here with the code, because the trap did.
        for key: PackedInt64Array in _sets:
            var doomed: RID = _sets[key].rid
            if doomed.is_valid() and _rd.uniform_set_is_valid(doomed):
                GlobalShaderCompiler.queue_free_uniform_set(doomed)
        _sets.clear()
        gpu_id = RID()


## One set the cache holds, and the use it was last found at.
class Kept:
    extends RefCounted

    var rid: RID
    var used: int = 0

    func _init(set_rid: RID, at_use: int) -> void:
        rid = set_rid
        used = at_use
