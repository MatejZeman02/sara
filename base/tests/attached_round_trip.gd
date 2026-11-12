## What the seven attached-filter round-trip suites share: a document of four
## chunks in four colours, one filter attached over it with a known parameter
## set, a save and a load back into the same easel, and the composite read at
## the centre of every chunk before and after.
##
## The load goes through `set_parameters` with a scrub first, so the filter's
## one instance holds nothing of the record when the compositor evaluates it
## again, and a texel that comes back equal came back from the file.
extends RefCounted

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const SIZE := Vector2i(512, 512)
const GRIDS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
const COLOURS: Array[Color] = [
    Color(0.8, 0.3, 0.2, 1.0), Color(0.2, 0.6, 0.9, 1.0), Color(0.45, 0.45, 0.45, 1.0), Color(0.95, 0.85, 0.1, 1.0)
]
static var scratch_path: String = SaDataRoot.path("b7_attached_round_trip.sad")

var easel: SaEasel = null
var layer: SaLayer = null
var record: SaAttachedFilter = null
var filter: SaFilter = null
var key: StringName = &""


## *its_filter* registered under *owner*, over the four chunks.
func _init(its_filter: SaFilter, owner: StringName) -> void:
    filter = its_filter
    easel = Bench.easel(SIZE)
    easel.compositor.filter_chain.registry.register(filter, owner)
    key = SaFilterRegistry.key_for(owner, filter)
    layer = easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    for index in GRIDS.size():
        layer.get_or_create_chunk(GRIDS[index]).clear(COLOURS[index])


func release() -> void:
    record = null
    layer = null
    easel.free()
    easel = null


## Attaches the filter to the layer with what its own `parameters` answers
## after *wanted* went in, which is what the Filter menu attaches.
func attach(wanted: Dictionary) -> Dictionary:
    filter.set_parameters(wanted)
    var kept := filter.parameters()
    record = SaFilterOps.new(easel.document).attach(layer, key, kept)
    return kept


## The composite at the centre of every chunk.
func texels() -> Array[Color]:
    Bench.composite(easel)
    var out: Array[Color] = []
    for grid_pos in GRIDS:
        out.append(Bench.texel(easel.output, grid_pos * SaChunk.SIZE + Vector2i.ONE * (SaChunk.SIZE >> 1)))
    return out


## Saves, hands the filter *scrub*, loads into the same easel and answers the
## loaded record's parameters, or an empty dictionary when the file lost it.
func round_trip(scrub: Dictionary = {}) -> Dictionary:
    if SaExport.save_sad(easel.document, scratch_path, 0) != OK:
        return {}
    filter.set_parameters(scrub)
    var loaded := SaExport.load_sad(easel.document, ProjectSettings.globalize_path(scratch_path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))
    if loaded != OK:
        return {}
    layer = easel.document.get_node_or_null("Background") as SaLayer
    record = layer.filters[0] if layer != null and layer.filters.size() == 1 else null
    return record.parameters if record != null else {}


## The largest channel distance between two readings of [method texels].
static func distance(one: Array[Color], other: Array[Color]) -> float:
    var most := 0.0
    for index in mini(one.size(), other.size()):
        var a := one[index]
        var b := other[index]
        most = maxf(most, maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))))
    return most
